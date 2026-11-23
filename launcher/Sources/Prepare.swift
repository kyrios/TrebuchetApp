// Trebuchet 2.1: the app prepares its own CrossOver copy from the payload inside the app (no installer),
// and moves a 2.0 install out of the way once. Nothing here touches /Applications/CrossOver.app or a bottle.
import Foundation

enum Prepare {
    /// PREFIX/.prepared: "payload <id>" and "crossover <build>" from the last successful preparation.
    static func stamp() -> [String: String] {
        guard let t = try? String(contentsOf: Install.prefix.appendingPathComponent(".prepared"), encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for l in t.split(whereSeparator: \.isNewline) {
            let p = l.split(separator: " ", maxSplits: 1).map(String.init)
            if p.count == 2 { d[p[0]] = p[1] }
        }
        return d
    }

    private static func installer(_ args: [String], extraEnv: [String: String] = [:]) -> Process? {
        guard let pl = Install.payload else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [pl.appendingPathComponent("scripts/install.sh").path] + args
        var env = ProcessInfo.processInfo.environment
        env["PREBUILT"] = pl.appendingPathComponent("bin").path
        env["MANIFEST"] = pl.appendingPathComponent("MANIFEST").path
        env["PREFIX"] = Install.prefix.path
        env["CX_APP"] = Install.crossOverApp.path
        env["NO_LAUNCHER"] = "1"
        env.merge(extraEnv) { _, n in n }
        p.environment = env
        return p
    }

    /// The id of this app's payload (install.sh --payload-id; about 0.6 s).
    static func payloadID() -> String? {
        guard let p = installer(["--payload-id"]) else { return nil }
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Does the copy have to be (re)made? Missing, made by another app version, or from another CrossOver build.
    static func needed() -> Bool {
        guard Install.managesPrefix else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: Install.prefix.appendingPathComponent("SoftFault-CrossOver.app").path),
              fm.isExecutableFile(atPath: Install.script.path) else { return true }
        let s = stamp()
        guard let have = Install.bundleVersion(Install.crossOverApp), s["crossover"] == have else { return true }
        return s["payload"] != payloadID()
    }

    /// Runs install.sh (NO_LAUNCHER=1). `progress` gets the text of each "step:" line. Returns nil on success,
    /// else the installer's reason in plain words.
    static func run(progress: @escaping (String) -> Void) -> String? {
        guard let p = installer([]) else { return "this app has no payload" }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        var all = ""
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let t = String(data: d, encoding: .utf8) else { return }
            lock.lock(); all += t; lock.unlock()
            for l in t.split(whereSeparator: \.isNewline) where l.hasPrefix("step: ") { progress(String(l.dropFirst(6))) }
        }
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        if p.terminationStatus == 0 { return nil }
        lock.lock(); let text = all; lock.unlock()
        let err = text.split(whereSeparator: \.isNewline).last { $0.hasPrefix("Error: ") }.map { String($0.dropFirst(7)) }
        var r = (err ?? "preparing Trebuchet failed").replacingOccurrences(of: " Nothing installed.", with: "")
        while r.hasSuffix(".") { r.removeLast() }
        return r
    }

    /// After a failed preparation: put only our scripts into the folder, so the normal CrossOver start (run-aoe2.sh stock) works.
    static func installScriptsOnly() {
        guard let pl = Install.payload else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: Install.prefix, withIntermediateDirectories: true)
        for f in ["run-aoe2.sh", "find-game.sh", "names.conf", "defaults.conf", "rules.manifest", "mk_reorder.py", "mk_rules.py"] {
            let dst = Install.prefix.appendingPathComponent(f)
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: pl.appendingPathComponent("scripts/\(f)"), to: dst)
        }
        for f in ["run-aoe2.sh"] { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Install.prefix.appendingPathComponent(f).path) }
    }

    /// Settings > Reset Trebuchet: remove the folder (the CrossOver copy, our files, logs). The app prepares it again on the next Launch.
    static func reset() throws {
        guard Install.managesPrefix else { return }
        if Install.gameRunning {
            throw NSError(domain: "Trebuchet", code: 1, userInfo: [NSLocalizedDescriptionKey: Names.text("UI_RESET_RUNNING", "Quit Age of Empires II first, then reset.")])
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: Install.prefix.path) { try fm.removeItem(at: Install.prefix) }
    }
}

/// One-time move from Trebuchet 2.0 / "AoE2 DE (Part A)" (installed by get.sh into ~/Library/Application Support/aoe2-mac-softfault
/// and ~/Applications). The old folder and the old apps go to the Trash (recoverable); logs are kept in the new folder.
/// A harness test passes `-legacyDir` and `-legacyAppsDir` (with `-supportDir`) to run it on copies.
enum Migration {
    static var legacyDir: URL {
        if let a = Install.argument("legacyDir") { return URL(fileURLWithPath: a) }
        return Install.home.appendingPathComponent("Library/Application Support/aoe2-mac-softfault")
    }
    static var legacyAppsDir: URL {
        if let a = Install.argument("legacyAppsDir") { return URL(fileURLWithPath: a) }
        return Install.home.appendingPathComponent("Applications")
    }
    /// Only for the app's own folder; a scratch -supportDir migrates only when the test names its legacy copies.
    static var enabled: Bool {
        guard Install.managesPrefix, !Install.isTestBuild else { return false }
        if Install.argument("supportDir") != nil { return Install.argument("legacyDir") != nil }
        return true
    }

    /// Returns plain lines for the log (what was moved).
    @discardableResult
    static func run() -> [String] {
        guard enabled else { return [] }
        let fm = FileManager.default
        var done: [String] = []
        let old = legacyDir
        if fm.fileExists(atPath: old.path), old.standardizedFileURL != Install.prefix.standardizedFileURL {
            let newLogs = Install.prefix.appendingPathComponent("logs/from-2.0")
            try? fm.createDirectory(at: newLogs.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: old.appendingPathComponent("logs").path), !fm.fileExists(atPath: newLogs.path) {
                try? fm.copyItem(at: old.appendingPathComponent("logs"), to: newLogs)
            }
            // Markers the player already saw (e.g. the C runtime notice) carry over.
            for f in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where f.hasPrefix(".ucrt-notice") {
                try? fm.copyItem(at: old.appendingPathComponent(f), to: Install.prefix.appendingPathComponent(f))
            }
            if (try? fm.trashItem(at: old, resultingItemURL: nil)) != nil { done.append("moved the 2.0 folder \(old.path) to the Trash (logs kept in logs/from-2.0)") }
        }
        let me = URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL
        let ours = Set([(Bundle.main.bundleIdentifier ?? "io.github.kyrios.trebuchet"), "local.aoe2de.parta"])
        for name in ["Trebuchet.app", "AoE2 DE (Part A).app"] {
            let a = legacyAppsDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: a.path), a.standardizedFileURL != me,
                  let info = NSDictionary(contentsOf: a.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  let bid = info["CFBundleIdentifier"] as? String, ours.contains(bid) else { continue }
            let v = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "0"
            guard v.compare("2.1", options: .numeric) == .orderedAscending else { continue }
            if (try? fm.trashItem(at: a, resultingItemURL: nil)) != nil { done.append("moved the old app \(a.path) (\(v)) to the Trash") }
        }
        if !done.isEmpty {
            try? fm.createDirectory(at: Install.logs, withIntermediateDirectories: true)
            let line = done.map { "migration: \($0)" }.joined(separator: "\n") + "\n"
            let f = Install.logs.appendingPathComponent("migration.log")
            if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.write(to: f, atomically: true, encoding: .utf8) }
        }
        return done
    }
}

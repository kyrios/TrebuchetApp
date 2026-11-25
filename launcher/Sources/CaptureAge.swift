// Trebuchet 2.1: CaptureAge. A second launch mode (run-aoe2.sh captureage), and detection of a CaptureAge that was
// started outside Trebuchet (its main process maps no files from our CrossOver copy), with a restart into the copy.
// Design: fixes/_captureage/DESIGN.md. The app only reads process lists here; starting and stopping CaptureAge is
// run-aoe2.sh's job (anchored process pattern, CaptureAge's processes only, never the game or Steam).
import Foundation
import Darwin
import CoreGraphics

enum CaptureAge {
    /// CaptureAge.exe inside the bottle (per-user install by its own installer).
    static func exe(bottle: String) -> URL {
        Install.home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/\(bottle)/drive_c/users/crossover/AppData/Local/Programs/CaptureAge/CaptureAge.exe")
    }
    /// Build switch (build-app.sh NO_CAPTUREAGE=1 → Info.plist TrebuchetCaptureAge = false): a release without the
    /// CaptureAge button and its detection, e.g. while CaptureAge's replay view has no working graphics backend.
    static var enabledInBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "TrebuchetCaptureAge") as? Bool ?? true }
    static func installed(bottle: String?) -> Bool {
        guard enabledInBuild else { return false }
        if ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE"] == "1" { return true }
        guard let b = bottle else { return false }
        return FileManager.default.fileExists(atPath: exe(bottle: b).path)
    }

    /// 2.2: CaptureAge is tested on DXMT with the text-fix set, which needs macOS 27 (run-aoe2.sh stops the start otherwise).
    /// nil = can start; else the reason, shown under the button. Fixes off = CrossOver's own way, always allowed.
    static func blockedReason(_ fixes: Fixes) -> String? {
        if fixes.plain { return nil }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_MACOS"].flatMap(Int.init).map { $0 * 10000 } ?? (v.majorVersion * 10000 + v.minorVersion * 100 + v.patchVersion)
        let need = textfixMinMacOS
        if os < need { return Names.text("UI_CA_NEEDS_MACOS", "CaptureAge needs macOS \(need / 10000) or later.") }
        if !fixes.textfix || fixes.backendValue != .dxmt { return Names.text("UI_CA_NEEDS_TEXTFIX", "CaptureAge needs Clear Menu Text and the DXMT graphics path (Settings > Fixes).") }
        return nil
    }

    /// The oldest macOS the text-fix set runs on, as run-aoe2.sh says (TEXTFIX_TESTED_MACOS=270000 → 27.0); the script is
    /// the one source, so a release that lowers it there needs no app change. 270000 if it can't be read.
    static var textfixMinMacOS: Int {
        guard let t = try? String(contentsOf: Install.script, encoding: .utf8),
              let line = t.split(separator: "\n").first(where: { $0.hasPrefix("TEXTFIX_TESTED_MACOS=") }),
              let n = Int(line.dropFirst("TEXTFIX_TESTED_MACOS=".count).prefix(while: \.isNumber)) else { return 270000 }
        return n
    }

    /// Wine shows Windows processes with their Windows path as argv[0]; anchored so no shell or tool that merely
    /// mentions CaptureAge matches (same pattern as captureage-crossover/run-captureage.sh).
    static let pattern = #"^C:.users.crossover.AppData.Local.Programs.CaptureAge.CaptureAge\.exe( |$)"#

    typealias Status = GameCheck.Status   // none, withFixes, outside

    /// Judged on CaptureAge's MAIN process only (its Electron helpers carry "--type=…"). Wine runs each process from a
    /// temporary copy of its loader, so the executable path says nothing; the files it maps do: a CaptureAge started by
    /// Trebuchet maps Wine's libraries from our CrossOver copy, one started elsewhere maps none from it.
    /// `window`: the main process already shows a window (CaptureAge's UI can take about a minute to appear).
    static func status() -> (status: Status, window: Bool) {
        guard enabledInBuild else { return (.none, false) }
        if let d = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE_STATE"] {
            return (d == "outside" ? .outside : d == "fixes" ? .withFixes : .none, true)
        }
        let mains = matchingPIDs(pattern).filter { !(commandLine($0) ?? "").contains(" --type=") }
        guard !mains.isEmpty else { return (.none, false) }
        let copy = Install.prefix.appendingPathComponent("SoftFault-CrossOver.app").path + "/"
        let window = mains.contains { hasWindow($0) }
        for pid in mains where !mapsFiles(pid, under: copy) { return (.outside, window) }
        return (.withFixes, window)
    }

    // The game's own check (started with or without the fixes) is GameCheck.gameStatus().

    private static func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
    private static func commandLine(_ pid: pid_t) -> String? {
        let c = run("/bin/ps", ["-o", "command=", "-p", String(pid)]).trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? nil : c
    }
    private static func mapsFiles(_ pid: pid_t, under dir: String) -> Bool {
        run("/usr/sbin/lsof", ["-p", String(pid), "-Fn"]).split(whereSeparator: \.isNewline).contains { $0.hasPrefix("n" + dir) }
    }
    private static func hasWindow(_ pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    private static func matchingPIDs(_ pattern: String) -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }
}

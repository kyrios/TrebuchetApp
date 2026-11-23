// Trebuchet launcher: data model. Everything the player reads comes from names.conf; release defaults from defaults.conf.
// The launch interface (environment for run-aoe2.sh) is unchanged from AoE2Launcher.swift 2.0.
import SwiftUI
import Foundation

// MARK: - Install location

enum Install {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }

    /// The payload inside the app (2.1+): Contents/Resources/Trebuchet with MANIFEST, bin/ and scripts/. nil for a 2.0-style app.
    static var payload: URL? {
        guard let r = Bundle.main.resourceURL?.appendingPathComponent("Trebuchet"),
              fm.fileExists(atPath: r.appendingPathComponent("scripts/install.sh").path) else { return nil }
        return r
    }
    /// Command-line arguments only (NSArgumentDomain, e.g. `-supportDir /path`); never read from or written to stored settings.
    static func argument(_ key: String) -> String? {
        let v = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
        return (v?.isEmpty ?? true) ? nil : v
    }
    /// AOE2_PREFIX: a ready install that is used as it is (harness, screenshots). The app never prepares or migrates it.
    static var fixedPrefix: URL? {
        guard let p = ProcessInfo.processInfo.environment["AOE2_PREFIX"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p)
    }
    /// The folder with the CrossOver copy and our files.
    /// 2.1: ~/Library/Application Support/Trebuchet (a harness test may pass `-supportDir <scratch folder>`).
    static var prefix: URL {
        if let p = fixedPrefix { return p }
        if let s = argument("supportDir") { return URL(fileURLWithPath: s) }
        if payload != nil { return home.appendingPathComponent("Library/Application Support/Trebuchet") }
        return home.appendingPathComponent("Library/Application Support/aoe2-mac-softfault")
    }
    /// True when this app prepares the folder itself from its payload (no installer).
    static var managesPrefix: Bool { payload != nil && fixedPrefix == nil }
    static var script: URL { prefix.appendingPathComponent("run-aoe2.sh") }
    static var logs: URL { prefix.appendingPathComponent("logs") }
    static var isInstalled: Bool { managesPrefix || fm.isExecutableFile(atPath: script.path) }

    /// CrossOver: /Applications/CrossOver.app unless the player chose another copy in Settings. Read only, never changed.
    static var crossOverApp: URL {
        if let p = UserDefaults.standard.string(forKey: "crossOverPath"), !p.isEmpty { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: "/Applications/CrossOver.app")
    }
    static var crossOverInstalled: Bool {
        if let d = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_NOCX"], d == "1" { return false }
        return fm.fileExists(atPath: crossOverApp.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine").path)
    }
    static func bundleVersion(_ app: URL) -> String? {
        (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleVersion"] as? String
    }

    /// A text file of this release (names.conf, defaults.conf, rules.manifest): the app's own copy first, else the install folder.
    static func config(_ name: String) -> URL {
        if let p = payload { return p.appendingPathComponent("scripts/\(name)") }
        return prefix.appendingPathComponent(name)
    }

    /// The app is running from a disk image or from App Translocation (opened before it was moved to Applications).
    static var runsFromDiskImageOrTranslocated: Bool {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") { return true }
        if path.hasPrefix("/Volumes/") {
            let v = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly
            return v ?? false
        }
        return false
    }

    /// Licences and notices: the copy inside the app (build-app.sh puts LICENSES/ into Contents/Resources) first, then the prefix.
    static var notice: URL? {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("LICENSES/NOTICE.md")) }
        candidates += ["LICENSES/NOTICE.md", "NOTICE.md"].map { prefix.appendingPathComponent($0) }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }
}

// MARK: - names.conf (player-facing text) and defaults.conf

enum Names {
    static let table: [String: String] = {
        var d: [String: String] = [:]
        guard let text = try? String(contentsOf: Install.config("names.conf"), encoding: .utf8) else { return d }
        for raw in text.split(whereSeparator: \.isNewline) where !raw.hasPrefix("#") {
            let p = raw.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { d[p[0].trimmingCharacters(in: .whitespaces)] = p[1].trimmingCharacters(in: .whitespaces) }
        }
        return d
    }()
    static func text(_ key: String, _ fallback: String = "") -> String {
        let v = table[key] ?? ""
        return v.isEmpty ? fallback : v
    }
    static func fix(_ id: String, _ fallback: String) -> String { text("FIX_" + id.uppercased(), fallback) }
    static func gain(_ id: String) -> String { table["GAIN_" + id.uppercased()] ?? "" }
    static func info(_ id: String) -> String { table["INFO_" + id.uppercased()] ?? "" }
    static func marked(_ id: String) -> Bool { table["DETECT_" + id.uppercased()] == "1" }
    static var anyMarked: Bool { table.contains { $0.key.hasPrefix("DETECT_") && $0.value == "1" } }

    static var appName: String { text("APP_NAME", "Trebuchet") }
    /// TAGLINE is "Trebuchet. Bringing a classic …"; under the big app name only the second sentence is shown.
    static var taglineShort: String {
        let t = text("TAGLINE", "Bringing a classic to modern silicon.")
        let prefix = appName + ". "
        return t.hasPrefix(prefix) ? String(t.dropFirst(prefix.count)) : t
    }
}

func loadDefaults() -> [String: Bool] {
    guard let text = try? String(contentsOf: Install.config("defaults.conf"), encoding: .utf8) else { return [:] }
    var d: [String: Bool] = [:]
    for raw in text.split(whereSeparator: \.isNewline) {
        let parts = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].hasPrefix("#"), parts[1] == "0" || parts[1] == "1" else { continue }
        d[parts[0]] = parts[1] == "1"
    }
    return d
}

// MARK: - Version-bound fixes (rules.manifest)

struct Rule: Identifiable { let id, name, grade, target, offEnv: String }

func loadRules() -> (pack: String, rules: [Rule]) {
    let fallback = [Rule(id: "reorder", name: "Swift Health Bars", grade: "D", target: "game", offEnv: "AOE2_NO_REORDER"),
                    Rule(id: "f54a", name: "Hitch Guard", grade: "C", target: "rosetta", offEnv: "AOE2_NO_F54A")]
    guard let text = try? String(contentsOf: Install.config("rules.manifest"), encoding: .utf8) else { return ("built-in", fallback) }
    var pack = "?"; var rules: [Rule] = []
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = String(raw)
        if line.hasPrefix("pack ") { pack = String(line.split(separator: " ")[1]) }
        guard line.hasPrefix("rule ") else { continue }
        func field(_ k: String) -> String {
            if let r = line.range(of: " \(k)=\"") { return String(line[r.upperBound...].prefix { $0 != "\"" }) }
            if let r = line.range(of: " \(k)=") { return String(line[r.upperBound...].prefix { $0 != " " }) }
            return ""
        }
        let id = String(line.split(separator: " ")[1])
        let off = field("off")
        guard !off.isEmpty else { continue }
        rules.append(Rule(id: id, name: Names.fix(id, field("name").isEmpty ? id : field("name")), grade: field("grade"), target: field("target"), offEnv: off))
    }
    return (pack, rules.isEmpty ? fallback : rules)
}

/// Optional parts the installer marks with a file.
enum InstallParts {
    /// 2.1: the words in the app's bin/FEATURES; 2.0: the installer's .has-* marker files.
    static let features: Set<String>? = {
        guard let p = Install.payload, let t = try? String(contentsOf: p.appendingPathComponent("bin/FEATURES"), encoding: .utf8) else { return nil }
        return Set(t.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() })
    }()
    static func has(_ f: String) -> Bool {
        if let s = features { return s.contains(f) }
        return FileManager.default.fileExists(atPath: Install.prefix.appendingPathComponent(".has-\(f)").path)
    }
    static var fastClock: Bool { has("fastqpc") }
    static var localCursor: Bool { has("t4") }
}

/// CrossOver bottles that contain AoE2 DE (Steam).
func gameBottles() -> [String] {
    if ProcessInfo.processInfo.environment["TREBUCHET_DEMO_NOBOTTLE"] == "1" { return [] }
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.sorted().filter {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("\($0)/drive_c/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe").path)
    }
}

enum Backend: String, CaseIterable, Identifiable {
    case dxmt, d3dmetal, wined3d
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dxmt: return "DXMT"
        case .d3dmetal: return "D3DMetal"
        case .wined3d: return "wined3d"
        }
    }
    var caption: String {
        switch self {
        case .dxmt: return Names.text("UI_BACKEND_DXMT", "Metal, recommended. Needed for Clear Menu Text.")
        case .d3dmetal: return Names.text("UI_BACKEND_D3DMETAL", "Apple's Game Porting Toolkit renderer.")
        case .wined3d: return Names.text("UI_BACKEND_WINED3D", "CrossOver's OpenGL path. Most conservative.")
        }
    }
}

// MARK: - The player's switches (keys unchanged from 2.0 so saved choices carry over)

final class Fixes: ObservableObject {
    @AppStorage("ruleOff") var ruleOffRaw = ""
    @AppStorage("textfix") var textfix = true
    @AppStorage("msync") var msync = false
    @AppStorage("fastqpc") var fastqpc = false
    @AppStorage("t4") var t4 = false
    @AppStorage("backend") var backend = Backend.dxmt.rawValue
    @AppStorage("plain") var plain = false
    @AppStorage("bottle") var bottle = ""
    @AppStorage("hud") var hud = false
    @AppStorage("args") var args = ""
    @AppStorage("crossOverPath") var crossOverPath = ""

    let rules: [Rule]
    let pack: String
    init() {
        (pack, rules) = loadRules()
        let d = loadDefaults()
        var reg: [String: Any] = [:]
        if let v = d["TEXTFIX"] { reg["textfix"] = v }
        if let v = d["MSYNC"] { reg["msync"] = v }
        if let v = d["FASTQPC"] { reg["fastqpc"] = v }
        if let v = d["T4"] { reg["t4"] = v }
        reg["ruleOff"] = rules.filter { d[$0.id.uppercased()] == false }.map(\.id).sorted().joined(separator: ",")
        UserDefaults.standard.register(defaults: reg)
    }

    func isOn(_ r: Rule) -> Bool { !ruleOffRaw.split(separator: ",").contains(Substring(r.id)) }
    func set(_ r: Rule, _ on: Bool) {
        var ids = Set(ruleOffRaw.split(separator: ",").map(String.init))
        if on { ids.remove(r.id) } else { ids.insert(r.id) }
        ruleOffRaw = ids.sorted().joined(separator: ",")
        objectWillChange.send()
    }
    func binding(_ r: Rule) -> Binding<Bool> { Binding(get: { self.isOn(r) }, set: { self.set(r, $0) }) }
    var useFixes: Binding<Bool> { Binding(get: { !self.plain }, set: { self.plain = !$0 }) }

    var effectiveBottle: String? { bottle.isEmpty ? gameBottles().first : bottle }
    var backendValue: Backend { Backend(rawValue: backend) ?? .dxmt }

    /// (on, total) over the fixes a player can see as on/off in this install.
    var counts: (on: Int, total: Int) {
        var on = 0, total = 0
        func add(_ v: Bool) { total += 1; if v { on += 1 } }
        add(true)                               // Quick Traps
        add(true)                               // Renderer Guard
        add(backendValue == .dxmt)              // Metal Renderer
        for r in rules { add(isOn(r)) }
        add(textfix && backendValue == .dxmt)   // Clear Menu Text
        add(msync)
        if InstallParts.localCursor { add(t4) }
        if InstallParts.fastClock { add(fastqpc) }
        return (on, total)
    }

    /// The environment run-aoe2.sh reads: explicit on or off for every fix (unchanged from 2.0).
    func environment() -> [String: String] {
        var env: [String: String] = [:]
        func set(_ name: String, _ on: Bool) { env[on ? "AOE2_\(name)" : "AOE2_NO_\(name)"] = "1" }
        for r in rules { set(r.id.uppercased(), isOn(r)) }
        set("TEXTFIX", textfix)
        set("MSYNC", msync)
        set("FASTQPC", fastqpc && InstallParts.fastClock)
        set("T4", t4 && InstallParts.localCursor)
        env["AOE2_BACKEND"] = backend
        env["CX_APP"] = Install.crossOverApp.path
        if let b = effectiveBottle { env["AOE2_BOTTLE"] = b }
        if hud { env["AOE_HUD"] = "1" }
        let a = args.trimmingCharacters(in: .whitespaces)
        if !a.isEmpty { env["AOE2_ARGS"] = a }
        return env
    }
    var managedKeys: [String] {
        (rules.map { $0.id.uppercased() } + ["TEXTFIX", "MSYNC", "FASTQPC", "T4"]).flatMap { ["AOE2_\($0)", "AOE2_NO_\($0)"] }
            + ["AOE2_BACKEND", "AOE2_BOTTLE", "AOE_HUD", "AOE2_ARGS", "AOE_SUBST_COUNT", "AOE_RECLAIM_TEST_MUTATE", "CX_APP"]
    }
}

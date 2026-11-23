// Trebuchet 2.1: is the running game Trebuchet's? A game started elsewhere (Steam's Play button) runs in Steam's
// normal CrossOver without the fixes. The app only reads the process list here; it never starts or stops anything.
import Foundation

enum GameCheck {
    enum Status: Equatable { case none, withFixes, outside }

    /// Wine shows Windows processes with their Windows path as argv[0]; anchored so nothing that merely mentions the game matches.
    static let gamePattern = #"^C:.Program Files .x86..Steam.steamapps.common.AoE2DE.AoE2DE_s\.exe( |$)"#

    /// Wine runs each process from a temporary copy of its loader, so the executable path says nothing; the files it maps
    /// do: a game started by Trebuchet maps Wine's libraries from our CrossOver copy, one started elsewhere maps none from it.
    static func gameStatus() -> Status {
        if let d = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_GAME_STATE"] { return d == "outside" ? .outside : d == "fixes" ? .withFixes : .none }
        let pids = matchingPIDs(gamePattern)
        guard !pids.isEmpty else { return .none }
        let copy = Install.prefix.appendingPathComponent("SoftFault-CrossOver.app").path + "/"
        return pids.allSatisfy { mapsFiles($0, under: copy) } ? .withFixes : .outside
    }

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
    private static func mapsFiles(_ pid: pid_t, under dir: String) -> Bool {
        run("/usr/sbin/lsof", ["-p", String(pid), "-Fn"]).split(whereSeparator: \.isNewline).contains { $0.hasPrefix("n" + dir) }
    }
    private static func matchingPIDs(_ pattern: String) -> [pid_t] {
        run("/usr/bin/pgrep", ["-f", pattern]).split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }
}

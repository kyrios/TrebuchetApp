// Trebuchet 2.1: CaptureAge. A second launch mode (run-aoe2.sh captureage), and detection of a CaptureAge that was
// started outside Trebuchet (its Wine loader is not the one in our CrossOver copy), with a restart into the copy.
// Design: fixes/_captureage/DESIGN.md. The app only reads process lists here; starting and stopping CaptureAge is
// run-aoe2.sh's job (anchored process pattern, CaptureAge's processes only, never the game or Steam).
import Foundation
import Darwin

enum CaptureAge {
    /// CaptureAge.exe inside the bottle (per-user install by its own installer).
    static func exe(bottle: String) -> URL {
        Install.home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/\(bottle)/drive_c/users/crossover/AppData/Local/Programs/CaptureAge/CaptureAge.exe")
    }
    static func installed(bottle: String?) -> Bool {
        if ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE"] == "1" { return true }
        guard let b = bottle else { return false }
        return FileManager.default.fileExists(atPath: exe(bottle: b).path)
    }

    /// Wine shows Windows processes with their Windows path as argv[0]; anchored so no shell or tool that merely
    /// mentions CaptureAge matches (same pattern as captureage-crossover/run-captureage.sh).
    static let pattern = #"^C:.users.crossover.AppData.Local.Programs.CaptureAge.CaptureAge\.exe( |$)"#

    enum Status: Equatable { case none, withFixes, outside }

    /// none: no CaptureAge. withFixes: every CaptureAge process runs from our CrossOver copy. outside: at least one runs
    /// from another CrossOver (the user's own CaptureAge.app, or a stock start).
    static func status() -> Status {
        if let d = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE_STATE"] {
            return d == "outside" ? .outside : d == "fixes" ? .withFixes : .none
        }
        let pids = matchingPIDs()
        guard !pids.isEmpty else { return .none }
        let copy = Install.prefix.appendingPathComponent("SoftFault-CrossOver.app").resolvingSymlinksInPath().path + "/"
        for pid in pids {
            guard let path = executablePath(pid) else { continue }
            if !URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(copy) { return .outside }
        }
        return .withFixes
    }

    private static func matchingPIDs() -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }

    /// The real executable of a process (for a Wine process: the wine loader of the CrossOver it runs in).
    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }
}

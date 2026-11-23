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
    static func installed(bottle: String?) -> Bool {
        if ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE"] == "1" { return true }
        guard let b = bottle else { return false }
        return FileManager.default.fileExists(atPath: exe(bottle: b).path)
    }

    /// Wine shows Windows processes with their Windows path as argv[0]; anchored so no shell or tool that merely
    /// mentions CaptureAge matches (same pattern as captureage-crossover/run-captureage.sh).
    static let pattern = #"^C:.users.crossover.AppData.Local.Programs.CaptureAge.CaptureAge\.exe( |$)"#

    enum Status: Equatable { case none, withFixes, outside }

    /// Judged on CaptureAge's MAIN process only (its Electron helpers carry "--type=…"). Wine runs each process from a
    /// temporary copy of its loader, so the executable path says nothing; the files it maps do: a CaptureAge started by
    /// Trebuchet maps Wine's libraries from our CrossOver copy, one started elsewhere maps none from it.
    /// `window`: the main process already shows a window (CaptureAge's UI can take about a minute to appear).
    static func status() -> (status: Status, window: Bool) {
        if let d = ProcessInfo.processInfo.environment["TREBUCHET_DEMO_CAPTUREAGE_STATE"] {
            return (d == "outside" ? .outside : d == "fixes" ? .withFixes : .none, true)
        }
        let mains = matchingPIDs().filter { !(commandLine($0) ?? "").contains(" --type=") }
        guard !mains.isEmpty else { return (.none, false) }
        let copy = Install.prefix.appendingPathComponent("SoftFault-CrossOver.app").path + "/"
        let window = mains.contains { hasWindow($0) }
        for pid in mains where !mapsFiles(pid, under: copy) { return (.outside, window) }
        return (.withFixes, window)
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
}

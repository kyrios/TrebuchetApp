// Trebuchet launcher: starts run-aoe2.sh and turns its plain-language lines into one state for the main window.
// The line prefixes below are the interface with run-aoe2.sh (agreed with the integrator).
import SwiftUI
import Foundation

enum LaunchState: Equatable {
    case ready
    case preparing(String)          // first Launch or after an update: making the CrossOver copy (one progress line)
    case launching(String)          // last plain line
    case running(plain: Bool)
    case fixOff(String)             // "<fix> is off: …"
    case fallback(String)           // "Part A not used: …"
    case steamOffline(String)
    case alreadyRunning
    case failed(String)
    case noCrossOver
    case notInstalled
    case noBottle
    case notInApplications          // opened from the disk image (or translocated): move it first

    /// Shows a spinner.
    var isBusy: Bool {
        switch self {
        case .preparing, .launching: return true
        default: return false
        }
    }
    /// States that block the Launch button.
    var blocks: Bool {
        switch self {
        case .preparing, .launching, .running, .noCrossOver, .notInstalled, .noBottle, .notInApplications: return true
        default: return false
        }
    }
}

@MainActor
final class Runner: ObservableObject {
    @Published var state: LaunchState = .ready
    @Published var lines: [String] = []
    private var process: Process?
    private var sawMode = false

    /// Blocking problems found before any launch (read-only checks).
    func refreshPreflight(_ fixes: Fixes) {
        if let d = Demo.state { state = d; return }
        switch state {
        case .preparing, .launching, .running: return
        default: break
        }
        if Install.managesPrefix && Install.runsFromDiskImageOrTranslocated { state = .notInApplications }
        else if !Install.crossOverInstalled { state = .noCrossOver }
        else if !Install.isInstalled { state = .notInstalled }
        else if fixes.effectiveBottle == nil { state = .noBottle }
        else if state.blocks { state = .ready }
    }

    nonisolated static func launchEnvironment(_ fixes: Fixes) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for k in fixes.managedKeys { env[k] = nil }
        env.merge(fixes.environment()) { _, new in new }
        return env
    }
    nonisolated static func makeProcess(_ fixes: Fixes, forceStock: Bool = false) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [Install.script.path, (fixes.plain || forceStock) ? "stock" : "soft"]
        p.environment = launchEnvironment(fixes)
        return p
    }

    /// Launch: first (2.1) move a 2.0 install aside and prepare the CrossOver copy if needed, then start the game.
    func launch(_ fixes: Fixes) {
        // Demo builds (screenshots) never start anything.
        guard Demo.state == nil, !state.blocks else { return }
        guard Install.managesPrefix, !Install.gameRunning else { start(fixes); return }   // running game: run-aoe2.sh says so
        state = .preparing(Names.text("UI_CHECKING_FILES", "Checking Trebuchet's files…"))
        let cx = Install.bundleVersion(Install.crossOverApp).map { $0.split(separator: ".").prefix(2).joined(separator: ".") } ?? ""
        Task.detached {
            Migration.run()
            var failure: String? = nil
            if Prepare.needed() {
                await MainActor.run {
                    self.state = .preparing(Names.text("UI_PREPARING", "Preparing Trebuchet for CrossOver %@… about 5 s").replacingOccurrences(of: "%@", with: cx))
                }
                failure = Prepare.run { _ in }
                if failure != nil { Prepare.installScriptsOnly() }
            }
            let reason = failure
            await MainActor.run {
                if let r = reason {
                    // Unsupported CrossOver or a damaged app: the normal CrossOver start, and say why.
                    self.start(fixes, forceStock: true)
                    self.state = .fallback(r + ". " + Names.text("UI_FALLBACK_STOCK", "Starting the game the normal CrossOver way."))
                } else {
                    self.start(fixes)
                }
            }
        }
    }

    private func start(_ fixes: Fixes, forceStock: Bool = false) {
        let p = Runner.makeProcess(fixes, forceStock: forceStock)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let new = text.split(whereSeparator: \.isNewline).map(String.init)
            Task { @MainActor in self?.consume(new, plain: fixes.plain || forceStock) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.finished(proc.terminationStatus, fixes) }
        }
        lines = []; sawMode = false
        do {
            try p.run()
            process = p
            state = .launching(Names.text("UI_STARTING_DETAIL", "Checking CrossOver and the game."))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func consume(_ new: [String], plain: Bool) {
        lines.append(contentsOf: new)
        for l in new {
            if l.contains("this release is built for") || l.contains("differs from the release") || l.contains("has no MANIFEST") { state = .fallback(l) }
            else if l.hasPrefix("Part A not used:") { state = .fallback(String(l.dropFirst("Part A not used:".count)).trimmingCharacters(in: .whitespaces)) }
            else if l.range(of: #"^.+ is off: "#, options: .regularExpression) != nil { state = .fixOff(l) }
            else if l.hasPrefix("Steam is in offline mode") { state = .steamOffline(l) }
            else if l.hasPrefix("AoE2 is already running") { state = .alreadyRunning }
            else if l.hasPrefix("mode soft") || l.hasPrefix("mode stock") {
                sawMode = true
                switch state {
                case .fixOff, .fallback, .steamOffline: break        // keep the warning visible; the game still runs
                default: state = .running(plain: l.hasPrefix("mode stock"))
                }
            } else if case .launching = state, !l.isEmpty, !l.hasPrefix("rule "), !l.contains("/") {
                state = .launching(l)
            }
        }
    }

    private func finished(_ code: Int32, _ fixes: Fixes) {
        process = nil
        switch state {
        case .fixOff, .fallback, .steamOffline, .alreadyRunning: return   // keep what the player should read
        default: break
        }
        if code == 0 { state = .ready; refreshPreflight(fixes) }
        else { state = .failed(lines.last(where: { !$0.isEmpty }) ?? "") }
    }
}

// MARK: - Demo states (screenshots and review only; never launches)

enum Demo {
    /// TREBUCHET_DEMO=<window>[-<state>]: main-ready, main-launching, main-running, main-fixoff, main-fallback, main-steamoffline,
    /// main-failed, main-nocrossover, main-notinstalled, main-nobottle, settings-fixes, settings-graphics, settings-game, popover, about.
    static let mode = ProcessInfo.processInfo.environment["TREBUCHET_DEMO"] ?? ""
    static var active: Bool { !mode.isEmpty }
    static var state: LaunchState? {
        guard active else { return nil }
        switch mode {
        case "main-launching": return .launching("Starting Steam first. The game starts when Steam is ready.")
        case "main-running": return .running(plain: false)
        case "main-fixoff": return .fixOff("Swift Health Bars is off: it does not match this game build. The game runs normally; the other fixes stay on.")
        case "main-fallback": return .fallback("the bottle is now on CrossOver 26.4, Part A is built for 26.3. Rebuild Part A for the new version. Starting normally.")
        case "main-steamoffline": return .steamOffline("Steam is in offline mode, so multiplayer won't connect. In Steam choose Steam > Go Online, then start the game.")
        case "main-failed": return .failed("the patched start failed (cannot open the game).")
        case "main-nocrossover": return .noCrossOver
        case "main-notinstalled": return .notInstalled
        case "main-nobottle": return .noBottle
        case "main-preparing": return .preparing("Preparing Trebuchet for CrossOver 26.3… about 5 s")
        case "main-notinapplications": return .notInApplications
        default: return .ready
        }
    }
    static var settingsTab: String? {
        switch mode {
        case "settings-fixes", "popover": return "fixes"
        case "settings-graphics": return "graphics"
        case "settings-game": return "game"
        default: return nil
        }
    }
}

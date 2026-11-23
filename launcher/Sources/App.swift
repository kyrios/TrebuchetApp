// Trebuchet launcher: entry point, scenes and the command-line modes (--print-env, --launch).
import SwiftUI
import AppKit
#if SPARKLE
import Sparkle
#endif

@main
enum Entry {
    static func main() {
        let a = CommandLine.arguments
        // --print-env: the switches the Launch button would pass (for checks; starts nothing)
        if a.contains("--print-env") {
            let fixes = Fixes()
            let env = Runner.launchEnvironment(fixes)
            for k in fixes.managedKeys.sorted() { if let v = env[k] { print("\(k)=\(v)") } }
            print("mode=\(fixes.plain ? "stock" : "soft")")
            return
        }
        // --game-status: none | withFixes | outside (read-only; is the running game Trebuchet's?)
        if a.contains("--game-status") { print(GameCheck.gameStatus()); return }
        // --prepare: only the 2.1 first-launch work (move a 2.0 install aside, make the CrossOver copy); starts no game
        if a.contains("--prepare") {
            let r = prepareForLaunch()
            print(r.map { "not prepared: \($0)" } ?? "prepared: \(Install.prefix.path)")
            exit(r == nil ? 0 : 1)
        }
        // --launch: the same launch as the button, without a window (scripted real start); waits for the game
        if a.contains("--launch") {
            let failure = prepareForLaunch()
            if let r = failure { print("Part A not used: \(r). Starting the game the normal CrossOver way.") }
            let p = Runner.makeProcess(Fixes(), forceStock: failure != nil)
            do { try p.run() } catch { print("could not start: \(error)"); exit(1) }
            p.waitUntilExit()
            exit(p.terminationStatus)
        }
        TrebuchetApp.main()
    }
}

/// The 2.1 work before a start, for the command-line modes (the Launch button does the same in Runner.launch).
/// Returns nil when the copy is ready (or this app does not manage one), else the reason.
func prepareForLaunch() -> String? {
    guard Install.managesPrefix, !Install.gameRunning else { return nil }
    for l in Migration.run() { print("migration: \(l)") }
    guard Prepare.needed() else { return nil }
    let r = Prepare.run { print("step: \($0)") }
    if r != nil { Prepare.installScriptsOnly() }
    return r
}

/// Automatic updates (Sparkle 2, EdDSA-signed feed on GitHub Pages). Only in builds with the public key (build-app.sh).
/// An update replaces only this app; the game runs from the prepared folder, so it is safe while the game runs.
/// The next Launch then prepares the folder for the new version (never while the game is running).
enum Updates {
    #if SPARKLE
    #if SPARKLE_DIAG
    // Local update tests only (build-app.sh SPARKLE_TEST_FEED): every Sparkle decision goes to logs/updates.log.
    static let diag = UpdateDiag()
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: diag, userDriverDelegate: diag)
    #else
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    static var available: Bool { true }
    /// Creating the controller starts the updater (scheduled checks); never in demo/screenshot builds or command-line modes.
    static func start() { if !Demo.active { _ = controller } }
    static func check() { controller.checkForUpdates(nil) }
    #else
    static func start() {}
    static var available: Bool { false }
    static func check() {}
    #endif
}

#if SPARKLE && SPARKLE_DIAG
final class UpdateDiag: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private func log(_ s: String) {
        let f = Install.logs.appendingPathComponent("updates.log")
        try? FileManager.default.createDirectory(at: Install.logs, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: f, atomically: true, encoding: .utf8) }
    }
    private func describe(_ e: Error) -> String {
        let n = e as NSError
        return "\(n.domain) \(n.code): \(n.localizedDescription) \(n.userInfo[NSUnderlyingErrorKey].map { "underlying: \($0)" } ?? "") \(n.userInfo["SPUNoUpdateFoundReason"].map { "reason \($0)" } ?? "")"
    }
    func feedURLString(for updater: SPUUpdater) -> String? { log("feed \(updater.feedURL?.absoluteString ?? "nil"), automatic checks \(updater.automaticallyChecksForUpdates), automatic downloads \(updater.automaticallyDownloadsUpdates)"); return nil }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) { log("appcast loaded: \(appcast.items.count) item(s): \(appcast.items.map { "\($0.versionString) \($0.fileURL?.absoluteString ?? "-")" })") }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { log("valid update found: \(item.versionString)") }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { log("no update: \(describe(error))") }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { log("aborted: \(describe(error))") }
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) { log("download failed: \(describe(error))") }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { log("downloaded \(item.versionString)") }
    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) { log("extracted \(item.versionString)") }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { log("will install \(item.versionString)") }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool { log("will install \(item.versionString) on quit"); return false }
    func standardUserDriverWillShowModalAlert() { log("Sparkle shows a window to the user (a prompt instead of a silent update)") }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) { log("showing update \(update.versionString): handled=\(handleShowingUpdate) userInitiated=\(state.userInitiated) stage=\(state.stage.rawValue)") }
}
#endif

struct TrebuchetApp: App {
    @StateObject private var fixes = Fixes()
    @StateObject private var runner = Runner()
    init() { Updates.start() }

    var body: some Scene {
        Window(Names.appName, id: "main") {
            MainView()
                .environmentObject(fixes)
                .environmentObject(runner)
                .background(DemoOpener())
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
                if Updates.available { Button(Names.text("UI_CHECKUPDATES", "Check for Updates…")) { Updates.check() } }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button(Names.text("UI_SHOWLOG", "Show Log")) { openLogs() }
            }
        }

        Window(Names.text("UI_ABOUT_TITLE", "About \(Names.appName)"), id: "about") {
            AboutView().environmentObject(fixes)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView().environmentObject(fixes)
        }
        .windowResizability(.contentMinSize)
    }
}

struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(Names.text("UI_ABOUT_TITLE", "About \(Names.appName)")) { openWindow(id: "about") }
    }
}

/// Opens the window a demo state asks for (screenshots only).
struct DemoOpener: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear {
                guard Demo.active else { return }
                switch ProcessInfo.processInfo.environment["TREBUCHET_DEMO_APPEARANCE"] {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: break
                }
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if Demo.settingsTab != nil { openSettings(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.activate(ignoringOtherApps: true) } }
                    if Demo.mode == "about" { openWindow(id: "about") }
                }
            }
    }
}

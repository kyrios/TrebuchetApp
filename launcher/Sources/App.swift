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
        // --captureage-status: none | withFixes | outside (read-only; for the CaptureAge detection test)
        if a.contains("--captureage-status") { let s = CaptureAge.status(); print("\(s.status) window=\(s.window)"); return }
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
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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

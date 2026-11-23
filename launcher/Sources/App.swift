// Trebuchet launcher: entry point, scenes and the command-line modes (--print-env, --launch).
import SwiftUI
import AppKit

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
    guard Install.managesPrefix else { return nil }
    for l in Migration.run() { print("migration: \(l)") }
    guard Prepare.needed() else { return nil }
    let r = Prepare.run { print("step: \($0)") }
    if r != nil { Prepare.installScriptsOnly() }
    return r
}

struct TrebuchetApp: App {
    @StateObject private var fixes = Fixes()
    @StateObject private var runner = Runner()

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
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
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

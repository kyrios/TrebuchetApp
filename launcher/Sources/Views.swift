// Trebuchet launcher: views. Layout, tokens and states: fixes/_launcher/DESIGN.md.
import SwiftUI
import AppKit

// MARK: - Tokens

enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 20, xl: CGFloat = 28 }

extension Color {
    /// Launch button fill: white text stays above 4.5:1 in both modes.
    static let launchFill = Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.31, green: 0.42, blue: 0.56, alpha: 1)
            : NSColor(srgbRed: 0.25, green: 0.33, blue: 0.44, alpha: 1)
    })
    /// The icon's slate blue (background layer #405571 → #627892); lighter in dark mode for contrast on dark grounds.
    static let trebuchet = Color(nsColor: NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.56, green: 0.65, blue: 0.77, alpha: 1)
            : NSColor(srgbRed: 0.25, green: 0.33, blue: 0.44, alpha: 1)
    })
}

func appIcon() -> NSImage {
    if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { return i }
    return NSApp?.applicationIconImage ?? NSImage(size: NSSize(width: 96, height: 96))
}

func openLogs() {
    let fm = FileManager.default
    NSWorkspace.shared.open(fm.fileExists(atPath: Install.logs.path) ? Install.logs : Install.prefix)
}

// MARK: - Main window

struct MainView: View {
    @EnvironmentObject var fixes: Fixes
    @EnvironmentObject var runner: Runner
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.s) {
                Image(nsImage: appIcon()).resizable().interpolation(.high).frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text(Names.appName).font(.largeTitle.weight(.semibold))
                Text(Names.taglineShort).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, Space.l)

            StatusCard(state: runner.state, fixes: fixes, captureAgeWindow: runner.captureAgeWindow, openSettings: { openSettings() })
                .padding(.bottom, Space.l)

            Button { runner.launch(fixes) } label: {
                HStack(spacing: Space.s) {
                    if runner.state.isBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "play.fill") }
                    Text(launchTitle)
                }
                .font(.title3.weight(.semibold))
                .frame(minWidth: 260)
                .padding(.vertical, Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.launchFill)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(runner.state.blocks)
            .accessibilityHint(Text("Starts Age of Empires II in CrossOver"))

            if CaptureAge.installed(bottle: fixes.effectiveBottle) {
                Button { runner.launch(fixes, target: .captureAge) } label: {
                    Label(Names.text("UI_LAUNCH_CAPTUREAGE", "Launch CaptureAge"), systemImage: "eye")
                        .frame(minWidth: 260)
                }
                .controlSize(.large)
                .disabled(runner.state.blocks || runner.captureAge != .none)
                .padding(.top, Space.s)
                .accessibilityHint(Text("Starts CaptureAge in Trebuchet's runtime. Start the game with Launch first so it has the fixes."))
            }
            if runner.game == .outside, !runner.state.isGame {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(Names.text("UI_GAME_OUTSIDE", "Age of Empires II is running without Trebuchet's fixes (started through Steam or CaptureAge). Quit it and press Launch to play with the fixes."))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if runner.captureAge == .outside, !runner.state.isCaptureAge {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Names.text("UI_CA_OUTSIDE", "CaptureAge was started outside Trebuchet."))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button(Names.text("UI_CA_RESTART", "Restart CaptureAge with fixes")) { runner.restartCaptureAge(fixes) }
                            .buttonStyle(.link).font(.callout)
                            .disabled(runner.state.blocks)
                    }
                }
                .padding(.top, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Space.m) {
                Button(Names.text("UI_SETTINGS", "Settings…")) { openSettings() }
                Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                Button(Names.text("UI_SHOWLOG", "Show Log")) { openLogs() }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.top, Space.m)

            Divider().padding(.top, Space.l).padding(.bottom, Space.m)

            Label {
                Text(Names.text("STATEMENT", "No game file is ever changed.")).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.shield").foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
        .frame(width: 440)
        .onAppear { runner.refreshPreflight(fixes); runner.watchCaptureAge() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in runner.refreshPreflight(fixes) }
    }

    private var launchTitle: String {
        switch runner.state {
        case .launching, .preparing: return Names.text("UI_LAUNCHING", "Starting…")
        case .running, .captureAgeRunning: return Names.text("UI_RUNNING_BUTTON", "Running")
        default: return Names.text("UI_LAUNCH", "Launch")
        }
    }
}

// MARK: - Status card

struct StatusCard: View {
    let state: LaunchState
    let fixes: Fixes
    var captureAgeWindow = true
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            icon.font(.title2).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if !detail.isEmpty {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if let a = action {
                    Button(a.0, action: a.1).buttonStyle(.link).font(.callout).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .onChange(of: title) { _, new in
            AccessibilityNotification.Announcement(new).post()
        }
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .launching, .preparing: ProgressView().controlSize(.small).frame(height: 22)
        case .running: Image(systemName: "play.circle.fill").foregroundStyle(Color.trebuchet)
        case .captureAgeRunning: if captureAgeWindow { Image(systemName: "play.circle.fill").foregroundStyle(Color.trebuchet) } else { ProgressView().controlSize(.small).frame(height: 22) }
        case .fixOff, .fallback, .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .steamOffline: Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
        case .alreadyRunning: Image(systemName: "info.circle.fill").foregroundStyle(Color.trebuchet)
        case .noCrossOver, .notInstalled: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .notInApplications: Image(systemName: "arrow.down.app.fill").foregroundStyle(Color.trebuchet)
        case .noBottle: Image(systemName: "questionmark.folder.fill").foregroundStyle(.orange)
        }
    }

    private var summary: String {
        if fixes.plain { return Names.text("UI_SUMMARY_PLAIN", "All fixes off: plain CrossOver start.") }
        let c = fixes.counts
        let renderer = fixes.backendValue == .dxmt ? Names.fix("dxmt", "Metal Renderer") : fixes.backendValue.title
        return "\(c.on) of \(c.total) " + Names.text("UI_SUMMARY_FIXES", "fixes on") + " · " + renderer
    }

    private var title: String {
        switch state {
        case .ready: return Names.text("UI_READY", "Ready to launch")
        case .launching: return Names.text("UI_STARTING", "Starting…")
        case .preparing: return Names.text("UI_PREPARING_TITLE", "Getting ready")
        case .notInApplications: return Names.text("UI_MOVE_TITLE", "Move Trebuchet to Applications")
        case .running: return Names.text("UI_RUNNING", "Age of Empires II is running")
        case .captureAgeRunning: return captureAgeWindow ? Names.text("UI_CA_RUNNING", "CaptureAge is running") : Names.text("UI_CA_STARTING_TITLE", "Starting CaptureAge")
        case .fixOff: return Names.text("UI_FIXOFF", "One fix is off for this start")
        case .fallback: return Names.text("UI_FALLBACK", "Started without fixes")
        case .steamOffline: return Names.text("UI_STEAMOFFLINE", "Steam is offline")
        case .alreadyRunning: return Names.text("UI_ALREADY", "Age of Empires II is already running")
        case .failed: return Names.text("UI_FAILED", "The start did not complete")
        case .noCrossOver: return Names.text("UI_NOCROSSOVER", "CrossOver is not installed")
        case .notInstalled: return Names.text("UI_NOTINSTALLED", "Trebuchet's files are missing")
        case .noBottle: return Names.text("UI_NOBOTTLE", "No bottle with the game found")
        }
    }

    private var detail: String {
        switch state {
        case .ready: return summary
        case .launching(let l), .preparing(let l): return l
        case .notInApplications: return Names.text("UI_MOVE_DETAIL", "Drag Trebuchet from this window into your Applications folder, then open it from there.")
        case .running(let plain): return plain ? Names.text("UI_RUNNING_PLAIN", "Without fixes, like Steam's Play button.") : summary
        case .captureAgeRunning(let plain):
            if !captureAgeWindow { return Names.text("UI_CA_STARTING", "Starting CaptureAge… its window can take about a minute to appear.") }
            return plain ? Names.text("UI_CA_RUNNING_PLAIN", "Without fixes, like CrossOver's CaptureAge.")
                         : Names.text("UI_CA_RUNNING_DETAIL", "A game CaptureAge starts itself goes through Steam and runs without the fixes. Start the game with Launch first; CaptureAge then shows it with the fixes.")
        case .fixOff(let l), .steamOffline(let l): return l
        case .fallback(let l): return l.prefix(1).uppercased() + l.dropFirst()
        case .alreadyRunning: return Names.text("UI_ALREADY_DETAIL", "Switch to the game window to play.")
        case .failed(let l): return l.isEmpty ? Names.text("UI_FAILED_DETAIL", "The log has the details.") : l.prefix(1).uppercased() + l.dropFirst()
        case .noCrossOver: return Names.text("UI_NOCROSSOVER_DETAIL", "Trebuchet runs the game in CrossOver 26.")
        case .notInstalled: return Names.text("UI_NOTINSTALLED_DETAIL", "Download Trebuchet again from trebuchetapp.com.")
        case .noBottle: return Names.text("UI_NOBOTTLE_DETAIL", "Install Age of Empires II: DE from Steam in a CrossOver bottle.")
        }
    }

    private var action: (String, () -> Void)? {
        switch state {
        case .fixOff, .fallback, .failed: return (Names.text("UI_SHOWLOG", "Show Log"), openLogs)
        case .noCrossOver: return (Names.text("UI_GETCROSSOVER", "Get CrossOver"), { NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!) })
        case .notInstalled: return (Names.text("UI_SHOWFOLDER", "Show Folder"), { NSWorkspace.shared.open(Install.prefix.deletingLastPathComponent()) })
        case .noBottle: return (Names.text("UI_SETTINGS", "Settings…"), openSettings)
        case .notInApplications: return (Names.text("UI_SHOWAPPS", "Open Applications Folder"), { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) })
        default: return nil
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var fixes: Fixes
    @State private var tab = Demo.settingsTab ?? "fixes"
    var body: some View {
        TabView(selection: $tab) {
            FixesTab().tabItem { Label(Names.text("UI_TAB_FIXES", "Fixes"), systemImage: "wand.and.stars") }.tag("fixes")
            GraphicsTab().tabItem { Label(Names.text("UI_TAB_GRAPHICS", "Graphics"), systemImage: "display") }.tag("graphics")
            GameTab().tabItem { Label(Names.text("UI_TAB_GAME", "Game"), systemImage: "gamecontroller") }.tag("game")
        }
        .frame(width: 600)
    }
}

/// One fix: name, marker, measured gain, info popover, and its control.
struct FixRow: View {
    enum Control { case toggle(Binding<Bool>), alwaysOn, unavailable, offer }
    let id: String
    let fallbackName: String
    let control: Control
    @State private var showInfo = false

    private var name: String { Names.fix(id, fallbackName) }
    private var gain: String { Names.gain(id) }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                    if Names.marked(id) { Marker() }
                }
                if !gain.isEmpty {
                    Text(gain).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.m)
            if !Names.info(id).isEmpty {
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle").imageScale(.medium) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .focusEffectDisabled(Demo.active)
                    .help(Names.text("UI_MORE_ABOUT", "More about") + " " + name)
                    .accessibilityLabel(Text(Names.text("UI_MORE_ABOUT", "More about") + " " + name))
                    .popover(isPresented: $showInfo, arrowEdge: .trailing) { InfoPopover(id: id, name: name, gain: gain) }
                    .onAppear { if Demo.mode == "popover" && id == "reorder" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showInfo = true } } }
            }
            trailing.frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch control {
        case .toggle(let b):
            Toggle(name, isOn: b).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(Text(name)).accessibilityValue(Text(gain))
        case .alwaysOn:
            Text(Names.text("UI_ALWAYS_ON", "On")).font(.callout).foregroundStyle(.secondary)
        case .unavailable:
            Text(Names.text("UI_NOT_IN_INSTALL", "Not installed")).font(.callout).foregroundStyle(.tertiary)
        case .offer:
            Text(Names.text("UI_OFFER", "Optional")).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Marker: View {
    var body: some View {
        Image(systemName: "seal.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.trebuchet)
            .help(Names.text("LEGEND"))
            .accessibilityLabel(Text(Names.text("UI_MARKER", "Unique to Trebuchet")))
    }
}

struct InfoPopover: View {
    let id: String, name: String, gain: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 6) {
                Text(name).font(.headline)
                if Names.marked(id) { Marker() }
            }
            Text(Names.info(id)).fixedSize(horizontal: false, vertical: true)
            if !gain.isEmpty {
                Text(Names.text("UI_MEASURED", "Measured:") + " " + gain)
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if Names.marked(id) {
                Divider()
                Label { Text(Names.text("LEGEND")).fixedSize(horizontal: false, vertical: true) } icon: { Marker() }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

/// Always visible under the fix list: what is never changed, where the numbers come from, and the marker legend.
struct StatementFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if Names.anyMarked {
                Label { Text(Names.text("LEGEND")).fixedSize(horizontal: false, vertical: true) } icon: { Marker() }
            }
            Label { Text(Names.text("STATEMENT", "No game file is ever changed.")).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "checkmark.shield")
            }
            Text(Names.text("FOOTNOTE")).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FixesTab: View {
    @EnvironmentObject var fixes: Fixes
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: fixes.useFixes) {
                        Text(Names.text("UI_MASTER", "Use Trebuchet's fixes"))
                        Text(Names.text("UI_MASTER_FOOTER", "Off starts the game like Steam's Play button."))
                    }
                }
                Section(Names.text("UI_SEC_ALWAYS", "Always on")) {
                    FixRow(id: "parta", fallbackName: "Quick Traps", control: .alwaysOn)
                    FixRow(id: "rpath", fallbackName: "Renderer Guard", control: .alwaysOn)
                }.disabled(fixes.plain)
                Section {
                    ForEach(fixes.rules) { r in FixRow(id: r.id, fallbackName: r.name, control: .toggle(fixes.binding(r))) }
                } header: {
                    Text(Names.text("UI_SEC_RULES", "Tied to a game or macOS version"))
                } footer: {
                    Text(Names.text("UI_SEC_RULES_FOOTER", "These switch themselves off after an update they don't recognise, and tell you."))
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(fixes.plain)
                Section(Names.text("UI_SEC_OPTIONAL", "More fixes")) {
                    FixRow(id: "textfix", fallbackName: "Clear Menu Text", control: .toggle($fixes.textfix))
                        .disabled(fixes.backendValue != .dxmt)
                    FixRow(id: "msync", fallbackName: "Fast Sync", control: .toggle($fixes.msync))
                    if InstallParts.localCursor { FixRow(id: "t4", fallbackName: "Local Cursor", control: .toggle($fixes.t4)) }
                    if InstallParts.fastClock { FixRow(id: "fastqpc", fallbackName: "Fast Clock", control: .toggle($fixes.fastqpc)) }
                    // Modern C Runtime (UCRT): R1.1 download action; slot reserved here (control: .offer).
                }.disabled(fixes.plain)
            }
            .formStyle(.grouped)
            Divider()
            StatementFooter()
        }
        .frame(height: 900)   // fits every release row (incl. Lean Stack Check and Fast Clock) without scrolling
    }
}

struct GraphicsTab: View {
    @EnvironmentObject var fixes: Fixes
    var body: some View {
        Form {
            Section(Names.text("UI_SEC_RENDERER", "Renderer")) {
                FixRow(id: "dxmt", fallbackName: "Metal Renderer", control: .alwaysOn)
                Picker(Names.text("UI_BACKEND", "Graphics"), selection: $fixes.backend) {
                    ForEach(Backend.allCases) { b in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.title)
                            Text(b.caption).font(.caption).foregroundStyle(.secondary)
                        }.tag(b.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }.disabled(fixes.plain)
            Section(Names.text("UI_SEC_DISPLAY", "Display")) {
                Toggle(isOn: $fixes.hud) {
                    Text(Names.text("UI_HUD", "Show the Metal performance HUD"))
                    Text(Names.text("UI_HUD_FOOTER", "Frame rate and GPU time in the corner of the game window.")).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}

struct GameTab: View {
    @EnvironmentObject var fixes: Fixes
    var body: some View {
        let bottles = gameBottles()
        Form {
            Section {
                Picker(Names.text("UI_BOTTLE", "CrossOver bottle"), selection: $fixes.bottle) {
                    Text(Names.text("UI_AUTOMATIC", "Automatic") + (bottles.first.map { " (\($0))" } ?? "")).tag("")
                    ForEach(bottles, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                Text(bottles.isEmpty ? Names.text("UI_NOBOTTLE_DETAIL", "Install Age of Empires II: DE from Steam in a CrossOver bottle.")
                                     : Names.text("UI_BOTTLE_FOOTER", "Only bottles with Age of Empires II: DE from Steam are listed."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent(Names.text("UI_CROSSOVER", "CrossOver")) {
                    HStack {
                        Text(Install.crossOverApp.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button(Names.text("UI_CHOOSE", "Choose…")) { chooseCrossOver() }
                        if !fixes.crossOverPath.isEmpty { Button(Names.text("UI_DEFAULT", "Default")) { fixes.crossOverPath = "" } }
                    }
                }
            } footer: {
                Text(Names.text("UI_CROSSOVER_FOOTER", "Trebuchet reads CrossOver and never changes it.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField(Names.text("UI_ARGS", "Extra launch options"), text: $fixes.args, prompt: Text("SKIPINTRO"))
            } footer: {
                Text(Names.text("UI_ARGS_FOOTER", "For single-player tests only.")).font(.caption).foregroundStyle(.secondary)
            }
            if Install.managesPrefix {
                Section {
                    Button(Names.text("UI_RESET", "Reset Trebuchet…"), role: .destructive) { confirmReset = true }
                        .disabled(resetting)
                } footer: {
                    Text(Names.text("UI_RESET_FOOTER", "Removes Trebuchet's copy of CrossOver and its logs. Your CrossOver, your bottle and your game stay as they are. The next Launch prepares everything again. To uninstall, reset, then move Trebuchet to the Trash."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: Install.managesPrefix ? 470 : 300)
        .confirmationDialog(Names.text("UI_RESET_CONFIRM", "Reset Trebuchet?"), isPresented: $confirmReset) {
            Button(Names.text("UI_RESET_BUTTON", "Reset"), role: .destructive) {
                resetting = true
                do { try Prepare.reset() } catch { resetError = error.localizedDescription }
                resetting = false
            }
        } message: {
            Text(Install.prefix.path)
        }
        .alert(resetError ?? "", isPresented: Binding(get: { resetError != nil }, set: { if !$0 { resetError = nil } })) { Button("OK") {} }
    }

    @State private var confirmReset = false
    @State private var resetting = false
    @State private var resetError: String?

    private func chooseCrossOver() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.applicationBundle]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.message = Names.text("UI_CHOOSE_CROSSOVER", "Choose your CrossOver app")
        if p.runModal() == .OK, let u = p.url { fixes.crossOverPath = u.path }
    }
}

// MARK: - About

/// Hook for automatic updates (Sparkle in R1.1). R1: nothing is checked and no menu item is shown.
protocol UpdateChecker { func checkForUpdates() }
struct NoUpdates: UpdateChecker { func checkForUpdates() {} }

struct AboutView: View {
    @EnvironmentObject var fixes: Fixes
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0" }
    var body: some View {
        VStack(spacing: Space.s) {
            Image(nsImage: appIcon()).resizable().interpolation(.high).frame(width: 72, height: 72).accessibilityHidden(true)
            Text(Names.appName).font(.title.weight(.semibold))
            Text(Names.text("UI_VERSION", "Version") + " \(version) · " + Names.text("UI_RULESET", "rule set") + " \(fixes.pack)").font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(Names.text("TAGLINE", "Trebuchet. Bringing a classic to modern silicon."))
                .font(.body).multilineTextAlignment(.center).padding(.top, Space.xs)
            HStack(spacing: Space.s) {
                Button(Names.text("UI_WEBSITE", "Website")) { open("SITE_URL", "https://trebuchetapp.com") }
                Button(Names.text("UI_SOURCE", "Source Code")) { open("REPO_URL", "https://github.com/kyrios/TrebuchetApp") }
            }
            .padding(.top, Space.s)
            Button(Names.text("UI_LICENCES", "Licences and Notices…")) {
                if let n = Install.notice { NSWorkspace.shared.open(n) } else { open("REPO_URL", "https://github.com/kyrios/TrebuchetApp") }
            }
            .buttonStyle(.link).font(.callout).padding(.top, Space.xs)
            if Install.managesPrefix {
                HStack(spacing: Space.xs) {
                    Text(Names.text("UI_FILES_AT", "Files:")).foregroundStyle(.secondary)
                    Text(Install.prefix.path.replacingOccurrences(of: Install.home.path, with: "~"))
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button(Names.text("UI_SHOWINFINDER", "Show in Finder")) {
                        let fm = FileManager.default
                        NSWorkspace.shared.open(fm.fileExists(atPath: Install.prefix.path) ? Install.prefix : Install.prefix.deletingLastPathComponent())
                    }.buttonStyle(.link)
                }
                .font(.caption).padding(.top, Space.s)
            }
            Text(Names.text("UI_DISCLAIMER", "Not affiliated with or endorsed by Microsoft, World's Edge or Forgotten Empires. Age of Empires is a trademark of Microsoft."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.top, Space.m)
        }
        .padding(Space.xl)
        .frame(width: 380)
    }
    private func open(_ key: String, _ fallback: String) {
        if let u = URL(string: Names.text(key, fallback)) { NSWorkspace.shared.open(u) }
    }
}

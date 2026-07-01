import SwiftUI
import ServiceManagement

// MARK: - Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General",   systemImage: "gearshape") }
            TweaksTab()
                .tabItem { Label("Tweaks",    systemImage: "slider.horizontal.3") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            ToolsTab()
                .tabItem { Label("Tools",     systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540, height: 520)
    }
}

// MARK: - General

struct GeneralTab: View {
    @State private var extStatus: ExtStatus = .checking
    @State private var accessOK      = AXIsProcessTrusted()
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLoginItem($0) }
                if let err = loginError {
                    HintText(err).foregroundColor(.red)
                }
            } header: { SectionHeader("App") }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        Text(extStatus.label).foregroundColor(extStatus.color).font(.callout)
                        if extStatus == .disabled || extStatus == .registering {
                            Button("System Settings") { openExtSettings() }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Check Again") { checkExtStatus() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                switch extStatus {
                case .disabled:
                    HintText("System Settings → General → Login Items & Extensions → Finder Extensions → enable \"Handy Extension\".")
                case .registering:
                    HintText("macOS is registering the extension. Tap Check Again in a moment, or restart Handy.")
                default: EmptyView()
                }
            } header: { SectionHeader("Finder Extension") }

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        if accessOK {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.callout)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("Not granted").foregroundColor(.orange).font(.callout)
                            Button("Open Settings") { requestAccess() }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Check Again") { accessOK = AXIsProcessTrusted() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                if !accessOK {
                    HintText("""
                        1. Click "Open Settings" — this also registers the current Handy build with macOS.
                        2. Find Handy in the Accessibility list and toggle it on.
                        3. Already in the list but still "Not granted"? Click the − button to remove it, then click "Open Settings" again.
                        """)
                }
            } header: { SectionHeader("Permissions") }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            checkExtStatus()
            accessOK = AXIsProcessTrusted()
            // Poll so the badge flips to green as soon as the user grants access
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                let trusted = AXIsProcessTrusted()
                if trusted != accessOK { accessOK = trusted }
                if trusted { EventTap.shared.startIfPermitted() }
            }
        }
    }

    // MARK: Helpers

    private func checkExtStatus() {
        extStatus = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            forceRegisterExtension()
            let out    = pluginkitQuery()
            let inApps = Bundle.main.bundlePath.hasPrefix("/Applications/")
            DispatchQueue.main.async {
                if out.contains("+")      { extStatus = .active      }
                else if out.contains("-") { extStatus = .disabled    }
                else if inApps            { extStatus = .registering }
                else                      { extStatus = .missing     }
            }
        }
    }

    private func requestAccess() {
        // AXIsProcessTrustedWithOptions(prompt:true) registers THIS binary's code
        // signature with macOS. Without this call, manually toggling in System
        // Settings can link the permission to a stale binary hash from a prior build.
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        // Also navigate directly to the Accessibility pane
        for raw in [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ] {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    private func applyLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register()   }
            else  { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = !on
        }
    }

    private func openExtSettings() {
        for raw in [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general",
        ] {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Tweaks

struct TweaksTab: View {
    @AppStorage("kb.cutPaste")        var cutPaste        = false
    @AppStorage("kb.returnToOpen")    var returnToOpen    = false
    @AppStorage("feature.btOffOnSleep") var btOffOnSleep  = false
    @State private var keepAwake     = KeepAwake.shared.isActive
    @State private var hiddenFiles   = false
    @State private var accessOK      = AXIsProcessTrusted()
    @State private var tapRunning    = EventTap.shared.isRunning
    @State private var automationOK: Bool? = nil  // nil = not yet checked

    var body: some View {
        Form {
            // ── Finder ───────────────────────────────────────────────────────
            Section {
                kbRow("Cut & Paste Files", icon: "scissors",
                      detail: "Cmd+X marks files for move; Cmd+V in another folder moves them",
                      binding: $cutPaste)
                kbRow("Open Files with Return", icon: "return",
                      detail: "Return opens selected items; Shift+Return to rename",
                      binding: $returnToOpen)
                staticRow("Copy Path",        icon: "doc.on.clipboard", detail: "Right-click any file → Copy Path")
                staticRow("Open in Terminal", icon: "terminal",          detail: "Right-click any folder → Open in Terminal (iTerm2 if installed)")
                staticRow("New .txt File Here", icon: "doc.badge.plus", detail: "Right-click empty folder space → New .txt File Here")
                comingSoonRow("Delete Immediately", icon: "trash",       detail: "Delete without going to Trash")
                if accessOK {
                    // Tap status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tapRunning ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(tapRunning
                            ? "Keyboard tap active"
                            : "Keyboard tap starting… (up to 3 s after launch)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.top, 2)

                    // Finder Automation status — required for Cmd+X to see selected files
                    if let autoOK = automationOK {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(autoOK ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            if autoOK {
                                Text("Finder automation: granted")
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("Finder automation: denied — Cmd+X can't see selected files")
                                    .font(.caption).foregroundColor(.red)
                                Button("Open Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.mini)
                                Button("Test Again") { checkAutomation() }
                                    .buttonStyle(.bordered).controlSize(.mini)
                            }
                        }
                    } else if cutPaste || returnToOpen {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Checking Finder automation…")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            } header: { SectionHeader("Finder") }

            // ── System ───────────────────────────────────────────────────────
            Section {
                HStack {
                    Label {
                        twRow("Keep Awake",
                              detail: keepAwake ? "Screen and system stay on" : "Normal sleep behavior")
                    } icon: {
                        Image(systemName: keepAwake ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(keepAwake ? .yellow : .secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $keepAwake).labelsHidden()
                        .onChange(of: keepAwake) { on in on ? KeepAwake.shared.enable() : KeepAwake.shared.disable() }
                }
                HStack {
                    Label {
                        twRow("Bluetooth off when sleeping",
                              detail: btOffOnSleep
                                ? "Bluetooth turns off on sleep, back on when you wake"
                                : "Bluetooth stays on during sleep")
                    } icon: {
                        Image(systemName: "bluetooth")
                            .foregroundColor(btOffOnSleep ? .blue : .secondary)
                    }
                    Spacer()
                    if BluetoothManager.shared.isAvailable {
                        Toggle("", isOn: $btOffOnSleep).labelsHidden()
                            .onChange(of: btOffOnSleep) { BluetoothSleepFeature.shared.isEnabled = $0 }
                    } else {
                        Text("Not available").font(.caption).foregroundColor(.secondary)
                    }
                }
                HStack {
                    Label {
                        twRow("Show Hidden Files",
                              detail: hiddenFiles ? "Dotfiles visible in Finder" : "Dotfiles hidden")
                    } icon: { Image(systemName: hiddenFiles ? "eye" : "eye.slash") }
                    Spacer()
                    Toggle("", isOn: $hiddenFiles).labelsHidden()
                        .onChange(of: hiddenFiles) { applyHiddenFiles($0) }
                }
                HStack {
                    Label {
                        twRow("Dark Mode", detail: "Toggle system-wide appearance")
                    } icon: { Image(systemName: "circle.lefthalf.filled") }
                    Spacer()
                    Button("Toggle") { toggleDarkMode() }.buttonStyle(.bordered)
                }
            } header: { SectionHeader("System") }
        }
        .formStyle(.grouped)
        .onAppear {
            hiddenFiles = UserDefaults(suiteName: "com.apple.finder")?
                .bool(forKey: "AppleShowAllFiles") ?? false
            accessOK   = AXIsProcessTrusted()
            tapRunning = EventTap.shared.isRunning
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                accessOK   = AXIsProcessTrusted()
                tapRunning = EventTap.shared.isRunning
            }
            if cutPaste || returnToOpen { checkAutomation() }
        }
        .onChange(of: cutPaste) { newValue in
            syncEventTap()
            if newValue { checkAutomation() }
        }
        .onChange(of: returnToOpen) { newValue in
            syncEventTap()
            if newValue { checkAutomation() }
        }
    }

    // MARK: Row builders

    @ViewBuilder
    private func kbRow(_ title: String, icon: String, detail: String,
                       binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                        if !accessOK {
                            Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Text(accessOK ? detail : "\(detail) — grant Accessibility on the General tab")
                        .font(.caption).foregroundColor(.secondary)
                }
            } icon: { Image(systemName: icon) }
        }
        .disabled(!accessOK)
    }

    @ViewBuilder
    private func staticRow(_ title: String, icon: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    Text("Right-click")
                        .font(.caption2).fontWeight(.medium)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundColor(.accentColor)
                }
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        } icon: { Image(systemName: icon) }
    }

    @ViewBuilder
    private func comingSoonRow(_ title: String, icon: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).foregroundColor(.secondary)
                    Text("Soon")
                        .font(.caption2).fontWeight(.medium)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                }
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        } icon: { Image(systemName: icon).foregroundColor(.secondary) }
    }

    @ViewBuilder
    private func twRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: Actions

    private func syncEventTap() {
        if cutPaste || returnToOpen { EventTap.shared.startIfPermitted() }
        else { EventTap.shared.stop() }
    }

    private func checkAutomation() {
        automationOK = nil  // show spinner while checking
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppleScriptRunner.shared.run("tell application \"Finder\" to get name")
            let ok = result.descriptor != nil && result.error == nil
            DispatchQueue.main.async { automationOK = ok }
        }
    }

    private func applyHiddenFiles(_ on: Bool) {
        let ud = UserDefaults(suiteName: "com.apple.finder")
        ud?.set(on, forKey: "AppleShowAllFiles"); ud?.synchronize()
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        t.arguments = ["Finder"]
        try? t.run()
    }

    private func toggleDarkMode() {
        DispatchQueue.global(qos: .userInitiated).async {
            AppleScriptRunner.shared.run(
                "tell app \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        }
    }
}

// MARK: - Shortcuts (placeholder)

struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                HintText("Global shortcuts to toggle features — coming soon. For now, use the quick toggles in the menu bar.")
            } header: { SectionHeader("Coming Soon") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tools

struct ToolsTab: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Empty Trash")
                            Text("Permanently delete all items in the Trash")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } icon: { Image(systemName: "trash") }
                    Spacer()
                    Button("Empty\u{2026}") { emptyTrash() }.buttonStyle(.bordered).tint(.red)
                }
            } header: { SectionHeader("Maintenance") }
        }
        .formStyle(.grouped)
    }

    private func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Deleted items cannot be recovered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Let Finder do it: handles dotfiles, external-volume trashes, and
        // shows its own progress UI — unlike a raw `rm -rf ~/.Trash/*`.
        DispatchQueue.global(qos: .userInitiated).async {
            AppleScriptRunner.shared.run("tell application \"Finder\" to empty trash")
        }
    }
}

// MARK: - Reusable components

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.headline).textCase(nil)
    }
}

struct HintText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Extension status model

enum ExtStatus: Equatable {
    case checking, active, disabled, missing, registering
    var label: String {
        switch self {
        case .checking:    return "Checking\u{2026}"
        case .active:      return "\u{2713}  Active \u{2014} right-click any .zip to use"
        case .disabled:    return "\u{2717}  Disabled \u{2014} enable in System Settings"
        case .missing:     return "\u{26A0}  Move Handy.app to /Applications first"
        case .registering: return "\u{231B}  Almost there \u{2014} tap Check Again"
        }
    }
    var color: Color {
        switch self {
        case .active:               return .green
        case .disabled, .missing:   return .red
        case .registering:          return .orange
        case .checking:             return .secondary
        }
    }
}

// MARK: - Shared utility

func pluginkitQuery() -> String {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    t.arguments = ["-m", "-i", "com.lonfeng.handy.extension"]
    let pipe = Pipe()
    t.standardOutput = pipe; t.standardError = Pipe()
    try? t.run(); t.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

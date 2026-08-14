import SwiftUI
import AppKit
import Carbon
import UniformTypeIdentifiers
import Utils

// Helpers
func getModifierString(for modifiers: UInt64) -> String {
    var str = ""
    let flags = CGEventFlags(rawValue: modifiers)
    if flags.contains(.maskControl) { str += "⌃" }
    if flags.contains(.maskAlternate) { str += "⌥" }
    if flags.contains(.maskShift) { str += "⇧" }
    if flags.contains(.maskCommand) { str += "⌘" }
    return str
}

func getKeyString(for key: UInt16) -> String {
    switch key {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 53: return "Esc"
    case 51: return "Delete"
    case 57: return "Caps Lock"
    case 123: return "Left"
    case 124: return "Right"
    case 125: return "Down"
    case 126: return "Up"
    default:
        if let char = KeyCodeMapping.characterForKeyCode(key)?.uppercased(), !char.isEmpty {
            return char
        }
        return "Key \(key)"
    }
}

class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin: Bool = PreferencesManager.shared.launchAtLogin {
        didSet { PreferencesManager.shared.launchAtLogin = launchAtLogin }
    }
    
    @Published var correctionMode: CorrectionMode = PreferencesManager.shared.correctionMode {
        didSet { PreferencesManager.shared.correctionMode = correctionMode }
    }
    
    @Published var hotkeyKeyCode: UInt16 = PreferencesManager.shared.hotkeyKeyCode {
        didSet { PreferencesManager.shared.hotkeyKeyCode = hotkeyKeyCode }
    }
    
    @Published var hotkeyModifiers: UInt64 = PreferencesManager.shared.hotkeyModifiers {
        didSet { PreferencesManager.shared.hotkeyModifiers = hotkeyModifiers }
    }
    
    @Published var revertHotkeyKeyCode: UInt16 = PreferencesManager.shared.revertHotkeyKeyCode {
        didSet { PreferencesManager.shared.revertHotkeyKeyCode = revertHotkeyKeyCode }
    }
    
    @Published var revertHotkeyModifiers: UInt64 = PreferencesManager.shared.revertHotkeyModifiers {
        didSet { PreferencesManager.shared.revertHotkeyModifiers = revertHotkeyModifiers }
    }

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(syncFromPreferences), name: .preferencesDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func syncFromPreferences() {
        // Sync back only if different to avoid loops
        if self.correctionMode != PreferencesManager.shared.correctionMode {
            self.correctionMode = PreferencesManager.shared.correctionMode
        }
        // ... extend for others if needed, but mainly Mode is likely to change externally via Menu
    }
}

class RecorderState: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    deinit {
        stop()
    }

    func start(completion: @escaping (UInt16, UInt64) -> Void) {
        stop()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Handle CapsLock specifically
            if event.type == .flagsChanged && event.keyCode == 57 {
                completion(57, 0)
                self.stop()
                return nil
            }
            // Pass through other modifier transitions so app-wide modifier state stays intact.
            if event.type == .flagsChanged {
                return event
            }

            if event.type == .keyDown {
                if event.keyCode == 53 { // ESC
                    self.stop()
                    return nil
                }
                
                var flags: UInt64 = 0
                if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
                if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
                if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
                if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
                
                completion(event.keyCode, flags)
                self.stop()
                return nil
            }
            
            return nil
        }
    }
    
    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
    }
}

struct HotkeyRecorder: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    @StateObject private var recorder = RecorderState()
    
    var displayText: String {
        if recorder.isRecording {
            return "Type Key..."
        }
        let modStr = getModifierString(for: modifiers)
        let keyStr = getKeyString(for: keyCode)
        return modStr + keyStr
    }
    
    var body: some View {
        Button(action: {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start { newKey, newMods in
                    self.keyCode = newKey
                    self.modifiers = newMods
                }
            }
        }) {
            Text(displayText)
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(recorder.isRecording ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(recorder.isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ExcludedAppRow: Identifiable, Hashable {
    let id: String // bundle identifier
    let name: String
    let icon: NSImage?
}

class ExclusionsViewModel: ObservableObject {
    @Published var apps: [ExcludedAppRow] = []
    @Published var selection: Set<String> = []
    @Published var runningApps: [ExcludedAppRow] = []
    @Published var showingRunningAppsPicker = false

    init() {
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .appFilterDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func reload() {
        apps = AppFilter.shared.allBlacklisted.map { bundleID -> ExcludedAppRow in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            return ExcludedAppRow(id: bundleID, name: name, icon: icon)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Drop selections that no longer exist (e.g. removed via the menu-bar toggle).
        selection.formIntersection(apps.map { $0.id })
    }

    /// Refreshes the list of currently running apps eligible to be added (excludes ones already excluded and SwitchFix itself).
    func refreshRunningApps() {
        let alreadyExcluded = Set(apps.map { $0.id })
        let ownBundleID = Bundle.main.bundleIdentifier

        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ExcludedAppRow? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != ownBundleID,
                      !alreadyExcluded.contains(bundleID) else { return nil }
                return ExcludedAppRow(id: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addBundleIDs<S: Sequence>(_ bundleIDs: S) where S.Element == String {
        for bundleID in bundleIDs {
            AppFilter.shared.addToBlacklist(bundleID)
        }
        reload()
    }

    /// Presents an Open panel (defaulting to /Applications, but browsable anywhere) to pick app bundles.
    func addAppFromFileSystem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Non-blocking: runModal() would spin a modal session on the main run loop
        // and steal frontmost-app focus from the capture pipeline.
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.addBundleIDs(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }

    func removeSelected() {
        for bundleID in selection {
            AppFilter.shared.removeFromBlacklist(bundleID)
        }
        selection.removeAll()
        reload()
    }
}

struct RunningAppPickerView: View {
    @ObservedObject var model: ExclusionsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Running Apps").font(.headline)

            if model.runningApps.isEmpty {
                Text("All running apps are already excluded.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(width: 360, height: 260, alignment: .center)
            } else {
                List(model.runningApps, selection: $selection) { app in
                    HStack(spacing: 6) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                    }
                    .tag(app.id)
                }
                .frame(width: 360, height: 260)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    model.addBundleIDs(selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
    }
}

struct ExcludedAppsView: View {
    @StateObject private var model = ExclusionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Excluded Apps").font(.headline)
            Text("SwitchFix won't correct text while these apps are active.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                List(model.apps, selection: $model.selection) { app in
                    HStack(spacing: 6) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                        Spacer()
                        Text(app.id)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(app.id)
                }
                .frame(height: 140)

                Divider()

                HStack(spacing: 0) {
                    Menu {
                        Button("Choose from Running Apps…") {
                            model.refreshRunningApps()
                            model.showingRunningAppsPicker = true
                        }
                        Button("Choose from Applications Folder…") {
                            model.addAppFromFileSystem()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Divider().frame(height: 12)

                    Button(action: model.removeSelected) {
                        Image(systemName: "minus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selection.isEmpty)

                    Spacer()
                }
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .sheet(isPresented: $model.showingRunningAppsPicker) {
            RunningAppPickerView(model: model)
        }
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()

    private var correctionModeDescription: String {
        switch model.correctionMode {
        case .automatic:
            return "Auto-corrects on word boundaries (space, enter)."
        case .hotkey:
            return "Corrects only when triggered via hotkey."
        case .layoutSwitch:
            return "Corrects the current word (or selection) when you switch the system keyboard layout."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            
            // GENERAL
            VStack(alignment: .leading, spacing: 8) {
                Text("General").font(.headline)
                Toggle("Launch at Login", isOn: $model.launchAtLogin)
            }
            
            Divider()
            
            // CORRECTION MODE
            VStack(alignment: .leading, spacing: 12) {
                Text("Correction Mode").font(.headline)
                
                Picker("", selection: $model.correctionMode) {
                    Text("Automatic (Space / Enter)").tag(CorrectionMode.automatic)
                    Text("Hotkey Only").tag(CorrectionMode.hotkey)
                    Text("On Layout Switch").tag(CorrectionMode.layoutSwitch)
                }
                .pickerStyle(RadioGroupPickerStyle())
                
                Text(correctionModeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // SHORTCUTS
            VStack(alignment: .leading, spacing: 16) {
                Text("Shortcuts").font(.headline)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text("Trigger Correction:")
                            .gridColumnAlignment(.trailing)
                        HotkeyRecorder(
                            keyCode: $model.hotkeyKeyCode,
                            modifiers: $model.hotkeyModifiers
                        )
                    }
                    
                    GridRow {
                        Text("Revert Last:")
                        HotkeyRecorder(
                            keyCode: $model.revertHotkeyKeyCode,
                            modifiers: $model.revertHotkeyModifiers
                        )
                    }
                }
                
                Text("Recommended: Set 'Revert Last' to Caps Lock to avoid conflicts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // EXCLUDED APPS
            ExcludedAppsView()

            Spacer()
        }
        .padding(30)
        .frame(width: 480, height: 700)
    }
}

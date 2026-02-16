import SwiftUI
import AppKit
import Carbon
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

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    
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
                }
                .pickerStyle(RadioGroupPickerStyle())
                
                Text(model.correctionMode == .automatic
                     ? "Auto-corrects on word boundaries (space, enter)."
                     : "Corrects only when triggered via hotkey.")
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
            
            Spacer()
        }
        .padding(30)
        .frame(width: 480, height: 500)
    }
}

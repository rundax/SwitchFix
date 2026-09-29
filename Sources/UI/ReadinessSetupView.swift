import AppKit
import Core
import SwiftUI
import Utils

public struct ReadinessSetupView: View {
    @ObservedObject private var store = ReadinessStore.shared
    private let compact: Bool
    @State private var settingsError: String?
    @State private var diagnosticsCopied = false
    @State private var exerciseText = ""
    @State private var exerciseMessage: String?
    @State private var exerciseActive = false
    @FocusState private var exerciseFocused: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    private var snapshot: RuntimeReadinessSnapshot { store.snapshot }
    private var canExercise: Bool {
        snapshot.canTryCorrection &&
            snapshot.installedLayouts.isSuperset(of: [.english, .russian]) &&
            snapshot.dictionaryLayouts.isSuperset(of: [.english, .russian])
    }
    private var exerciseInstructions: String {
        switch snapshot.mode {
        case .automatic:
            return "Select Russian, press the keys for hello, then press Space. SwitchFix should replace the Russian text with hello."
        case .hotkey:
            let preferences = PreferencesManager.shared
            let shortcut = getModifierString(for: preferences.hotkeyModifiers) + getKeyString(for: preferences.hotkeyKeyCode)
            return "Select Russian, press the keys for hello, then press \(shortcut). SwitchFix should replace the Russian text with hello."
        case .layoutSwitch:
            return "Select Russian, press the keys for hello, then switch the input source to English. SwitchFix should replace the Russian text with hello."
        }
    }

    public var body: some View {
        Group {
            if compact {
                setupContent
            } else {
                ScrollView {
                    setupContent
                        .padding(24)
                }
                .frame(minWidth: 480, idealWidth: 520)
            }
        }
        .onAppear { store.refresh() }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text(compact ? "SwitchFix status" : "Finish setting up SwitchFix")
                .font(.title2.weight(.semibold))
            Text(compact
                 ? snapshot.message
                 : "Grant each permission below in System Settings, then return here. SwitchFix checks access automatically and will guide you through a typing test.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "Accessibility",
                granted: snapshot.accessibilityGranted,
                explanation: "Allows SwitchFix to replace text and switch layouts.",
                open: openAccessibility
            )
            permissionRow(
                title: "Input Monitoring",
                granted: snapshot.inputMonitoringGranted,
                explanation: "Allows SwitchFix to detect keyboard input.",
                open: openInputMonitoring
            )

            if !snapshot.accessibilityGranted || !snapshot.inputMonitoringGranted {
                Label {
                    Text("After an update, System Settings can show an old SwitchFix entry as enabled while this copy still lacks access. Use Open Settings + Show App to open the right pane and reveal this copy in Finder. In each affected pane, select the old entry, click −, then click + and add the Finder-selected SwitchFix.app.")
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !snapshot.postingGranted && snapshot.checked {
                Label("Text replacement access is unavailable. Check Accessibility, then restart SwitchFix if it remains unavailable.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if snapshot.checked && snapshot.accessibilityGranted && snapshot.inputMonitoringGranted {
                Label(snapshot.message, systemImage: snapshot.status == .working ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let settingsError {
                Text(settingsError).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button("Check Again") { store.refresh(retry: true) }
                Button("Show SwitchFix in Finder") { revealCurrentAppInFinder() }
            }
            if snapshot.accessibilityGranted && snapshot.inputMonitoringGranted &&
                (!snapshot.postingGranted || snapshot.monitor != .active) {
                Button("Restart SwitchFix") { restartSwitchFix() }
            }

            DisclosureGroup("Manual steps") {
                Text("For Accessibility and Input Monitoring, select the current SwitchFix entry and enable it. If an old entry is checked but SwitchFix still says Not allowed, select the old row and click −, then click + and choose SwitchFix.app from Applications. The Open Settings buttons reveal the installed app in Finder. Return here and select Check Again. If an older installer added a separate SwitchFix login item, remove it in General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Try a correction").font(.headline)
                    Spacer()
                    Button("Start") { startExercise() }
                        .disabled(!canExercise)
                }
                Text(exerciseInstructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if exerciseActive {
                    TextField("Type the example here", text: $exerciseText)
                        .textFieldStyle(.roundedBorder)
                        .focused($exerciseFocused)
                        .onReceive(NotificationCenter.default.publisher(for: .switchFixCorrectionApplied)) { note in
                            guard let pid = note.userInfo?["pid"] as? Int32,
                                  pid == ProcessInfo.processInfo.processIdentifier else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                let expected = snapshot.mode == .automatic ? "hello " : "hello"
                                if exerciseText == expected {
                                    exerciseMessage = "Confirmed: the test field contains the corrected text."
                                } else {
                                    exerciseMessage = "SwitchFix attempted a correction, but the test field did not confirm the expected text."
                                }
                            }
                        }
                    if let exerciseMessage {
                        Text(exerciseMessage)
                            .font(.caption)
                            .foregroundStyle(exerciseMessage.hasPrefix("Confirmed") ? .green : .orange)
                    }
                } else if !canExercise {
                    Text("This check needs working access and English and Russian layouts with their dictionaries ready.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(diagnosticsCopied ? "Diagnostics copied" : "Copy diagnostics") {
                    copyDiagnostics()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, explanation: String, open: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).fontWeight(.medium)
                    Spacer()
                    Text(granted ? "Allowed" : "Not allowed")
                        .foregroundStyle(.secondary)
                }
                Text(explanation).font(.caption).foregroundStyle(.secondary)
                if !granted {
                    Button("Open Settings + Show App") { open() }
                        .buttonStyle(.link)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openAccessibility() {
        if !snapshot.accessibilityGranted { Permissions.requestAccessibility() }
        if !Permissions.openAccessibilitySettings() {
            settingsError = "System Settings could not be opened. Open System Settings > Privacy & Security > Accessibility manually."
        } else {
            settingsError = nil
            revealCurrentAppInFinder()
        }
        store.refresh()
    }

    private func openInputMonitoring() {
        if !snapshot.inputMonitoringGranted { _ = Permissions.requestInputMonitoring() }
        if !Permissions.openInputMonitoringSettings() {
            settingsError = "System Settings could not be opened. Open System Settings > Privacy & Security > Input Monitoring manually."
        } else {
            settingsError = nil
            revealCurrentAppInFinder()
        }
        store.refresh()
    }

    private func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func startExercise() {
        exerciseText = ""
        let waiting = "Select Russian and enter the example to check correction."
        exerciseMessage = waiting
        exerciseActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exerciseFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            guard exerciseActive, exerciseMessage == waiting else { return }
            exerciseMessage = "No correction was observed. \(snapshot.message) Check the selected layout and mode, then try again or copy diagnostics."
        }
    }

    private func restartSwitchFix() {
        let launch = Process()
        launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-n", Bundle.main.bundleURL.path]
        launch.standardOutput = FileHandle.nullDevice
        launch.standardError = FileHandle.nullDevice
        do {
            try launch.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { NSApp.terminate(nil) }
        } catch {
            settingsError = "SwitchFix could not restart. Quit and reopen it from Applications."
        }
    }

    private func copyDiagnostics() {
        let signing = signatureDetails()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let lines = [
            "SwitchFix \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(hostArchitecture)",
            "App path: \(Bundle.main.bundleURL.path)",
            "Signing: \(signing)",
            "Accessibility: \(snapshot.accessibilityGranted)",
            "Input Monitoring: \(snapshot.inputMonitoringGranted)",
            "Event posting: \(snapshot.postingGranted)",
            "Monitor: \(snapshot.monitor.rawValue)",
            "Installed layouts: \(snapshot.installedLayouts.map(\.rawValue).sorted().joined(separator: ", "))",
            "Dictionary layouts: \(snapshot.dictionaryLayouts.map(\.rawValue).sorted().joined(separator: ", "))",
            "Mode: \(snapshot.modeName)",
            "Runtime status: \(snapshot.message)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        diagnosticsCopied = true
    }

    private var hostArchitecture: String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }
        return value == 1 ? "arm64" : "x86_64"
    }

    private func signatureDetails() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", Bundle.main.bundleURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let details = String(decoding: data, as: UTF8.self).split(separator: "\n").filter {
                $0.hasPrefix("Identifier=") || $0.hasPrefix("TeamIdentifier=") || $0.hasPrefix("Authority=") || $0.hasPrefix("Runtime Version=")
            }
            return details.joined(separator: "; ").replacingOccurrences(of: "Executable=", with: "")
        } catch {
            return "unavailable"
        }
    }
}

# Feature Plan: Per-App Default Language / Layout Switching

> **Status**: ✅ Approved / Ready for Implementation (Council Reviewed)  
> **Priority**: High  
> **Date created**: 2026-09-01 (Amended: 2026-09-01)  
> **Target Module**: `Core`, `UI`, `SwitchFixApp`, `TestRunner`  
> **Plan ID**: `004_per_app_default_language`

---

## 1. Context & Motivation

SwitchFix currently operates primarily as a reactive keyboard layout detector and text corrector. When users type in the wrong layout, SwitchFix automatically detects the mistake and fixes both the typed text and the active system keyboard layout.

However, many users work across multilingual contexts where specific applications have distinct language expectations:
- **Messengers & Chat Apps** (e.g., Telegram, Slack, WhatsApp, Messages) are predominantly used in the user's native language (e.g., **Ukrainian**).
- **Browsers & Dev Tools** (e.g., Arc, Chrome, Terminal, VS Code) are predominantly used in **English**.
- **Email Clients & Note Apps** (e.g., Apple Mail, Obsidian, Notion) often follow specific language workflows.

Currently, when users switch between Telegram and Arc, they must manually press hotkeys or rely on typing and auto-correction. Adding **Per-App Default Language** enables SwitchFix to automatically switch the macOS keyboard layout as soon as a target application gains focus, creating a seamless multilingual experience.

---

## 2. Goals & Non-Goals

### Goals
1. **Per-App Language Rules**: Allow users to assign a default keyboard layout (e.g., *English*, *Ukrainian*, *Russian*) to any installed application by its Bundle Identifier.
2. **Proactive Layout Switching**: When an application with a configured rule becomes frontmost, automatically switch macOS to that layout via `InputSourceManager`.
3. **Settings UI**: Add a clean, native SwiftUI configuration section in the Settings window with:
   - List of configured apps showing App Icon, App Name, Bundle ID, and a Language Picker dropdown.
   - Add button (`+`) with options: "Choose from Running Apps…" and "Choose from Applications Folder…".
   - Remove button (`-`) to delete rules.
   - Full scrollability to prevent clipping alongside the Excluded Apps section.
4. **Status Bar Menu Integration**: Provide a fast contextual submenu in the Menu Bar item to view or change the default language for the currently active app without opening Settings.
5. **Zero-Lag & Pipeline Safety**: Ensure automatic layout switching on app activation does not interfere with the zero-lag event tap, does not corrupt detector state, and does not trigger spurious text corrections.
6. **Persistence & Thread-Safety**: Persist all rules in `UserDefaults` with atomic, lock-protected in-memory caching (`OSAllocatedUnfairLock`).

### Non-Goals (for this phase)
1. Window-specific or tab-specific rules within the same application (macOS accessibility limits make per-app bundle ID the standard and robust scope).
2. Modifying native macOS input sources beyond existing supported layouts (`Layout.english`, `Layout.ukrainian`, `Layout.russian`).

---

## 3. Architecture & Data Design

```
+-------------------------------------------------------------------------+
|                              Settings UI                                |
|       (SettingsView -> AppDefaultLanguagesView -> AppPickerView)        |
+------------------------------------+------------------------------------+
                                     |
                                     v (Modifies rules)
+------------------------------------+------------------------------------+
|               PerAppLanguageManager (Sources/Core)                      |
|   - Thread-safe storage: OSAllocatedUnfairLock<[String: Layout]>        |
|   - Persistence: UserDefaults ("SwitchFix_perAppDefaultLanguages")      |
|   - Notifications: .perAppLanguageDidChange                             |
+------------------------------------+------------------------------------+
                                     |
                                     v (Queried on app activation)
+------------------------------------+------------------------------------+
|                           AppDelegate                                   |
|   - NSWorkspace.didActivateApplicationNotification                      |
|   - Checks: activationPolicy == .regular && bundleID != ownBundleID     |
|   - Checks: newBundleID != previousBundleID (prevents intra-app reset)  |
|   - Checks: PerAppLanguageManager.shared.defaultLayout(for: bundleID)   |
+------------------------------------+------------------------------------+
                                     |
                                     v (If target layout != current layout)
+------------------------------------+------------------------------------+
|                       InputSourceManager                                |
|   - TISSelectInputSource(preferredSources[targetLayout])                |
|   - Sets pendingSelectionID to prevent false autocorrection             |
+-------------------------------------------------------------------------+
```

### 3.1 Data Model: `PerAppLanguageManager`

**Location:** `Sources/Core/PerAppLanguageManager.swift`  
*(Note: Placed in `Core` because `Layout` is defined in `Core`, preserving `Utils` as a zero-dependency foundational module).*

```swift
import Foundation
import os
import Utils

public final class PerAppLanguageManager {
    public static let shared = PerAppLanguageManager()

    private let defaults = UserDefaults.standard
    private static let storageKey = "SwitchFix_perAppDefaultLanguages"

    private struct State {
        /// Map of bundle identifier -> Layout
        var rules: [String: Layout]
    }

    private let state: OSAllocatedUnfairLock<State>

    private init() {
        let rawDict = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        let initialRules = rawDict.compactMapValues { Layout(rawValue: $0) }
        self.state = OSAllocatedUnfairLock(initialState: State(rules: initialRules))
    }

    public func defaultLayout(for bundleID: String) -> Layout? {
        state.withLock { $0.rules[bundleID] }
    }

    public func setDefaultLayout(_ layout: Layout?, for bundleID: String) {
        let snapshot = state.withLock { state -> [String: Layout] in
            if let layout = layout {
                state.rules[bundleID] = layout
            } else {
                state.rules.removeValue(forKey: bundleID)
            }
            return state.rules
        }
        save(snapshot)
        NotificationCenter.default.post(name: .perAppLanguageDidChange, object: nil)
    }

    public func removeDefaultLayout(for bundleID: String) {
        setDefaultLayout(nil, for: bundleID)
    }

    public var allRules: [(bundleID: String, layout: Layout)] {
        state.withLock {
            $0.rules.map { (bundleID: $0.key, layout: $0.value) }
                .sorted { $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending }
        }
    }

    private func save(_ rules: [String: Layout]) {
        let rawDict = rules.mapValues { $0.rawValue }
        defaults.set(rawDict, forKey: Self.storageKey)
    }
}

public extension Notification.Name {
    static let perAppLanguageDidChange = Notification.Name("SwitchFix_PerAppLanguageDidChange")
}
```

### 3.2 App Activation Flow (`AppDelegate.swift`)

When an application is activated (`NSWorkspace.didActivateApplicationNotification`):
1. Receive `NSRunningApplication` and extract its `bundleIdentifier`.
2. **Pre-Conditions & Guards**:
   - Guard `application.activationPolicy == .regular` (ignore background helpers, ScreenSaver, LoginWindow, Spotlight overlays).
   - Guard `bundleID != Bundle.main.bundleIdentifier` (never apply rules to SwitchFix itself).
   - Guard `bundleID != previousBundleID` (**Intra-app protection**: if the user switches windows within Telegram or clicks Telegram again after a brief system event, do *not* clobber the user's manual in-session layout changes).
3. **Rule Lookup & Switching**:
   - Update `previousBundleID = bundleID`.
   - Check if a rule exists: `guard let targetLayout = PerAppLanguageManager.shared.defaultLayout(for: bundleID)`.
   - Check current layout: `let currentLayout = inputSourceManager.currentLayout()`.
   - If `currentLayout != targetLayout`:
     - Call `inputSourceManager.switchTo(targetLayout)`.
     - `switchTo` sets `pendingSelectionID` so that the asynchronous `kTISNotifySelectedKeyboardInputSourceChanged` notification treats it as expected programmatic selection rather than manual user switching.
4. Update `CaptureStateStore` and `InputEngine` context with the updated layout and clear any pending keystroke buffer for the new application.

---

## 4. UI / UX Design

### 4.1 Settings View Integration

A new dedicated section **"App Default Languages"** will be added to `SettingsView.swift` above the "Excluded Apps" section.

#### Visual Layout Specification:

```
+-----------------------------------------------------------------------+
|  App Default Languages                                                |
|  Automatically switch keyboard layout when an app becomes active.    |
|                                                                       |
|  +-----------------------------------------------------------------+  |
|  | [Icon] Telegram                       [ Ukrainian         v ]   |  |
|  |        ru.keepcoder.Telegram                                    |  |
|  |-----------------------------------------------------------------|  |
|  | [Icon] Arc                            [ English           v ]   |  |
|  |        company.thebrowser.Browser                               |  |
|  |-----------------------------------------------------------------|  |
|  | [Icon] Mail                           [ English           v ]   |  |
|  |        com.apple.mail                                           |  |
|  +-----------------------------------------------------------------+  |
|  | [ + v ] | [ - ]                                                 |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
```

#### Key UI Elements:
1. **List of App Rules**:
   - **App Icon**: 18x18 icon retrieved via `NSWorkspace.shared.icon(forFile:)` or fallback to `NSRunningApplication.icon`.
   - **App Display Name**: `FileManager.default.displayName` or `NSRunningApplication.localizedName`.
   - **Bundle Identifier**: Displayed in `caption2` style under the app name.
   - **Language Picker**: Dropdown menu inline with each row listing available installed layouts (`English`, `Ukrainian`, `Russian`). Changing the picker updates the rule immediately.
2. **Toolbar (`+` / `-`)**:
   - **`+` Button (Menu)**:
     - `Choose from Running Apps…`: Opens reusable `AppPickerView` sheet.
     - `Choose from Applications Folder…`: Opens `NSOpenPanel` defaulting to `/Applications`.
     - **Default Heuristic**: When an app is added, default to the user's primary secondary layout (e.g. `.ukrainian` if available, or currently active layout).
   - **`-` Button**: Enabled when a row is selected; removes the rule for that app.
3. **Window Size & Scrolling**:
   - Wrap `SettingsView` root in a `ScrollView` and configure `SettingsWindowController` dimensions (e.g. `width: 480, height: 720`, `minHeight: 600`) to guarantee no vertical clipping when both App Default Languages and Excluded Apps lists are populated.
4. **Reusable `AppPickerView` Sheet**:
   - Refactor the existing running app picker into a shared `AppPickerView` that accepts `excludedBundleIDs: Set<String>` and an `onSelect: (Set<String>) -> Void` callback, eliminating code duplication between `ExcludedAppsView` and `AppDefaultLanguagesView`.

### 4.2 Status Bar Menu Quick Toggle

In `StatusBarController.swift`, add a contextual item for the active frontmost app:
- Menu Item: `Default Language (Telegram)` -> Submenu:
  - `None (Keep Active Layout)` (checked if no rule)
  - `✓ Ukrainian`
  - `English`
  - `Russian`
- Selecting an item immediately updates `PerAppLanguageManager` and switches the current layout immediately via `InputSourceManager.shared.switchTo(...)` if the frontmost app is the one being modified.

---

## 5. Edge Cases & Robustness

| Edge Case | Impact | Mitigation / Solution |
|---|---|---|
| **Intra-App Window Switch (`⌘ + \`` / Chat switch)** | User in Telegram manually switches to EN to type code, then clicks another Telegram window | Track `previousBundleID` in `AppDelegate`. Only apply default rule if `newBundleID != previousBundleID`. Manual layout stays intact within app session. |
| **System Overlays & Daemons (Spotlight, Lock Screen)** | Spotlight or background helpers activate and change frontmost status | Guard `application.activationPolicy == .regular`. Skip language switching for system overlays and background agents. |
| **SwitchFix Self-Activation** | User opens SwitchFix Settings or clicks menu bar | Guard `bundleID != Bundle.main.bundleIdentifier`. SwitchFix never triggers per-app layout switching on itself. |
| **Rapid App Switching (`⌘ + Tab` cycling)** | Multiple rapid layout switches could queue excessive TIS calls | Only call `switchTo(layout)` if `currentLayout != targetLayout` and `pendingSelectionID != targetSourceID`. |
| **macOS Native "Switch to document source"** | macOS fires `kTISNotifySelectedKeyboardInputSourceChanged` after app activation | Handled cleanly via `consumeExpectedSelection(sourceID:)` marking programmatic switches. |
| **Excluded App with Default Language** | App is blacklisted from autocorrection (e.g. Terminal) but user wants English by default | Supported seamlessly. App filtering (correction disabled) and language switching are orthogonal. |
| **Corrupted / Invalid Layout in Storage** | Unknown string in `UserDefaults` | `compactMapValues { Layout(rawValue: $0) }` safely drops unknown entries without throwing or crashing. |
| **Uninstalled / Missing Layout** | User configures Ukrainian, but later uninstalls the Ukrainian layout from macOS Settings | `InputSourceManager.switchTo()` already verifies cached sources; if missing, it logs a notice and fails gracefully without crashing. |
| **Accidental Correction on App Switch** | Switching layout triggers `kTISNotifySelectedKeyboardInputSourceChanged` | Mark the switch via `pendingSelectionID` so `InputEngine` recognizes it as programmatic, resetting detector buffer without triggering false text corrections. |

---

## 6. Implementation Steps (Phased)

### Phase 1: Data Model & Persistence
- [ ] Create `Sources/Core/PerAppLanguageManager.swift`.
- [ ] Implement `UserDefaults` serialization under key `SwitchFix_perAppDefaultLanguages` (`[String: String]`).
- [ ] Add thread-safe accessors (`defaultLayout(for:)`, `setDefaultLayout(_:for:)`, `removeDefaultLayout(for:)`, `allRules`).
- [ ] Add `.perAppLanguageDidChange` notification.

### Phase 2: App Activation Integration
- [ ] Update `activeApplicationChanged(_ notification:)` in `Sources/SwitchFixApp/AppDelegate.swift`.
- [ ] Add `previousBundleID` state tracking to prevent intra-app layout clobbering.
- [ ] Guard `activationPolicy == .regular` and `bundleID != Bundle.main.bundleIdentifier`.
- [ ] Invoke `inputSourceManager.switchTo(targetLayout)` if different from `previousLayout`.
- [ ] Ensure `CaptureStateStore` context and `InputEngine` state are synchronized.

### Phase 3: Settings UI & Component Refactoring
- [ ] Refactor `RunningAppPickerView` into a reusable `AppPickerView` in `Sources/UI/SettingsView.swift`.
- [ ] Create `AppDefaultLanguagesView` and `AppLanguageRow` in `Sources/UI/SettingsView.swift`.
- [ ] Create `AppLanguageSettingsViewModel` (or integrate into `SettingsViewModel`).
- [ ] Support adding apps via `AppPickerView` and `NSOpenPanel` with smart default layout heuristic.
- [ ] Support in-place language picker dropdown per row.
- [ ] Add rule deletion via selection and minus (`-`) button.
- [ ] Wrap `SettingsView` in `ScrollView` and adjust `SettingsWindowController` height.

### Phase 4: Menu Bar Quick-Access
- [ ] Update `StatusBarController.swift` to include "Default Language for [Active App]" submenu.
- [ ] Sync menu bar state with `PerAppLanguageManager.shared.defaultLayout(for:)`.
- [ ] Apply layout immediately on menu selection if frontmost.

### Phase 5: Testing & Verification
- [ ] Add unit test suite in `Sources/TestRunner/main.swift` for `PerAppLanguageManager` (CRUD operations, serialization, corrupted entry filtering, thread safety).
- [ ] Run `swift run TestRunner` and `swift run InputPipelineTestRunner`.
- [ ] Test switching between Telegram (Ukrainian) and Arc / Browser (English).
- [ ] Test manual layout switching persistence across intra-app window focus changes.
- [ ] Test interaction between Excluded Apps and Per-App Language rules.

---

## 7. Verification & Acceptance Criteria

1. **Telegram -> Ukrainian**: Activating Telegram automatically sets keyboard layout to Ukrainian.
2. **Arc / Chrome -> English**: Activating Arc automatically sets keyboard layout to English.
3. **Intra-App Retention**: Manually changing layout within Telegram and clicking across Telegram windows retains the manually selected layout.
4. **Unconfigured Apps**: Activating an app without a rule retains whatever layout was previously active.
5. **System Overlays**: Opening Spotlight or Notification Center does not reset or alter the layout.
6. **Settings Persistence**: Rules added in Settings persist across SwitchFix restarts; corrupted entries are cleanly ignored.
7. **No Typing Interruption**: Keystrokes typed immediately after switching apps are captured cleanly with zero lag or duplicate characters.
8. **No Spurious Correction**: Switching apps does not trigger layout-switch autocorrection on stale buffers.
9. **TestRunner Suite**: All automated test suites in `TestRunner` pass with 0 failures.

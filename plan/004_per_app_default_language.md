# Feature Plan: Per-App Default Language / Layout Switching

> **Status**: ✅ Implementation-ready after council amendments
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
1. **Per-App Language Rules**: Allow users to assign a default keyboard layout (e.g., *English*, *Ukrainian*, *Russian*) to any supported installed application by its Bundle Identifier. Supported targets are applications that activate with `NSApplication.ActivationPolicy.regular`.
2. **Proactive Layout Switching**: When an application with a configured rule becomes frontmost, automatically switch macOS to that layout via `InputSourceManager`.
3. **Settings UI**: Add a clean, native SwiftUI configuration section in the Settings window with:
   - List of configured apps showing App Icon, App Name, Bundle ID, and a Language Picker dropdown.
   - Add button (`+`) with options: "Choose from Running Apps…" and "Choose from Applications Folder…".
   - Remove button (`-`) to delete rules.
   - Full scrollability to prevent clipping alongside the Excluded Apps section.
4. **Status Bar Menu Integration**: Provide a fast contextual submenu in the Menu Bar item to view or change the default language for the currently active app without opening Settings.
5. **Zero-Lag & Pipeline Safety**: Ensure automatic layout switching on app activation does not interfere with the zero-lag event tap, does not corrupt detector state, and does not trigger spurious text corrections.
6. **Persistence & Thread-Safety**: Persist all rules in `UserDefaults` with one lock covering the in-memory mutation and snapshot write (`OSAllocatedUnfairLock`); expose an injectable defaults store for isolated tests.

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
|   - Main-thread coordinator + (bundleID, PID) activation identity       |
|   - Context invalidation for every activation; rules only for .regular |
|   - Checks: PerAppLanguageManager.shared.defaultLayout(for: bundleID)   |
|   - Correlated selection token rejects stale TIS notifications          |
+------------------------------------+------------------------------------+
                                     |
                                     v (If configured layout has no matching current source)
+------------------------------------+------------------------------------+
|                       InputSourceManager                                |
|   - TISSelectInputSource(preferredSources[targetLayout])                |
|   - Coalesced, tokenized pending selection                              |
|   - Mismatched/stale notifications do not consume current expectation   |
+-------------------------------------------------------------------------+
```

### 3.1 Data Model: `PerAppLanguageManager`

**Location:** `Sources/Core/PerAppLanguageManager.swift`  
*(Note: Placed in `Core` because `Layout` is defined in `Core`, preserving `Utils` as a zero-dependency foundational module).*

The manager is the only owner of rule mutation. Production uses the singleton; tests use the public initializer with an isolated `UserDefaults(suiteName:)` store.

Required behavior:

- Parse `UserDefaults.dictionary(forKey:)` as `[String: Any]`; preserve valid string/layout entries even when other entries have invalid types or raw values.
- Ignore empty bundle identifiers and no-op when a write would not change the current rule.
- Mutate state and write the complete `[String: String]` snapshot under the same lock. Post notifications after releasing the lock, on the main thread.
- Keep rules for uninstalled apps so reinstalling the same bundle can recover the rule. A missing layout is retained but treated as unavailable by the UI and activation path.

```swift
import Foundation
import os

public final class PerAppLanguageManager {
    public static let shared = PerAppLanguageManager(defaults: .standard)

    private let defaults: UserDefaults
    private static let storageKey = "SwitchFix_perAppDefaultLanguages"

    private struct State {
        /// Map of bundle identifier -> Layout
        var rules: [String: Layout]
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawDict = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        let initialRules = rawDict.compactMapValues { value in
            (value as? String).flatMap(Layout.init(rawValue:))
        }
        self.state = OSAllocatedUnfairLock(initialState: State(rules: initialRules))
    }

    public func defaultLayout(for bundleID: String) -> Layout? {
        state.withLock { $0.rules[bundleID] }
    }

    public func setDefaultLayout(_ layout: Layout?, for bundleID: String) {
        guard !bundleID.isEmpty else { return }
        let changed = state.withLock { state -> Bool in
            let oldLayout = state.rules[bundleID]
            if let layout = layout {
                state.rules[bundleID] = layout
            } else {
                state.rules.removeValue(forKey: bundleID)
            }
            let newLayout = state.rules[bundleID]
            guard oldLayout != newLayout else { return false }
            defaults.set(state.rules.mapValues(\.rawValue), forKey: Self.storageKey)
            return true
        }
        guard changed else { return }
        let post = {
            NotificationCenter.default.post(name: .perAppLanguageDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
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

}

public extension Notification.Name {
    static let perAppLanguageDidChange = Notification.Name("SwitchFix_PerAppLanguageDidChange")
}
```

### 3.2 App Activation Flow (`AppDelegate.swift`)

All activation handling and TIS selection requests run on the main thread. Add a small, testable activation coordinator (in `Core`) that accepts an `ActivationIdentity` (`bundleID`, PID, and `isRegular`) and returns whether to apply a rule. It tracks the last observed identity, not only a bundle ID: a relaunch with a new PID is a new activation, while same-process window changes do not reset the user's layout. This is app-level retention; the plan does not claim to identify individual windows.

Use this exact sequence for both startup and `NSWorkspace.didActivateApplicationNotification`:

1. Read the application identity and increment an activation generation. Update the last observed identity even for non-regular apps, overlays, and SwitchFix itself.
2. Refresh the current input source and immediately replace `CaptureStateStore` context with the new PID, current layout, current source ID, and unknown focus. This invalidates stale detector/correction state for every activation; skipping a default rule must never skip context invalidation.
3. Queue `InputEngine.updateContext` before any selection request. Events captured against the old epoch are rejected by the existing stale-context guard.
4. For a regular, non-SwitchFix app with a rule, compare the actual current source ID against `InputSourceManager`'s layout match/preferred-source contract. Do not compare only `Layout`, because unsupported sources currently fall back to `.english`.
5. If a switch is needed, call a new tokenized `InputSourceManager.requestSwitch(to: activationGeneration:)` API on the main thread. The manager coalesces to the newest request and invokes callbacks with the token, target source ID, and result.
6. `willSelect` may publish a generated-layout transition only if its token still matches the current activation generation and PID. A delayed selection from an earlier app is ignored/reconciled, never applied to the new app.
7. On a matching TIS notification, update the context to the confirmed source and call `handleGeneratedLayoutContext`. On failure or a stale/mismatched notification, refresh the actual source, update context, clear the pending expectation, and do not invoke layout-switch autocorrection.

`InputSourceManager` must return an explicit `.matched`, `.superseded`, or `.manual` result when observing a source notification. A mismatched source must never silently consume the expectation and then be reported as manual: it either remains pending until the matching source arrives or is atomically cancelled as superseded, with its token returned so the app delegate can reconcile without correction. The API must make it impossible for two rapid requests to overwrite a token without the observer being able to distinguish the stale notification.

At launch, initialize the identity and process the already-frontmost application through the same routine after the initial context is created. This covers a configured app that was frontmost before SwitchFix launched.

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
   - **Default Heuristic**: Use the current active layout when it is non-English and installed; otherwise prefer installed Ukrainian, then Russian, then English. This is deterministic and does not invent a new preference.
   - **Duplicate apps**: Existing rules are preserved; configured bundle IDs are excluded from both pickers and duplicate filesystem selections are ignored.
   - **`-` Button**: Enabled when a row is selected; removes the rule for that app.
3. **Window Size & Scrolling**:
   - Configure `SettingsWindowController` to `width: 480, height: 720`, with a `minSize` height of 600.
   - Wrap the settings content in one outer `ScrollView`; replace the fixed-height nested `List` controls with bounded `ScrollView`/`LazyVStack` sections so the window has one predictable scroll owner and never clips populated sections.
4. **Reusable `AppPickerView` Sheet**:
   - Refactor the existing running app picker into a shared `AppPickerView` that receives app records, `excludedBundleIDs: Set<String>`, a title/empty-state string, and an `onSelect: (Set<String>) -> Void` callback. It owns selection and dismissal; the parent owns persistence.

Rules with an uninstalled app remain visible using the bundle ID as the name and a placeholder icon. Rules whose layout is no longer installed remain visible as `Unavailable`, do not trigger a switch, and become active automatically if that layout is later installed. The row picker lists only `InputSourceManager.availableLayouts()`.

### 4.2 Status Bar Menu Quick Toggle

In `StatusBarController.swift`, add a contextual item for the last regular frontmost app:
- Menu Item: `Default Language (Telegram)` -> Submenu:
  - `None (Keep Active Layout)` (checked if no rule)
  - `✓ Ukrainian`
  - `English`
  - `Russian`
- `menuWillOpen` snapshots bundle ID, PID, and display name before the status menu can make SwitchFix frontmost. Menu actions use that snapshot, never a fresh unvalidated `frontmostApplication` lookup.
- Selecting an item immediately updates `PerAppLanguageManager`. `None` only removes the rule and never changes the current layout. A language selection switches immediately only if the snapshot app is still frontmost; if the app changed while the menu was open, persist the rule but skip the immediate switch.
- Show only installed layouts and disable the submenu with a clear message when there is no eligible frontmost app.

---

## 5. Edge Cases & Robustness

| Edge Case | Impact | Mitigation / Solution |
|---|---|---|
| **Intra-App Window Switch (`⌘ + \`` / Chat switch)** | User in Telegram manually switches to EN to type code, then clicks another Telegram window | Track `(bundleID, PID)` identity. Same-process activation does not reapply the rule; individual windows are intentionally out of scope. |
| **System Overlays & Daemons (Spotlight, Lock Screen)** | An ineligible app activates while the old app has buffered state | Always replace/invalidate capture context; skip only the default-layout action for non-regular apps. Update the observed identity so returning to the configured app is not suppressed. |
| **SwitchFix Self-Activation** | User opens SwitchFix Settings or clicks the menu bar | Invalidate context as usual, but never apply a rule to SwitchFix. The status menu uses its saved last-regular-app snapshot. |
| **Rapid App Switching (`⌘ + Tab` cycling)** | Multiple layout switches produce delayed/out-of-order TIS notifications | Serialize activation on main, coalesce to the latest tokenized request, return explicit mismatch/superseded results, and ignore/reconcile stale notifications. |
| **macOS Native "Switch to document source"** | macOS fires `kTISNotifySelectedKeyboardInputSourceChanged` after app activation | Match notifications by selection token and target source ID. Only a matching notification is generated; manual or stale notifications update actual state without correction. |
| **Unsupported current input source** | Current source is not in `Layout.allCases` but fallback mapping reports English | Compare `currentInputSourceID` against `Layout.matches(sourceID:)`; select the configured layout's preferred source when the source is unsupported. |
| **Excluded App with Default Language** | App is blacklisted from autocorrection (e.g. Terminal) but user wants English by default | Supported seamlessly. App filtering (correction disabled) and language switching are orthogonal. |
| **Corrupted / Invalid Layout in Storage** | Unknown string or non-string value in `UserDefaults` | Parse each value independently; preserve valid entries and drop only invalid values without throwing or crashing. |
| **Uninstalled / Missing Layout** | User configures Ukrainian, but later uninstalls the Ukrainian layout from macOS Settings | Retain the rule, show `Unavailable`, skip selection, and log a notice. Refresh installed sources at the normal readiness/startup boundary. |
| **Accidental Correction on App Switch** | Switching layout triggers a TIS notification while a word/correction is pending | New app context increments the epoch and resets detector state; stale queued correction requests are cancelled. A generated transition never enters layout-switch autocorrection. |
| **Persistence race** | Settings and status menu write different rules concurrently | Mutate and persist one complete snapshot inside the same lock; test concurrent writers with an isolated defaults suite. |
| **Menu target changes** | User opens the menu for Telegram, then activates another app before selecting a language | Persist the Telegram rule, but only switch immediately if the captured Telegram PID/bundle is still frontmost. |

---

## 6. Implementation Steps (Phased)

Each phase must leave the repository buildable. Keep TIS calls and all activation state transitions on the main thread; keep rule reads lock-bounded and free of AppKit dependencies.

### Phase 1: Data Model & Persistence
- [ ] Create `Sources/Core/PerAppLanguageManager.swift` with `public init(defaults:)` and the production singleton.
- [ ] Implement `[String: String]` serialization under `SwitchFix_perAppDefaultLanguages`; parse mixed/invalid stored values individually.
- [ ] Add CRUD accessors and sorted `allRules`; ignore empty bundle IDs and suppress no-op notifications.
- [ ] Perform the state mutation and complete snapshot write under one `OSAllocatedUnfairLock` critical section to prevent lost updates.
- [ ] Deliver `.perAppLanguageDidChange` on the main thread after unlocking.

### Phase 2: Testable Activation and Selection Contracts
- [ ] Add a pure `ActivationIdentity`/activation coordinator in `Sources/Core` that tracks `(bundleID, PID, isRegular)` and an activation generation. Same PID/bundle does not reapply a rule; every observed activation still invalidates context.
- [ ] Add a selection port/protocol or equivalent seam so tests can model success, failure, delayed notifications, mismatches, and coalescing without calling Carbon/TIS.
- [ ] Extend `InputSourceManager` with an atomic tokenized/coalesced request API. A mismatched notification must not clear the current expectation; stale tokens must be distinguishable from manual changes.
- [ ] Add an explicit `isCurrentSource(_:)`/preferred-source contract based on source IDs and `Layout.matches(sourceID:)`.

### Phase 3: App Activation Integration
- [ ] Refactor `activeApplicationChanged(_:)` into the sequence defined in section 3.2: observe identity, replace context, queue engine reset, then request a guarded selection.
- [ ] Reuse the same activation routine for the initial frontmost app during launch.
- [ ] Apply rules only to non-SwitchFix regular applications; context invalidation must still occur for all activation notifications.
- [ ] Gate `willSelect`, confirmation, and failure callbacks by activation generation/PID; stale callbacks only reconcile actual input state and never trigger correction.
- [ ] Verify failed/missing source selection leaves `CaptureStateStore` and `InputEngine` synchronized with the actual source.

### Phase 4: Settings UI & Component Refactoring
- [ ] Introduce a shared app-record type and refactor `RunningAppPickerView` into `AppPickerView` with parent-owned persistence and callback-based selection.
- [ ] Create `AppDefaultLanguagesView` and `AppLanguageRow`; show icon/name/bundle ID, installed-layout picker, unavailable-layout state, and duplicate suppression.
- [ ] Filter running and filesystem choices to supported regular applications, excluding SwitchFix; reject or explain unsupported bundles.
- [ ] Implement the deterministic default heuristic from section 4.1 and immediate persistence for add/change/remove.
- [ ] Replace nested fixed-height `List`s with bounded `LazyVStack` sections inside one outer settings `ScrollView`; set the window size/minimum from section 4.1.

### Phase 5: Menu Bar Quick-Access
- [ ] Add the contextual default-language submenu and rebuild it from the last regular frontmost `(bundleID, PID, name)` snapshot.
- [ ] Capture the snapshot when the menu opens; use it as the action target and validate that the same app is still frontmost before switching.
- [ ] Persist `None` as rule removal without changing the current layout; persist a language selection even if the app changed, but skip immediate switching in that case.
- [ ] Observe `.perAppLanguageDidChange` or rebuild on open so Settings/menu changes are reflected without stale checkmarks.

### Phase 6: Automated and Manual Verification
- [ ] Extend `Sources/TestRunner/main.swift` with isolated-defaults tests for CRUD, reload, mixed corruption, empty IDs, no-op writes, and concurrent writers.
- [ ] Test the pure activation coordinator with startup, regular/unconfigured, non-regular, self-activation, same-PID repeat, and relaunch/new-PID cases.
- [ ] Test the fake selection port with rapid A→B→A, delayed/out-of-order notifications, mismatches, failures, and stale callback rejection.
- [ ] Run `swift build`, `swift run TestRunner`, and `swift run InputPipelineTestRunner`.
- [ ] Manually test Telegram/Arc or equivalent regular apps, immediate typing around activation, manual in-app layout retention, missing layouts, menu target changes, and Excluded Apps coexistence.

---

## 7. Verification & Acceptance Criteria

1. **Configured regular app**: Activating a configured app selects the preferred installed source for its configured layout once, and the confirmed source/layout is reflected in `CaptureStateStore` and `InputEngine`.
2. **Startup**: Launching SwitchFix while a configured app is already frontmost applies that rule through the same activation path.
3. **Intra-app retention**: Same-process window changes do not reapply the rule; a relaunch with a new PID does.
4. **Unconfigured/ineligible apps**: Context is invalidated on every activation, but an app without a rule or with a non-regular policy does not cause a default-layout selection.
5. **Selection races**: Delayed, mismatched, or stale TIS notifications cannot update the wrong app, consume the latest expectation, or trigger layout-switch autocorrection.
6. **Source identity**: An unsupported current input source is not mistaken for a matching English source; equivalent supported variants are not switched unnecessarily.
7. **Settings persistence**: Rules added/changed/removed in Settings persist across restarts; valid entries survive mixed corrupted defaults; concurrent writes lose no rules.
8. **UI behavior**: Installed layouts, unavailable rules, duplicate app selection, one-owner scrolling, and missing app icons/names behave as specified.
9. **Status menu safety**: The menu edits the app captured at open time; it does not switch a different app if focus changes while the menu is open; `None` leaves the current layout unchanged.
10. **Pipeline safety**: Keystrokes around app activation are not delayed, duplicated, or corrected from a stale buffer.
11. **Automated verification**: `swift build`, `swift run TestRunner`, and `swift run InputPipelineTestRunner` pass with 0 failures.

# Feature Plan: Support for Custom Keyboard Layouts

> **Status**: ✅ Implementation-ready after council amendments  
> **Priority**: Critical  
> **Date created**: 2026-09-03 (Amended: 2026-09-03)  
> **Target Module**: `Core`, `UI`, `SwitchFixApp`, `Dictionary`, `TestRunner`, `InputPipelineTestRunner`  
> **Plan ID**: `005_custom_keyboard_layouts`  
> **Reference**: GitHub Issue #13 (*"Не видит кастомных раскладок"*)

---

## 1. Context & Motivation

In GitHub Issue #13, a user reported that SwitchFix does not recognize custom keyboard layouts. Specifically, the user uses **`RU – UA – Birman`** (the widely popular Ilya Birman Typography Layout variant combining Russian, Ukrainian, and typography symbols), alongside macOS default **`ABC`**.

### Current Failure Mode (from Issue #13)

1. **Menu Bar Empty**: The SwitchFix "Installed Layouts" submenu only lists `English -> ABC`. Neither Ukrainian nor Russian appears.
2. **Dictionary Preparation Skipped**: SwitchFix determines ready dictionaries based on `inputSourceManager.availableLayouts()`. Because the custom layout is ignored, `availableLayouts()` returns only `[.english]`. Dictionaries for Ukrainian and Russian are never prewarmed or loaded into memory.
3. **Misclassified Active Layout**: When the user switches to `RU – UA – Birman`, `InputSourceManager.layout(for:)` cannot match the custom source ID and defaults to `.english`.
4. **Auto-Detection & Switching Broken**: SwitchFix cannot detect wrong-layout typing or switch to the custom layout because `preferredSources[.ukrainian]` and `preferredSources[.russian]` are empty.

### Root Cause in Codebase

In [`Sources/Core/LayoutMapper.swift`](file:///Users/roman/dev/bots/switchfix/Sources/Core/LayoutMapper.swift#L27-L54):
```swift
public var inputSourceIDs: [String] {
    switch self {
    case .english: return [
        "keylayout.US", "keylayout.USExtended", "keylayout.ABC", "keylayout.British",
        "keylayout.USInternational-PC", "keylayout.Colemak", "keylayout.Dvorak",
    ]
    case .ukrainian: return [
        "keylayout.Ukrainian", "keylayout.Ukrainian-PC",
    ]
    case .russian: return [
        "keylayout.Russian", "keylayout.RussianWin", "keylayout.Russian-Phonetic",
    ]
    }
}

public func matches(sourceID: String) -> Bool {
    return inputSourceIDs.contains(where: { sourceID.hasSuffix($0) })
}
```

And in [`Sources/Core/InputSourceManager.swift`](file:///Users/roman/dev/bots/switchfix/Sources/Core/InputSourceManager.swift#L54-L58):
```swift
for source in sources {
    guard let sourceID = Self.stringProperty(source, kTISPropertyInputSourceID),
          let layout = Layout.allCases.first(where: { $0.matches(sourceID: sourceID) }) else {
        continue
    }
    // ...
}
```

Custom layouts (installed in `~/Library/Keyboard Layouts/` or `/Library/Keyboard Layouts/`, often created with **Ukelele**) have arbitrary bundle IDs such as:
- `org.sil.ukelele.keyboardlayout.ru-ua-birman`
- `org.unknown.keylayout.RU-UA-Birman`
- `com.apple.keyboardlayout.ru-ua-birman`
- `com.alexkolodko.keylayout.ru-ua-birman`

Because these IDs do not end with the hardcoded suffixes (`keylayout.Ukrainian`, `keylayout.Russian`, etc.), SwitchFix silently drops them during input source discovery.

### Critical Council Finding: The "Hybrid Autocorrection Death Spiral"

Beyond discovery, a critical architectural challenge exists for **hybrid layouts** (like `RU – UA – Birman`). Ilya Birman's typography layout allows typing **both** Russian (unshifted) and Ukrainian (`і, ї, є, ґ` via `Option` key) on the *same* physical layout without switching input sources in macOS.

If the engine forces an active hybrid layout to report as a single `Layout` case (e.g. `.russian`), then whenever the user types legitimate Ukrainian words (`"привіт"`, `"як"`, `"справи"`):
1. `LayoutDetector` evaluates the word against the Russian dictionary and fails.
2. Alternative conversion to Ukrainian succeeds.
3. `LayoutDetector` triggers text correction and calls `switchTo(.ukrainian)`.
4. `switchTo(.ukrainian)` selects `RU – UA – Birman` — which was already active!
5. `TextCorrector` deletes the typed word with backspaces and retypes it.

Every Ukrainian word typed on a Birman layout would flicker, get erased, and be re-typed. To prevent this, the engine must support **multi-language active input sources** and **suppress self-switching**.

---

## 2. Goals & Non-Goals

### Goals

1. **Automatic Custom Layout Discovery**: Detect and classify any installed third-party keyboard layout (`.keylayout` or `.bundle` from Ukelele, Birman, etc.) without requiring hardcoded IDs.
2. **Robust Multi-Tier Classification with Option-Key Probing**:
   - **Tier 1 (TIS Metadata)**: Inspect `kTISPropertyInputSourceLanguages` (e.g., `["uk"]`, `["ru"]`, `["en"]`).
   - **Tier 2 (Token & Name Heuristics)**: Inspect `kTISPropertyLocalizedName` and `kTISPropertyInputSourceID` for language tokens (`ru`, `ua`, `ukr`, `rus`, `birman`, `colemak`, `dvorak`, etc.).
   - **Tier 3 (Dynamic UCKeyTranslate Probing)**: Probe keycodes in **both unshifted and Option-shifted states** to detect Cyrillic letters and AltGr Ukrainian typography symbols (`і`, `ї`, `є`, `ґ`).
3. **First-Class Hybrid Layout Support & False Correction Suppression**:
   - Register hybrid layouts under all supported languages (`Set<Layout>`).
   - Allow `LayoutDetector` to validate words against *any* language supported by the active layout before flagging a wrong-layout error.
   - Suppress layout switching and text correction if source and target share the same physical input source ID.
4. **Pure Domain Types & Carbon Encapsulation**:
   - Expose `DiscoveredInputSourceDescriptor` as a pure, `Sendable`, `Equatable`, and `Identifiable` value type. Keep raw `TISInputSource` pointer handles encapsulated inside `InputSourceManager`.
5. **Headless Testability via Seam**:
   - Provide an `InputSourcePropertyProviding` protocol so classification, probing, and hybrid resolution can be tested 100% deterministically in `TestRunner` without depending on live macOS Carbon TIS.
6. **Dynamic System Layout Registration**:
   - Observe `kTISNotifyEnabledKeyboardInputSourcesChanged` to automatically refresh sources and prewarm dictionaries when users enable or add layouts in macOS Settings without restarting SwitchFix.
7. **User Customization & Selection Persistence**:
   - Allow users in Settings / Menu Bar to pick their preferred input source for each language when multiple layouts exist. Persist preferences under `SwitchFix_preferredInputSources`.
8. **Zero-Lag & Pipeline Safety**:
   - All TIS enumeration and `UCKeyTranslate` probing must happen off the typing path (during initialization or notification callbacks), never on the event-tap capture thread.

### Non-Goals

1. Supporting arbitrary non-Cyrillic/non-Latin languages (e.g. Arabic, Hebrew, Chinese, Japanese) for dictionary correction in this milestone.
2. Building an in-app visual keyboard layout editor (Ukelele already fills this role).

---

## 3. Architecture & Data Design

```
+-----------------------------------------------------------------------------------+
|                        Carbon TIS / System Notifications                          |
|         (kTISNotifySelectedKeyboardInputSourceChanged / EnabledChanged)           |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------+-----------------------------------------+
|                    InputSourcePropertyProviding (Seam)                            |
|     (Production: CarbonTISPropertyAdapter | Tests: MockInputSourcePropertyReader) |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------+-----------------------------------------+
|                       InputSourceDiscoveryEngine                                  |
|   3-Tier Classification Cascade:                                                  |
|   - Tier 1: kTISPropertyInputSourceLanguages                                     |
|   - Tier 2: Token matching on ID & Localized Name                                 |
|   - Tier 3: UCKeyTranslate probing (Unshifted + Option/AltGr states)             |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------+-----------------------------------------+
|                  DiscoveredInputSourceDescriptor (Pure Swift)                     |
|   id: String, name: String, supportedLayouts: Set<Layout>, isCustom: Bool          |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------+-----------------------------------------+
|                           InputSourceManager                                      |
|   - Internal raw TISInputSource cache: [String: TISInputSource]                   |
|   - Preferred source mapping: [Layout: String] (persisted in UserDefaults)        |
|   - Active source supported layouts: Set<Layout>                                  |
+-----------------------------------------+-----------------------------------------+
                    |                                   |
                    v                                   v
+-------------------+-------------------+   +---------------+-------------------+
|              AppDelegate              |   |           LayoutDetector          |
| - Prewarms dictionaries for all       |   | - activeSourceSupportedLayouts    |
|   availableLayouts()                  |   | - Validates against ANY supported |
| - Updates CaptureContext with         |   |   language before correcting      |
|   current source ID and primary layout|   | - Suppresses self-switching       |
+---------------------------------------+   +-----------------------------------+
```

### 3.1 Data Structures

#### Pure Domain Descriptor
```swift
public struct DiscoveredInputSourceDescriptor: Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let supportedLayouts: Set<Layout>
    public let ukrainianVariant: UkrainianKeyboardVariant?
    public let isCustom: Bool

    public init(
        id: String,
        name: String,
        supportedLayouts: Set<Layout>,
        ukrainianVariant: UkrainianKeyboardVariant? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.supportedLayouts = supportedLayouts
        self.ukrainianVariant = ukrainianVariant
        self.isCustom = isCustom
    }
}
```

#### Testable Property Provider Seam
```swift
public protocol InputSourcePropertyProviding {
    var id: String { get }
    var localizedName: String { get }
    var inputSourceType: String? { get }
    var languages: [String]? { get }
    func translatedCharacter(keyCode: UInt16, modifierKeyState: UInt32) -> Character?
}
```

In production, `CarbonTISPropertyAdapter` wraps `TISInputSource` and delegates to `TISGetInputSourceProperty` and `UCKeyTranslate`. In tests, `MockInputSourcePropertyReader` supplies canned values.

#### Mapping Between Custom Layouts and `Layout`
A custom layout can map to one or more `Layout` targets:
- `RU – UA – Birman`: `supportedLayouts = [.russian, .ukrainian]`
- `Ukrainian - Enhanced`: `supportedLayouts = [.ukrainian]`
- `Colemak / Dvorak`: `supportedLayouts = [.english]`

When a layout maps to multiple languages, `InputSourceManager` registers it under all supported languages. If the user only has `ABC` and `RU – UA – Birman`:
- `availableLayouts()` returns `[.english, .ukrainian, .russian]`.
- All three dictionaries (`en_US`, `uk_UA`, `ru_RU`) are prewarmed and available.
- Switching to `.ukrainian` selects `RU – UA – Birman`.
- Switching to `.russian` selects `RU – UA – Birman`.
- Switching to `.english` selects `ABC`.

---

## 4. Multi-Tier Classification Engine

### Tier 1: `kTISPropertyInputSourceLanguages`
Inspect ISO language identifiers declared by the layout:
```swift
if let langs = provider.languages {
    for lang in langs {
        let code = lang.prefix(2).lowercased()
        if code == "uk" { layouts.insert(.ukrainian) }
        if code == "ru" { layouts.insert(.russian) }
        if code == "en" { layouts.insert(.english) }
    }
}
```

### Tier 2: Token & Name Heuristics
If language metadata is omitted or contains generic tags:
```swift
let normalized = (provider.id + " " + provider.localizedName).lowercased()
if normalized.contains("ukrain") || normalized.contains("ukr") || normalized.contains("-ua") {
    layouts.insert(.ukrainian)
}
if normalized.contains("russian") || normalized.contains("rus") || normalized.contains("-ru") {
    layouts.insert(.russian)
}
if normalized.contains("birman") {
    // Birman layout variants natively support Russian and Ukrainian typography
    layouts.insert(.russian)
    layouts.insert(.ukrainian)
}
if normalized.contains("colemak") || normalized.contains("dvorak") || normalized.contains("workman") || normalized.contains("qwerty") {
    layouts.insert(.english)
}
```

### Tier 3: Dynamic `UCKeyTranslate` Probing (Unshifted + Option/AltGr)
To correctly classify custom Cyrillic and hybrid layouts without relying on naming:

```swift
// 1. Probe unshifted characters
let keyA = provider.translatedCharacter(keyCode: 0, modifierKeyState: 0)   // ANSI 'A'
let keyS = provider.translatedCharacter(keyCode: 1, modifierKeyState: 0)   // ANSI 'S'
let keyQ = provider.translatedCharacter(keyCode: 12, modifierKeyState: 0)  // ANSI 'Q'
let keyOpenBracket = provider.translatedCharacter(keyCode: 33, modifierKeyState: 0) // ANSI '['
let keyCloseBracket = provider.translatedCharacter(keyCode: 30, modifierKeyState: 0) // ANSI ']'
let keyQuote = provider.translatedCharacter(keyCode: 39, modifierKeyState: 0)       // ANSI '''

if keyQ == "й" && keyA == "ф" {
    // Definitive Cyrillic ЙЦУКЕН layout
    if keyS == "і" || keyQuote == "є" || keyCloseBracket == "ї" {
        layouts.insert(.ukrainian)
    }
    if keyS == "ы" || keyQuote == "э" || keyCloseBracket == "ъ" {
        layouts.insert(.russian)
    }

    // 2. Probe Option / AltGr state (crucial for Ilya Birman layouts)
    // Option modifier bit in Carbon UCKeyTranslate modifierKeyState: (optionKey >> 8) or 0x08
    let optS = provider.translatedCharacter(keyCode: 1, modifierKeyState: 0x08)
    let optQuote = provider.translatedCharacter(keyCode: 39, modifierKeyState: 0x08)
    let optCloseBracket = provider.translatedCharacter(keyCode: 30, modifierKeyState: 0x08)
    let optG = provider.translatedCharacter(keyCode: 5, modifierKeyState: 0x08) // ANSI 'G'

    if optS == "і" || optQuote == "є" || optCloseBracket == "ї" || optG == "ґ" {
        layouts.insert(.ukrainian)
    }
    if optS == "ы" || optQuote == "э" || optCloseBracket == "ъ" {
        layouts.insert(.russian)
    }

    if layouts.isEmpty {
        // Fallback for unidentified Cyrillic
        layouts.insert(.ukrainian)
        layouts.insert(.russian)
    }
} else if keyQ == "q" || keyA == "a" {
    layouts.insert(.english)
}
```

---

## 5. Active Layout Identification & Hybrid Layout Handling

### 5.1 Hybrid Layout Architecture

When an input source like `RU – UA – Birman` is active:
1. `InputSourceManager.currentInputSourceID()` returns the active custom source ID.
2. `InputSourceManager.activeSourceSupportedLayouts()` returns `Set([.russian, .ukrainian])`.
3. `InputSourceManager.currentLayout()` returns the primary/preferred layout (e.g. `.ukrainian` or `.russian` based on user preference or recent typing).

### 5.2 `LayoutDetector` Hybrid Validation Contract

In [`LayoutDetector.swift`](file:///Users/roman/dev/bots/switchfix/Sources/Core/LayoutDetector.swift):
```swift
/// The set of languages supported by the currently active physical input source.
public var activeSourceSupportedLayouts: Set<Layout> = [.english]
```

When evaluating `checkBuffer()` on a word:
1. **Multi-Language Acceptance**: If `activeSourceSupportedLayouts` contains multiple layouts (e.g. `[.ukrainian, .russian]`):
   - Check validity in **all** supported languages:
     ```swift
     let isLocallyValid = activeSourceSupportedLayouts.contains { layout in
         let lang = languageForLayout(layout)
         return validator.validate(currentValidationInput, language: lang, allowSuggestion: false).isValid
     }
     if isLocallyValid {
         // Accepted as valid in current hybrid layout — zero correction, zero backspaces
         return nil
     }
     ```
2. **Self-Switch Suppression**:
   When proposing a `DetectionResult`:
   ```swift
   let currentSourceID = inputSourceManager.currentInputSourceID()
   let targetPreferredSourceID = inputSourceManager.sourceID(for: targetLayout)
   if currentSourceID == targetPreferredSourceID {
       // Target layout uses the exact same physical input source already active.
       // Suppress switching and suppress text replacement if characters match.
       return nil
   }
   ```
3. **QWERTY Mistype on Hybrid Layout**:
   If the user is on `RU – UA – Birman` and types `"hello"` (`"руддщ"`):
   - `"руддщ"` is invalid in Russian AND invalid in Ukrainian.
   - Conversion to `.english` yields `"hello"`, which is valid in English.
   - Target layout is `.english` (`targetPreferredSourceID = "com.apple.keylayout.ABC"`).
   - Target source ID differs from current source ID: correction proceeds normally, switching to `ABC`!

---

## 6. Layout Mapping & Ukrainian Variant Detection

### 6.1 Ukrainian Variant Detection
In `InputSourceManager`:
- Dynamic probe on keycode 1 (`s`) and keycode 11 (`b`):
  - `s == "и"` and `b == "і"` -> `.legacy`
  - `s == "і"` and `b == "и"` -> `.standard`
- If unshifted key 1 is `"ы"` (as in Birman layout), it falls back to `.standard`, which correctly uses standard QWERTY ↔ ЙЦУКЕН translation tables for correction.

### 6.2 Preserving `Layout.matches(sourceID:)`
- `Layout.matches(sourceID:)` remains unchanged as a fast static check for native Apple bundle IDs.
- New dynamic checks use `InputSourceManager.shared.matches(sourceID:layout:)` and `InputSourceManager.shared.supportedLayouts(for: sourceID)`.

---

## 7. UI & Preferences Integration

### 7.1 Status Bar Menu ("Installed Layouts")
In [`StatusBarController.swift`](file:///Users/roman/dev/bots/switchfix/Sources/UI/StatusBarController.swift#L224-L254):
- Group custom layouts under their classified language headers.
- If a custom layout is hybrid (`RU – UA – Birman`), display it under Ukrainian and Russian sections with an indicator `(Custom)` or `(Hybrid)`.
- Mark the currently active input source with `✓`.
- **Click-to-Switch Action**: Attach `@objc private func selectInstalledSource(_ sender: NSMenuItem)` using `sender.representedObject` as source ID to allow immediate switching.

### 7.2 Settings View & Persistence
In `SettingsView.swift`:
- Under a new "Keyboards & Layouts" section:
  - Display all detected input sources grouped by language.
  - When multiple layouts are installed for the same language (e.g. Apple `Ukrainian` and `RU – UA – Birman`), display a picker to select the **Preferred Source**.
  - Provide a "Refresh Layouts" button.
- **Persistence**: Store bindings in `UserDefaults` under key `SwitchFix_preferredInputSources` as `[String: String]` (e.g. `["ukrainian": "org.sil.ukelele.keyboardlayout.ru-ua-birman"]`).

### 7.3 Dynamic System Notification
In [`AppDelegate.swift`](file:///Users/roman/dev/bots/switchfix/Sources/SwitchFixApp/AppDelegate.swift):
```swift
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(installedInputSourcesChanged),
    name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
    object: nil,
    suspensionBehavior: .deliverImmediately
)
```
When triggered, invoke `inputSourceManager.refreshInstalledSources()` to re-enumerate sources and dynamically prewarm dictionaries for newly enabled languages.

---

## 8. Edge Cases & Robustness Matrix

| Edge Case | Impact | Mitigation / Solution |
|---|---|---|
| **Bilingual Hybrid Layout (Birman)** | Typing Ukrainian words while hybrid layout is active | `LayoutDetector` validates against `activeSourceSupportedLayouts` (`[.russian, .ukrainian]`). Valid words in either language pass without correction. |
| **Self-Switch Attempt** | Engine tries to switch from hybrid layout to itself | Suppress correction and layout switch when `targetPreferredSourceID == currentInputSourceID`. |
| **Option-Key Ukrainian Symbols** | Layout metadata missing; letters only under AltGr | Tier 3 probes `UCKeyTranslate` with `modifierKeyState = 0x08` (Option) detecting `і`, `ї`, `є`, `ґ`. |
| **New Layout Installed at Runtime** | User adds custom layout in macOS Settings | Observe `kTISNotifyEnabledKeyboardInputSourcesChanged` and refresh cache dynamically. |
| **Corrupted / Nil UnicodeKeyLayoutData** | Input method or third-party bundle with missing binary table | Guard `kTISPropertyUnicodeKeyLayoutData` safely; fall back to Tier 2 tokens or default to `.english`. |
| **Custom Latin Layouts (Colemak / Dvorak)** | Keycodes produce unexpected Latin letters | Tier 3 probes keycode 0 (`a`) and keycode 12 (`q`/`'`); classifies as `.english`. |
| **Multiple Layouts for One Language** | User has Apple Ukrainian and Birman installed | User selects preferred source in Settings; persisted in `UserDefaults` (`SwitchFix_preferredInputSources`). |
| **Headless CI / Non-GUI Test Execution** | `TISCreateInputSourceList` returns nil in CI | Decouple classification into `InputSourceDiscoveryEngine` backed by `InputSourcePropertyProviding` seam. |

---

## 9. Implementation Phases

### Phase 1: Testable Discovery Engine & Seam
- [x] Create `Sources/Core/InputSourcePropertyProviding.swift` protocol.
- [x] Implement `CarbonTISPropertyAdapter` wrapping `TISInputSource` for production.
- [x] Implement `MockInputSourcePropertyReader` for unit tests.
- [x] Define `DiscoveredInputSourceDescriptor` as a pure, `Sendable`, `Equatable` struct.
- [x] Implement `InputSourceDiscoveryEngine` with 3-tier cascade:
  - Tier 1: `kTISPropertyInputSourceLanguages` ISO matching.
  - Tier 2: Token matching (Ukrainian, Russian, Birman, Colemak, Dvorak, Workman).
  - Tier 3: `UCKeyTranslate` probing in unshifted (`0`) and Option (`0x08`) states.

### Phase 2: Hybrid Layout Handling & Core Engine Protection
- [x] Update `LayoutDetector` with `activeSourceSupportedLayouts: Set<Layout>`.
- [x] Update `LayoutDetector.checkBuffer()`: validate against all languages in `activeSourceSupportedLayouts`.
- [x] Implement self-switch suppression in `LayoutDetector`: abort correction if target source ID equals current source ID.
- [x] Update `ScriptAnalyzer.resolvedSourceLayout` to honor hybrid layout membership.

### Phase 3: `InputSourceManager` Integration & Dynamic Notifications
- [x] Refactor `InputSourceManager.refreshInstalledSources()` to use `InputSourceDiscoveryEngine`.
- [x] Add persistence for preferred source IDs per layout (`SwitchFix_preferredInputSources`).
- [x] Expose `activeSourceSupportedLayouts()` and `discoveredDescriptors()`.
- [x] Add `matches(sourceID:layout:)` and `supportedLayouts(for sourceID:)`.
- [x] Add `kTISNotifyEnabledKeyboardInputSourcesChanged` observer in `AppDelegate.swift`.

### Phase 4: UI Updates
- [x] Update `StatusBarController.buildInstalledLayoutsMenu()`:
  - Add click-to-switch target action.
  - Display `(Custom)` or `(Hybrid)` tags for third-party layouts.
- [x] Add "Keyboards & Layouts" section in `SettingsView.swift` with preferred source picker per language.

### Phase 5: Test Suite & Verification
- [x] Add synthetic unit tests in `Sources/TestRunner/main.swift`:
  - Test Tier 1 language array matching (`["uk"]`, `["ru-RU"]`, etc.).
  - Test Tier 2 token parsing (`org.sil.ukelele.keyboardlayout.ru-ua-birman`).
  - Test Tier 3 Option-key probing on simulated Birman layout.
  - Test hybrid layout acceptance: verify Ukrainian words typed on Russian-preferred Birman trigger zero corrections.
  - Test QWERTY mistypes on Birman layout correctly switch to `ABC`.
- [x] Run `swift build`, `swift run TestRunner`, and `swift run InputPipelineTestRunner`.

---

## 10. Verification & Acceptance Criteria

1. **Issue #13 Resolution**:
   - On a system with `ABC` and `RU – UA – Birman` (no Apple Ukrainian/Russian layouts enabled):
     - `availableLayouts()` returns `[.english, .ukrainian, .russian]`.
     - Dictionaries for English, Ukrainian, and Russian are prewarmed on launch.
     - "Installed Layouts" menu lists `RU – UA – Birman` under both Ukrainian and Russian sections.
2. **Hybrid Layout Typing Invariant (No Death Spiral)**:
   - Typing Ukrainian words (`"привіт"`, `"єдина"`, `"м'яч"`) on `RU – UA – Birman` produces zero false corrections, zero backspaces, and zero layout flickers.
   - Typing Russian words (`"привет"`, `"это"`, `"хорошо"`) on `RU – UA – Birman` produces zero false corrections.
3. **QWERTY Correction on Custom Layout**:
   - Typing `"ghbdtn"` while on `ABC` converts to `"привіт"` (or `"привет"`) and cleanly switches layout to `RU – UA – Birman`.
   - Typing `"руддщ"` while on `RU – UA – Birman` converts to `"hello"` and cleanly switches layout to `ABC`.
4. **Dynamic Layout Discovery**:
   - Enabling a new layout in macOS Settings updates SwitchFix's installed layout list and prewarms dictionaries without restarting the app.
5. **Headless Test Suite**:
   - `swift test` / `swift run TestRunner` executes all synthetic classification tests without requiring Carbon GUI.
   - All 847+ pipeline tests in `InputPipelineTestRunner` pass with 0 regressions.
6. **Pipeline Invariants**:
   - No TIS enumeration or layout probing occurs on the event tap thread or in the typing hot path.

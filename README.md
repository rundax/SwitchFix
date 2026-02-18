# SwitchFix

macOS menu bar utility that auto-corrects keyboard layout mistakes. Type in the wrong layout (English instead of Ukrainian/Russian) and SwitchFix detects it, deletes the mistyped word, switches the layout, and retypes the correct text — like PuntoSwitcher, but native and lightweight.

## Features

- **Automatic correction** — detects wrong-layout words on space/enter and corrects them instantly
- **Hotkey mode** — correct only when you press Ctrl+Shift+Space (configurable)
- **Selection correction** — select text and press the hotkey to convert it
- **Undo** — Cmd+Z within 5 seconds reverts the last correction
- **Revert hotkey** — CapsLock reverts the last correction (configurable)
- **Three layouts** — English (US/ABC/British/Dvorak/Colemak), Ukrainian, Russian
- **Ukrainian variants** — auto-detects and supports both Ukrainian and Ukrainian Legacy keymaps
- **Smart filtering** — skips password fields, URLs, emails, camelCase, mixed scripts
- **App blacklist** — disabled in terminals, IDEs, and code editors by default (toggle per app)
- **Launch at Login** — optional auto-start via SMAppService
- **Confidence-based switching** — delays layout switch for ambiguous short words
- **Compact bundle** — ~11MB .app bundle with expanded dictionaries, no external dependencies

## Requirements

- macOS 13.0+
- Accessibility permission (prompted on first launch)
- Swift 5.9+ and Command Line Tools (for building)

## Build

```bash
# Debug build
swift build

# Run tests (54 tests, standalone runner — no Xcode required)
swift run TestRunner

# Build .app bundle (ad-hoc signed)
scripts/build-app.sh

# Create DMG for distribution
scripts/create-dmg.sh
```

The built app is at `dist/SwitchFix.app`.

## How It Works

1. **KeyboardMonitor** installs a CGEventTap (listen-only) to capture keystrokes
2. Characters accumulate in **LayoutDetector**'s word buffer
3. On word boundary (space, enter, tab), the buffer is checked:
   - Convert the word to alternative layouts via **LayoutMapper** character tables
   - Validate each conversion against **BloomFilter** dictionaries (EN: 48k, UK: 320k, RU: 146k words)
4. If a valid word is found in another layout, **TextCorrector**:
   - Deletes the mistyped characters (+ boundary char) via CGEvent backspaces
   - Switches the input source via TIS API
   - Retypes the correct text via `keyboardSetUnicodeString`
   - Retypes the boundary character (space/enter)

## Architecture

```
Sources/
├── SwitchFixApp/     # Entry point, AppDelegate (wires the pipeline)
├── Core/             # KeyboardMonitor, LayoutDetector, LayoutMapper,
│                     #   TextCorrector, InputSourceManager
├── Dictionary/       # BloomFilter, DictionaryLoader, WordValidator
│   └── Resources/    #   en_US.txt, uk_UA.txt, ru_RU.txt
├── UI/               # StatusBarController, PreferencesManager
└── Utils/            # Permissions (AXUIElement), AppFilter, KeyCodeMapping,
                      #   SystemHotkeyConflicts
```

## Menu Bar

SwitchFix lives in the menu bar with an **Ab** icon. The menu provides:

- **Enable/Disable** toggle
- **Correction Mode** — Automatic or Hotkey Only
- **Conflict warning** — shows when CapsLock is also used by macOS for input source switching
- **Installed Layouts** — shows all detected system layouts
- **Launch at Login**
- **Quit**

## Hotkey Configuration

SwitchFix stores hotkeys in `UserDefaults`:

- `SwitchFix_hotkeyKeyCode` + `SwitchFix_hotkeyModifiers` for correction hotkey (default: Ctrl+Shift+Space)
- `SwitchFix_revertHotkeyKeyCode` + `SwitchFix_revertHotkeyModifiers` for revert hotkey (default: CapsLock)

Examples:

```bash
# Set revert hotkey to CapsLock (no modifiers)
defaults write com.switchfix.app SwitchFix_revertHotkeyKeyCode -int 57
defaults write com.switchfix.app SwitchFix_revertHotkeyModifiers -int 0

# Set correction hotkey to Ctrl+Shift+Space
defaults write com.switchfix.app SwitchFix_hotkeyKeyCode -int 49
defaults write com.switchfix.app SwitchFix_hotkeyModifiers -int $((262144+131072))
```

If SwitchFix observes that pressing CapsLock also triggers a macOS input-source switch, it shows a conflict warning in the menu.

## Diagnostics

SwitchFix logs key decisions via `NSLog`. Open Console.app and filter for `[SwitchFix]` to see:

- Discovered input sources at startup
- Dictionary loading (word counts, paths)
- Detection decisions (buffer contents, conversion results)
- Correction actions (deletion count, layout switch, typed text)
- App switching (allowed/blocked)

## License

MIT

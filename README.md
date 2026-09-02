# SwitchFix

A macOS menu bar utility that automatically corrects keyboard layout mistakes. Type in the wrong layout (e.g., English instead of Ukrainian/Russian) and SwitchFix detects it, deletes the mistyped word, switches the layout, and retypes the correct text — like PuntoSwitcher, but native, lightweight, and modern.

![SwitchFix Demo](SwitchFix.gif)
![SwitchFix App Icon](Resources/Assets.xcassets/AppIcon.svg)

## Features

- **Automatic correction** — detects wrong-layout words on space/enter and corrects them instantly.
- **Hotkey mode** — correct only when you press Ctrl+Shift+Space (configurable).
- **Selection correction** — select text and press the hotkey to convert it.
- **Permissions indicator** — shows the status of required macOS permissions in the app menu.
- **Undo** — `Cmd+Z` within 5 seconds reverts the last correction.
- **Revert hotkey** — `CapsLock` reverts the last correction (configurable).
- **Three layouts** — English (US/ABC/British/Dvorak/Colemak), Ukrainian, and Russian.
- **Smart filtering** — skips password fields, URLs, emails, camelCase, mixed scripts.
- **App blacklist** — disabled in terminals, IDEs, and code editors by default (toggle per app).
- **Launch at Login** — optional auto-start.

## Requirements

- macOS 13.0 or later

## Installation

### From source

```bash
git clone https://github.com/rundax/SwitchFix.git
cd SwitchFix
./install.sh
```

The script builds the app, installs it to `/Applications`, sets it to run at startup, and guides you through the required **Accessibility** and **Input Monitoring** permissions.

> **Note:** Requires Xcode Command Line Tools. The script will prompt you to install them if missing.

### From DMG

Download a pre-built `.dmg` from the [Releases page](https://github.com/rundax/SwitchFix/releases), open it, and double-click **Install SwitchFix**.

## Development

### Stable code signing (recommended)

Ad-hoc signing (the default) changes the binary hash on every build, which forces you to re-grant Accessibility and Input Monitoring permissions each time. To avoid this, create a local code-signing certificate once:

```bash
./scripts/setup-codesign.sh
```

This creates a self-signed certificate in your Keychain and saves it to `.codesign-identity`. All subsequent builds via `build-app.sh` and `install.sh` will use it automatically — permissions survive rebuilds.

### Build without installing

```bash
./scripts/build-app.sh          # → dist/SwitchFix.app
```

### Create a DMG

```bash
./scripts/create-dmg.sh         # → dist/SwitchFix.dmg
```

## Menu Bar Options

SwitchFix lives in your menu bar with an **Ab** icon. The menu provides:
- **Enable/Disable** toggle
- **Correction Mode** — Automatic or Hotkey Only
- **Permissions Status** — visually indicates if required permissions are granted
- **Installed Layouts** — shows all detected system layouts
- **Launch at Login** — toggle automatic startup

## Advanced Configuration

SwitchFix stores hotkeys in `UserDefaults`. Customize via Terminal:

```bash
# Revert hotkey: CapsLock (no modifiers)
defaults write com.switchfix.app SwitchFix_revertHotkeyKeyCode -int 57
defaults write com.switchfix.app SwitchFix_revertHotkeyModifiers -int 0

# Correction hotkey: Ctrl+Shift+Space
defaults write com.switchfix.app SwitchFix_hotkeyKeyCode -int 49
defaults write com.switchfix.app SwitchFix_hotkeyModifiers -int $((262144+131072))
```

## How It Works

1. **KeyboardMonitor** securely captures keystrokes without blocking them.
2. Characters accumulate in a short-lived **LayoutDetector** word buffer.
3. On a word boundary (space, enter, tab), the buffer is checked against alternative layout dictionaries (e.g. checking if an English typo forms a valid Ukrainian word).
4. If a valid word is found in another layout, **TextCorrector** safely deletes the mistyped characters, switches your input layout, and retypes the correct word.

## License

MIT

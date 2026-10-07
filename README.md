# SwitchFix

A macOS menu bar utility that automatically corrects keyboard layout mistakes. Type in the wrong layout (e.g., English instead of Ukrainian/Russian) and SwitchFix detects it, deletes the mistyped word, switches the layout, and retypes the correct text — like PuntoSwitcher, but native, lightweight, and modern.

[![Website](https://img.shields.io/badge/Website-rundax.github.io%2FSwitchFix-blue?style=flat-square)](https://rundax.github.io/SwitchFix/)
[![Watch Demo Video](https://img.shields.io/badge/Demo-20s%20Video-purple?style=flat-square)](https://rundax.github.io/SwitchFix/#video)
[![Setup Guide](https://img.shields.io/badge/Guide-Interactive%20Setup-green?style=flat-square)](https://rundax.github.io/SwitchFix/tutorial/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

<p align="center">
  <a href="https://rundax.github.io/SwitchFix/#video">
    <img src="images/SwitchFix-video-poster.jpg" alt="SwitchFix 20s Launch Overview" width="800" style="border-radius: 12px; max-width: 100%;">
  </a>
  <br>
  <em>🎬 <strong><a href="https://rundax.github.io/SwitchFix/#video">Watch the 20-second video demo</a></strong> with sound and narration on the website.</em>
</p>

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

Open Terminal and run:

```bash
/bin/bash -o pipefail -c 'curl --fail --location --silent --show-error https://raw.githubusercontent.com/rundax/SwitchFix/master/install.sh | /bin/bash'
```

> 🌐 **Website**: Visit the [SwitchFix Landing Page](https://rundax.github.io/SwitchFix/) to try the live typo simulator and explore features.  
> 💡 **Visual Guide**: Need help setting up permissions? Check out the **[Interactive Setup Guide](https://rundax.github.io/SwitchFix/tutorial/)** (with step-by-step animations and practice simulators).

The installer downloads and verifies the native release for your Mac, installs it to `/Applications`, and opens SwitchFix. Follow the setup window: use **Open Settings + Show App** for Accessibility and, if keyboard input access is unavailable, Input Monitoring. Return to SwitchFix and wait for the live access check, then use **Try a correction** to confirm setup.

macOS can provide keyboard-listening access through Accessibility without listing SwitchFix under Input Monitoring. Public access checks (including IOHID) do not distinguish that from a separate Input Monitoring grant. The setup window therefore checks **Keyboard input access — Available**, not the separate toggle. It shows **Setup complete** when required access, the keyboard monitor, and mode prerequisites are ready. **Check Again** refreshes these live facts, and temporary correction pauses do not undo setup completion. The keyboard-input Settings button remains available to inspect or enable Input Monitoring.

Releases are free ad-hoc signed builds, not notarized. macOS may require a one-time approval in **System Settings → Privacy & Security → Open Anyway** before opening SwitchFix. Use this only for builds downloaded through the command above. Because ad-hoc signatures do not provide a stable publisher identity, an update may need fresh Accessibility and Input Monitoring grants. The setup window’s **Open Settings + Show App** buttons open the relevant pane and reveal the installed app in Finder. If a permission is checked but SwitchFix still reports **Not allowed** or **Unavailable**, select the old SwitchFix row, click **−**, then click **+** and add the current SwitchFix.app. Repeat in each affected pane and return to **Check Again**. Launch at Login is optional and can be enabled in Settings.

The currently published release predates the guided setup. Until version **0.0.10** is published, `install.sh` will refuse it and leave any existing installation unchanged.

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

import AppKit
import ServiceManagement

public class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var enableMenuItem: NSMenuItem!

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        setupIcon()
        setupMenu()

        statusItem.menu = menu
    }

    private func setupIcon() {
        guard let button = statusItem.button else { return }

        // Create a template image with "Ab" text for menu bar
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: "Ab", attributes: attrs)
            let strSize = str.size()
            let origin = NSPoint(
                x: (rect.width - strSize.width) / 2,
                y: (rect.height - strSize.height) / 2
            )
            str.draw(at: origin)
            return true
        }
        image.isTemplate = true
        button.image = image
        button.toolTip = "SwitchFix"
    }

    private func setupMenu() {
        let prefs = PreferencesManager.shared

        // Enable/Disable toggle
        enableMenuItem = NSMenuItem(
            title: prefs.isEnabled ? "Disable" : "Enable",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Correction mode submenu
        let modeMenu = NSMenu()
        let autoItem = NSMenuItem(title: "Automatic", action: #selector(setAutomaticMode), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = prefs.correctionMode == .automatic ? .on : .off
        modeMenu.addItem(autoItem)

        let hotkeyItem = NSMenuItem(title: "Hotkey Only", action: #selector(setHotkeyMode), keyEquivalent: "")
        hotkeyItem.target = self
        hotkeyItem.state = prefs.correctionMode == .hotkey ? .on : .off
        modeMenu.addItem(hotkeyItem)

        let modeMenuItem = NSMenuItem(title: "Correction Mode", action: nil, keyEquivalent: "")
        modeMenuItem.submenu = modeMenu
        menu.addItem(modeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = prefs.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit SwitchFix", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleEnabled() {
        let prefs = PreferencesManager.shared
        prefs.isEnabled = !prefs.isEnabled
        enableMenuItem.title = prefs.isEnabled ? "Disable" : "Enable"
        updateIcon()
    }

    @objc private func setAutomaticMode() {
        PreferencesManager.shared.correctionMode = .automatic
        refreshModeMenu()
    }

    @objc private func setHotkeyMode() {
        PreferencesManager.shared.correctionMode = .hotkey
        refreshModeMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let prefs = PreferencesManager.shared
        prefs.launchAtLogin = !prefs.launchAtLogin
        sender.state = prefs.launchAtLogin ? .on : .off

        if #available(macOS 13.0, *) {
            do {
                if prefs.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // SMAppService may fail without a proper bundle identifier
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshModeMenu() {
        let mode = PreferencesManager.shared.correctionMode
        guard let modeMenuItem = menu.items.first(where: { $0.title == "Correction Mode" }),
              let submenu = modeMenuItem.submenu else { return }
        for item in submenu.items {
            if item.title == "Automatic" {
                item.state = mode == .automatic ? .on : .off
            } else if item.title == "Hotkey Only" {
                item.state = mode == .hotkey ? .on : .off
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isEnabled = PreferencesManager.shared.isEnabled
        button.appearsDisabled = !isEnabled
    }
}

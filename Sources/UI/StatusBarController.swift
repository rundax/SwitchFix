import AppKit
import ServiceManagement
import Core
import Utils

public class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var enableMenuItem: NSMenuItem!
    private var appFilterMenuItem: NSMenuItem!
    private var installedLayoutsMenuItem: NSMenuItem!
    private var conflictMenuItem: NSMenuItem?
    private var conflictSeparatorItem: NSMenuItem?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        super.init()

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

        menu.delegate = self

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

        // App filter toggle for current app
        appFilterMenuItem = NSMenuItem(title: "Enable in Current App", action: #selector(toggleCurrentAppFilter), keyEquivalent: "")
        appFilterMenuItem.target = self
        menu.addItem(appFilterMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Installed layouts submenu
        installedLayoutsMenuItem = NSMenuItem(title: "Installed Layouts", action: nil, keyEquivalent: "")
        installedLayoutsMenuItem.submenu = buildInstalledLayoutsMenu()
        menu.addItem(installedLayoutsMenuItem)

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

        refreshSystemHotkeyConflictIndicator()
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

    @objc private func toggleCurrentAppFilter(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if AppFilter.shared.isBlacklisted(bundleID) {
            AppFilter.shared.removeFromBlacklist(bundleID)
        } else {
            AppFilter.shared.addToBlacklist(bundleID)
        }
        refreshAppFilterMenuItem()
    }

    private func refreshAppFilterMenuItem() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            appFilterMenuItem.title = "App Filtering Unavailable"
            appFilterMenuItem.isEnabled = false
            appFilterMenuItem.representedObject = nil
            return
        }

        let name = app.localizedName ?? "Current App"
        appFilterMenuItem.isEnabled = true
        appFilterMenuItem.representedObject = bundleID

        if AppFilter.shared.isBlacklisted(bundleID) {
            appFilterMenuItem.title = "Enable in \(name)"
        } else {
            appFilterMenuItem.title = "Disable in \(name)"
        }
    }

    private func buildInstalledLayoutsMenu() -> NSMenu {
        let sub = NSMenu()
        let sourcesByLayout = InputSourceManager.shared.availableInputSourcesByLayout()
        let currentID = InputSourceManager.shared.currentInputSourceID()

        var added = false
        for layout in Layout.allCases {
            guard let sources = sourcesByLayout[layout], !sources.isEmpty else { continue }
            let layoutItem = NSMenuItem(title: layout.displayName, action: nil, keyEquivalent: "")
            let layoutMenu = NSMenu()
            for source in sources {
                let item = NSMenuItem(title: source.name, action: nil, keyEquivalent: "")
                item.toolTip = source.id
                if source.id == currentID {
                    item.state = .on
                }
                layoutMenu.addItem(item)
            }
            layoutItem.submenu = layoutMenu
            sub.addItem(layoutItem)
            added = true
        }

        if !added {
            let item = NSMenuItem(title: "No supported layouts found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }

        return sub
    }

    private func refreshInstalledLayoutsMenu() {
        installedLayoutsMenuItem.submenu = buildInstalledLayoutsMenu()
    }

    private func refreshSystemHotkeyConflictIndicator() {
        let hasConflict = SystemHotkeyConflicts.hasCapsLockConflict(
            revertHotkeyKeyCode: PreferencesManager.shared.revertHotkeyKeyCode
        )

        if hasConflict {
            if conflictMenuItem == nil {
                let item = NSMenuItem(
                    title: "Warning: CapsLock conflicts with macOS input switching",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.toolTip = "CapsLock is configured both in SwitchFix (revert) and in macOS (input source switch)."

                let separator = NSMenuItem.separator()
                menu.insertItem(item, at: 0)
                menu.insertItem(separator, at: 1)
                conflictMenuItem = item
                conflictSeparatorItem = separator
            }
            statusItem.button?.toolTip = "SwitchFix (CapsLock conflict detected)"
        } else {
            if let item = conflictMenuItem {
                menu.removeItem(item)
                conflictMenuItem = nil
            }
            if let separator = conflictSeparatorItem {
                menu.removeItem(separator)
                conflictSeparatorItem = nil
            }
            statusItem.button?.toolTip = "SwitchFix"
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            refreshSystemHotkeyConflictIndicator()
            refreshAppFilterMenuItem()
            refreshInstalledLayoutsMenu()
        }
    }
}

import Foundation
import AppKit

public class AppFilter {
    public static let shared = AppFilter()

    private let defaults = UserDefaults.standard
    private static let blacklistKey = "SwitchFix_blacklistedApps"

    /// Default blacklisted bundle IDs — apps where correction should be disabled.
    private static let defaultBlacklist: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "org.vim.MacVim",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.CLion",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.rubymine",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.fleet",
    ]

    private var blacklistedBundleIDs: Set<String>

    private init() {
        if let saved = defaults.stringArray(forKey: AppFilter.blacklistKey) {
            blacklistedBundleIDs = Set(saved)
        } else {
            blacklistedBundleIDs = AppFilter.defaultBlacklist
        }
    }

    /// Check if correction is allowed for the currently frontmost application.
    public func isCurrentAppAllowed() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return true
        }
        return !blacklistedBundleIDs.contains(bundleID)
    }

    public func addToBlacklist(_ bundleID: String) {
        blacklistedBundleIDs.insert(bundleID)
        save()
    }

    public func removeFromBlacklist(_ bundleID: String) {
        blacklistedBundleIDs.remove(bundleID)
        save()
    }

    public func isBlacklisted(_ bundleID: String) -> Bool {
        return blacklistedBundleIDs.contains(bundleID)
    }

    public var allBlacklisted: [String] {
        return Array(blacklistedBundleIDs).sorted()
    }

    private func save() {
        defaults.set(Array(blacklistedBundleIDs), forKey: AppFilter.blacklistKey)
    }
}

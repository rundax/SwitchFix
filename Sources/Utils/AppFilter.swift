import Foundation
import AppKit
import os

public class AppFilter {
    public static let shared = AppFilter()

    private let defaults = UserDefaults.standard
    private static let legacyBlacklistKey = "SwitchFix_blacklistedApps"
    private static let userAddedKey = "SwitchFix_userAddedApps"
    private static let userRemovedKey = "SwitchFix_userRemovedApps"

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

    private struct State {
        var userAdded: Set<String>
        var userRemoved: Set<String>

        var effective: Set<String> {
            AppFilter.defaultBlacklist.union(userAdded).subtracting(userRemoved)
        }
    }

    // Persisting user deltas (instead of the full effective set) lets default
    // blacklist additions in future releases apply to existing users.
    private let state: OSAllocatedUnfairLock<State>

    private init() {
        var userAdded = Set(defaults.stringArray(forKey: AppFilter.userAddedKey) ?? [])
        var userRemoved = Set(defaults.stringArray(forKey: AppFilter.userRemovedKey) ?? [])

        // Migrate the legacy full-set format: reconstruct deltas against defaults.
        if defaults.object(forKey: AppFilter.userAddedKey) == nil,
           defaults.object(forKey: AppFilter.userRemovedKey) == nil,
           let legacySaved = defaults.stringArray(forKey: AppFilter.legacyBlacklistKey) {
            let saved = Set(legacySaved)
            userAdded = saved.subtracting(AppFilter.defaultBlacklist)
            userRemoved = AppFilter.defaultBlacklist.subtracting(saved)
            defaults.set(Array(userAdded), forKey: AppFilter.userAddedKey)
            defaults.set(Array(userRemoved), forKey: AppFilter.userRemovedKey)
        }

        state = OSAllocatedUnfairLock(initialState: State(userAdded: userAdded, userRemoved: userRemoved))
    }

    /// Check if correction is allowed for the currently frontmost application.
    public func isCurrentAppAllowed() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return true
        }
        return !isBlacklisted(bundleID)
    }

    public func addToBlacklist(_ bundleID: String) {
        state.withLock { value in
            value.userRemoved.remove(bundleID)
            if !AppFilter.defaultBlacklist.contains(bundleID) {
                value.userAdded.insert(bundleID)
            }
            save(value)
        }
        NotificationCenter.default.post(name: .appFilterDidChange, object: nil)
    }

    public func removeFromBlacklist(_ bundleID: String) {
        state.withLock { value in
            value.userAdded.remove(bundleID)
            if AppFilter.defaultBlacklist.contains(bundleID) {
                value.userRemoved.insert(bundleID)
            }
            save(value)
        }
        NotificationCenter.default.post(name: .appFilterDidChange, object: nil)
    }

    public func isBlacklisted(_ bundleID: String) -> Bool {
        state.withLock { $0.effective.contains(bundleID) }
    }

    public var allBlacklisted: [String] {
        state.withLock { Array($0.effective).sorted() }
    }

    private func save(_ value: State) {
        defaults.set(Array(value.userAdded), forKey: AppFilter.userAddedKey)
        defaults.set(Array(value.userRemoved), forKey: AppFilter.userRemovedKey)
        // Keep the legacy key in sync so downgrades keep the user's list.
        defaults.set(Array(value.effective), forKey: AppFilter.legacyBlacklistKey)
    }
}

public extension Notification.Name {
    static let appFilterDidChange = Notification.Name("SwitchFix_AppFilterDidChange")
}

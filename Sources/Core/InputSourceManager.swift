import Foundation
import Carbon

public class InputSourceManager {
    public static let shared = InputSourceManager()

    private var cachedLayout: Layout?

    private init() {
        // Listen for input source changes to invalidate cache
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        cachedLayout = nil
    }

    /// Get the current active keyboard layout (cached until input source changes).
    public func currentLayout() -> Layout {
        if let cached = cachedLayout {
            return cached
        }
        let layout = fetchCurrentLayout()
        cachedLayout = layout
        return layout
    }

    /// Force-refresh the cached layout after a programmatic switch.
    public func invalidateCache() {
        cachedLayout = nil
    }

    private func fetchCurrentLayout() -> Layout {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .english
        }

        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return .english
        }

        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

        // Match known layout identifiers
        for layout in Layout.allCases {
            if sourceID == layout.inputSourceID || sourceID.contains(layout.inputSourceID) {
                return layout
            }
        }

        // Fallback: check if the source ID contains language hints
        let lowered = sourceID.lowercased()
        if lowered.contains("russian") { return .russian }
        if lowered.contains("ukrainian") { return .ukrainian }

        return .english
    }

    /// Switch to the specified keyboard layout.
    public func switchTo(_ layout: Layout) {
        let targetID = layout.inputSourceID

        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            if sourceID == targetID {
                TISSelectInputSource(source)
                cachedLayout = layout
                return
            }
        }
    }

    /// Get all available keyboard layouts installed on the system.
    public func availableLayouts() -> [Layout] {
        var result = [Layout]()

        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return result
        }

        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            for layout in Layout.allCases {
                if sourceID == layout.inputSourceID && !result.contains(layout) {
                    result.append(layout)
                }
            }
        }

        return result
    }
}

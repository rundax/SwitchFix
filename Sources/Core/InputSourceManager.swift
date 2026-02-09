import Foundation
import Carbon

public class InputSourceManager {
    public static let shared = InputSourceManager()

    private init() {}

    /// Get the current active keyboard layout.
    public func currentLayout() -> Layout {
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

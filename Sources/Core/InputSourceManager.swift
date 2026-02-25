import Foundation
import Carbon

public class InputSourceManager {
    public static let shared = InputSourceManager()

    private var cachedLayout: Layout?

    /// Maps each Layout to the user's actual installed input source ID.
    /// Populated at startup by `discoverInstalledSources()`.
    private var installedSourceIDs: [Layout: String] = [:]
    private var ukrainianVariantBySourceID: [String: UkrainianKeyboardVariant] = [:]

    private static let sKeyCode: UInt16 = 1
    private static let bKeyCode: UInt16 = 11

    private init() {
        // Listen for input source changes to invalidate cache
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        discoverInstalledSources()
    }

    @objc private func inputSourceChanged() {
        cachedLayout = nil
    }

    public struct InputSourceDescriptor: Equatable {
        public let id: String
        public let name: String
    }

    /// Scan all installed input sources and record the actual ID for each Layout.
    private func discoverInstalledSources() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            guard let sourceID = stringProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceName = stringProperty(source, kTISPropertyLocalizedName)

            for layout in Layout.allCases {
                if layout.matches(sourceID: sourceID) && installedSourceIDs[layout] == nil {
                    installedSourceIDs[layout] = sourceID
                    NSLog("[SwitchFix] Discovered layout: %@ → %@", layout.rawValue, sourceID)
                }
            }

            if Layout.ukrainian.matches(sourceID: sourceID) && ukrainianVariantBySourceID[sourceID] == nil {
                let variant = detectUkrainianVariant(for: source, sourceName: sourceName)
                ukrainianVariantBySourceID[sourceID] = variant
                NSLog("[SwitchFix] Ukrainian variant: %@ → %@", sourceID, variant.rawValue)
            }
        }
    }

    /// Get the current active keyboard layout (cached until input source changes).
    public func currentLayout() -> Layout {
        // Query TIS every time to avoid stale cache when system notifications are missed.
        let layout = fetchCurrentLayout()
        cachedLayout = layout
        return layout
    }

    /// Force-refresh the cached layout after a programmatic switch.
    public func invalidateCache() {
        cachedLayout = nil
    }

    /// The raw input source ID of the current keyboard layout.
    public func currentInputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    private func fetchCurrentLayout() -> Layout {
        let sourceID = currentInputSourceID()

        // Match against all known IDs for each layout
        for layout in Layout.allCases {
            if layout.matches(sourceID: sourceID) {
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
    /// Tries the user's actual installed source ID first, then falls back to all known IDs.
    public func switchTo(_ layout: Layout) {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            NSLog("[SwitchFix] switchTo(%@): failed to list input sources", layout.rawValue)
            return
        }

        // Build a priority-ordered list of IDs to try
        var targetIDs = layout.inputSourceIDs
        if let installed = installedSourceIDs[layout] {
            // Put the discovered installed ID first
            targetIDs.removeAll { $0 == installed }
            targetIDs.insert(installed, at: 0)
        }

        for targetID in targetIDs {
            for source in sources {
                guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                    continue
                }
                let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

                if sourceID == targetID {
                    let status = TISSelectInputSource(source)
                    NSLog("[SwitchFix] switchTo(%@): selected %@ (status: %d)", layout.rawValue, sourceID, status)
                    cachedLayout = layout
                    return
                }
            }
        }

        NSLog("[SwitchFix] switchTo(%@): no matching source found among %d sources", layout.rawValue, sources.count)
    }

    /// Get all available keyboard layouts installed on the system.
    public func availableLayouts() -> [Layout] {
        let byLayout = availableInputSourcesByLayout()
        return Layout.allCases.filter { !(byLayout[$0]?.isEmpty ?? true) }
    }

    /// Get installed input sources grouped by supported layout.
    public func availableInputSourcesByLayout() -> [Layout: [InputSourceDescriptor]] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return [:]
        }

        var result: [Layout: [InputSourceDescriptor]] = [:]

        for source in sources {
            guard let sourceID = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName) else {
                continue
            }

            if let type = stringProperty(source, kTISPropertyInputSourceType),
               type != (kTISTypeKeyboardLayout as String) {
                continue
            }

            for layout in Layout.allCases where layout.matches(sourceID: sourceID) {
                var list = result[layout] ?? []
                if !list.contains(where: { $0.id == sourceID }) {
                    list.append(InputSourceDescriptor(id: sourceID, name: name))
                }
                result[layout] = list
            }
        }

        // Sort each layout's sources by localized name
        for (layout, list) in result {
            result[layout] = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        return result
    }

    /// Variant for the currently selected Ukrainian input source, if current source is Ukrainian.
    public func currentUkrainianVariant() -> UkrainianKeyboardVariant? {
        let sourceID = currentInputSourceID()
        guard Layout.ukrainian.matches(sourceID: sourceID) else { return nil }
        return ukrainianVariant(forInputSourceID: sourceID)
    }

    /// Variant that SwitchFix will target when switching to Ukrainian.
    public func preferredUkrainianVariant() -> UkrainianKeyboardVariant {
        guard let preferredID = installedSourceIDs[.ukrainian],
              let variant = ukrainianVariant(forInputSourceID: preferredID) else {
            return .standard
        }
        return variant
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func ukrainianVariant(forInputSourceID sourceID: String) -> UkrainianKeyboardVariant? {
        if let cached = ukrainianVariantBySourceID[sourceID] {
            return cached
        }

        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        for source in sources {
            guard let id = stringProperty(source, kTISPropertyInputSourceID), id == sourceID else { continue }
            let sourceName = stringProperty(source, kTISPropertyLocalizedName)
            let variant = detectUkrainianVariant(for: source, sourceName: sourceName)
            ukrainianVariantBySourceID[sourceID] = variant
            return variant
        }

        return nil
    }

    private func detectUkrainianVariant(
        for source: TISInputSource,
        sourceName: String?
    ) -> UkrainianKeyboardVariant {
        if let sChar = translatedCharacter(for: source, keyCode: InputSourceManager.sKeyCode),
           let bChar = translatedCharacter(for: source, keyCode: InputSourceManager.bKeyCode) {
            if sChar == "и", bChar == "і" {
                return .legacy
            }
            if sChar == "і", bChar == "и" {
                return .standard
            }
        }

        if let name = sourceName?.lowercased(), name.contains("legacy") {
            return .legacy
        }

        return .standard
    }

    private func translatedCharacter(for source: TISInputSource, keyCode: UInt16) -> Character? {
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        let keyboardLayout = layoutData.withUnsafeBytes { ptr in
            ptr.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else { return nil }
        let str = String(utf16CodeUnits: chars, count: actualLength)
        return str.first
    }
}

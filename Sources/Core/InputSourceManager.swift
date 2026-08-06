import Carbon
import Foundation
import os

public final class InputSourceManager {
    public static let shared = InputSourceManager()

    public struct InputSourceDescriptor: Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private struct State {
        var preferredSources: [Layout: TISInputSource] = [:]
        var sourceIDs: [Layout: String] = [:]
        var descriptors: [Layout: [InputSourceDescriptor]] = [:]
        var ukrainianVariants: [String: UkrainianKeyboardVariant] = [:]
        var currentLayout: Layout?
        var currentInputSourceID: String?
        var pendingSelectionID: String?
    }

    private struct SelectionCallbacks {
        var willSelect: ((Layout, String) -> Void)?
        var selectionFailed: (() -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let selectionCallbacks = OSAllocatedUnfairLock(initialState: SelectionCallbacks())
    private static let sKeyCode: UInt16 = 1
    private static let bKeyCode: UInt16 = 11

    private init() {
        refreshInstalledSources()
    }

    /// Refresh source discovery away from the input and correction hot paths.
    public func refreshInstalledSources() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        var preferred: [Layout: TISInputSource] = [:]
        var ids: [Layout: String] = [:]
        var descriptors: [Layout: [InputSourceDescriptor]] = [:]
        var variants: [String: UkrainianKeyboardVariant] = [:]

        for source in sources {
            guard let sourceID = Self.stringProperty(source, kTISPropertyInputSourceID),
                  let layout = Layout.allCases.first(where: { $0.matches(sourceID: sourceID) }) else {
                continue
            }
            let sourceName = Self.stringProperty(source, kTISPropertyLocalizedName) ?? sourceID
            if let type = Self.stringProperty(source, kTISPropertyInputSourceType),
               type != (kTISTypeKeyboardLayout as String) {
                continue
            }

            if preferred[layout] == nil {
                preferred[layout] = source
                ids[layout] = sourceID
            }
            descriptors[layout, default: []].append(InputSourceDescriptor(id: sourceID, name: sourceName))
            if layout == .ukrainian {
                variants[sourceID] = Self.detectUkrainianVariant(for: source, sourceName: sourceName)
            }
        }

        for (layout, list) in descriptors {
            descriptors[layout] = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let discoveredPreferred = preferred
        let discoveredIDs = ids
        let discoveredDescriptors = descriptors
        let discoveredVariants = variants
        state.withLock { value in
            value.preferredSources = discoveredPreferred
            value.sourceIDs = discoveredIDs
            value.descriptors = discoveredDescriptors
            value.ukrainianVariants = discoveredVariants
        }
    }

    public func refreshCurrentInputSource() {
        let sourceID = Self.fetchCurrentInputSourceID()
        let layout = Self.layout(for: sourceID)
        state.withLock { value in
            value.currentInputSourceID = sourceID
            value.currentLayout = layout
        }
    }

    public func setSelectionCallbacks(
        willSelect: ((Layout, String) -> Void)?,
        selectionFailed: (() -> Void)?
    ) {
        selectionCallbacks.withLock { value in
            value.willSelect = willSelect
            value.selectionFailed = selectionFailed
        }
    }

    public func consumeExpectedSelection(sourceID: String) -> Bool {
        state.withLock { value in
            guard let pending = value.pendingSelectionID else { return false }
            value.pendingSelectionID = nil
            return pending == sourceID
        }
    }

    public func currentLayout() -> Layout {
        if let cached = state.withLock({ $0.currentLayout }) {
            return cached
        }
        refreshCurrentInputSource()
        return state.withLock { $0.currentLayout ?? .english }
    }

    public func currentInputSourceID() -> String {
        if let cached = state.withLock({ $0.currentInputSourceID }) {
            return cached
        }
        refreshCurrentInputSource()
        return state.withLock { $0.currentInputSourceID ?? "unknown" }
    }

    /// Select a cached source with one TIS call and no source enumeration.
    @discardableResult
    public func switchTo(_ layout: Layout) -> Bool {
        guard let target = state.withLock({ value -> (TISInputSource, String)? in
            guard let source = value.preferredSources[layout],
                  let sourceID = value.sourceIDs[layout] else {
                return nil
            }
            if value.currentInputSourceID == sourceID {
                return (source, sourceID)
            }
            value.pendingSelectionID = sourceID
            return (source, sourceID)
        }) else {
            NSLog("[SwitchFix] switchTo(%@): no cached source", layout.rawValue)
            return false
        }
        if currentInputSourceID() == target.1 {
            state.withLock { $0.pendingSelectionID = nil }
            return true
        }

        let callbacks = selectionCallbacks.withLock { $0 }
        callbacks.willSelect?(layout, target.1)
        let status = TISSelectInputSource(target.0)
        if status != noErr {
            state.withLock { value in
                if value.pendingSelectionID == target.1 {
                    value.pendingSelectionID = nil
                }
            }
            callbacks.selectionFailed?()
            NSLog("[SwitchFix] switchTo(%@): TISSelectInputSource failed (%d)", layout.rawValue, status)
        }
        return status == noErr
    }

    public func availableLayouts() -> [Layout] {
        let available = state.withLock { Set($0.descriptors.keys) }
        return Layout.allCases.filter { available.contains($0) }
    }

    public func availableInputSourcesByLayout() -> [Layout: [InputSourceDescriptor]] {
        state.withLock { $0.descriptors }
    }

    public func currentUkrainianVariant() -> UkrainianKeyboardVariant? {
        let sourceID = currentInputSourceID()
        guard Layout.ukrainian.matches(sourceID: sourceID) else { return nil }
        return ukrainianVariant(forInputSourceID: sourceID)
    }

    public func preferredUkrainianVariant() -> UkrainianKeyboardVariant {
        state.withLock { value in
            guard let id = value.sourceIDs[.ukrainian] else { return .standard }
            return value.ukrainianVariants[id] ?? .standard
        }
    }

    public func ukrainianVariant(forInputSourceID sourceID: String) -> UkrainianKeyboardVariant? {
        state.withLock { $0.ukrainianVariants[sourceID] }
    }

    private static func fetchCurrentInputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = stringProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return id
    }

    private static func layout(for sourceID: String) -> Layout {
        if let layout = Layout.allCases.first(where: { $0.matches(sourceID: sourceID) }) {
            return layout
        }
        let lowered = sourceID.lowercased()
        if lowered.contains("russian") { return .russian }
        if lowered.contains("ukrainian") { return .ukrainian }
        return .english
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func detectUkrainianVariant(
        for source: TISInputSource,
        sourceName: String?
    ) -> UkrainianKeyboardVariant {
        if let sCharacter = translatedCharacter(for: source, keyCode: sKeyCode),
           let bCharacter = translatedCharacter(for: source, keyCode: bKeyCode) {
            if sCharacter == "и", bCharacter == "і" { return .legacy }
            if sCharacter == "і", bCharacter == "и" { return .standard }
        }
        if sourceName?.lowercased().contains("legacy") == true {
            return .legacy
        }
        return .standard
    }

    private static func translatedCharacter(for source: TISInputSource, keyCode: UInt16) -> Character? {
        guard let layoutDataReference = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataReference, to: CFData.self) as Data
        guard let keyboardLayout = layoutData.withUnsafeBytes({ pointer in
            pointer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
        }) else {
            return nil
        }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &actualLength,
            &characters
        )
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: actualLength).first
    }
}

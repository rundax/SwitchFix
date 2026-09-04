import Carbon
import Foundation
import os
import Utils

public final class InputSourceManager {
    public static let shared = InputSourceManager()

    public typealias InputSourceDescriptor = DiscoveredInputSourceDescriptor

    private struct State {
        var rawSources: [String: TISInputSource] = [:]
        var preferredSources: [Layout: TISInputSource] = [:]
        var sourceIDs: [Layout: String] = [:]
        var descriptors: [Layout: [DiscoveredInputSourceDescriptor]] = [:]
        var allDiscoveredDescriptors: [DiscoveredInputSourceDescriptor] = []
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

    private init() {
        refreshInstalledSources()
    }

    /// Refresh source discovery away from the input and correction hot paths.
    public func refreshInstalledSources() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        var raw: [String: TISInputSource] = [:]
        var descriptors: [Layout: [DiscoveredInputSourceDescriptor]] = [:]
        var allDescriptors: [DiscoveredInputSourceDescriptor] = []
        var variants: [String: UkrainianKeyboardVariant] = [:]

        for source in sources {
            let adapter = CarbonTISPropertyAdapter(source: source)
            guard let descriptor = InputSourceDiscoveryEngine.classify(provider: adapter) else {
                continue
            }
            raw[descriptor.id] = source
            allDescriptors.append(descriptor)
            if let variant = descriptor.ukrainianVariant {
                variants[descriptor.id] = variant
            }
            for layout in descriptor.supportedLayouts {
                descriptors[layout, default: []].append(descriptor)
            }
        }

        for (layout, list) in descriptors {
            descriptors[layout] = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let savedPrefs = UserDefaults.standard.dictionary(forKey: "SwitchFix_preferredInputSources") as? [String: String] ?? [:]
        var preferred: [Layout: TISInputSource] = [:]
        var ids: [Layout: String] = [:]

        for layout in Layout.allCases {
            guard let list = descriptors[layout], !list.isEmpty else { continue }
            let chosenID: String
            if let saved = savedPrefs[layout.rawValue], list.contains(where: { $0.id == saved }) {
                chosenID = saved
            } else if let native = list.first(where: { !$0.isCustom }) {
                chosenID = native.id
            } else {
                chosenID = list[0].id
            }
            ids[layout] = chosenID
            preferred[layout] = raw[chosenID]
        }

        let discoveredRaw = raw
        let discoveredPreferred = preferred
        let discoveredIDs = ids
        let discoveredDescriptors = descriptors
        let discoveredAllDescriptors = allDescriptors
        let discoveredVariants = variants

        state.withLock { value in
            value.rawSources = discoveredRaw
            value.preferredSources = discoveredPreferred
            value.sourceIDs = discoveredIDs
            value.descriptors = discoveredDescriptors
            value.allDiscoveredDescriptors = discoveredAllDescriptors
            value.ukrainianVariants = discoveredVariants
        }
    }

    public func refreshCurrentInputSource() {
        let sourceID = Self.fetchCurrentInputSourceID()
        guard sourceID != "unknown" else { return }
        state.withLock { value in
            value.currentInputSourceID = sourceID
            let supported = value.allDiscoveredDescriptors.first(where: { $0.id == sourceID })?.supportedLayouts
                ?? Self.fallbackSupportedLayouts(for: sourceID)
            if let existing = value.currentLayout, supported.contains(existing) {
                return
            }
            for layout in Layout.allCases {
                if value.sourceIDs[layout] == sourceID {
                    value.currentLayout = layout
                    return
                }
            }
            if supported.contains(.ukrainian) {
                value.currentLayout = .ukrainian
            } else if supported.contains(.russian) {
                value.currentLayout = .russian
            } else if supported.contains(.english) {
                value.currentLayout = .english
            } else {
                value.currentLayout = .english
            }
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
        refreshCurrentInputSource()
        return state.withLock { $0.currentLayout ?? .english }
    }

    public func currentInputSourceID() -> String {
        refreshCurrentInputSource()
        return state.withLock { $0.currentInputSourceID ?? "unknown" }
    }

    public func sourceID(for layout: Layout) -> String? {
        state.withLock { $0.sourceIDs[layout] }
    }

    public func setPreferredSource(id: String, for layout: Layout) {
        state.withLock { value in
            guard let source = value.rawSources[id] else { return }
            value.preferredSources[layout] = source
            value.sourceIDs[layout] = id
            var savedPrefs = UserDefaults.standard.dictionary(forKey: "SwitchFix_preferredInputSources") as? [String: String] ?? [:]
            savedPrefs[layout.rawValue] = id
            UserDefaults.standard.set(savedPrefs, forKey: "SwitchFix_preferredInputSources")
        }
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    public func activeSourceSupportedLayouts() -> Set<Layout> {
        let currentID = currentInputSourceID()
        return supportedLayouts(for: currentID)
    }

    public func supportedLayouts(for sourceID: String) -> Set<Layout> {
        state.withLock { value in
            if let desc = value.allDiscoveredDescriptors.first(where: { $0.id == sourceID }) {
                return desc.supportedLayouts
            }
            return Self.fallbackSupportedLayouts(for: sourceID)
        }
    }

    public func matches(sourceID: String, layout: Layout) -> Bool {
        supportedLayouts(for: sourceID).contains(layout)
    }

    public func discoveredDescriptors() -> [DiscoveredInputSourceDescriptor] {
        state.withLock { $0.allDiscoveredDescriptors }
    }

    /// Select a cached source with one TIS call and no source enumeration.
    @discardableResult
    public func switchTo(_ layout: Layout) -> Bool {
        guard let target = state.withLock({ value -> (TISInputSource, String)? in
            guard let source = value.preferredSources[layout],
                  let sourceID = value.sourceIDs[layout] else {
                return nil
            }
            value.pendingSelectionID = sourceID
            return (source, sourceID)
        }) else {
            SwitchFixLog.source.error("switchTo(\(layout.rawValue)): no cached input source")
            return false
        }

        let liveSourceID = Self.fetchCurrentInputSourceID()
        let callbacks = selectionCallbacks.withLock { $0 }

        if liveSourceID == target.1 {
            state.withLock {
                $0.pendingSelectionID = nil
                $0.currentInputSourceID = target.1
                $0.currentLayout = layout
            }
            callbacks.willSelect?(layout, target.1)
            SwitchFixLog.source.debug("switchTo(\(layout.rawValue)): already active")
            return true
        }

        callbacks.willSelect?(layout, target.1)
        let status = TISSelectInputSource(target.0)
        if status != noErr {
            state.withLock { value in
                if value.pendingSelectionID == target.1 {
                    value.pendingSelectionID = nil
                }
            }
            callbacks.selectionFailed?()
            SwitchFixLog.source.error("switchTo(\(layout.rawValue)): TISSelectInputSource failed (\(status))")
        } else {
            state.withLock {
                $0.currentInputSourceID = target.1
                $0.currentLayout = layout
            }
            SwitchFixLog.source.notice("layout switched to \(layout.rawValue) (\(target.1))")
        }
        return status == noErr
    }

    @discardableResult
    public func switchToSource(id: String) -> Bool {
        guard let target = state.withLock({ value -> (TISInputSource, Layout)? in
            guard let source = value.rawSources[id] else { return nil }
            let layout = value.allDiscoveredDescriptors.first(where: { $0.id == id })?.supportedLayouts.first ?? .english
            value.pendingSelectionID = id
            return (source, layout)
        }) else {
            SwitchFixLog.source.error("switchToSource(\(id)): no cached input source")
            return false
        }

        let liveSourceID = Self.fetchCurrentInputSourceID()
        let callbacks = selectionCallbacks.withLock { $0 }

        if liveSourceID == id {
            state.withLock {
                $0.pendingSelectionID = nil
                $0.currentInputSourceID = id
                $0.currentLayout = target.1
            }
            callbacks.willSelect?(target.1, id)
            SwitchFixLog.source.debug("switchToSource(\(id)): already active")
            return true
        }

        callbacks.willSelect?(target.1, id)
        let status = TISSelectInputSource(target.0)
        if status != noErr {
            state.withLock { value in
                if value.pendingSelectionID == id {
                    value.pendingSelectionID = nil
                }
            }
            callbacks.selectionFailed?()
            SwitchFixLog.source.error("switchToSource(\(id)): TISSelectInputSource failed (\(status))")
        } else {
            state.withLock {
                $0.currentInputSourceID = id
                $0.currentLayout = target.1
            }
            SwitchFixLog.source.notice("layout switched to source \(id)")
        }
        return status == noErr
    }

    public func availableLayouts() -> [Layout] {
        let available = state.withLock { Set($0.descriptors.keys) }
        return Layout.allCases.filter { available.contains($0) }
    }

    public func availableInputSourcesByLayout() -> [Layout: [DiscoveredInputSourceDescriptor]] {
        state.withLock { $0.descriptors }
    }

    public func currentUkrainianVariant() -> UkrainianKeyboardVariant? {
        let sourceID = currentInputSourceID()
        guard matches(sourceID: sourceID, layout: .ukrainian) else { return nil }
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

    private static func fallbackSupportedLayouts(for sourceID: String) -> Set<Layout> {
        var matched = Set<Layout>()
        for layout in Layout.allCases {
            if layout.matches(sourceID: sourceID) {
                matched.insert(layout)
            }
        }
        if !matched.isEmpty { return matched }
        let lowered = sourceID.lowercased()
        if lowered.contains("russian") { matched.insert(.russian) }
        if lowered.contains("ukrainian") { matched.insert(.ukrainian) }
        if lowered.contains("birman") {
            matched.insert(.russian)
            matched.insert(.ukrainian)
        }
        return matched.isEmpty ? [.english] : matched
    }

    static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

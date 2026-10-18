import Foundation
import Dictionary
import Utils

/// Represents a detection result — the target layout and converted word.
public struct DetectionResult {
    public let sourceLayout: Layout
    public let targetLayout: Layout
    public let convertedWord: String
    public let originalWord: String
    public let shouldSwitchLayout: Bool

    public init(
        sourceLayout: Layout,
        targetLayout: Layout,
        convertedWord: String,
        originalWord: String,
        shouldSwitchLayout: Bool
    ) {
        self.sourceLayout = sourceLayout
        self.targetLayout = targetLayout
        self.convertedWord = convertedWord
        self.originalWord = originalWord
        self.shouldSwitchLayout = shouldSwitchLayout
    }
}

/// State machine for layout detection.
public enum DetectorState {
    case idle
    case buffering
    case detecting
}

/// Delegate protocol for layout detection events.
public protocol LayoutDetectorDelegate: AnyObject {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?)
}

public class LayoutDetector {
    public weak var delegate: LayoutDetectorDelegate?

    /// Minimum characters before triggering detection.
    public var detectionThreshold: Int = 3

    /// Require this many consecutive wrong-layout words before correcting.
    public var consecutiveThreshold: Int = 1
    public var lowConfidenceMaxLength: Int = 3
    public var lowConfidenceConfirmations: Int = 2
    public var ukrainianFromVariant: UkrainianKeyboardVariant = .standard
    public var ukrainianToVariant: UkrainianKeyboardVariant = .standard
    public var shortWordSuppressionLength: Int = 2
    public var shortWordSuppressionMinValidContext: Int = 2
    public var shortWordSuppressionContextWindow: Int = 6

    private var wordBuffer: String = ""
    private var state: DetectorState = .idle
    private var consecutiveWrongCount: Int = 0
    private var lastDetectionResult: DetectionResult?
    private var pendingBoundaryCharacter: String?
    private var pendingSwitchLayout: Layout?
    private var pendingSwitchCount: Int = 0
    private var recentOutcomes: [RecentOutcome] = []
    private var journal: [JournalToken] = []
    private var currentTokenID: UInt64?
    private var pendingSweepMarks: [(index: Int, display: String, target: Layout)] = []
    private var isOutOfSync: Bool = false

    private let validator = WordValidator.shared

    /// Layouts that are allowed as correction targets (defaults to all).
    public var allowedLayouts: Set<Layout> = Set(Layout.allCases)

    /// The Cyrillic layout the user is currently on, or was last on. Latin text is only ever
    /// converted to this Cyrillic layout; `nil` means no history, so every allowed one is tried.
    /// Cyrillic ↔ Cyrillic (Ukrainian ↔ Russian) conversion is intentionally unsupported.
    public var preferredCyrillicLayout: Layout?

    private enum RecentOutcome {
        case valid(Layout)
        case corrected(from: Layout, to: Layout)
        case unknown
    }

    /// A word flushed earlier in the current typing run that is still on screen right before
    /// the word being checked. `display` is what the screen shows now: `typed`, or its
    /// same-length conversion once a correction has covered it.
    private struct JournalToken {
        let id: UInt64?
        let typed: String
        let boundary: String
        var display: String
        var convertedTo: Layout?
    }

    private struct RunSweep {
        let original: String
        let converted: String
        let sourceLayout: Layout
    }

    private static let maxJournalLength = 16
    /// InputEngine refuses corrections longer than this, so a sweep must stay within it.
    private static let maxSweepLength = 64

    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        // Keep punctuation keys that may correspond to letters in other layouts.
        set.subtract(CharacterSet(charactersIn: ",.;'[]`<>:\"{}~"))
        return set
    }()

    private static let englishVowels = CharacterSet(charactersIn: "aeiouyAEIOUY")
    private static let ukrainianVowels = CharacterSet(charactersIn: "аеєиіїоуюяАЕЄИІЇОУЮЯ")
    private static let russianVowels = CharacterSet(charactersIn: "аеёиоуыэюяАЕЁИОУЫЭЮЯ")
    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    /// The currently active keyboard layout (set externally by InputSourceManager).
    public var currentLayout: Layout = .english {
        didSet {
            if activeSourceSupportedLayouts == [oldValue] {
                activeSourceSupportedLayouts = [currentLayout]
            }
        }
    }

    /// The set of languages supported by the currently active physical input source.
    public var activeSourceSupportedLayouts: Set<Layout> = [.english]

    /// The ID of the currently active input source.
    public var currentInputSourceID: String = "unknown"

    /// Provider to look up the preferred physical input source ID for a target layout.
    public var preferredSourceIDProvider: ((Layout) -> String?)? = { layout in
        InputSourceManager.shared.sourceID(for: layout)
    }

    /// The trigger provenance for the current detection request.
    public var currentTrigger: CorrectionTrigger = .automaticBoundary

    /// Personal exceptions protecting specific words from automatic correction.
    public var personalExceptions: PersonalExceptionsPolicy = .empty

    public init() {}

    /// Add a character to the word buffer.
    public func addCharacter(_ char: String) {
        wordBuffer += char
        state = .buffering
    }

    /// Called when a word boundary is detected (space, enter, tab, punctuation).
    /// This is the only point where detection fires and triggers correction.
    /// - Parameter boundaryCharacter: The character that triggered the flush (e.g. " ", "\n"), or nil for hotkey-triggered flush.
    @discardableResult
    public func flushBuffer(boundaryCharacter: String? = nil) -> DetectionResult? {
        let tokenID = currentTokenID
        currentTokenID = nil
        guard !wordBuffer.isEmpty else {
            // A boundary with no word before it: earlier words are no longer adjacent.
            journal.removeAll()
            state = .idle
            isOutOfSync = false
            return nil
        }

        // Split trailing punctuation from the buffer (e.g. "hello," -> "hello" + ",")
        let typedWord = wordBuffer
        let (coreWord, trailingPunctuation) = splitTrailingBoundary(from: wordBuffer)
        wordBuffer = coreWord

        guard !wordBuffer.isEmpty else {
            record(typed: typedWord, display: typedWord, convertedTo: nil, boundary: boundaryCharacter, id: tokenID)
            state = .idle
            isOutOfSync = false
            return nil
        }

        // Store boundary string (trailing punctuation + explicit boundary like space/newline)
        let boundary = trailingPunctuation + (boundaryCharacter ?? "")
        pendingBoundaryCharacter = boundary.isEmpty ? nil : boundary

        // Check buffer at word boundaries (short words are handled by WordValidator whitelist)
        pendingSweepMarks = []
        let result = isOutOfSync ? nil : checkBuffer()
        if let result {
            delegate?.layoutDetector(self, didDetectWrongLayout: result, boundaryCharacter: pendingBoundaryCharacter)
        }

        if isOutOfSync {
            journal.removeAll()
        } else if let result {
            for mark in pendingSweepMarks {
                journal[mark.index].display = mark.display
                journal[mark.index].convertedTo = mark.target
            }
            // Conversion maps key to key, so the current word is the tail of the corrected span.
            record(
                typed: typedWord,
                display: String(result.convertedWord.suffix(coreWord.count)) + trailingPunctuation,
                convertedTo: result.targetLayout,
                boundary: boundaryCharacter,
                id: tokenID
            )
        } else {
            record(typed: typedWord, display: typedWord, convertedTo: nil, boundary: boundaryCharacter, id: tokenID)
        }
        pendingSweepMarks = []

        // Reset buffer
        pendingBoundaryCharacter = nil
        wordBuffer = ""
        state = .idle
        isOutOfSync = false
        return result
    }

    /// Called when backspace/delete is pressed — remove last character from buffer.
    public func deleteLastCharacter() {
        guard !wordBuffer.isEmpty else {
            isOutOfSync = true
            journal.removeAll()
            return
        }
        wordBuffer.removeLast()
        if wordBuffer.isEmpty {
            state = .idle
        }
    }

    /// Discard the current buffer without running detection (used in hotkey mode on word boundary).
    public func discardBuffer() {
        wordBuffer = ""
        state = .idle
        isOutOfSync = false
    }

    /// Mark the detector as out of sync (e.g. when navigation keys are pressed).
    public func invalidateSync() {
        wordBuffer = ""
        state = .idle
        isOutOfSync = true
        journal.removeAll()
    }

    /// Replace the run journal with the words the caller knows are still on screen right before
    /// the word about to be flushed, keeping what earlier corrections changed about them.
    public func syncRun(_ preceding: [RunToken], currentTokenID: UInt64) {
        let known = journal
        journal = preceding.map { token in
            let match = known.first { $0.id == token.id && $0.typed == token.text }
            return JournalToken(
                id: token.id,
                typed: token.text,
                boundary: token.boundary,
                display: match?.display ?? token.text,
                convertedTo: match?.convertedTo
            )
        }
        self.currentTokenID = currentTokenID
    }

    /// Reset all state (e.g., when app loses focus).
    public func reset() {
        wordBuffer = ""
        state = .idle
        consecutiveWrongCount = 0
        lastDetectionResult = nil
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        recentOutcomes = []
        journal.removeAll()
        currentTokenID = nil
        isOutOfSync = false
    }

    /// The current word buffer contents.
    public var currentBuffer: String {
        return wordBuffer
    }

    // MARK: - Detection Logic

    private func checkBuffer() -> DetectionResult? {
        state = .detecting

        let word = wordBuffer

        if currentTrigger == .automaticBoundary && (personalExceptions.matches(rawToken: word) || personalExceptions.matches(rawToken: wordBuffer)) {
            SwitchFixLog.detector.debug("personal exception matched '\(word)' — suppressing automatic correction")
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            state = .buffering
            return nil
        }

        let sourceLayout = resolvedSourceLayout(for: word)

        // Skip if the word contains mixed scripts (both Latin and Cyrillic)
        if containsMixedScripts(word) {
            SwitchFixLog.detector.debug("mixed scripts skipped chars=\(word.count)")
            state = .buffering
            return nil
        }

        let currentLanguage = languageForLayout(sourceLayout)

        // Check if the word is valid in the current layout's language or ANY language supported by active hybrid source
        let currentWordParts = splitTokenForValidation(word)
        let currentValidationInput = currentWordParts.core.isEmpty ? word : currentWordParts.core

        let activeLayouts = activeLayoutSet
        let isLocallyValid = isValidInActiveLayouts(word)

        if isLocallyValid {
            if let sweep = sweepRun(
                toward: sourceLayout,
                currentOriginal: word,
                currentConverted: word,
                isLowConfidence: word.count <= lowConfidenceMaxLength,
                shouldSwitch: false
            ) {
                let result = DetectionResult(
                    sourceLayout: sweep.sourceLayout,
                    targetLayout: sourceLayout,
                    convertedWord: sweep.converted,
                    originalWord: sweep.original,
                    shouldSwitchLayout: false
                )
                consecutiveWrongCount = 0
                lastDetectionResult = nil
                recordOutcome(.corrected(from: sweep.sourceLayout, to: sourceLayout))
                state = .buffering
                return result
            }

            // A word valid in both layouts is undecidable in isolation. It stays in the run
            // journal, where a later word that confirms the other layout can still reach it.
            SwitchFixLog.detector.debug("valid in active layout set (\(activeLayouts.map(\.rawValue).joined(separator: ", "))): chars=\(word.count) — no correction")
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            recordOutcome(.valid(sourceLayout))
            state = .buffering
            return nil
        }

        // If the word is typed in a script not supported by active layouts, but is ALREADY valid
        // in an allowed alternative layout, switch layout without modifying the text (layout-only switch).
        if !activeLayouts.contains(sourceLayout), allowedLayouts.contains(sourceLayout) {
            let isCyrillicCrossSwitch = currentLayout.isCyrillic && sourceLayout.isCyrillic
            if !isCyrillicCrossSwitch {
                let candidateLanguage = languageForLayout(sourceLayout)
                if validator.validate(currentValidationInput, language: candidateLanguage, allowSuggestion: false).isValid {
                    let isLowConfidence = word.count <= lowConfidenceMaxLength
                    let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: sourceLayout)

                    if let sweep = sweepRun(
                        toward: sourceLayout,
                        currentOriginal: word,
                        currentConverted: word,
                        isLowConfidence: isLowConfidence,
                        shouldSwitch: shouldSwitch
                    ) {
                        let result = DetectionResult(
                            sourceLayout: sweep.sourceLayout,
                            targetLayout: sourceLayout,
                            convertedWord: sweep.converted,
                            originalWord: sweep.original,
                            shouldSwitchLayout: shouldSwitch
                        )
                        consecutiveWrongCount = 0
                        lastDetectionResult = nil
                        recordOutcome(.corrected(from: sweep.sourceLayout, to: sourceLayout))
                        state = .buffering
                        return result
                    }

                    if shouldSuppressLowConfidenceCorrection(
                        original: word,
                        converted: word,
                        targetLayout: sourceLayout,
                        sourceLayout: currentLayout,
                        isLowConfidence: isLowConfidence,
                        shouldSwitch: shouldSwitch
                    ) {
                        SwitchFixLog.detector.info("suppressed desynchronized word chars=\(word.count) (weak evidence, deferring)")
                        consecutiveWrongCount = 0
                        lastDetectionResult = nil
                        recordOutcome(.unknown)
                        state = .buffering
                        return nil
                    }

                    consecutiveWrongCount += 1
                    lastDetectionResult = DetectionResult(
                        sourceLayout: currentLayout,
                        targetLayout: sourceLayout,
                        convertedWord: word,
                        originalWord: word,
                        shouldSwitchLayout: shouldSwitch
                    )

                    SwitchFixLog.detector.notice("detected desynchronized layout chars=\(word.count) active=\(self.currentLayout.rawValue) actual=\(sourceLayout.rawValue) switch=\(shouldSwitch)")

                    if consecutiveWrongCount >= consecutiveThreshold {
                        let result = lastDetectionResult
                        consecutiveWrongCount = 0
                        recordOutcome(.corrected(from: currentLayout, to: sourceLayout))
                        state = .buffering
                        return result
                    }

                    recordOutcome(.corrected(from: currentLayout, to: sourceLayout))
                    state = .buffering
                    return nil
                }
            }
        }

        if shouldSkipAutomaticEnglishAcronymCorrection(word: word, sourceLayout: sourceLayout) {
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            recordOutcome(.valid(sourceLayout))
            state = .buffering
            return nil
        }

        // Try converting to alternative layouts
        let alternatives = LayoutMapper.convertToAlternatives(
            word,
            from: sourceLayout,
            ukrainianFromVariant: ukrainianFromVariant,
            ukrainianToVariant: ukrainianToVariant
        )
            .filter { targetLayout, _ in
                isEligibleTarget(targetLayout, sourceLayout: sourceLayout)
            }
        for (targetLayout, converted) in alternatives {
            // Self-switch suppression: if target layout uses the exact same physical input source already active
            if isSelfSwitch(targetLayout) {
                let currentSourceID = currentInputSourceID
                SwitchFixLog.detector.debug("self-switch suppressed: target \(targetLayout.rawValue) shares active source \(currentSourceID)")
                continue
            }

            let targetLanguage = languageForLayout(targetLayout)
            var candidateConversions: [String] = [converted]
            if sourceLayout == .ukrainian && targetLayout == .english {
                let fallbackVariant: UkrainianKeyboardVariant = (ukrainianFromVariant == .legacy) ? .standard : .legacy
                let fallbackConverted = LayoutMapper.convert(
                    word,
                    from: .ukrainian,
                    to: .english,
                    ukrainianFromVariant: fallbackVariant,
                    ukrainianToVariant: ukrainianToVariant
                )
                if fallbackConverted != converted && !candidateConversions.contains(fallbackConverted) {
                    candidateConversions.append(fallbackConverted)
                }
            } else if sourceLayout == .english && targetLayout == .ukrainian {
                let fallbackVariant: UkrainianKeyboardVariant = (ukrainianToVariant == .legacy) ? .standard : .legacy
                let fallbackConverted = LayoutMapper.convert(
                    word,
                    from: .english,
                    to: .ukrainian,
                    ukrainianFromVariant: ukrainianFromVariant,
                    ukrainianToVariant: fallbackVariant
                )
                if fallbackConverted != converted && !candidateConversions.contains(fallbackConverted) {
                    candidateConversions.append(fallbackConverted)
                }
            }

            for candidate in candidateConversions {
                let tokenParts = splitTokenForValidation(candidate)
                let originalParts = splitTokenForValidation(word)

                // Prevent 'fake switches' where a letter key maps to punctuation at the start of a word.
                // e.g. 'бігу' (no prefix) -> ',sue' (prefix ',').
                if tokenParts.prefix.count > originalParts.prefix.count {
                    continue
                }

                // Pure punctuation in the source layout must not be converted to letters
                // in the target layout without explicit target-layout context (e.g. ':' -> 'Ж' / 'ж').
                if originalParts.core.isEmpty && !tokenParts.core.isEmpty && !hasTargetContext(targetLayout) {
                    SwitchFixLog.detector.debug("suppressed punctuation-to-letter conversion without \(targetLayout.rawValue) context")
                    continue
                }

                // Tokens with a hyphen prefix (e.g. flags like '-r', '--r', '-rf')
                // must never be converted to letters in another layout.
                if originalParts.prefix.contains("-") && tokenParts.prefix.contains("-") && originalParts.core.count <= shortWordSuppressionLength {
                    SwitchFixLog.detector.debug("suppressed prefixed flag conversion chars=\(word.count)")
                    continue
                }

                let validationInput = tokenParts.core.isEmpty ? candidate : tokenParts.core

                let validation = validator.validate(
                    validationInput,
                    language: targetLanguage,
                    allowSuggestion: false
                )
                if validation.isValid {
                    let correctedCore = validationInput
                    let recomposedWord = tokenParts.prefix + correctedCore + tokenParts.suffix
                    var finalWord = applyCase(from: word, to: recomposedWord)
                    var originalForCorrection = word
                    let isLowConfidence = word.count <= lowConfidenceMaxLength
                    let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: targetLayout)

                    if shouldSuppressLowConfidenceCorrection(
                        original: word,
                        converted: finalWord,
                        targetLayout: targetLayout,
                        sourceLayout: sourceLayout,
                        isLowConfidence: isLowConfidence,
                        shouldSwitch: shouldSwitch
                    ) {
                        SwitchFixLog.detector.info("suppressed short word chars=\(word.count) (weak evidence, deferring)")
                        consecutiveWrongCount = 0
                        lastDetectionResult = nil
                        recordOutcome(.unknown)
                        state = .buffering
                        return nil
                    }

                    var correctionSourceLayout = sourceLayout
                    if let sweep = sweepRun(
                        toward: targetLayout,
                        currentOriginal: word,
                        currentConverted: finalWord,
                        isLowConfidence: isLowConfidence,
                        shouldSwitch: shouldSwitch
                    ) {
                        originalForCorrection = sweep.original
                        finalWord = sweep.converted
                        correctionSourceLayout = sweep.sourceLayout
                    }

                    consecutiveWrongCount += 1
                    lastDetectionResult = DetectionResult(
                        sourceLayout: correctionSourceLayout,
                        targetLayout: targetLayout,
                        convertedWord: finalWord,
                        originalWord: originalForCorrection,
                        shouldSwitchLayout: shouldSwitch
                    )

                    if consecutiveWrongCount >= consecutiveThreshold {
                        let result = lastDetectionResult
                        consecutiveWrongCount = 0
                        recordOutcome(.corrected(from: correctionSourceLayout, to: targetLayout))
                        state = .buffering
                        return result
                    }

                    recordOutcome(.corrected(from: correctionSourceLayout, to: targetLayout))
                    state = .buffering
                    return nil
                }
            }

            if shouldAllowAcronymFallback(original: word, converted: converted, currentLanguage: currentLanguage) {
                let finalWord = applyCase(from: word, to: converted)
                let shouldSwitch = shouldSwitchLayout(isLowConfidence: true, targetLayout: targetLayout)

                if shouldSuppressAcronymFallback(
                    targetLayout: targetLayout,
                    sourceLayout: sourceLayout,
                    shouldSwitch: shouldSwitch
                ) {
                    consecutiveWrongCount = 0
                    lastDetectionResult = nil
                    recordOutcome(.unknown)
                    state = .buffering
                    return nil
                }

                consecutiveWrongCount += 1
                lastDetectionResult = DetectionResult(
                    sourceLayout: sourceLayout,
                    targetLayout: targetLayout,
                    convertedWord: finalWord,
                    originalWord: word,
                    shouldSwitchLayout: shouldSwitch
                )

                if consecutiveWrongCount >= consecutiveThreshold {
                    let result = lastDetectionResult
                    consecutiveWrongCount = 0
                    recordOutcome(.corrected(from: sourceLayout, to: targetLayout))
                    state = .buffering
                    return result
                }

                recordOutcome(.corrected(from: sourceLayout, to: targetLayout))
                state = .buffering
                return nil
            }
        }

        // No valid alternative found — unknown word, do nothing
        SwitchFixLog.detector.debug("unknown word chars=\(word.count) — no valid alternative in any layout")
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        if !currentWordParts.core.isEmpty {
            recordOutcome(.unknown)
        }
        state = .buffering
        return nil
    }

    private func shouldSwitchLayout(isLowConfidence: Bool, targetLayout: Layout) -> Bool {
        if !isLowConfidence {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        if pendingSwitchLayout == targetLayout {
            pendingSwitchCount += 1
        } else {
            pendingSwitchLayout = targetLayout
            pendingSwitchCount = 1
        }

        if pendingSwitchCount >= lowConfidenceConfirmations {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        return false
    }

    private func isEligibleTarget(_ targetLayout: Layout, sourceLayout: Layout) -> Bool {
        LayoutMapper.isEligibleTarget(
            targetLayout,
            source: sourceLayout,
            allowed: allowedLayouts,
            current: currentLayout,
            activeSourceSupported: activeSourceSupportedLayouts,
            preferredCyrillic: preferredCyrillicLayout
        )
    }

    private func isSelfSwitch(_ targetLayout: Layout) -> Bool {
        guard targetLayout == currentLayout else { return false }
        let currentSourceID = currentInputSourceID
        let targetPreferred = preferredSourceIDProvider?(targetLayout)
        return (currentSourceID != "unknown" && targetPreferred != nil && currentSourceID == targetPreferred)
            || (activeSourceSupportedLayouts.contains(targetLayout) && (targetPreferred == nil || targetPreferred == currentSourceID))
    }

    private func shouldSuppressLowConfidenceCorrection(
        original: String,
        converted: String,
        targetLayout: Layout,
        sourceLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> Bool {
        guard isLowConfidence else { return false }
        let originalCoreCount = splitTokenForValidation(original).core.count
        let convertedCoreCount = splitTokenForValidation(converted).core.count
        guard originalCoreCount <= shortWordSuppressionLength else { return false }
        guard !shouldSwitch else { return false }
        guard targetLayout != sourceLayout else { return false }
        guard !converted.isEmpty else { return false }
        if hasStrongCurrentContext(for: sourceLayout) {
            return true
        }
        // An isolated single-character conversion (e.g. 'r' -> 'к') without target-layout context
        // must always be suppressed rather than converted immediately.
        if convertedCoreCount <= 1 && !hasTargetContext(targetLayout) {
            return true
        }
        return false
    }

    private func shouldSuppressAcronymFallback(
        targetLayout: Layout,
        sourceLayout: Layout,
        shouldSwitch: Bool
    ) -> Bool {
        guard targetLayout != sourceLayout else { return false }
        guard !shouldSwitch else { return false }
        return hasStrongCurrentContext(for: sourceLayout)
    }

    private var activeLayoutSet: Set<Layout> {
        activeSourceSupportedLayouts.contains(currentLayout) ? activeSourceSupportedLayouts : [currentLayout]
    }

    private func isValidInActiveLayouts(_ word: String) -> Bool {
        let parts = splitTokenForValidation(word)
        let validationInput = parts.core.isEmpty ? word : parts.core
        return activeLayoutSet.contains { layout in
            validator.validate(validationInput, language: languageForLayout(layout), allowSuggestion: false).isValid
        }
    }

    private func record(typed: String, display: String, convertedTo: Layout?, boundary: String?, id: UInt64?) {
        // Without a boundary after it the word is not committed (hotkey flush), and the
        // correction it may trigger rewrites text the journal cannot follow.
        guard let boundary, !boundary.isEmpty else {
            journal.removeAll()
            return
        }
        journal.append(JournalToken(
            id: id,
            typed: typed,
            boundary: boundary,
            display: display,
            convertedTo: convertedTo
        ))
        if journal.count > LayoutDetector.maxJournalLength {
            journal.removeFirst(journal.count - LayoutDetector.maxJournalLength)
        }
    }

    /// The word as it would read on `targetLayout`, when that reading is a valid word there.
    private func validConversion(of word: String, from sourceLayout: Layout, to targetLayout: Layout) -> String? {
        guard !word.isEmpty,
              !containsMixedScripts(word),
              isEligibleTarget(targetLayout, sourceLayout: sourceLayout),
              !isSelfSwitch(targetLayout) else {
            return nil
        }
        if sourceLayout == .english, word.count >= 2, isAllUppercase(word) {
            return nil
        }

        var candidates = [LayoutMapper.convert(
            word,
            from: sourceLayout,
            to: targetLayout,
            ukrainianFromVariant: ukrainianFromVariant,
            ukrainianToVariant: ukrainianToVariant
        )]
        if sourceLayout == .ukrainian && targetLayout == .english {
            candidates.append(LayoutMapper.convert(
                word,
                from: sourceLayout,
                to: targetLayout,
                ukrainianFromVariant: ukrainianFromVariant == .legacy ? .standard : .legacy,
                ukrainianToVariant: ukrainianToVariant
            ))
        } else if sourceLayout == .english && targetLayout == .ukrainian {
            candidates.append(LayoutMapper.convert(
                word,
                from: sourceLayout,
                to: targetLayout,
                ukrainianFromVariant: ukrainianFromVariant,
                ukrainianToVariant: ukrainianToVariant == .legacy ? .standard : .legacy
            ))
        }

        let originalParts = splitTokenForValidation(word)
        for candidate in candidates where candidate != word {
            let parts = splitTokenForValidation(candidate)
            // Same guards as a direct correction: no letter that turns into leading
            // punctuation, no punctuation that turns into letters, no short flags.
            if parts.prefix.count > originalParts.prefix.count { continue }
            if originalParts.core.isEmpty || parts.core.isEmpty { continue }
            if originalParts.prefix.contains("-") && originalParts.core.count <= shortWordSuppressionLength { continue }
            guard validator.validate(
                parts.core,
                language: languageForLayout(targetLayout),
                allowSuggestion: false
            ).isValid else {
                continue
            }
            return applyCase(from: word, to: candidate)
        }
        return nil
    }

    /// Extends a correction of the current word back over the words typed right before it in
    /// the same run. The layout cannot change mid-run, so once the current word shows the run
    /// is on the wrong layout, every earlier word that also reads as a valid `targetLayout`
    /// word belongs to the same mistake — including ones that looked fine on their own.
    private func sweepRun(
        toward targetLayout: Layout,
        currentOriginal: String,
        currentConverted: String,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> RunSweep? {
        // Rewrite earlier words only when the current word is stronger evidence than a lone short one.
        let hasStrongCurrentSignal = currentOriginal.count > shortWordSuppressionLength || shouldSwitch || !isLowConfidence
        guard hasStrongCurrentSignal, !journal.isEmpty else { return nil }

        // Nearest word first. `converted == nil` means the screen already shows the target layout.
        var swept: [(index: Int, converted: String?, isAmbiguous: Bool)] = []
        var sweepSource: Layout?
        var stoppedAtCurrentLayoutWord = false
        var spanLength = currentOriginal.count

        for index in journal.indices.reversed() {
            let token = journal[index]
            // Enter may have submitted the earlier text; never rewrite across it.
            if token.boundary.contains(where: \.isNewline) { break }
            let tokenLength = token.typed.count + token.boundary.count
            if spanLength + tokenLength > LayoutDetector.maxSweepLength { break }

            // Personal exceptions barrier: backward sweep stops before any protected token
            if currentTrigger == .automaticBoundary && (personalExceptions.matches(rawToken: token.typed) || personalExceptions.matches(rawToken: token.display)) {
                break
            }

            if let convertedTo = token.convertedTo {
                guard convertedTo == targetLayout else { break }
                swept.append((index, nil, false))
            } else {
                let tokenSource = resolvedSourceLayout(for: token.typed)
                guard tokenSource != targetLayout, sweepSource == nil || sweepSource == tokenSource else { break }
                let (core, trailing) = splitTrailingBoundary(from: token.typed)
                let isValidAsTyped = isValidInActiveLayouts(core)
                guard let converted = validConversion(of: core, from: tokenSource, to: targetLayout) else {
                    stoppedAtCurrentLayoutWord = isValidAsTyped
                    break
                }
                sweepSource = tokenSource
                swept.append((index, converted + trailing, isValidAsTyped))
            }
            spanLength += tokenLength
        }

        // A word valid in both layouts sides with its neighbours: right after a word that only
        // makes sense as typed, it is far more likely part of that text than of the mistake.
        if stoppedAtCurrentLayoutWord {
            while let farthest = swept.last, farthest.converted != nil, farthest.isAmbiguous {
                swept.removeLast()
            }
        }
        // Nothing to rewrite before the farthest word that actually changes.
        while let farthest = swept.last, farthest.converted == nil {
            swept.removeLast()
        }
        guard !swept.isEmpty, let sourceLayout = sweepSource else { return nil }

        var original = ""
        var converted = ""
        for entry in swept.reversed() {
            let token = journal[entry.index]
            original += token.display + token.boundary
            converted += (entry.converted ?? token.display) + token.boundary
            if let display = entry.converted {
                pendingSweepMarks.append((entry.index, display, targetLayout))
            }
        }
        SwitchFixLog.detector.info("run sweep: correction extended over \(swept.count) earlier words")
        return RunSweep(
            original: original + currentOriginal,
            converted: converted + currentConverted,
            sourceLayout: sourceLayout
        )
    }

    private func hasStrongCurrentContext(for layout: Layout) -> Bool {
        let window = max(1, shortWordSuppressionContextWindow)
        let recent = recentOutcomes.suffix(window)
        let validCount = recent.reduce(0) { partial, outcome in
            if case .valid(let l) = outcome, l == layout {
                return partial + 1
            }
            return partial
        }
        let hasRecentCorrection = recent.contains { outcome in
            if case .corrected = outcome { return true }
            return false
        }
        return validCount >= shortWordSuppressionMinValidContext && !hasRecentCorrection
    }

    private func hasTargetContext(_ targetLayout: Layout) -> Bool {
        let window = max(1, shortWordSuppressionContextWindow)
        let recent = recentOutcomes.suffix(window)
        return recent.contains { outcome in
            switch outcome {
            case .valid(let layout):
                return layout == targetLayout
            case .corrected(_, let to):
                return to == targetLayout
            case .unknown:
                return false
            }
        }
    }

    private func recordOutcome(_ outcome: RecentOutcome) {
        recentOutcomes.append(outcome)
        let window = max(1, shortWordSuppressionContextWindow)
        if recentOutcomes.count > window {
            recentOutcomes.removeFirst(recentOutcomes.count - window)
        }
    }

    private func applyCase(from original: String, to word: String) -> String {
        guard !word.isEmpty else { return word }
        if isAllUppercase(original) {
            return word.uppercased()
        }
        if isCapitalized(original) {
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return word
    }

    private func isAllUppercase(_ word: String) -> Bool {
        var hasLetters = false
        for char in word {
            if char.isLetter {
                hasLetters = true
                if !char.isUppercase {
                    return false
                }
            }
        }
        return hasLetters
    }

    private func isCapitalized(_ word: String) -> Bool {
        var chars = Array(word)
        while let first = chars.first, !first.isLetter {
            chars.removeFirst()
        }
        guard let first = chars.first, first.isUppercase else { return false }
        for c in chars.dropFirst() where c.isLetter {
            if !c.isLowercase { return false }
        }
        return true
    }

    private func shouldAllowAcronymFallback(original: String, converted: String, currentLanguage: Language) -> Bool {
        guard original.count >= 2 else { return false }
        guard original.count <= 3 else { return false }
        guard isAllUppercase(original) else { return false }
        if containsVowel(original, language: currentLanguage) { return false }
        if containsMixedScripts(converted) { return false }
        return true
    }

    private func shouldSkipAutomaticEnglishAcronymCorrection(word: String, sourceLayout: Layout) -> Bool {
        guard sourceLayout == .english else { return false }
        // Keep manual/hotkey correction available; suppress only automatic boundary-triggered rewrites.
        guard pendingBoundaryCharacter != nil else { return false }
        guard word.count >= 2 else { return false }
        return isAllUppercase(word)
    }

    private func containsVowel(_ text: String, language: Language) -> Bool {
        let vowels: CharacterSet
        switch language {
        case .english: vowels = LayoutDetector.englishVowels
        case .ukrainian: vowels = LayoutDetector.ukrainianVowels
        case .russian: vowels = LayoutDetector.russianVowels
        }
        for scalar in text.unicodeScalars where vowels.contains(scalar) {
            return true
        }
        return false
    }

    /// Map Layout to Language for dictionary lookup.
    private func languageForLayout(_ layout: Layout) -> Language {
        switch layout {
        case .english: return .english
        case .ukrainian: return .ukrainian
        case .russian: return .russian
        }
    }

    /// Check if a string contains both Latin and Cyrillic characters.
    private func containsMixedScripts(_ text: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for char in text {
            for scalar in char.unicodeScalars {
                if (scalar.value >= 0x0041 && scalar.value <= 0x005A) || (scalar.value >= 0x0061 && scalar.value <= 0x007A) {
                    hasLatin = true
                } else if (scalar.value >= 0x0400 && scalar.value <= 0x04FF) {
                    hasCyrillic = true
                }
            }
            if hasLatin && hasCyrillic { return true }
        }
        return false
    }

    private enum ScriptKind {
        case latin
        case cyrillic
        case mixed
        case unknown
    }

    private func resolvedSourceLayout(for word: String) -> Layout {
        let script = scriptKind(for: word)
        switch script {
        case .latin:
            if allowedLayouts.contains(.english) {
                return .english
            }
            return currentLayout
        case .cyrillic:
            if currentLayout == .ukrainian || currentLayout == .russian {
                return currentLayout
            }
            if activeSourceSupportedLayouts.contains(.ukrainian) || activeSourceSupportedLayouts.contains(.russian) {
                if let inferred = inferCyrillicLayout(for: word), activeSourceSupportedLayouts.contains(inferred) {
                    return inferred
                }
                if activeSourceSupportedLayouts.contains(currentLayout) {
                    return currentLayout
                }
                if activeSourceSupportedLayouts.contains(.ukrainian) {
                    return .ukrainian
                }
                if activeSourceSupportedLayouts.contains(.russian) {
                    return .russian
                }
            }
            return inferCyrillicLayout(for: word) ?? currentLayout
        case .mixed, .unknown:
            return currentLayout
        }
    }

    private func scriptKind(for text: String) -> ScriptKind {
        var hasLatin = false
        var hasCyrillic = false

        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            if LayoutDetector.latinLowercaseRange.contains(value) || LayoutDetector.latinUppercaseRange.contains(value) {
                hasLatin = true
            } else if LayoutDetector.cyrillicRange.contains(value) {
                hasCyrillic = true
            }
            if hasLatin && hasCyrillic {
                return .mixed
            }
        }

        if hasLatin { return .latin }
        if hasCyrillic { return .cyrillic }
        return .unknown
    }

    private func inferCyrillicLayout(for word: String) -> Layout? {
        let lower = word.lowercased()

        if containsAnyCharacter(from: "іїєґ", in: lower), allowedLayouts.contains(.ukrainian) {
            return .ukrainian
        }
        if containsAnyCharacter(from: "ыэёъ", in: lower), allowedLayouts.contains(.russian) {
            return .russian
        }

        let hasUkrainian = allowedLayouts.contains(.ukrainian)
        let hasRussian = allowedLayouts.contains(.russian)
        if hasUkrainian && !hasRussian { return .ukrainian }
        if hasRussian && !hasUkrainian { return .russian }
        if hasUkrainian && hasRussian {
            if hasTargetContext(.russian) && !hasTargetContext(.ukrainian) {
                return .russian
            }
            if hasTargetContext(.ukrainian) && !hasTargetContext(.russian) {
                return .ukrainian
            }
        }
        if hasUkrainian { return .ukrainian }
        if hasRussian { return .russian }
        return nil
    }

    private func containsAnyCharacter(from candidates: String, in text: String) -> Bool {
        let set = Set(candidates)
        return text.contains { set.contains($0) }
    }

    private func splitTokenForValidation(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let chars = Array(token)
        if chars.isEmpty {
            return ("", "", "")
        }

        var start = 0
        while start < chars.count {
            let ch = chars[start]
            if ch.isLetter || ch.isNumber {
                break
            }
            start += 1
        }

        var end = chars.count
        while end > start {
            let ch = chars[end - 1]
            if ch.isLetter || ch.isNumber {
                break
            }
            end -= 1
        }

        let prefix = start > 0 ? String(chars[0..<start]) : ""
        let core = start < end ? String(chars[start..<end]) : ""
        let suffix = end < chars.count ? String(chars[end..<chars.count]) : ""
        return (prefix, core, suffix)
    }

    /// Split trailing punctuation/symbols from a word.
    private func splitTrailingBoundary(from text: String) -> (core: String, trailing: String) {
        var core = text
        var trailing = ""
        while let last = core.last, isBoundaryChar(last) {
            trailing.insert(last, at: trailing.startIndex)
            core.removeLast()
        }
        return (core, trailing)
    }

    private func isBoundaryChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return LayoutDetector.boundaryCharacterSet.contains(scalar)
    }
}

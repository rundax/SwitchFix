import AppKit
import Carbon
import Core
import Dictionary
import Foundation

// Spike for plan 05: can the spell-checking dictionaries macOS ships replace bundled word lists?
// Measures availability, latency, thread safety, case handling, coverage against the bundled
// lists, and how often wrong-layout text is (mis)accepted, on this Mac. Never prints typed text
// from the user; all words come from bundled lists or the system dictionaries.

// MARK: - Utilities

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "n/a" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
}

func nanoseconds(_ body: () -> Void) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return DispatchTime.now().uptimeNanoseconds - start
}

func quantile(_ sorted: [UInt64], _ q: Double) -> String {
    guard !sorted.isEmpty else { return "n/a" }
    let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * q))
    return String(format: "%.2f", Double(sorted[index]) / 1_000_000)
}

func isWord(_ text: String) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
}

/// A random sample of `count` lines from a bundled text dictionary.
func sampleBundledWords(_ file: String, count: Int, seed: UInt64) -> [String] {
    guard let text = try? String(contentsOfFile: "Sources/Dictionary/Resources/\(file).txt", encoding: .utf8) else {
        return []
    }
    var words: [String] = []
    text.enumerateLines { line, _ in
        let word = line.trimmingCharacters(in: .whitespaces).lowercased()
        if word.count >= 3, isWord(word) { words.append(word) }
    }
    var generator = SeededGenerator(seed: seed)
    words.shuffle(using: &generator)
    return Array(words.prefix(count))
}

/// Words the system dictionary itself proposes for random prefixes: common words, mixed case.
func sampleSystemWords(language: String, alphabet: [Character], count: Int, seed: UInt64) -> [String] {
    let checker = NSSpellChecker.shared
    var generator = SeededGenerator(seed: seed)
    var prefixes = alphabet.map { String($0) }
    for _ in 0..<160 {
        if let a = alphabet.randomElement(using: &generator), let b = alphabet.randomElement(using: &generator) {
            prefixes.append(String([a, b]))
        }
    }
    var seen: Set<String> = []
    var words: [String] = []
    for prefix in prefixes {
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        for completion in checker.completions(forPartialWordRange: range, in: prefix, language: language, inSpellDocumentWithTag: 0) ?? [] {
            guard (3...14).contains(completion.count), isWord(completion), seen.insert(completion).inserted else { continue }
            words.append(completion)
        }
    }
    words.shuffle(using: &generator)
    return Array(words.prefix(count))
}

// MARK: - Keyboard layouts

struct KeyStroke: Hashable {
    let keyCode: UInt16
    let shift: Bool
}

struct KeyboardLayoutMap {
    let sourceID: String
    let output: [KeyStroke: Character]
    let strokes: [Character: KeyStroke]

    init?(sourceID: String) {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var output: [KeyStroke: Character] = [:]
        var strokes: [Character: KeyStroke] = [:]
        for shift in [false, true] {
            for keyCode in UInt16(0)..<UInt16(51) { // main block, number row through backquote
                guard let character = Self.translate(data, keyCode: keyCode, shift: shift) else { continue }
                let stroke = KeyStroke(keyCode: keyCode, shift: shift)
                output[stroke] = character
                if strokes[character] == nil { strokes[character] = stroke }
            }
        }
        self.sourceID = sourceID
        self.output = output
        self.strokes = strokes
    }

    var lowercaseLetters: [Character] {
        output.filter { !$0.key.shift }.map(\.value)
            .filter { $0.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) } && String($0) == String($0).lowercased() }
            .sorted()
    }

    /// Spacing forms a dead key produces with dead keys disabled, by the combining mark it adds.
    private static let deadKeyForms: [UInt32: [Character]] = [
        0x0301: ["\u{0384}", "\u{00B4}"], // acute / Greek tonos
        0x0308: ["\u{00A8}"],              // diaeresis / dialytika
        0x0300: ["`"],
        0x0302: ["^"],
    ]

    /// The text produced by typing `word` (as typed on this layout) on `other`, or nil when a
    /// character needs more than Shift or one dead key on this layout.
    func render(_ word: String, on other: KeyboardLayoutMap) -> String? {
        if let direct = renderDirect(word, on: other) { return direct }
        var strokesTyped: [KeyStroke] = []
        var lastBaseIndex: Int?
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            if let stroke = strokes[Character(scalar)] {
                lastBaseIndex = strokesTyped.count
                strokesTyped.append(stroke)
            } else if let forms = Self.deadKeyForms[scalar.value],
                      let deadKey = forms.lazy.compactMap({ strokes[$0] }).first,
                      let base = lastBaseIndex {
                strokesTyped.insert(deadKey, at: base) // dead key first, then the letter
                lastBaseIndex = nil
            } else if let precomposed = strokes[Character(String(scalar).precomposedStringWithCanonicalMapping)] {
                strokesTyped.append(precomposed)
            } else {
                return nil
            }
        }
        var result = ""
        for stroke in strokesTyped {
            guard let typed = other.output[stroke] else { return nil }
            result.append(typed)
        }
        return result
    }

    private func renderDirect(_ word: String, on other: KeyboardLayoutMap) -> String? {
        var result = ""
        for scalar in word.unicodeScalars {
            guard let stroke = strokes[Character(scalar)], let typed = other.output[stroke] else { return nil }
            result.append(typed)
        }
        return result
    }

    private static func translate(_ data: Data, keyCode: UInt16, shift: Bool) -> Character? {
        data.withUnsafeBytes { pointer -> Character? in
            guard let base = pointer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                base, keyCode, UInt16(kUCKeyActionDown), shift ? UInt32(shiftKey >> 8) : 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length == 1, let scalar = UnicodeScalar(chars[0]),
                  scalar.value >= 0x21, !(0xE000...0xF8FF).contains(scalar.value) else { return nil }
            return Character(scalar)
        }
    }
}

// MARK: - Measurements

let spellChecker = SystemSpellChecker.shared

func isSystemValid(_ word: String, _ language: String, _ policy: SystemSpellChecker.CasePolicy) -> Bool {
    spellChecker.casePolicy = policy
    return spellChecker.isValid(word, language: language)
}

struct LanguageCase {
    let code: String
    let layoutID: String
    let script: String
}

let languageCases: [LanguageCase] = [
    .init(code: "uk", layoutID: "com.apple.keylayout.Ukrainian-PC", script: "Cyrillic"),
    .init(code: "ru", layoutID: "com.apple.keylayout.RussianWin", script: "Cyrillic"),
    .init(code: "bg", layoutID: "com.apple.keylayout.Bulgarian", script: "Cyrillic"),
    .init(code: "el", layoutID: "com.apple.keylayout.Greek", script: "Greek"),
    .init(code: "he", layoutID: "com.apple.keylayout.Hebrew", script: "Hebrew"),
    .init(code: "ar", layoutID: "com.apple.keylayout.Arabic", script: "Arabic"),
    .init(code: "hi", layoutID: "com.apple.keylayout.Devanagari", script: "Devanagari"),
    .init(code: "de", layoutID: "com.apple.keylayout.German", script: "Latin"),
    .init(code: "fr", layoutID: "com.apple.keylayout.French", script: "Latin"),
    .init(code: "es", layoutID: "com.apple.keylayout.Spanish-ISO", script: "Latin"),
    .init(code: "it", layoutID: "com.apple.keylayout.Italian-Pro", script: "Latin"),
    .init(code: "pt_PT", layoutID: "com.apple.keylayout.Portuguese", script: "Latin"),
    .init(code: "pl", layoutID: "com.apple.keylayout.PolishPro", script: "Latin"),
    .init(code: "cs", layoutID: "com.apple.keylayout.Czech-QWERTY", script: "Latin"),
    .init(code: "tr", layoutID: "com.apple.keylayout.Turkish-QWERTY-PC", script: "Latin"),
    .init(code: "sv", layoutID: "com.apple.keylayout.Swedish-Pro", script: "Latin"),
    .init(code: "nl", layoutID: "com.apple.keylayout.Dutch", script: "Latin"),
    .init(code: "hu", layoutID: "com.apple.keylayout.Hungarian", script: "Latin"),
    .init(code: "ro", layoutID: "com.apple.keylayout.Romanian", script: "Latin"),
    .init(code: "fi", layoutID: "com.apple.keylayout.Finnish", script: "Latin"),
    .init(code: "da", layoutID: "com.apple.keylayout.Danish", script: "Latin"),
    .init(code: "nb", layoutID: "com.apple.keylayout.Norwegian", script: "Latin"),
    .init(code: "lt", layoutID: "com.apple.keylayout.Lithuanian", script: "Latin"),
    .init(code: "sl", layoutID: "com.apple.keylayout.Slovenian", script: "Latin"),
    .init(code: "vi", layoutID: "com.apple.keylayout.Vietnamese", script: "Latin"),
]

/// The control: random 4–7 letter strings from the layout's letters that the checker accepts.
/// A language whose spelling data is not installed accepts all of them.
func randomStringsAccepted(_ language: String, letters: [Character], count: Int) -> Int {
    var random = SeededGenerator(seed: 31)
    var accepted = 0
    for _ in 0..<count {
        let length = Int.random(in: 4...7, using: &random)
        let candidate = String((0..<length).map { _ in letters.randomElement(using: &random)! })
        if isSystemValid(candidate, language, .lowercaseOrCapitalized) { accepted += 1 }
    }
    return accepted
}

// MARK: - Spelling data installation probe

/// Turns on each language's keyboard layout, as a user adding it in System Settings would.
func enableLayouts(_ codes: [String]) {
    for code in codes {
        guard let language = languageCases.first(where: { $0.code == code }) else {
            print("\(code): unknown language")
            continue
        }
        let filter = [kTISPropertyInputSourceID as String: language.layoutID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else {
            print("\(language.layoutID): not installed")
            continue
        }
        print("\(language.layoutID): TISEnableInputSource status \(TISEnableInputSource(source))")
    }
}

/// One line of the control per language, for polling from fresh processes while macOS may be
/// installing spelling data.
func printControl(_ codes: [String]) {
    let fields = codes.map { code -> String in
        guard let language = languageCases.first(where: { $0.code == code }),
              let layout = KeyboardLayoutMap(sourceID: language.layoutID) else {
            return "\(code)=n/a"
        }
        return "\(code)=\(percent(randomStringsAccepted(code, letters: layout.lowercaseLetters, count: 100), 100))"
    }
    print(fields.joined(separator: " "))
}

func environmentSection() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersionString
    let languages = SystemSpellChecker.availableLanguages
    return """
    ## Environment

    - macOS: \(version)
    - Spell-checking languages available (\(languages.count)): \(languages.joined(separator: " "))
    - Learned words excluded: \(spellChecker.excludesLearnedWords)

    """
}

func latencySection(samples: [String: [String]]) -> String {
    var lines = ["## Latency (one lookup, background thread, serialized)", "",
                 "| Language | First lookup ms | p50 ms | p95 ms | p99 ms | max ms |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for code in samples.keys.sorted() {
        let words = samples[code] ?? []
        guard let first = words.first else { continue }
        var cold: UInt64 = 0
        var warm: [UInt64] = []
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            cold = nanoseconds { _ = isSystemValid(first, code, .lowercaseOrCapitalized) }
            for _ in 0..<2 {
                for word in words {
                    warm.append(nanoseconds { _ = isSystemValid(word.lowercased(), code, .lowercaseOrCapitalized) })
                }
            }
            done.signal()
        }
        done.wait()
        warm.sort()
        lines.append("| \(code) | \(String(format: "%.2f", Double(cold) / 1_000_000)) | \(quantile(warm, 0.5)) | \(quantile(warm, 0.95)) | \(quantile(warm, 0.99)) | \(quantile(warm, 1)) |")
    }
    return lines.joined(separator: "\n") + "\n\n"
}

/// Run in a child process: unsynchronized concurrent calls may crash the process.
func runThreadCheck() {
    var words: [(String, String)] = []
    for code in ["en", "uk", "ru", "de"] {
        let sample = sampleSystemWords(language: code, alphabet: KeyboardLayoutMap(sourceID: code == "en" ? "com.apple.keylayout.US" : languageCases.first { $0.code == code }!.layoutID)!.lowercaseLetters, count: 150, seed: 7)
        for word in sample {
            words.append((word.lowercased(), code))
            words.append((String(word.lowercased().reversed()), code))
        }
    }
    let expected = words.map { SystemSpellChecker.unsynchronizedIsValid($0.0, language: $0.1, casePolicy: .lowercaseOrCapitalized, excludesLearnedWords: true) }
    let lock = NSLock()
    var mismatches = 0
    var calls = 0
    let elapsed = nanoseconds {
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            var local = 0
            var count = 0
            for round in 0..<4 {
                for index in words.indices where (index + thread + round) % 2 == 0 {
                    let (word, code) = words[index]
                    let result = SystemSpellChecker.unsynchronizedIsValid(word, language: code, casePolicy: .lowercaseOrCapitalized, excludesLearnedWords: true)
                    if result != expected[index] { local += 1 }
                    count += 1
                }
            }
            lock.lock(); mismatches += local; calls += count; lock.unlock()
        }
    }
    print("THREADS calls=\(calls) mismatches=\(mismatches) wallMs=\(elapsed / 1_000_000)")
}

func threadSection() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["threads"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    var outcome = ""
    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let line = output.split(separator: "\n").first { $0.hasPrefix("THREADS") }.map(String.init) ?? "no result"
        outcome = process.terminationReason == .uncaughtSignal
            ? "crashed (signal \(process.terminationStatus))"
            : "exit \(process.terminationStatus): \(line)"
    } catch {
        outcome = "could not run: \(error)"
    }
    return """
    ## Thread safety (8 threads, no lock, en/uk/ru/de words and reversed non-words)

    \(outcome)

    """
}

func bundledComparisonSection(english: [String]) -> String {
    DictionaryLoader.shared.enableTextFallbackForTesting()
    var lines = ["## Against the bundled dictionaries (en, uk, ru)", ""]
    lines.append("Coverage: share of a random sample of bundled words (3+ letters) the system accepts. Collision: share of real words of the other language that, typed in the wrong layout, form a word the dictionary accepts. A collision is text SwitchFix may change when the typed word is not also recognized in its own language.")
    lines.append("")
    lines.append("| Language | Coverage, lowercase | Coverage, +capitalized | Collisions: bundled | Collisions: system |")
    lines.append("| --- | ---: | ---: | ---: | ---: |")

    let cases: [(Language, String, String)] = [(.english, "en", "en_US"), (.ukrainian, "uk", "uk_UA"), (.russian, "ru", "ru_RU")]
    for (language, code, file) in cases {
        let sample = sampleBundledWords(file, count: 2000, seed: 11)
        let lower = sample.filter { isSystemValid($0, code, .lowercase) }.count
        let capital = sample.filter { isSystemValid($0, code, .lowercaseOrCapitalized) }.count

        // Real words of the other side, as they come out when typed on the wrong layout.
        func typedOnWrongLayout(_ words: [String], from source: Layout, to target: Layout) -> [(String, String)] {
            words.map { ($0, LayoutMapper.convert($0, from: source, to: target, ukrainianFromVariant: .standard, ukrainianToVariant: .standard)) }
        }
        let pairs: [(String, String)]
        switch language {
        case .english:
            pairs = typedOnWrongLayout(sampleBundledWords("uk_UA", count: 1000, seed: 13), from: .ukrainian, to: .english) +
                typedOnWrongLayout(sampleBundledWords("ru_RU", count: 1000, seed: 13), from: .russian, to: .english)
        case .ukrainian:
            pairs = typedOnWrongLayout(english, from: .english, to: .ukrainian)
        case .russian:
            pairs = typedOnWrongLayout(english, from: .english, to: .russian)
        }
        var bundledHits = 0, systemHits = 0, considered = 0
        for (word, typed) in pairs {
            guard typed != word, typed.count >= 3, isWord(typed) else { continue }
            considered += 1
            if DictionaryLoader.shared.containsExact(typed, language: language) { bundledHits += 1 }
            if isSystemValid(typed, code, .lowercaseOrCapitalized) { systemHits += 1 }
        }
        lines.append("| \(code) | \(percent(lower, sample.count)) | \(percent(capital, sample.count)) | \(percent(bundledHits, considered)) | \(percent(systemHits, considered)) |")
    }
    return lines.joined(separator: "\n") + "\n\n"
}

func languageSection(english: [String], us: KeyboardLayoutMap) -> (String, [String: [String]]) {
    var lines = ["## Other languages paired with English (US layout)", ""]
    lines.append("Words are sampled from the system dictionary's own completions (common words). *Lowercase ok*: accepted as SwitchFix normalizes them. *Detectable*: typed on the US layout by mistake, the result differs and is not an English word, so SwitchFix can notice it. *Collision*: English words typed on this layout by mistake that form a word of this language.")
    lines.append("")
    lines.append("*Random strings accepted* is the control: random 4–7 letter strings from the layout's letters. A dictionary that accepts them cannot tell words from typos.")
    lines.append("")
    lines.append("| Language | Layout | Script | Random strings accepted | Words | Lowercase ok | +Capitalized ok | Typable | Detectable | Collision |")
    lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    var samples: [String: [String]] = ["en": Array(english.prefix(300))]
    let available = Set(SystemSpellChecker.availableLanguages)
    for language in languageCases {
        guard available.contains(language.code) else {
            lines.append("| \(language.code) | \(language.layoutID) | \(language.script) | no system dictionary | | | | | | |")
            continue
        }
        guard let layout = KeyboardLayoutMap(sourceID: language.layoutID) else {
            lines.append("| \(language.code) | \(language.layoutID) | \(language.script) | layout unavailable | | | | | | |")
            continue
        }
        let letters = layout.lowercaseLetters
        let randomAccepted = randomStringsAccepted(language.code, letters: letters, count: 300)
        let words = sampleSystemWords(language: language.code, alphabet: letters, count: 400, seed: 21)
        samples[language.code] = Array(words.prefix(300))
        let lowered = words.map { $0.lowercased() }
        let lowerOK = lowered.filter { isSystemValid($0, language.code, .lowercase) }.count
        let capitalOK = lowered.filter { isSystemValid($0, language.code, .lowercaseOrCapitalized) }.count
        var typable = 0, detectable = 0
        for word in lowered {
            guard let typed = layout.render(word, on: us) else { continue }
            typable += 1
            if typed != word, !isSystemValid(typed.lowercased(), "en", .lowercaseOrCapitalized) { detectable += 1 }
        }
        var considered = 0, collisions = 0
        for word in english {
            guard let typed = us.render(word, on: layout), typed != word, isWord(typed) else { continue }
            considered += 1
            if isSystemValid(typed.lowercased(), language.code, .lowercaseOrCapitalized) { collisions += 1 }
        }
        lines.append("| \(language.code) | \(language.layoutID.replacingOccurrences(of: "com.apple.keylayout.", with: "")) | \(language.script) | \(percent(randomAccepted, 300)) | \(words.count) | \(percent(lowerOK, words.count)) | \(percent(capitalOK, words.count)) | \(percent(typable, words.count)) | \(percent(detectable, typable)) | \(percent(collisions, considered)) (\(considered)) |")
    }
    return (lines.joined(separator: "\n") + "\n\n", samples)
}

// MARK: - Entry point

let command = CommandLine.arguments.dropFirst().first ?? "report"
switch command {
case "threads":
    runThreadCheck()
case "enable-layouts":
    enableLayouts(Array(CommandLine.arguments.dropFirst(2)))
case "control":
    printControl(Array(CommandLine.arguments.dropFirst(2)))
case "report":
    guard let us = KeyboardLayoutMap(sourceID: "com.apple.keylayout.US") else {
        print("US layout unavailable")
        exit(1)
    }
    let english = sampleBundledWords("en_US", count: 2000, seed: 5)
    var report = "# macOS spell checker spike: measurements\n\n" + environmentSection()
    let (languages, samples) = languageSection(english: english, us: us)
    report += bundledComparisonSection(english: english)
    report += languages
    report += latencySection(samples: samples)
    report += threadSection()
    print(report)
    if let index = CommandLine.arguments.firstIndex(of: "--output"), index + 1 < CommandLine.arguments.count {
        try report.write(toFile: CommandLine.arguments[index + 1], atomically: true, encoding: .utf8)
    }
default:
    print("usage: SpellCheckerSpike [report [--output <file>] | threads | enable-layouts <lang>... | control <lang>...]")
    exit(1)
}

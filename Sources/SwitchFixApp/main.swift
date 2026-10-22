import AppKit
import Dictionary
import UI

// Packaging check (#14): load every bundled dictionary through the app's own
// resource lookup, then exit without starting the menu bar app.
if CommandLine.arguments.contains("--verify-dictionaries") {
    let missing = Language.allCases.filter { !DictionaryLoader.shared.prewarm(language: $0) }
    for language in Language.allCases where !missing.contains(language) {
        print("loaded \(language.rawValue)")
    }
    for language in missing {
        FileHandle.standardError.write(Data("missing \(language.rawValue)\n".utf8))
    }
    exit(missing.isEmpty ? 0 : 1)
}

// SwitchFix - Menu bar app, no Dock icon
// LSUIElement behavior is set via Info.plist in the final .app bundle.
// For swift run, we set the activation policy programmatically.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// Resolves dictionary resources in a SwitchFix_Dictionary.bundle the way
// DictionaryLoader does, using Foundation's own bundle lookup.
// Usage: swift scripts/check_bundle_lookup.swift <bundle> <lang>...
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let bundlePath = arguments.first, let bundle = Bundle(url: URL(fileURLWithPath: bundlePath)) else {
    FileHandle.standardError.write(Data("usage: check_bundle_lookup.swift <bundle> <lang>...\n".utf8))
    exit(2)
}

var failed = false
for language in arguments.dropFirst() {
    guard let url = bundle.url(forResource: language, withExtension: "bin") else {
        print("\(language).bin: not found")
        failed = true
        continue
    }
    print("\(language).bin: \(url.path)")
}
if bundle.url(forResource: "en_US_allow", withExtension: "txt", subdirectory: "overrides") == nil {
    print("overrides/en_US_allow.txt: not found")
    failed = true
}
exit(failed ? 1 : 0)

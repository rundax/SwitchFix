import Foundation
import Carbon

public enum TableExporter {
    public static func osBuildVersion() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    public static func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    public static func translateKey(
        layoutData: Data,
        keyCode: UInt16,
        modifierKeyState: UInt32,
        keyboardType: UInt32
    ) -> StrokeOutput {
        return layoutData.withUnsafeBytes { ptr -> StrokeOutput in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return StrokeOutput(output: nil, rejection: "nullLayoutPointer")
            }

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 255)
            var actualLength = 0

            let status = UCKeyTranslate(
                base,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                keyboardType,
                0, // options 0: return no dead keys, pure deadKeyState tracking
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )

            if status != noErr {
                return StrokeOutput(output: nil, rejection: "statusError")
            }

            if deadKeyState != 0 {
                return StrokeOutput(output: nil, rejection: "deadKey")
            }

            if actualLength == 0 {
                return StrokeOutput(output: nil, rejection: "empty")
            }

            if actualLength > 1 {
                return StrokeOutput(output: nil, rejection: "multiScalar")
            }

            let codeUnit = chars[0]
            guard let scalar = UnicodeScalar(codeUnit) else {
                return StrokeOutput(output: nil, rejection: "invalidUTF16")
            }

            let val = scalar.value
            if val == 0x20 {
                // Space is explicitly allowed
                return StrokeOutput(output: " ", rejection: nil)
            }

            // Reject surrogates and private use area
            if (val >= 0xD800 && val <= 0xDFFF) || (val >= 0xE000 && val <= 0xF8FF) || val > 0xFFFF {
                return StrokeOutput(output: nil, rejection: "privateUseOrSurrogate")
            }

            // Reject controls, newlines, C0 and C1 controls
            if CharacterSet.controlCharacters.contains(scalar) ||
                CharacterSet.newlines.contains(scalar) ||
                val < 0x20 ||
                (val >= 0x7F && val <= 0x9F) {
                return StrokeOutput(output: nil, rejection: "control")
            }

            return StrokeOutput(output: String(Character(scalar)), rejection: nil)
        }
    }

    public static func exportTable(
        source: TISInputSource,
        sourceID: String,
        keyboardType: UInt32
    ) -> LayoutTable? {
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data

        var keyOutputs: [String: KeyCodeOutputs] = [:]

        // Modifiers shifted right 8 bits:
        // unmodified: 0
        // shift: 2 (shiftKey >> 8)
        // caps: 4 (alphaLock >> 8)
        // shiftCaps: 6 ((shiftKey | alphaLock) >> 8)
        // option: 8 (optionKey >> 8)
        // shiftOption: 10 ((shiftKey | optionKey) >> 8)
        // capsOption: 12 ((alphaLock | optionKey) >> 8)
        // shiftCapsOption: 14 ((shiftKey | alphaLock | optionKey) >> 8)

        for keyCode in UInt16(0)..<128 {
            let unmodified = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 0, keyboardType: keyboardType)
            let shift = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 2, keyboardType: keyboardType)
            let caps = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 4, keyboardType: keyboardType)
            let shiftCaps = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 6, keyboardType: keyboardType)
            let option = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 8, keyboardType: keyboardType)
            let shiftOption = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 10, keyboardType: keyboardType)
            let capsOption = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 12, keyboardType: keyboardType)
            let shiftCapsOption = translateKey(layoutData: layoutData, keyCode: keyCode, modifierKeyState: 14, keyboardType: keyboardType)

            let outputs = KeyCodeOutputs(
                keyCode: keyCode,
                unmodified: unmodified,
                shift: shift,
                caps: caps,
                shiftCaps: shiftCaps,
                option: option,
                shiftOption: shiftOption,
                capsOption: capsOption,
                shiftCapsOption: shiftCapsOption
            )
            keyOutputs[String(keyCode)] = outputs
        }

        return LayoutTable(
            schemaVersion: 1,
            sourceID: sourceID,
            keyboardType: keyboardType,
            osVersion: osVersionString(),
            osBuild: osBuildVersion(),
            keyOutputs: keyOutputs
        )
    }

    public static func findAllInstalledSources() -> [String: TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return [:]
        }
        var result: [String: TISInputSource] = [:]
        for src in list {
            guard let typePtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceType) else { continue }
            let type = Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String
            guard type == "TISTypeKeyboardLayout" else { continue }
            guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            result[id] = src
        }
        return result
    }

    public static func exportAllStandardTables(outputDirectory: URL, keyboardTypes: [UInt32]) throws -> [URL] {
        let sources = findAllInstalledSources()
        let standardSourceIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.British",
            "com.apple.keylayout.Dvorak",
            "com.apple.keylayout.Colemak",
            "com.apple.keylayout.Ukrainian",
            "com.apple.keylayout.Ukrainian-PC",
            "com.apple.keylayout.Ukrainian-QWERTY",
            "com.apple.keylayout.Russian",
            "com.apple.keylayout.RussianWin",
            "com.apple.keylayout.Russian-Phonetic"
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var writtenURLs: [URL] = []
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for sourceID in standardSourceIDs {
            guard let source = sources[sourceID] else {
                print("Warning: Source not installed on this system: \(sourceID)")
                continue
            }
            for kbdType in keyboardTypes {
                guard let table = exportTable(source: source, sourceID: sourceID, keyboardType: kbdType) else {
                    print("Warning: Failed to export table for \(sourceID)@\(kbdType)")
                    continue
                }
                let fileURL = outputDirectory.appendingPathComponent("\(sourceID)@\(kbdType).json")
                let data = try encoder.encode(table)
                try data.write(to: fileURL)
                writtenURLs.append(fileURL)
            }
        }

        return writtenURLs
    }
}

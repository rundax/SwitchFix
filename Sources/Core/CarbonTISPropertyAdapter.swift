import Carbon
import Foundation

public final class CarbonTISPropertyAdapter: InputSourcePropertyProviding {
    public let source: TISInputSource

    public init(source: TISInputSource) {
        self.source = source
    }

    public var id: String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    public var localizedName: String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return id
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    public var inputSourceType: String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    public var languages: [String]? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return array
    }

    public func translatedCharacter(keyCode: UInt16, modifierKeyState: UInt32) -> Character? {
        guard let layoutDataReference = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataReference, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        let status = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self),
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &actualLength,
                &characters
            )
        }
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: actualLength).first
    }
}

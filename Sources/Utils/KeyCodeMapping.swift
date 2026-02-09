import Foundation
import Carbon

public class KeyCodeMapping {
    /// Attempt to get the character for a virtual key code using the current input source.
    /// Uses UCKeyTranslate for dynamic mapping.
    public static func characterForKeyCode(_ keyCode: UInt16, shift: Bool = false) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        let keyboardLayout = layoutData.withUnsafeBytes { ptr in
            ptr.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        }

        var deadKeyState: UInt32 = 0
        let modifierKeyState: UInt32 = shift ? (UInt32(shiftKey >> 8) & 0xFF) : 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierKeyState,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}

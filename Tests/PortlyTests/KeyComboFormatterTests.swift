import Carbon.HIToolbox
import Testing
@testable import Portly

struct KeyComboFormatterTests {

    @Test func formatsDefaultHotkeyAsCmdShiftP() {
        let result = KeyComboFormatter.string(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        #expect(result == "⇧⌘P")
    }

    @Test func ordersModifiersControlOptionShiftCommand() {
        let result = KeyComboFormatter.string(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(result == "⌃⌥⇧⌘A")
    }

    @Test func formatsDigitsAndSpace() {
        #expect(KeyComboFormatter.string(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey)) == "⌘7")
        #expect(KeyComboFormatter.string(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) == "⌥Space")
    }

    @Test func unknownKeyCodeRendersPlaceholder() {
        // kVK_Escape isn't in the recorder's allowed set.
        #expect(KeyComboFormatter.string(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)) == "⌘?")
    }
}

import AppKit

/// A menu of the printable ASCII characters (32 to 126), by kind, for inserting while editing.
/// Each item shows the character with its code in decimal and hex, as an ASCII table does.
enum ASCIIMenu {
    private static let groups: [(zh: String, en: String, codes: [Int])] = [
        ("標點與符號", "Punctuation & Symbols", Array(32...47) + Array(58...64) + Array(91...96) + Array(123...126)),
        ("數字", "Digits", Array(48...57)),
        ("大寫字母", "Capital Letters", Array(65...90)),
        ("小寫字母", "Small Letters", Array(97...122)),
    ]

    /// One submenu per kind; an item's represented object is the character to insert.
    static func items(target: AnyObject, action: Selector) -> [NSMenuItem] {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let dim = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        return groups.map { group in
            let submenu = NSMenu()
            for code in group.codes {
                let character = String(UnicodeScalar(UInt8(code)))
                let item = NSMenuItem(title: character, action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = character
                // The space shows as its name: there's nothing else to see.
                let shown = code == 32 ? tr("空白", "Space") : character
                let title = NSMutableAttributedString(string: shown.padding(toLength: 4, withPad: " ", startingAt: 0),
                                                      attributes: [.font: font])
                title.append(NSAttributedString(string: String(format: "%4d   0x%02X", code, code),
                                                attributes: [.font: dim, .foregroundColor: NSColor.secondaryLabelColor]))
                item.attributedTitle = title
                item.toolTip = tr("ASCII \(code)（十六進位 0x\(String(format: "%02X", code))）", "ASCII \(code) (hex 0x\(String(format: "%02X", code)))")
                submenu.addItem(item)
            }
            let item = NSMenuItem(title: tr(group.zh, group.en), action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }
    }
}

import AppKit

/// Line numbers down the left of the editor. A line that wraps gets one number, on its first row;
/// the line with the insertion point is numbered in a stronger color.
final class LineNumberRuler: NSRulerView {
    private var textView: NSTextView { clientView as! NSTextView }

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // Since macOS 14 views may draw outside their bounds, and the area asked to redraw can be
        // larger than the ruler; filling it would paint over the text beside it.
        clipsToBounds = true
        updateThickness()
    }

    required init(coder: NSCoder) { fatalError("not used") }

    private var font: NSFont {
        .monospacedDigitSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 14) * 0.8), weight: .regular)
    }

    /// Wide enough for the last line's number; call after the text or font changes.
    func updateThickness() {
        let lines = Self.lineNumber(at: (textView.string as NSString).length, in: textView.string as NSString)
        let digits = String(repeating: "0", count: max(2, String(lines).count))
        let width = ceil((digits as NSString).size(withAttributes: [.font: font]).width) + 16
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    /// 1 + the number of line breaks before `index`.
    private static func lineNumber(at index: Int, in string: NSString) -> Int {
        var count = 1
        var buffer = [unichar](repeating: 0, count: index)
        string.getCharacters(&buffer, range: NSRange(location: 0, length: index))
        for c in buffer where c == 0x0A { count += 1 }
        return count
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let string = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let current = Self.lineNumber(at: min(textView.selectedRange().location, string.length), in: string)

        func label(_ number: Int, inFragment fragment: NSRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: number == current ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            ]
            let text = "\(number)" as NSString
            let size = text.size(withAttributes: attributes)
            // Line fragments are in the text container; the ruler sits beside the text view's visible part.
            let top = convert(NSPoint(x: 0, y: fragment.minY + textView.textContainerOrigin.y), from: textView).y
            let lineHeight = layout.defaultLineHeight(for: textView.font ?? font)
            text.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: top + (lineHeight - size.height) / 2),
                      withAttributes: attributes)
        }

        // Start at the beginning of the first visible line, which may have scrolled partly out of view.
        var index = string.lineRange(for: NSRange(location: characters.location, length: 0)).location
        var number = Self.lineNumber(at: index, in: string)
        while index < NSMaxRange(characters) {
            let glyph = layout.glyphIndexForCharacter(at: index)
            label(number, inFragment: layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            number += 1
        }
        // The empty line after a final line break (or in an empty document) has a fragment of its own.
        if string.length == 0 || string.character(at: string.length - 1) == 0x0A {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0, extra.intersects(visible) { label(number, inFragment: extra) }
        }
    }
}

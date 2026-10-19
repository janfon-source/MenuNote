import AppKit

/// Turns Markdown into styled text for the read-only preview.
/// Apple's parser reads the Markdown; this lays out its blocks (which it leaves unstyled
/// and without line breaks between them) and styles headings, lists, quotes, code and tables.
enum MarkdownRenderer {
    static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// Checkboxes link to "menunote-task://<n>", n counting task items from the top of the document.
    static let taskScheme = "menunote-task"

    /// Where each task item's check mark sits in the source (the character between the brackets),
    /// in document order, so a clicked checkbox can be flipped in the text.
    /// Matches the parser's view of task items: list items starting "[ ]" or "[x]", outside fenced code.
    static func taskMarkerRanges(in source: String) -> [NSRange] {
        let ns = source as NSString
        let item = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\](?=[ \t])"#)
        let fence = try! NSRegularExpression(pattern: #"^[ \t>]*(```|~~~)"#)
        var ranges: [NSRange] = []
        var inFence = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if fence.firstMatch(in: source, range: line) != nil {
                inFence.toggle()
            } else if !inFence, let m = item.firstMatch(in: source, range: line) {
                ranges.append(m.range(at: 1))
            }
        }
        return ranges
    }

    static func render(_ source: String, fontSize: CGFloat, baseURL: URL?) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options, baseURL: baseURL) else {
            return NSAttributedString(string: source, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor])
        }

        let out = NSMutableAttributedString()
        var lastBlock: PresentationIntent?
        var lastRow: Int?
        var markedItems = Set<Int>()
        var doneItems = Set<Int>()
        var taskCount = 0

        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let block = run.presentationIntent
            let kinds = block?.components ?? []   // innermost first
            let style = BlockStyle(kinds, fontSize: fontSize)

            if block != lastBlock {
                let row = kinds.first { if case .tableRow = $0.kind { return true }; if case .tableHeaderRow = $0.kind { return true }; return false }?.identity
                if out.length > 0 {
                    // Cells of one table row share a line, separated by tabs.
                    out.append(NSAttributedString(string: row != nil && row == lastRow ? "\t" : "\n",
                                                  attributes: [.paragraphStyle: style.paragraph]))
                }
                lastRow = row
                if let marker = style.listMarker(kinds, alreadyMarked: &markedItems) {
                    if let done = taskState(text), let item = nearestItem(kinds) {
                        // "[ ] " / "[x] " starts a task item: draw a checkbox in place of the bullet.
                        text.removeFirst(4)
                        if done { doneItems.insert(item) }
                        out.append(checkbox(done: done, index: taskCount, fontSize: fontSize, paragraph: style.paragraph))
                        taskCount += 1
                    } else {
                        out.append(NSAttributedString(string: marker, attributes: [
                            .font: NSFont.systemFont(ofSize: fontSize),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: style.paragraph]))
                    }
                }
            }
            lastBlock = block

            if style.isCode, text.hasSuffix("\n") { text.removeLast() }
            var font = style.font
            var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: style.paragraph,
                                                        .foregroundColor: style.color]
            if style.isCode { attrs[.backgroundColor] = NSColor.quaternaryLabelColor }

            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) {
                font = .monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular)
                attrs[.backgroundColor] = NSColor.quaternaryLabelColor
            }
            if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let item = nearestItem(kinds), doneItems.contains(item) {
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                // The preview's own link styling is turned off so checkboxes don't look like links.
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor.linkColor
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.imageURL != nil {
                text = "🖼 " + text
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
            }
            attrs[.font] = font
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        return out
    }

    /// true for "[x] …", false for "[ ] …", nil if the text isn't a task item.
    private static func taskState(_ text: String) -> Bool? {
        switch text.prefix(4) {
        case "[ ] ", "[ ]\t": return false
        case "[x] ", "[X] ", "[x]\t", "[X]\t": return true
        default: return nil
        }
    }

    private static func nearestItem(_ kinds: [PresentationIntent.IntentType]) -> Int? {
        kinds.first { if case .listItem = $0.kind { return true }; return false }?.identity
    }

    private static func checkbox(done: Bool, index: Int, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
            // A checked box is a white check on an accent-colored square.
            .applying(.init(paletteColors: done ? [.white, .controlAccentColor] : [.secondaryLabelColor]))
        let image = NSImage(systemSymbolName: done ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let attachment = NSTextAttachment()
        attachment.image = image
        if let size = image?.size {
            // Sit the box on the text's baseline like a capital letter would.
            attachment.bounds = NSRect(x: 0, y: (NSFont.systemFont(ofSize: fontSize).capHeight - size.height) / 2,
                                       width: size.width, height: size.height)
        }
        let link = URL(string: "\(taskScheme)://\(index)")!
        let box = NSMutableAttributedString(attachment: attachment)
        box.append(NSAttributedString(string: "\t"))
        box.addAttributes([.link: link, .paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: fontSize),
                           .toolTip: done ? tr("標為未完成", "Mark as not done") : tr("標為完成", "Mark as done")],
                          range: NSRange(location: 0, length: box.length))
        return box
    }

    /// How one block (paragraph, heading, list item, quote, code block or table cell) looks.
    private struct BlockStyle {
        var font: NSFont
        var color = NSColor.labelColor
        var isCode = false
        let paragraph = NSMutableParagraphStyle()
        private let listDepth: Int

        init(_ kinds: [PresentationIntent.IntentType], fontSize: CGFloat) {
            font = .systemFont(ofSize: fontSize)
            var quoteDepth = 0, lists = 0
            paragraph.paragraphSpacing = fontSize * 0.5
            for intent in kinds {
                switch intent.kind {
                case .header(let level):
                    let scale: [CGFloat] = [1.6, 1.4, 1.2, 1.1, 1.0, 1.0]
                    font = .boldSystemFont(ofSize: fontSize * scale[min(max(level, 1), 6) - 1])
                    paragraph.paragraphSpacingBefore = fontSize * 0.6
                case .codeBlock:
                    font = .monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular)
                    isCode = true
                    paragraph.paragraphSpacing = 2   // its lines are paragraphs too; keep them tight
                case .blockQuote:
                    quoteDepth += 1
                    color = .secondaryLabelColor
                case .orderedList, .unorderedList:
                    lists += 1
                case .tableHeaderRow:
                    font = .boldSystemFont(ofSize: fontSize)
                default:
                    break
                }
            }
            listDepth = lists
            let indent = CGFloat(quoteDepth) * 16 + CGFloat(lists) * 22 + (isCode ? 8 : 0)
            paragraph.headIndent = indent
            paragraph.firstLineHeadIndent = lists > 0 ? indent - 22 : indent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            if kinds.contains(where: { if case .tableCell = $0.kind { return true }; return false }) {
                paragraph.paragraphSpacing = 2
                paragraph.tabStops = (1...8).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 120) }
            }
        }

        /// "•", "◦", "▪" by depth, or "3." for ordered lists, followed by a tab to the text's indent.
        /// Only the first block of each list item gets one.
        func listMarker(_ kinds: [PresentationIntent.IntentType], alreadyMarked: inout Set<Int>) -> String? {
            guard let itemIndex = kinds.firstIndex(where: { if case .listItem = $0.kind { return true }; return false }),
                  alreadyMarked.insert(kinds[itemIndex].identity).inserted,
                  case .listItem(let ordinal) = kinds[itemIndex].kind else { return nil }
            let list = kinds[(itemIndex + 1)...].first {
                if case .orderedList = $0.kind { return true }
                if case .unorderedList = $0.kind { return true }
                return false
            }
            if case .orderedList? = list?.kind { return "\(ordinal).\t" }
            return ["•", "◦", "▪"][(listDepth - 1) % 3] + "\t"
        }
    }
}

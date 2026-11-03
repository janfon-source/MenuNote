import AppKit

/// A calculator in a small window of its own, laid out like the Mac's Calculator: round keys,
/// the operators in orange, the expression so far above the number. It keeps × and ÷ ahead of
/// + and −, works out in decimal (so 0.1 + 0.2 is 0.3), and takes the keyboard as well as clicks.
/// ⌘C copies the number, ⌘V pastes one, and the titlebar's buttons copy it or insert it in the note.
final class CalculatorWindow: NSObject, NSWindowDelegate {
    static let shared = CalculatorWindow()

    /// Puts the shown number at the note's insertion point.
    var onInsert: ((String) -> Void)?
    /// Brings up the note, after the titlebar's buttons, to paste into or to see what went in.
    var onShowNote: (() -> Void)?

    private var panel: NSPanel?
    private let pad = CalculatorView()
    private var localizedToolTips: [(view: NSView, zh: String, en: String)] = []
    private static let frameName = "MenuNoteCalculatorWindow"

    /// Brings the window up, the first time beside `anchor` (the editor's window) if there's room.
    func show(beside anchor: NSWindow?) {
        let panel = self.panel ?? makePanel(beside: anchor)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(pad)
    }

    private func makePanel(beside anchor: NSWindow?) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: CalculatorView.size),
                            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Floats as the pinned editor does, so it stays in reach while typing elsewhere.
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = pad
        panel.delegate = self
        pad.onCopy = { [weak self] in self?.copyResult() }
        pad.onClose = { [weak panel] in panel?.performClose(nil) }

        let copy = titlebarButton("doc.on.doc", "拷貝結果（⌘C）", "Copy the Result (⌘C)", #selector(copyClicked(_:)))
        let insert = titlebarButton("text.insert", "把結果插入筆記的游標位置", "Insert the Result in the Note, at the Insertion Point",
                                    #selector(insertClicked(_:)))
        let buttons = NSStackView(views: [copy, insert])
        buttons.spacing = 2
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        buttons.frame.size = buttons.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = buttons
        accessory.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(accessory)

        // Where it was left last time; the first time, to the left of the editor, or else centered.
        if !panel.setFrameUsingName(Self.frameName) {
            if let anchor, let screen = anchor.screen?.visibleFrame, anchor.frame.minX - panel.frame.width - 8 >= screen.minX {
                panel.setFrameTopLeftPoint(NSPoint(x: anchor.frame.minX - panel.frame.width - 8, y: anchor.frame.maxY))
            } else {
                panel.center()
            }
        }
        panel.setFrameAutosaveName(Self.frameName)

        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            for (view, zh, en) in self.localizedToolTips {
                view.toolTip = tr(zh, en)
                view.setAccessibilityLabel(view.toolTip)
            }
            self.pad.needsDisplay = true
        }
        return panel
    }

    private func titlebarButton(_ symbol: String, _ zh: String, _ en: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
        let b = NSButton(image: image, target: self, action: action)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.toolTip = tr(zh, en)
        b.setAccessibilityLabel(b.toolTip)
        localizedToolTips.append((b, zh, en))
        b.contentTintColor = .secondaryLabelColor
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    @discardableResult
    private func copyResult() -> Bool {
        guard let text = pad.engine.plainResult else {
            NSSound.beep()
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    @objc private func copyClicked(_ sender: Any?) {
        if copyResult() { onShowNote?() }
    }

    @objc private func insertClicked(_ sender: Any?) {
        guard let text = pad.engine.plainResult, let onInsert else { return NSSound.beep() }
        onInsert(text)
        onShowNote?()
    }

    /// Hidden, not closed, so the number is still there next time.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// MARK: - The arithmetic

/// What the keys do, apart from how they look: an expression of numbers and operators,
/// the number being typed, and the last result.
struct CalculatorEngine {
    enum Operator: Character {
        case add = "+", subtract = "−", multiply = "×", divide = "÷"
        var binds: Int { self == .add || self == .subtract ? 1 : 2 }
    }

    private enum Token { case number(Decimal), op(Operator) }

    private var tokens: [Token] = []
    /// The digits typed so far, as typed ("0.50" stays "0.50"); nil until a digit is.
    private var entry: String?
    private var result: Decimal?
    /// What = adds again when pressed again: in 2 + 3 = =, the "+ 3".
    private var repeatStep: (Operator, Decimal)?
    /// The expression that gave `result`, shown above it.
    private var solved = ""
    private(set) var failed = false

    private static let maxDigits = 15

    /// The operator to show selected: the last one pressed, until a number follows it.
    var pendingOperator: Operator? {
        if entry == nil, result == nil, case .op(let op)? = tokens.last { return op }
        return nil
    }

    // MARK: Keys

    mutating func digit(_ d: Character) {
        startOverIfDone()
        var text = entry ?? ""
        guard text.filter(\.isNumber).count < Self.maxDigits else { return }
        if text == "0" { text = "" } else if text == "-0" { text = "-" }
        text.append(d)
        entry = text
    }

    mutating func point() {
        startOverIfDone()
        var text = entry ?? "0"
        if text == "-" { text = "-0" }
        guard !text.contains(".") else { return }
        entry = text + "."
    }

    mutating func operate(_ op: Operator) {
        guard !failed else { return }
        if let value = result {
            tokens = [.number(value)]
            result = nil
            solved = ""
        } else if let value = entryValue {
            tokens.append(.number(value))
        } else if case .op? = tokens.last {
            tokens.removeLast()   // pressed another one instead
        } else if tokens.isEmpty {
            tokens.append(.number(0))
        }
        entry = nil
        tokens.append(.op(op))
    }

    mutating func equals() {
        guard !failed else { return }
        if let value = result {
            // Again: apply the last step to the result.
            guard let (op, operand) = repeatStep else { return }
            tokens = [.number(value), .op(op), .number(operand)]
        } else {
            if let value = entryValue {
                tokens.append(.number(value))
            } else if case .op? = tokens.last {
                // 5 + = is 5 + 5, as on the Mac's Calculator.
                tokens.append(.number(valueBeforeLastOperator))
            }
            if tokens.count >= 3, case .op(let op) = tokens[tokens.count - 2], case .number(let operand) = tokens[tokens.count - 1] {
                repeatStep = (op, operand)
            } else {
                repeatStep = nil
            }
        }
        guard !tokens.isEmpty else { return }
        solved = Self.describe(tokens) + "="
        entry = nil
        if let value = Self.evaluate(tokens) {
            result = value
        } else {
            failed = true
        }
        tokens = []
    }

    /// Of the number on show: by itself a hundredth, but after + or − that share of the number before.
    mutating func percent() {
        guard !failed else { return }
        let value = shownValue / 100
        if result == nil, entry != nil, tokens.count >= 2,
           case .op(let op) = tokens[tokens.count - 1], op == .add || op == .subtract,
           case .number(let base) = tokens[tokens.count - 2] {
            setEntry(base * value)
        } else {
            setEntry(value)
        }
    }

    mutating func negate() {
        guard !failed else { return }
        if var text = entry {
            if text.hasPrefix("-") { text.removeFirst() } else { text = "-" + text }
            entry = text
        } else if result == nil, pendingOperator != nil {
            entry = "-0"
        } else {
            setEntry(-shownValue)
        }
    }

    mutating func backspace() {
        if failed { return clear() }
        guard var text = entry else { return }
        text.removeLast()
        entry = text.isEmpty || text == "-" ? nil : text
    }

    mutating func clear() { self = CalculatorEngine() }

    /// A pasted number replaces the one being typed.
    mutating func paste(_ string: String) -> Bool {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "e" || $0 == "E" || $0 == "+" }),
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        setEntry(value)
        return true
    }

    private mutating func startOverIfDone() {
        if failed || result != nil { clear() }
    }

    /// A worked-out number as the one being typed, starting afresh after a result.
    private mutating func setEntry(_ value: Decimal) {
        if result != nil {
            tokens = []
            result = nil
            solved = ""
        }
        entry = Self.plain(value)
    }

    private var entryValue: Decimal? {
        guard let entry, entry != "-" else { return nil }
        return Decimal(string: entry, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var valueBeforeLastOperator: Decimal {
        if tokens.count >= 2, case .number(let value) = tokens[tokens.count - 2] { return value }
        return 0
    }

    private var shownValue: Decimal {
        if let value = entryValue { return value }
        if let result { return result }
        if case .number(let value)? = tokens.last { return value }
        return valueBeforeLastOperator
    }

    // MARK: Display

    /// The big number: what's being typed, as typed, or else the last number.
    var display: String {
        if failed { return tr("錯誤", "Error") }
        if let entry { return Self.grouped(entry) }
        return Self.format(shownValue)
    }

    /// The small line above it: the expression so far, or the one that gave the result.
    var expression: String {
        if result != nil || failed { return solved }
        var line = Self.describe(tokens)
        if let entry { line += Self.grouped(entry) }
        return line
    }

    /// The number without grouping, for copying and inserting; nil after an error.
    var plainResult: String? {
        failed ? nil : Self.plain(entryValue ?? shownValue)
    }

    // MARK: Working it out

    /// × and ÷ first, then + and −, each left to right. nil for a division by zero.
    private static func evaluate(_ tokens: [Token]) -> Decimal? {
        var numbers: [Decimal] = []
        var ops: [Operator] = []
        func reduce() -> Bool {
            guard let op = ops.popLast(), numbers.count >= 2 else { return false }
            let b = numbers.removeLast(), a = numbers.removeLast()
            switch op {
            case .add: numbers.append(a + b)
            case .subtract: numbers.append(a - b)
            case .multiply: numbers.append(a * b)
            case .divide:
                guard !b.isZero else { return false }
                numbers.append(a / b)
            }
            return true
        }
        for token in tokens {
            switch token {
            case .number(let value): numbers.append(value)
            case .op(let op):
                while let top = ops.last, top.binds >= op.binds {
                    guard reduce() else { return nil }
                }
                ops.append(op)
            }
        }
        if numbers.count == ops.count { ops.removeLast() }   // ends with an operator
        while !ops.isEmpty {
            guard reduce() else { return nil }
        }
        guard let value = numbers.last, !value.isNaN else { return nil }
        return value
    }

    private static func describe(_ tokens: [Token]) -> String {
        tokens.map { token -> String in
            switch token {
            case .number(let value): return format(value)
            case .op(let op): return String(op.rawValue)
            }
        }.joined()
    }

    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = maxDigits
        return f
    }()

    private static let scientificFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .scientific
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 10
        f.exponentSymbol = "e"
        return f
    }()

    /// Grouped by thousands to 15 significant digits; very large or small numbers in e notation.
    static func format(_ value: Decimal) -> String {
        let size = abs(value)
        let formatter = size >= Decimal(string: "1e15")! || (!size.isZero && size < Decimal(string: "1e-9")!)
            ? scientificFormatter : groupedFormatter
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Like `format`, without the grouping commas, for a value someone will paste elsewhere.
    static func plain(_ value: Decimal) -> String {
        format(value).replacingOccurrences(of: ",", with: "")
    }

    /// Typed digits with thousands commas, keeping a trailing point or zeros.
    private static func grouped(_ typed: String) -> String {
        let negative = typed.hasPrefix("-")
        let unsigned = negative ? String(typed.dropFirst()) : typed
        let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var whole = String(parts[0].isEmpty ? "0" : parts[0])
        var index = whole.count - 3
        while index > 0 {
            whole.insert(",", at: whole.index(whole.startIndex, offsetBy: index))
            index -= 3
        }
        return (negative ? "-" : "") + whole + (parts.count > 1 ? "." + parts[1] : "")
    }
}

// MARK: - The keys

/// The display and the 20 round keys, all drawn here, in the window's light or dark look.
final class CalculatorView: NSView {
    var engine = CalculatorEngine() { didSet { needsDisplay = true } }
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?

    private enum Kind { case function, digit, op }

    private struct Key {
        let label: String        // text, or an SF Symbol name when `symbol`
        let symbol: Bool
        let kind: Kind
        let press: (inout CalculatorEngine) -> Void
        var op: CalculatorEngine.Operator?
    }

    private static let diameter: CGFloat = 50, gap: CGFloat = 8, margin: CGFloat = 12
    private static let displayHeight: CGFloat = 112, titlebar: CGFloat = 28
    static let size = NSSize(width: margin * 2 + diameter * 4 + gap * 3,
                             height: titlebar + displayHeight + diameter * 5 + gap * 4 + margin)

    private static func digit(_ d: Character) -> Key {
        Key(label: String(d), symbol: false, kind: .digit, press: { $0.digit(d) })
    }

    private static func op(_ o: CalculatorEngine.Operator, _ symbol: String) -> Key {
        Key(label: symbol, symbol: true, kind: .op, press: { $0.operate(o) }, op: o)
    }

    private let rows: [[Key]] = [
        [Key(label: "delete.left", symbol: true, kind: .function, press: { $0.backspace() }),
         Key(label: "AC", symbol: false, kind: .function, press: { $0.clear() }),
         Key(label: "percent", symbol: true, kind: .function, press: { $0.percent() }),
         op(.divide, "divide")],
        [digit("7"), digit("8"), digit("9"), op(.multiply, "multiply")],
        [digit("4"), digit("5"), digit("6"), op(.subtract, "minus")],
        [digit("1"), digit("2"), digit("3"), op(.add, "plus")],
        [Key(label: "plus.forwardslash.minus", symbol: true, kind: .function, press: { $0.negate() }),
         digit("0"),
         Key(label: ".", symbol: false, kind: .digit, press: { $0.point() }),
         Key(label: "equal", symbol: true, kind: .op, press: { $0.equals() })],
    ]

    /// The key under the pointer while it's held, or lit for a moment after a key on the keyboard.
    private var pressed: (row: Int, column: Int)?
    /// The key the mouse went down on, until it comes up.
    private var held: (row: Int, column: Int)?
    private var flashTimer: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func frame(row: Int, column: Int) -> NSRect {
        NSRect(x: Self.margin + CGFloat(column) * (Self.diameter + Self.gap),
               y: Self.titlebar + Self.displayHeight + CGFloat(row) * (Self.diameter + Self.gap),
               width: Self.diameter, height: Self.diameter)
    }

    private func key(at point: NSPoint) -> (row: Int, column: Int)? {
        for row in rows.indices {
            for column in rows[row].indices where NSBezierPath(ovalIn: frame(row: row, column: column)).contains(point) {
                return (row, column)
            }
        }
        return nil
    }

    // MARK: Drawing

    private var dark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    private static let orange = NSColor(srgbRed: 1, green: 0.62, blue: 0.04, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        bounds.fill()
        drawDisplay()
        for row in rows.indices {
            for column in rows[row].indices {
                drawKey(rows[row][column], in: frame(row: row, column: column), down: pressed.map { $0 == (row, column) } ?? false)
            }
        }
    }

    private func drawDisplay() {
        let width = bounds.width - Self.margin * 2 - 6
        let text = dark ? NSColor.white : NSColor.black
        // The number shrinks to fit rather than being cut off.
        var size: CGFloat = 48
        var number = NSAttributedString()
        repeat {
            number = NSAttributedString(string: engine.display, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .light), .foregroundColor: text])
            size -= 2
        } while number.size().width > width && size > 14
        let numberSize = number.size()
        let bottom = Self.titlebar + Self.displayHeight - 10
        number.draw(at: NSPoint(x: bounds.width - Self.margin - 3 - numberSize.width, y: bottom - numberSize.height))

        let small = NSMutableParagraphStyle()
        small.alignment = .right
        small.lineBreakMode = .byTruncatingHead
        NSAttributedString(string: engine.expression, attributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: text.withAlphaComponent(0.55), .paragraphStyle: small,
        ]).draw(in: NSRect(x: Self.margin + 3, y: bottom - numberSize.height - 20, width: width, height: 20))
    }

    private func drawKey(_ key: Key, in rect: NSRect, down: Bool) {
        let selected = key.op != nil && key.op == engine.pendingOperator
        var fill: NSColor, ink: NSColor
        switch key.kind {
        case .function:
            fill = dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.80, alpha: 1)
            ink = dark ? .white : .black
        case .digit:
            fill = dark ? NSColor(white: 0.36, alpha: 1) : .white
            ink = dark ? .white : .black
        case .op:
            // Selected, it turns over: orange on white, or on pale orange where the digits are white.
            fill = !selected ? Self.orange : dark ? .white : Self.orange.blended(withFraction: 0.78, of: .white) ?? .white
            ink = selected ? Self.orange : .white
        }
        if down { fill = fill.blended(withFraction: 0.3, of: dark || key.kind == .op ? .white : .black) ?? fill }
        fill.setFill()
        NSBezierPath(ovalIn: rect).fill()

        if key.symbol {
            let config = NSImage.SymbolConfiguration(pointSize: key.kind == .op ? 22 : 19, weight: .medium)
                .applying(.init(paletteColors: [ink]))
            guard let image = NSImage(systemSymbolName: key.label, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
            let s = image.size
            image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            let label = NSAttributedString(string: key.label, attributes: [
                .font: NSFont.systemFont(ofSize: key.kind == .function ? 22 : 26, weight: .regular), .foregroundColor: ink])
            let s = label.size()
            label.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let hit = key(at: convert(event.locationInWindow, from: nil)) else {
            return window?.performDrag(with: event) ?? ()
        }
        flashTimer?.invalidate()
        held = hit
        pressed = hit
        needsDisplay = true
    }

    /// Slid off, the key goes dark, and lights again back over it, as a button does.
    override func mouseDragged(with event: NSEvent) {
        guard let held else { return }
        let over = key(at: convert(event.locationInWindow, from: nil)).map { $0 == held } ?? false
        pressed = over ? held : nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let held else { return }
        self.held = nil
        if pressed != nil { rows[held.row][held.column].press(&engine) }
        pressed = nil
        needsDisplay = true
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty, let typed = event.charactersIgnoringModifiers else { return super.keyDown(with: event) }
        let target: (Int, Int)?
        switch event.keyCode {
        case 51, 117: target = (0, 0)       // delete, forward delete
        case 53: target = (0, 1)            // escape clears, as in Calculator
        case 36, 76: target = (4, 3)        // return, enter
        default:
            switch typed.lowercased() {
            case "c": target = (0, 1)
            case "%": target = (0, 2)
            case "/": target = (0, 3)
            case "*", "x": target = (1, 3)
            case "-": target = (2, 3)
            case "+": target = (3, 3)
            case "=": target = (4, 3)
            case ".", ",": target = (4, 2)
            case "7": target = (1, 0)
            case "8": target = (1, 1)
            case "9": target = (1, 2)
            case "4": target = (2, 0)
            case "5": target = (2, 1)
            case "6": target = (2, 2)
            case "1": target = (3, 0)
            case "2": target = (3, 1)
            case "3": target = (3, 2)
            case "0": target = (4, 1)
            default: target = nil
            }
        }
        guard let (row, column) = target else { return super.keyDown(with: event) }
        rows[row][column].press(&engine)
        flash(row, column)
    }

    /// Lights the key just typed for a moment, so the keyboard shows on the keys.
    private func flash(_ row: Int, _ column: Int) {
        pressed = (row, column)
        needsDisplay = true
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.pressed = nil
            self?.needsDisplay = true
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]) == .command
        else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "c": onCopy?(); return true
        case "v":
            if let string = NSPasteboard.general.string(forType: .string), engine.paste(string) {} else { NSSound.beep() }
            return true
        case "w": onClose?(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { tr("計算機", "Calculator") }
    override func accessibilityValue() -> Any? { engine.display }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The toolbar's calculator: SF Symbols has none, so it's drawn, as a template image so it
/// takes the toolbar's tint. A rounded body, the display across the top, three by three keys.
enum CalculatorIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 1, width: 12, height: 16), xRadius: 2.4, yRadius: 2.4)
            body.lineWidth = 1.3
            body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 4.4, y: 3.4, width: 7.2, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
            for row in 0..<3 {
                for column in 0..<3 {
                    NSBezierPath(ovalIn: NSRect(x: 4.1 + CGFloat(column) * 2.9, y: 8.2 + CGFloat(row) * 2.8, width: 1.9, height: 1.9)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

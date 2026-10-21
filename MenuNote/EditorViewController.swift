import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// The popover's content: a toolbar, a plain-text editor, and a status line.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSOpenSavePanelDelegate,
                                  NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    weak var popover: NSPopover?

    private(set) var fileURL: URL?
    private(set) var isDirty = false {
        didSet { updateHeader() }
    }

    /// The encoding the file was read with, used again when saving if the user keeps it.
    private var fileEncoding = String.Encoding.utf8 {
        didSet { updateStats() }
    }
    /// Whether the user already chose how to save a non-UTF-8 file, so we ask only once.
    private var encodingChosen = true

    /// Pinned keeps the popover open while the user clicks in other apps.
    private var pinned = UserDefaults.standard.bool(forKey: Keys.pinned) {
        didSet {
            UserDefaults.standard.set(pinned, forKey: Keys.pinned)
            applyPopoverBehavior()
        }
    }

    private var fontSize = CGFloat(UserDefaults.standard.object(forKey: Keys.fontSize) as? Double ?? Keys.defaultFontSize) {
        didSet {
            fontSize = min(36, max(10, fontSize))
            UserDefaults.standard.set(Double(fontSize), forKey: Keys.fontSize)
            textView.font = .systemFont(ofSize: fontSize)
            lineNumbers?.updateThickness()
            if previewMode != .off { renderPreview() }
        }
    }

    private enum Keys {
        static let pinned = "menunote.pinned"
        static let fontSize = "menunote.fontSize"
        static let defaultFontSize = 14.0
        static let size = "menunote.size"
        static let markdownPreview = "menunote.markdownPreview"   // before split view: a Bool for "full"
        static let previewMode = "menunote.previewMode"
        static let lineNumbers = "menunote.lineNumbers"
    }

    static let defaultSize = NSSize(width: 440, height: 520)
    static let minSize = NSSize(width: 380, height: 240)   // wide enough for every toolbar button

    /// The popover size the user last dragged to, kept across launches.
    private var savedSize: NSSize {
        get {
            guard let s = UserDefaults.standard.string(forKey: Keys.size) else { return Self.defaultSize }
            return clamp(NSSizeFromString(s))
        }
        set { UserDefaults.standard.set(NSStringFromSize(newValue), forKey: Keys.size) }
    }
    private var sizeAtDragStart = NSSize.zero

    private let scrollView = NSTextView.scrollableTextView()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }
    private let titleLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private var escapeMonitor: Any?
    private var typingMonitor: Any?
    /// Toolbar buttons with their Chinese and English tooltips, relabeled when the language changes.
    private var localizedToolTips: [(view: NSView, zh: String, en: String)] = []
    private var shareButton: NSButton!
    private var pinButton: NSButton!
    private var markdownButton: NSButton!
    private var splitButton: NSButton!

    /// A read-only rendering of the text as Markdown, shown in place of the editor or beside it.
    private let previewScrollView = NSTextView.scrollableTextView()
    private var previewView: NSTextView { previewScrollView.documentView as! NSTextView }
    private let splitDivider = NSBox()
    private var equalSplit: NSLayoutConstraint!
    /// Set while one side is being scrolled to match the other, so the other doesn't echo it back.
    private var syncingScroll = false

    private var isMarkdown: Bool {
        fileURL.map { MarkdownRenderer.fileExtensions.contains($0.pathExtension.lowercased()) } ?? false
    }

    enum PreviewMode: String {
        case off, full, split
    }

    /// The mode Markdown files open in, i.e. the last one used on a Markdown file.
    private var savedPreviewMode: PreviewMode {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: Keys.previewMode).flatMap(PreviewMode.init)
            ?? (defaults.bool(forKey: Keys.markdownPreview) ? .full : .off)
    }

    /// Any text can be previewed; the mode is remembered only for Markdown files.
    private var previewMode = PreviewMode.off {
        didSet {
            let top = editorTopCharacter()
            if isMarkdown { UserDefaults.standard.set(previewMode.rawValue, forKey: Keys.previewMode) }
            if previewMode != .off { renderPreview() }
            scrollView.isHidden = previewMode == .full
            previewScrollView.isHidden = previewMode == .off
            splitDivider.isHidden = previewMode != .split
            equalSplit?.isActive = previewMode == .split   // nil until the view loads
            updateMarkdownButton()
            focusText()
            if previewMode != .full {
                // The editor's width changed. Once laid out, put back the line that was at its top
                // (AppKit shifts it a little as the text rewraps), then start the preview there too.
                view.layoutSubtreeIfNeeded()
                scrollEditor(toTop: top)
                if previewMode == .split { syncScroll(from: scrollView, to: previewScrollView) }
            }
        }
    }

    /// The first character visible at the top of the editor, or nil when it's scrolled to the top.
    private func editorTopCharacter() -> Int? {
        let visible = textView.visibleRect
        guard visible.minY > textView.textContainerOrigin.y, let layout = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        let point = NSPoint(x: 0, y: visible.minY - textView.textContainerOrigin.y)
        return layout.characterIndexForGlyph(at: layout.glyphIndex(for: point, in: container))
    }

    private func scrollEditor(toTop character: Int?) {
        let clip = scrollView.contentView
        var y: CGFloat = 0
        if let character, let layout = textView.layoutManager, character < (textView.string as NSString).length {
            let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil)
            y = line.minY + textView.textContainerOrigin.y
        }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    private var displayName: String { fileURL?.lastPathComponent ?? tr("未命名", "Untitled") }

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: savedSize))

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shareButton = toolButton("square.and.arrow.up", "分享到備忘錄、訊息或其他 App", "Share to Notes, Messages or other apps", #selector(share(_:)))
        pinButton = toolButton("pin", "釘選：點其他地方時不關閉視窗（按 Esc 仍可隱藏）", "Pin: keep the window open when clicking elsewhere (Esc still hides it)", #selector(togglePin(_:)))

        markdownButton = toolButton("doc.richtext", "整頁 Markdown 預覽（⇧⌘M）", "Full Markdown Preview (⇧⌘M)", #selector(toggleMarkdownPreview(_:)))
        splitButton = toolButton("rectangle.split.2x1", "編輯區旁顯示 Markdown 預覽（⌥⇧⌘M）", "Markdown Preview Beside the Text (⌥⇧⌘M)", #selector(toggleSplitPreview(_:)))
        let spacer = NSView()
        let toolbar = NSStackView(views: [
            toolButton("doc.badge.plus", "新增（⌘N）", "New (⌘N)", #selector(newDocument(_:))),
            toolButton("folder", "開啟（⌘O）", "Open (⌘O)", #selector(openDocument(_:))),
            toolButton("square.and.arrow.down", "儲存（⌘S）", "Save (⌘S)", #selector(saveDocument(_:))),
            divider(),
            shareButton,
            toolButton("printer", "列印（⌘P）", "Print (⌘P)", #selector(printDocument(_:))),
            toolButton("face.smiling", "插入 Emoji", "Insert Emoji", #selector(showEmojiMenu(_:))),
            markdownButton,
            splitButton,
            spacer,
            pinButton,
            toolButton("ellipsis.circle", "更多", "More", #selector(showMoreMenu(_:))),
        ])
        toolbar.spacing = 2
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let header = NSStackView(views: [titleLabel, toolbar])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 8)

        configureTextView()
        configurePreview()

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        let grip = ResizeGrip()
        grip.onBegin = { [weak self] in self?.sizeAtDragStart = self?.view.frame.size ?? .zero }
        grip.onDrag = { [weak self] delta in
            guard let self else { return }
            // The popover stays centered under the menu bar icon, so its right edge moves
            // half as far as the width changes; doubling keeps the corner under the pointer.
            self.resize(to: NSSize(width: self.sizeAtDragStart.width + delta.width * 2,
                                   height: self.sizeAtDragStart.height + delta.height))
        }
        grip.onReset = { [weak self] in self?.resetSize(nil) }
        let footer = NSStackView(views: [statsLabel, NSView(), grip])
        // Inset enough that the popover's rounded corner doesn't clip the grip.
        footer.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 6, right: 12)
        footer.views[1].setContentHuggingPriority(.init(1), for: .horizontal)

        let separatorTop = NSBox(), separatorBottom = NSBox()
        separatorTop.boxType = .separator
        separatorBottom.boxType = .separator

        // A filled box rather than a separator box, which keeps its own height instead of stretching.
        splitDivider.boxType = .custom
        splitDivider.borderWidth = 0
        splitDivider.fillColor = .separatorColor
        splitDivider.isHidden = previewMode != .split   // a file opened from Finder may have set the mode already
        splitDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let body = NSStackView(views: [scrollView, splitDivider, previewScrollView])
        body.spacing = 0
        body.alignment = .height
        // Take all the height the header and footer leave, as the scroll views did on their own.
        body.setHuggingPriority(.init(1), for: .vertical)
        equalSplit = previewScrollView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        equalSplit.isActive = previewMode == .split

        let column = NSStackView(views: [header, separatorTop, body, separatorBottom, footer])
        column.orientation = .vertical
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            toolbar.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -20),
            body.widthAnchor.constraint(equalTo: column.widthAnchor),
            footer.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])

        view = root
        preferredContentSize = root.frame.size
        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }
        updatePinButton()
        updateMarkdownButton()
        updateHeader()
        updateStats()
        installEscapeMonitor()
        installScrollSync()
        installPreviewResizing()
        // A web image the preview asked for has arrived.
        NotificationCenter.default.addObserver(forName: ImageLoader.didLoad, object: nil, queue: .main) { [weak self] _ in
            if let self, self.previewMode != .off { self.renderPreview() }
        }
    }

    private var lineNumbers: LineNumberRuler?

    /// Line numbers beside the editor, remembered across launches.
    private var showingLineNumbers = UserDefaults.standard.bool(forKey: Keys.lineNumbers) {
        didSet {
            UserDefaults.standard.set(showingLineNumbers, forKey: Keys.lineNumbers)
            scrollView.rulersVisible = showingLineNumbers
        }
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        showingLineNumbers.toggle()
    }

    private func configureTextView() {
        // A solid page behind the text: the popover itself is translucent and would show what's beneath.
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let tv = textView
        tv.delegate = self
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.font = .systemFont(ofSize: fontSize)
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.drawsBackground = false
        // Smart substitutions surprise people in a plain-text editor.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false

        // The ruler finds lines through the layout manager, which switches the text view to
        // TextKit 1. Switch now rather than in the middle of the ruler's first drawing, which
        // leaves the text undrawn.
        _ = tv.layoutManager
        let ruler = LineNumberRuler(textView: tv)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showingLineNumbers
        lineNumbers = ruler
        // Scrolling moves the lines past the numbers.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                               queue: .main) { [weak ruler] _ in ruler?.needsDisplay = true }
    }

    private func configurePreview() {
        previewScrollView.isHidden = previewMode == .off
        previewScrollView.drawsBackground = true
        previewScrollView.backgroundColor = .textBackgroundColor
        previewScrollView.hasVerticalScroller = true
        previewScrollView.borderType = .noBorder
        let pv = previewView
        pv.textContainer?.replaceLayoutManager(PreviewLayoutManager())   // draws inline code shading
        pv.delegate = self   // for Esc, like the editor
        pv.isEditable = false
        pv.isSelectable = true
        pv.usesFindBar = true
        pv.isIncrementalSearchingEnabled = true
        pv.textContainerInset = NSSize(width: 12, height: 12)
        pv.drawsBackground = false
        // The renderer styles real links itself; leaving NSTextView's blue underline off keeps checkboxes plain.
        pv.linkTextAttributes = [.cursor: NSCursor.pointingHand]
    }

    /// The width the preview's text is laid out in, which table columns are sized to.
    private var previewTextWidth: CGFloat {
        previewView.bounds.width - previewView.textContainerInset.width * 2
            - (previewView.textContainer?.lineFragmentPadding ?? 0) * 2
    }
    private var renderedWidth: CGFloat = 0

    /// Tables are sized for the width they were rendered at, so render again when it changes:
    /// the popover resized, or the preview switched between full and split.
    private func installPreviewResizing() {
        previewView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: previewView,
                                               queue: .main) { [weak self] _ in
            guard let self, self.previewMode != .off, self.previewTextWidth != self.renderedWidth else { return }
            self.renderPreview()
        }
    }

    private func renderPreview() {
        // Keep the scroll position, so ticking a checkbox halfway down doesn't jump to the top.
        let origin = previewScrollView.contentView.bounds.origin
        // Replacing the text and restoring the position scroll the preview while its height is
        // still settling; don't let that drag the editor along. The editor leads, below.
        syncingScroll = true
        defer {
            syncingScroll = false
            // Beside the editor, the preview's height changes as text is typed; keep it lined up.
            if previewMode == .split { syncScroll(from: scrollView, to: previewScrollView) }
        }
        renderedWidth = previewTextWidth
        previewView.textStorage?.setAttributedString(MarkdownRenderer.render(
            textView.string, fontSize: fontSize, baseURL: fileURL?.deletingLastPathComponent(),
            // Not laid out yet: no width to size tables to. The resize afterwards renders again.
            width: renderedWidth > 0 ? renderedWidth : nil, expandedSpoilers: expandedSpoilers))
        previewView.layoutManager?.ensureLayout(for: previewView.textContainer!)
        previewScrollView.contentView.scroll(to: origin)
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    // MARK: - Scroll sync

    /// In the split view, scrolling either side scrolls the other to the same relative position.
    private func installScrollSync() {
        for (source, target) in [(scrollView, previewScrollView), (previewScrollView, scrollView)] {
            source.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                   object: source.contentView, queue: .main) { [weak self] _ in
                guard let self, self.previewMode == .split else { return }
                self.syncScroll(from: source, to: target)
            }
        }
    }

    /// Proportional rather than line by line: the rendered blocks don't map back to source lines,
    /// and for notes the two sides stay close enough.
    private func syncScroll(from source: NSScrollView, to target: NSScrollView) {
        guard !syncingScroll, let sourceDoc = source.documentView, let targetDoc = target.documentView else { return }
        syncingScroll = true
        defer { syncingScroll = false }
        let sourceRange = sourceDoc.frame.height - source.contentView.bounds.height
        let targetRange = targetDoc.frame.height - target.contentView.bounds.height
        let fraction = sourceRange > 0 ? min(1, max(0, source.contentView.bounds.origin.y / sourceRange)) : 0
        // Keep x: beside line numbers the editor's origin sits left of zero.
        target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: max(0, targetRange) * fraction))
        target.reflectScrolledClipView(target.contentView)
    }

    /// Links in the preview that act on the preview itself rather than open in a browser.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard textView === previewView, let url = link as? URL, let host = url.host else { return false }
        switch url.scheme {
        case MarkdownRenderer.taskScheme:
            if let index = Int(host) { toggleTask(index) }
        case HackMD.spoilerScheme:
            if let index = Int(host) {
                expandedSpoilers.formSymmetricDifference([index])
                renderPreview()
            }
        case HackMD.anchorScheme:
            scrollPreview(toAnchor: host)
        default:
            return false
        }
        return true
    }

    /// A checkbox in the preview flips its "[ ]" / "[x]" in the source, as an ordinary undoable edit.
    private func toggleTask(_ index: Int) {
        let markers = MarkdownRenderer.taskMarkerRanges(in: textView.string)
        guard markers.indices.contains(index) else { return }
        let range = markers[index]
        let mark = (textView.string as NSString).substring(with: range) == " " ? "x" : " "
        if textView.shouldChangeText(in: range, replacementString: mark) {
            textView.textStorage?.replaceCharacters(in: range, with: mark)
            textView.didChangeText()
        }
    }

    /// The spoilers opened in this document, by their order in it.
    private var expandedSpoilers = Set<Int>()

    /// Brings a heading ([TOC]) or footnote to the top of the preview.
    private func scrollPreview(toAnchor anchor: String) {
        guard let storage = previewView.textStorage, let layout = previewView.layoutManager,
              let container = previewView.textContainer else { return }
        var target: Int?
        storage.enumerateAttribute(HackMD.anchor, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? String == anchor {
                target = range.location
                stop.pointee = true
            }
        }
        guard let target else { return }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: target, length: 1), actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let clip = previewScrollView.contentView
        let bottom = max(0, previewView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x,
                                y: min(bottom, max(0, rect.minY + previewView.textContainerOrigin.y - 8))))
        previewScrollView.reflectScrolledClipView(clip)
    }

    /// Tints the button of the preview mode that's showing.
    private func updateMarkdownButton() {
        // May run before the view loads (a file opened from Finder), when there are no buttons yet.
        markdownButton?.contentTintColor = previewMode == .full ? .controlAccentColor : .secondaryLabelColor
        splitButton?.contentTintColor = previewMode == .split ? .controlAccentColor : .secondaryLabelColor
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        previewMode = previewMode == .full ? .off : .full
    }

    @objc func toggleSplitPreview(_ sender: Any?) {
        previewMode = previewMode == .split ? .off : .split
    }

    private func toolButton(_ symbol: String, _ zh: String, _ en: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))!
        let b = NSButton(image: image, target: self, action: action)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.toolTip = tr(zh, en)
        b.setAccessibilityLabel(b.toolTip)
        localizedToolTips.append((b, zh, en))
        b.contentTintColor = .secondaryLabelColor
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    private func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 9).isActive = true
        box.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return box
    }

    func focusText() {
        view.window?.makeFirstResponder(previewMode == .full ? previewView : textView)
    }

    // MARK: - Size

    private func clamp(_ size: NSSize) -> NSSize {
        // Leave room for the menu bar above and a margin around the popover.
        let screen = (isViewLoaded ? view.window?.screen : nil)?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(max(size.width, Self.minSize.width), screen.width - 40),
                      height: min(max(size.height, Self.minSize.height), screen.height - 30))
    }

    private func resize(to size: NSSize) {
        let size = clamp(size)
        preferredContentSize = size
        popover?.contentSize = size
        savedSize = size
        // Have the views beside the edges, the grip among them, track their new places.
        view.window?.invalidateCursorRects(for: view)
    }

    @objc func resetSize(_ sender: Any?) {
        resize(to: Self.defaultSize)
    }

    // MARK: - State display

    private func updateHeader() {
        titleLabel.stringValue = displayName + (isDirty ? tr(" — 已編輯", " — Edited") : "")
        titleLabel.toolTip = fileURL?.path ?? tr("尚未儲存", "Not saved yet")
    }

    private func updateStats() {
        let s = TextFile.stats(textView.string)
        let counts = tr("\(s.characters) 字 · \(s.lines) 行", "\(s.characters) chars · \(s.lines) lines")
        statsLabel.stringValue = "\(counts) · \(TextFile.name(of: fileEncoding))"
    }

    /// Esc hides the window. NSTextView would otherwise turn Esc into the autocomplete list.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSTextView.complete(_:)) else {
            return false
        }
        closePopover(nil)
        return true
    }

    /// Esc while no text field has focus never reaches a responder we own, so catch it here.
    /// Text views are left alone: the editor handles Esc above (after any input method has had
    /// its turn), and the find bar's field uses Esc to close itself.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53,
                  let window = self.view.window, event.window === window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function).isEmpty,
                  !(window.firstResponder is NSTextView) else { return event }
            self.closePopover(nil)
            return nil
        }
        typingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.leavePreviewForTyping(event)
            return event
        }
    }

    /// Typing while the full preview hides the editor goes back to the editor, and the key is
    /// typed there: someone who opens a note and starts typing wants to edit it. Arrows, page
    /// keys and shortcuts still act on the preview.
    private func leavePreviewForTyping(_ event: NSEvent) {
        guard previewMode == .full, let window = view.window, event.window === window,
              window.firstResponder === previewView,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              ![53, 48].contains(event.keyCode),   // Esc hides the window; Tab moves focus
              let scalar = event.characters?.unicodeScalars.first,
              !(0xF700...0xF8FF).contains(scalar.value)   // arrows, page and function keys
        else { return }
        previewMode = .off   // puts the editor back in front, so the key reaches it
        // The insertion point couldn't be seen; if it's still where opening put it, at the very
        // start, type at the end instead, as when adding to a note.
        if textView.selectedRange() == NSRange(location: 0, length: 0) {
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }

    /// The current line's number is drawn stronger.
    func textViewDidChangeSelection(_ notification: Notification) {
        if notification.object as AnyObject === textView { lineNumbers?.needsDisplay = true }
    }

    func textDidChange(_ notification: Notification) {
        lineNumbers?.updateThickness()
        isDirty = true
        updateStats()
        // Typing beside the split preview, and checkbox clicks in either preview, change the source.
        if previewMode != .off { renderPreview() }
    }

    private func setText(_ text: String, url: URL?, encoding: String.Encoding = .utf8) {
        textView.string = text
        fileEncoding = encoding
        encodingChosen = encoding == .utf8
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        textView.undoManager?.removeAllActions()
        fileURL = url
        isDirty = false
        updateStats()
        lineNumbers?.updateThickness()
        knownModification = url.flatMap(modificationDate)
        watchFile()
        expandedSpoilers = []
        previewMode = isMarkdown ? savedPreviewMode : .off
        focusText()
    }

    // MARK: - Popover behavior

    private func applyPopoverBehavior() {
        popover?.behavior = pinned ? .applicationDefined : .transient
    }

    /// Keeps the popover open while a panel or alert is up; a transient popover
    /// would otherwise close as soon as the panel takes focus.
    private func keepingPopoverOpen<T>(_ body: () -> T) -> T {
        stepAside()
        defer { stepBack() }
        return body()
    }

    private var savedLevel: NSWindow.Level?

    /// The popover lives at status-bar level, above every panel, alert and share sheet.
    /// Drop it to normal level while one of those is up so it doesn't hide them.
    private func stepAside() {
        popover?.behavior = .applicationDefined
        NSApp.activate(ignoringOtherApps: true)
        guard savedLevel == nil, let window = view.window else { return }
        savedLevel = window.level
        window.level = .normal
    }

    private func stepBack() {
        if let level = savedLevel {
            view.window?.level = level
            savedLevel = nil
        }
        applyPopoverBehavior()
        view.window?.makeKey()
    }

    private func updatePinButton() {
        let symbol = pinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tr("釘選", "Pin"))?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
    }

    @objc func togglePin(_ sender: Any?) {
        pinned.toggle()
        updatePinButton()
    }

    @objc func closePopover(_ sender: Any?) {
        popover?.performClose(sender)
    }

    // MARK: - File commands

    /// Asks to save unsaved changes. Returns false if the user cancels.
    func confirmDiscardChanges() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = tr("要儲存對「\(displayName)」所做的變更嗎？", "Save changes to “\(displayName)”?")
        alert.informativeText = tr("如果不儲存，這些變更就會遺失。", "Your changes will be lost if you don’t save them.")
        alert.addButton(withTitle: tr("儲存", "Save"))
        alert.addButton(withTitle: tr("不儲存", "Don’t Save"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        switch keepingPopoverOpen({ alert.runModal() }) {
        case .alertFirstButtonReturn: return save(askForLocation: false)
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    @objc func newDocument(_ sender: Any?) {
        guard confirmDiscardChanges() else { return }
        setText("", url: nil)
    }

    @objc func openDocument(_ sender: Any?) {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.delegate = self   // decides which files can be chosen; see panel(_:shouldEnable:)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard keepingPopoverOpen({ panel.runModal() }) == .OK, let url = panel.url else { return }
        load(url)
    }

    /// Text files can be chosen: plain text, other text such as JSON, HTML or XML (but not RTF,
    /// whose formatting codes would show), and ones the system can't type, such as README or
    /// .zshrc with no extension, which allowing only plain-text types would leave greyed out.
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        if values?.isDirectory == true { return values?.isPackage != true }   // folders to look in, not apps
        guard let type = values?.contentType else { return TextFile.looksLikeText(url) }
        if type.conforms(to: .text) { return !type.conforms(to: .rtf) }
        return (url.pathExtension.isEmpty || type.isDynamic) && TextFile.looksLikeText(url)
    }

    /// Opens a file handed over by Finder, asking about unsaved changes first.
    func open(_ url: URL) {
        guard url != fileURL || isDirty, confirmDiscardChanges() else { return }
        load(url)
    }

    // MARK: - Changes made elsewhere

    /// Watches the open file, so a change made in another app shows here.
    private var fileWatcher: DispatchSourceFileSystemObject?
    /// When the file was last read or saved here; a later date means someone else changed it.
    private var knownModification: Date?
    /// Both the file and the text here changed while the window was closed: ask when it opens.
    private var externalChangePending = false
    private var askingAboutExternalChange = false

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        guard let url = fileURL else { return }
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                // Most apps save by putting a new file in place of the old one, which is what this
                // watcher was following. Give the new one a moment to arrive, then follow it instead.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.watchFile()
                    self.checkFileOnDisk()
                }
            } else {
                self.checkFileOnDisk()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatcher = source
    }

    /// Takes in a change made to the file elsewhere: reloads it if there's nothing unsaved here,
    /// and otherwise asks which version to keep. Also called when the window opens.
    func checkFileOnDisk() {
        guard let url = fileURL, !askingAboutExternalChange else { return }
        guard let modified = modificationDate(url) else {
            isDirty = true   // gone: what's here now exists only here
            return
        }
        guard modified != knownModification || externalChangePending,
              let file = try? TextFile.read(url) else { return }
        if file.text == textView.string {
            knownModification = modified
            externalChangePending = false
            return
        }
        if !isDirty {
            reload(file, modified: modified)
            return
        }
        guard popover?.isShown == true else {
            externalChangePending = true
            return
        }
        askingAboutExternalChange = true
        defer { askingAboutExternalChange = false }
        let alert = NSAlert()
        alert.messageText = tr("「\(displayName)」已在其他地方修改", "“\(displayName)” was changed elsewhere")
        alert.informativeText = tr("你在這裡也有尚未儲存的修改。要載入檔案的新版本，還是保留這裡的內容？",
                                   "You also have unsaved changes here. Load the file’s new version, or keep what’s here?")
        alert.addButton(withTitle: tr("保留這裡的內容", "Keep What’s Here"))
        alert.addButton(withTitle: tr("載入新版本", "Load New Version"))
        let keep = keepingPopoverOpen({ alert.runModal() }) == .alertFirstButtonReturn
        externalChangePending = false
        if keep {
            knownModification = modified   // ask again only if it changes again
        } else if let latest = try? TextFile.read(url) {
            reload(latest, modified: modificationDate(url) ?? modified)
        }
    }

    /// Shows the file's new text, keeping the selection and scroll position as near as they'll go.
    private func reload(_ file: (text: String, encoding: String.Encoding), modified: Date) {
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        textView.string = file.text
        let length = (file.text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.undoManager?.removeAllActions()
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        fileEncoding = file.encoding
        knownModification = modified
        externalChangePending = false
        isDirty = false
        updateStats()
        lineNumbers?.updateThickness()
        if previewMode != .off { renderPreview() }
    }

    private func load(_ url: URL) {
        do {
            let file = try TextFile.read(url)
            setText(file.text, url: url, encoding: file.encoding)
        } catch {
            showError(tr("無法開啟「\(url.lastPathComponent)」", "Couldn’t open “\(url.lastPathComponent)”"), error)
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        save(askForLocation: false)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        save(askForLocation: true)
    }

    @discardableResult
    private func save(askForLocation: Bool) -> Bool {
        var target = fileURL
        if target == nil || askForLocation {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.allowsOtherFileTypes = true   // keep .md and other text extensions people type
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? tr("未命名.txt", "Untitled.txt")
            panel.canCreateDirectories = true
            guard keepingPopoverOpen({ panel.runModal() }) == .OK, let url = panel.url else { return false }
            target = url
        }
        guard let url = target, let encoding = chooseSaveEncoding() else { return false }
        do {
            try TextFile.write(textView.string, to: url, encoding: encoding)
            // Our own save changes the file too; remember it, so it doesn't count as someone else's.
            knownModification = modificationDate(url)
            let moved = url != fileURL
            fileURL = url
            if moved { watchFile() }
            fileEncoding = encoding
            encodingChosen = true
            isDirty = false
            return true
        } catch {
            showError(tr("無法儲存「\(url.lastPathComponent)」", "Couldn’t save “\(url.lastPathComponent)”"), error)
            return false
        }
    }

    /// For a file that wasn't UTF-8, asks whether to keep its encoding or convert to UTF-8.
    /// Asks again later only if the text gains characters the kept encoding can't hold.
    /// Returns nil if the user cancels.
    private func chooseSaveEncoding() -> String.Encoding? {
        let text = textView.string
        let canKeep = text.canBeConverted(to: fileEncoding)
        if fileEncoding == .utf8 || (encodingChosen && canKeep) { return fileEncoding }

        let name = TextFile.name(of: fileEncoding)
        let alert = NSAlert()
        alert.messageText = tr("「\(displayName)」原本是 \(name) 編碼，要用哪種編碼儲存？",
                               "“\(displayName)” was \(name). Which encoding should it be saved in?")
        alert.addButton(withTitle: tr("改存 UTF-8", "Save as UTF-8"))
        if canKeep {
            alert.informativeText = tr("UTF-8 是目前大多數 App 使用的編碼；保留 \(name) 則可讓只認得 \(name) 的舊程式繼續讀取。",
                                        "UTF-8 is what most apps use today. Keeping \(name) lets older programs that only read \(name) still open it.")
            alert.addButton(withTitle: tr("保留 \(name)", "Keep \(name)"))
        } else {
            alert.alertStyle = .warning
            alert.informativeText = tr("文字裡有 \(name) 無法表示的字元，只能改存 UTF-8。",
                                        "The text has characters \(name) can’t hold, so it can only be saved as UTF-8.")
        }
        alert.addButton(withTitle: tr("取消", "Cancel"))
        switch keepingPopoverOpen({ alert.runModal() }) {
        case .alertFirstButtonReturn: return .utf8
        case .alertSecondButtonReturn where canKeep: return fileEncoding
        default: return nil
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        keepingPopoverOpen { _ = alert.runModal() }
    }

    // MARK: - Share

    @objc func share(_ sender: Any?) {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        // Sharing plain text lets 備忘錄, 訊息, 郵件 and installed apps' share extensions all accept it.
        let picker = NSSharingServicePicker(items: [text])
        picker.delegate = self
        stepAside()
        picker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        // Cancelled: restore behavior now. Otherwise wait for the share sheet to finish.
        if service == nil { stepBack() }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        self
    }

    func sharingService(_ sharingService: NSSharingService,
                        sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        view.window
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        stepBack()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        stepBack()
    }

    // MARK: - Email

    /// Opens a new message in the default mail app, with the text as its body.
    @objc func emailDocument(_ sender: Any?) {
        guard !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        guard let url = Self.mailURL(subject: emailSubject, body: textView.string),
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = tr("找不到郵件軟體", "No mail app found")
            alert.informativeText = tr("請在「郵件」App 的設定裡選擇預設的郵件軟體。",
                                       "Choose a default email app in the Mail app’s settings.")
            keepingPopoverOpen { _ = alert.runModal() }
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// A mailto: URL as RFC 6068 has it: line breaks as CR LF, and everything but unreserved
    /// characters percent-encoded, so "&" or "?" in the text can't end the body early.
    static func mailURL(subject: String, body: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
                .addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        }
        return URL(string: "mailto:?subject=\(encode(subject))&body=\(encode(body))")
    }

    /// The file's name, or for an unsaved note its first line without Markdown heading marks.
    private var emailSubject: String {
        if let fileURL { return fileURL.deletingPathExtension().lastPathComponent }
        let first = textView.string.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .first { !$0.isEmpty } ?? ""
        return first.isEmpty ? tr("隨手記", "MenuNote") : String(first.prefix(60))
    }

    // MARK: - Print

    @objc func printDocument(_ sender: Any?) {
        let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .spool

        // Lay the text out at paper width in black on white, independent of the popover's size and theme.
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        printView.isRichText = false
        printView.string = textView.string
        printView.font = .systemFont(ofSize: 12)
        printView.textColor = .black
        printView.backgroundColor = .white
        printView.isVerticallyResizable = true
        printView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        printView.textContainer?.widthTracksTextView = true
        printView.layoutManager?.ensureLayout(for: printView.textContainer!)
        printView.sizeToFit()

        let op = NSPrintOperation(view: printView, printInfo: info)
        op.jobTitle = displayName
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        keepingPopoverOpen { _ = op.run() }
    }

    // MARK: - More menu

    // MARK: - Emoji

    @objc func showEmojiMenu(_ sender: NSButton) {
        let menu = NSMenu()
        EmojiMenu.items(target: self, action: #selector(insertEmoji(_:)), palette: #selector(showEmojiPalette(_:)))
            .forEach(menu.addItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// Right-clicking the text offers the emoji too.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard view === textView else { return menu }
        let submenu = NSMenu()
        EmojiMenu.items(target: self, action: #selector(insertEmoji(_:)), palette: #selector(showEmojiPalette(_:)))
            .forEach(submenu.addItem)
        let item = NSMenuItem(title: tr("插入 Emoji", "Insert Emoji"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    /// Inserts at the insertion point, replacing any selection, as one undoable edit.
    @objc func insertEmoji(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? EmojiMenu.Choice else { return }
        EmojiMenu.used(choice.name)
        textView.insertText(choice.text, replacementRange: textView.selectedRange())
        if previewMode != .full { view.window?.makeFirstResponder(textView) }
    }

    /// The system's picker, for emoji beyond the menu's.
    @objc func showEmojiPalette(_ sender: Any?) {
        view.window?.makeFirstResponder(textView)
        NSApp.orderFrontCharacterPalette(sender)
    }

    @objc func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        // Listed with their shortcuts so ⌘N / ⌘O / ⌘S are discoverable; the main menu handles the keys.
        add(menu, tr("新增", "New"), #selector(newDocument(_:)), key: "n")
        add(menu, tr("開啟…", "Open…"), #selector(openDocument(_:)), key: "o")
        add(menu, tr("儲存", "Save"), #selector(saveDocument(_:)), key: "s")
        add(menu, tr("另存新檔…", "Save As…"), #selector(saveDocumentAs(_:)), key: "S")
        add(menu, tr("以郵件寄出…", "Email…"), #selector(emailDocument(_:)), key: "E")
        menu.addItem(.separator())
        add(menu, tr("放大字體", "Larger Font"), #selector(biggerFont(_:)))
        add(menu, tr("縮小字體", "Smaller Font"), #selector(smallerFont(_:)))
        add(menu, tr("預設字體大小", "Default Font Size"), #selector(resetFont(_:)))
        add(menu, tr("恢復預設視窗大小", "Restore Default Window Size"), #selector(resetSize(_:)))
        let numbers = add(menu, tr("顯示行號", "Show Line Numbers"), #selector(toggleLineNumbers(_:)), key: "l")
        numbers.keyEquivalentModifierMask = [.command, .option]
        numbers.state = showingLineNumbers ? .on : .off
        menu.addItem(.separator())
        add(menu, tr("整頁 Markdown 預覽", "Full Markdown Preview"), #selector(toggleMarkdownPreview(_:)), key: "M")
            .state = previewMode == .full ? .on : .off
        let split = add(menu, tr("左右分割 Markdown 預覽", "Side-by-Side Markdown Preview"), #selector(toggleSplitPreview(_:)), key: "M")
        split.keyEquivalentModifierMask = [.command, .option, .shift]
        split.state = previewMode == .split ? .on : .off
        menu.addItem(.separator())
        let themeMenu = NSMenu()
        for theme in Theme.allCases {
            let item = add(themeMenu, theme.title, #selector(selectTheme(_:)))
            item.representedObject = theme.rawValue
            item.state = theme == Theme.current ? .on : .off
        }
        menu.addItem(withTitle: tr("主題", "Theme"), action: nil, keyEquivalent: "").submenu = themeMenu
        let languageMenu = NSMenu()
        for language in Language.allCases {
            let item = add(languageMenu, language.title, #selector(selectLanguage(_:)))
            item.representedObject = language.rawValue
            item.state = language == Language.current ? .on : .off
        }
        menu.addItem(withTitle: tr("語言", "Language"), action: nil, keyEquivalent: "").submenu = languageMenu
        menu.addItem(.separator())
        let login = add(menu, tr("登入時自動開啟", "Open at Login"), #selector(toggleLaunchAtLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, tr("關於隨手記", "About MenuNote"), #selector(showAbout(_:)))
        menu.addItem(withTitle: tr("結束隨手記", "Quit MenuNote"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func showAbout(_ sender: Any?) {
        // The About panel is modeless, so close the popover rather than leave it covering the panel.
        closePopover(nil)
        NSApp.activate(ignoringOtherApps: true)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: "Created by : Jeff Lee", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: tr("隨手記", "MenuNote"), .credits: credits])
    }

    @objc func biggerFont(_ sender: Any?) { fontSize += 1 }
    @objc func smallerFont(_ sender: Any?) { fontSize -= 1 }
    @objc func resetFont(_ sender: Any?) { fontSize = CGFloat(Keys.defaultFontSize) }

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw) else { return }
        Theme.current = theme
        Theme.apply(to: popover)
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        Language.current = language
    }

    /// Relabels everything already on screen; menus are rebuilt each time they open.
    private func applyLanguage() {
        for (view, zh, en) in localizedToolTips {
            view.toolTip = tr(zh, en)
            view.setAccessibilityLabel(view.toolTip)
        }
        updateHeader()
        updateStats()
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showError(tr("無法變更「登入時自動開啟」", "Couldn’t change “Open at Login”"), error)
        }
    }
}

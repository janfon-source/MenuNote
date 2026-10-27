import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// The popover's content: a toolbar, a plain-text editor, and a status line.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSOpenSavePanelDelegate,
                                  NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    weak var popover: NSPopover?
    /// The window the editor moves to while pinned, which can be dragged anywhere.
    weak var pinnedWindow: NSWindow?
    /// Called when the pin is switched on or off, to move the editor between popover and window.
    var onPinChange: ((Bool) -> Void)?
    private var inPinnedWindow: Bool { pinnedWindow != nil && view.window === pinnedWindow }
    /// On screen, in the popover or the pinned window.
    var isShowing: Bool { inPinnedWindow ? view.window?.isVisible == true : popover?.isShown == true }

    private(set) var fileURL: URL?
    private(set) var isDirty = false {
        didSet {
            updateHeader()
            updateButtons()
            if isDirty != oldValue { rebuildTabs() }   // its tab turns green, or back
        }
    }

    /// The files open, one per tab, in the order shown; `current` is the one in the editor. Its
    /// state lives in the editor and the properties above while it shows, and is kept in its
    /// Document while another does.
    private var documents = [Document()]
    private var current = 0
    private let tabStrip = NSStackView()

    /// The encoding the file was read with, used again when saving if the user keeps it.
    private var fileEncoding = String.Encoding.utf8 {
        didSet { updateStats() }
    }
    /// Whether the user already chose how to save a non-UTF-8 file, so we ask only once.
    private var encodingChosen = true

    /// Pinned moves the editor into a window of its own, which stays open while the user clicks in
    /// other apps and can be dragged anywhere.
    /// False while there's no menu bar icon for the popover to hang from, so the editor stays pinned.
    var canUnpin = true

    private(set) var pinned = UserDefaults.standard.bool(forKey: Keys.pinned) {
        didSet {
            UserDefaults.standard.set(pinned, forKey: Keys.pinned)
            applyPopoverBehavior()
            onPinChange?(pinned)
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
    private var saveButton: NSButton!
    private var printButton: NSButton!
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
            updateButtons()
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
        pinButton = toolButton("pin", "釘選：視窗固定顯示，可拖曳上緣或空白處移動、拖曳邊緣調整大小（按 Esc 仍可隱藏）；解除後回到選單列下方原本的大小",
                               "Pin: keep the window open, drag it anywhere by its top edge and resize it by its edges (Esc still hides it); unpinning puts it back under the menu bar at its earlier size",
                               #selector(togglePin(_:)))

        markdownButton = toolButton("doc.richtext", "整頁 Markdown 預覽（⇧⌘M）", "Full Markdown Preview (⇧⌘M)", #selector(toggleMarkdownPreview(_:)))
        splitButton = toolButton("rectangle.split.2x1", "編輯區旁顯示 Markdown 預覽（⌥⇧⌘M）", "Markdown Preview Beside the Text (⌥⇧⌘M)", #selector(toggleSplitPreview(_:)))
        saveButton = toolButton("square.and.arrow.down", "儲存（⌘S）", "Save (⌘S)", #selector(saveDocument(_:)))
        printButton = toolButton("printer", "列印（⌘P）", "Print (⌘P)", #selector(printDocument(_:)))
        let spacer = NSView()
        let toolbar = NSStackView(views: [
            toolButton("doc.badge.plus", "新增（⌘N）", "New (⌘N)", #selector(newDocument(_:))),
            toolButton("folder", "開啟（⌘O）", "Open (⌘O)", #selector(openDocument(_:))),
            saveButton,
            divider(),
            shareButton,
            printButton,
            toolButton("face.smiling", "插入 Emoji", "Insert Emoji", #selector(showEmojiMenu(_:))),
            markdownButton,
            splitButton,
            spacer,
            pinButton,
            toolButton("ellipsis.circle", "更多", "More", #selector(showMoreMenu(_:))),
        ])
        toolbar.spacing = 2
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        tabStrip.spacing = 4
        tabStrip.setHuggingPriority(.required, for: .vertical)
        tabStrip.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let header = NSStackView(views: [titleLabel, toolbar, tabStrip])
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
            // The pinned window keeps its left edge, so there the corner follows the pointer as it is.
            let factor: CGFloat = self.inPinnedWindow ? 1 : 2
            // The popover stays centered under the menu bar icon, so its right edge moves
            // half as far as the width changes; doubling keeps the corner under the pointer.
            self.resize(to: NSSize(width: self.sizeAtDragStart.width + delta.width * factor,
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
            tabStrip.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -20),
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
        rebuildTabs()
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
        // The pinned window has a size of its own (saved with its place); the popover's size is
        // left as it was, for when the pin comes off.
        if inPinnedWindow, let window = view.window {
            var frame = window.frame
            let top = frame.maxY
            frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
            frame.origin.y = top - frame.height
            preferredContentSize = size
            window.setFrame(frame, display: true)
            return
        }
        preferredContentSize = size
        popover?.contentSize = size
        savedSize = size
        // Have the views beside the edges, the grip among them, track their new places.
        view.window?.invalidateCursorRects(for: view)
    }

    @objc func resetSize(_ sender: Any?) {
        resize(to: Self.defaultSize)
    }

    /// Back in the popover after being pinned: the size it had before.
    func restorePopoverSize() {
        resize(to: savedSize)
    }

    // MARK: - State display

    private func updateHeader() {
        titleLabel.stringValue = displayName + (isDirty ? tr(" — 已編輯", " — Edited") : "")
        titleLabel.toolTip = fileURL?.path ?? tr("尚未儲存", "Not saved yet")
    }

    /// Buttons with nothing to act on are off: Save with no changes to save; Share, Print and
    /// the previews with no text (a preview that's showing can still be closed).
    private func updateButtons() {
        guard isViewLoaded else { return }
        saveButton?.isEnabled = isDirty
        for button in [shareButton, printButton] { button?.isEnabled = hasText }
        markdownButton?.isEnabled = hasText || previewMode == .full
        splitButton?.isEnabled = hasText || previewMode == .split
    }

    private var hasText: Bool { !textView.string.isEmpty }

    private func updateStats() {
        updateButtons()
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

    /// Each tab keeps its own undo: ⌘Z in one file never undoes typing in another.
    func undoManager(for view: NSTextView) -> UndoManager? {
        view === textView ? documents[current].undoManager : nil
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
        guard !pinned || canUnpin else { return NSSound.beep() }
        pinned.toggle()
        updatePinButton()
    }

    /// Hides the window; a pinned one stays pinned, and comes back where it was.
    @objc func closePopover(_ sender: Any?) {
        if inPinnedWindow { return view.window!.orderOut(sender) }
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

    /// A new, empty file in a tab of its own.
    @objc func newDocument(_ sender: Any?) {
        documents.append(Document())
        showTab(documents.count - 1)
    }

    /// Opens files, each in a tab (several may be chosen at once).
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.delegate = self   // decides which files can be chosen; see panel(_:shouldEnable:)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard keepingPopoverOpen({ panel.runModal() }) == .OK else { return }
        for url in panel.urls { openInTab(url) }
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

    /// Opens a file handed over by Finder, in a tab.
    func open(_ url: URL) {
        openInTab(url)
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
        guard isShowing else {
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

    @discardableResult
    private func load(_ url: URL) -> Bool {
        do {
            let file = try TextFile.read(url)
            setText(file.text, url: url, encoding: file.encoding)
            rebuildTabs()
            return true
        } catch {
            showError(tr("無法開啟「\(url.lastPathComponent)」", "Couldn’t open “\(url.lastPathComponent)”"), error)
            return false
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
            if moved {
                watchFile()
                rebuildTabs()   // its tab takes the new name
            }
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
        printView.appearance = NSAppearance(named: .aqua)   // the renderer's colors, as on white paper
        printView.backgroundColor = .white
        if isMarkdown || previewMode != .off {
            // As the preview shows it: headings, lists, tables and code, not the Markdown marks.
            printView.textContainer?.replaceLayoutManager(PreviewLayoutManager())   // inline code shading
            let padding = printView.textContainer?.lineFragmentPadding ?? 0
            printView.textStorage?.setAttributedString(MarkdownRenderer.render(
                textView.string, fontSize: 12, baseURL: fileURL?.deletingLastPathComponent(),
                width: width - padding * 2, expandedSpoilers: expandedSpoilers))
        } else {
            printView.isRichText = false
            printView.string = textView.string
            printView.font = .systemFont(ofSize: 12)
            printView.textColor = .black
        }
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
        // One of the two stays on, or there'd be no way back: the last one on can't be turned off.
        add(menu, tr("顯示在 Dock", "Show in Dock"), #selector(toggleShowInDock(_:))).state = Presence.showInDock ? .on : .off
        add(menu, tr("顯示在選單列", "Show in Menu Bar"), #selector(toggleShowInMenuBar(_:))).state = Presence.showInMenuBar ? .on : .off
        let hint = NSMenuItem(title: tr("Dock 和選單列至少要顯示一個", "Shows in the Dock, the menu bar, or both"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
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
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: "Created by : Jeff Lee\n", attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        let icon = NSTextAttachment()
        icon.image = Self.githubMark
        // Sits the mark on the baseline at about the height of a capital letter.
        let side = font.capHeight + 3
        icon.bounds = NSRect(x: 0, y: (font.capHeight - side) / 2, width: side, height: side)
        let iconString = NSMutableAttributedString(attachment: icon)
        iconString.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: iconString.length))
        credits.append(iconString)
        // "account / repo", as GitHub shows it, with only the repository name linked.
        credits.append(NSAttributedString(string: " janfon-source / ", attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]))
        credits.append(NSAttributedString(string: "MenuNote", attributes: [
            .font: font,
            .link: URL(string: "https://github.com/janfon-source/MenuNote")!,
            .paragraphStyle: paragraph,
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: tr("隨手記", "MenuNote"), .credits: credits])
    }

    /// GitHub's mark (the Octicon mark-github, 16×16), drawn in the label color so it follows
    /// light and dark appearance.
    private static let githubMark: NSImage = {
        let svg = "M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"
        let path = svgPath(svg)
        return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.labelColor.setFill()
            path.fill()
            return true
        }
    }()

    /// Builds a path from SVG path data, enough for the GitHub mark: M, C, A and Z, absolute or
    /// relative, with repeated arguments.
    private static func svgPath(_ data: String) -> NSBezierPath {
        let path = NSBezierPath()
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")
        var command: Character = "M"
        var current = NSPoint.zero
        var start = NSPoint.zero
        func number() -> CGFloat { CGFloat(scanner.scanDouble() ?? 0) }
        // Arc flags may run together with the next number ("0 1-5.45"), so read them one digit at a time.
        func flag() -> Bool {
            _ = scanner.scanCharacters(from: CharacterSet(charactersIn: " ,"))
            return scanner.scanCharacter() == "1"
        }
        while !scanner.isAtEnd {
            let index = scanner.currentIndex
            if let c = scanner.scanCharacter(), c.isLetter {
                command = c
            } else {
                scanner.currentIndex = index
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased() {
            case "M":
                current = NSPoint(x: base.x + number(), y: base.y + number())
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = NSPoint(x: base.x + number(), y: base.y + number())
                path.line(to: current)
            case "C":
                let c1 = NSPoint(x: base.x + number(), y: base.y + number())
                let c2 = NSPoint(x: base.x + number(), y: base.y + number())
                current = NSPoint(x: base.x + number(), y: base.y + number())
                path.curve(to: current, controlPoint1: c1, controlPoint2: c2)
            case "A":
                var r = number()
                _ = number()  // The mark's arcs are circles, so the second radius and rotation are ignored.
                _ = number()
                let large = flag(), sweep = flag()
                let end = NSPoint(x: base.x + number(), y: base.y + number())
                // The center, from the SVG endpoint parameterization for a circle.
                let mid = NSPoint(x: (current.x + end.x) / 2, y: (current.y + end.y) / 2)
                let dx = end.x - current.x, dy = end.y - current.y
                let half = hypot(dx, dy) / 2
                r = max(r, half)
                let h = sqrt(max(r * r - half * half, 0)) * (large == sweep ? -1 : 1)
                let center = NSPoint(x: mid.x - h * dy / (2 * half), y: mid.y + h * dx / (2 * half))
                let a1 = atan2(current.y - center.y, current.x - center.x) * 180 / .pi
                let a2 = atan2(end.y - center.y, end.x - center.x) * 180 / .pi
                path.appendArc(withCenter: center, radius: r, startAngle: a1, endAngle: a2, clockwise: !sweep)
                current = end
            case "Z":
                path.close()
                current = start
            default:
                return path
            }
        }
        return path
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
        rebuildTabs()   // "Untitled" in the language now
    }

    @objc func toggleShowInDock(_ sender: Any?) { Presence.showInDock.toggle() }
    @objc func toggleShowInMenuBar(_ sender: Any?) { Presence.showInMenuBar.toggle() }

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

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleShowInDock(_:)):
            return !Presence.showInDock || Presence.showInMenuBar
        case #selector(toggleShowInMenuBar(_:)):
            return !Presence.showInMenuBar || Presence.showInDock
        case #selector(saveDocument(_:)):
            return isDirty
        case #selector(share(_:)), #selector(printDocument(_:)), #selector(emailDocument(_:)):
            return hasText
        case #selector(toggleMarkdownPreview(_:)):
            return hasText || previewMode == .full
        case #selector(toggleSplitPreview(_:)):
            return hasText || previewMode == .split
        case #selector(nextTab(_:)), #selector(previousTab(_:)):
            return documents.count > 1
        default:
            return true
        }
    }
}

// MARK: - Tabs

/// A file open in a tab, kept here while another tab shows: what the editor needs to show it again.
private final class Document {
    var text = ""
    var fileURL: URL?
    var isDirty = false
    var encoding = String.Encoding.utf8
    var encodingChosen = true
    var knownModification: Date?
    var externalChangePending = false
    var selection = NSRange(location: 0, length: 0)
    var scroll = NSPoint.zero
    var previewMode = EditorViewController.PreviewMode.off
    var expandedSpoilers = Set<Int>()
    /// Its own, so ⌘Z only ever undoes what was typed in this file.
    let undoManager = UndoManager()

    var name: String { fileURL?.lastPathComponent ?? tr("未命名", "Untitled") }
}

extension EditorViewController {
    /// Keeps what the editor shows in the current tab's Document.
    private func stashCurrent() {
        let document = documents[current]
        document.text = textView.string
        document.fileURL = fileURL
        document.isDirty = isDirty
        document.encoding = fileEncoding
        document.encodingChosen = encodingChosen
        document.knownModification = knownModification
        document.externalChangePending = externalChangePending
        document.selection = textView.selectedRange()
        document.scroll = scrollView.contentView.bounds.origin
        document.previewMode = previewMode
        document.expandedSpoilers = expandedSpoilers
    }

    /// Shows a tab's file in the editor, as it was left: text, place, preview and all.
    /// `keepingCurrent`: the tab showing is kept first (not when it's just been closed).
    private func showTab(_ index: Int, keepingCurrent: Bool = true) {
        guard documents.indices.contains(index) else { return }
        if keepingCurrent { stashCurrent() }
        current = index
        let document = documents[index]
        fileURL = document.fileURL
        textView.string = document.text
        fileEncoding = document.encoding
        encodingChosen = document.encodingChosen
        knownModification = document.knownModification
        externalChangePending = document.externalChangePending
        expandedSpoilers = document.expandedSpoilers
        isDirty = document.isDirty
        let length = (document.text as NSString).length
        let start = min(document.selection.location, length)
        textView.setSelectedRange(NSRange(location: start, length: min(document.selection.length, length - start)))
        updateStats()
        updateHeader()
        lineNumbers?.updateThickness()
        watchFile()
        previewMode = document.previewMode   // renders the preview, if any, and focuses
        view.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: document.scroll)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        rebuildTabs()
        focusText()
        checkFileOnDisk()   // it may have changed elsewhere while another tab showed
    }

    /// Opens a file in a tab: the one it's already in, the tab showing if that's an untouched
    /// new one, or else a new tab.
    func openInTab(_ url: URL) {
        let target = url.standardizedFileURL
        stashCurrent()
        if let index = documents.firstIndex(where: { $0.fileURL?.standardizedFileURL == target }) {
            return showTab(index)
        }
        let showing = documents[current]
        let reuse = showing.fileURL == nil && !showing.isDirty && showing.text.isEmpty
        if !reuse {
            documents.append(Document())
            showTab(documents.count - 1)
        }
        if !load(url), !reuse { discardTab(current) }   // the new tab it would have gone in
    }

    /// Closes a tab, asking first about unsaved changes. Closing the last leaves a new, empty one.
    private func closeTab(at index: Int) {
        if index != current { showTab(index) }
        guard confirmDiscardChanges() else { return }
        discardTab(current)
    }

    private func discardTab(_ index: Int) {
        documents.remove(at: index)
        if documents.isEmpty { documents.append(Document()) }
        current = min(index, documents.count - 1)
        showTab(current, keepingCurrent: false)
    }

    @objc func closeTab(_ sender: Any?) {
        closeTab(at: (sender as? NSButton)?.tag ?? current)
    }

    @objc func nextTab(_ sender: Any?) { showTab((current + 1) % documents.count) }
    @objc func previousTab(_ sender: Any?) { showTab((current - 1 + documents.count) % documents.count) }

    /// Whether any tab has changes not saved, for quitting.
    func hasUnsavedChanges() -> Bool {
        stashCurrent()
        return documents.contains(where: \.isDirty)
    }

    /// Asks about each tab with unsaved changes in turn, showing it; false if one is cancelled.
    func confirmDiscardAllChanges() -> Bool {
        stashCurrent()
        for (index, document) in documents.enumerated() where document.isDirty {
            showTab(index)
            guard confirmDiscardChanges() else { return false }
        }
        return true
    }

    /// The tabs under the toolbar: each file's name, in bright green while it has unsaved changes.
    func rebuildTabs() {
        guard isViewLoaded else { return }
        for view in tabStrip.arrangedSubviews { view.removeFromSuperview() }
        for (index, document) in documents.enumerated() {
            let active = index == current
            let dirty = active ? isDirty : document.isDirty
            let title = NSTextField(labelWithString: active ? displayName : document.name)
            title.font = .systemFont(ofSize: 12, weight: active ? .semibold : .regular)
            title.textColor = dirty ? .systemGreen : active ? .labelColor : .secondaryLabelColor
            title.lineBreakMode = .byTruncatingMiddle
            title.setContentCompressionResistancePriority(.init(200), for: .horizontal)
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: tr("關閉", "Close"))!
                .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))!, target: self, action: #selector(closeTab(_:)))
            close.isBordered = false
            close.tag = index
            close.contentTintColor = .secondaryLabelColor
            close.toolTip = tr("關閉這個標籤頁", "Close This Tab")
            close.setContentHuggingPriority(.required, for: .horizontal)
            let chip = TabChip(views: [title, close], active: active)
            let path = (active ? fileURL : document.fileURL)?.path ?? tr("尚未儲存", "Not saved yet")
            chip.toolTip = path + (dirty ? tr("（已修改，尚未儲存）", " (edited, not saved)") : "") + tr("（拖曳可調整順序）", " (drag to reorder)")
            chip.onSelect = { [weak self] in
                guard let self, index != self.current else { return }
                self.showTab(index)
            }
            chip.onMove = { [weak self] from, to in self?.moveTab(from: from, to: to) }
            tabStrip.addArrangedSubview(chip)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        tabStrip.addArrangedSubview(spacer)
    }

    /// A tab dragged to another place: the files take the new order, the same one showing.
    private func moveTab(from: Int, to: Int) {
        guard documents.indices.contains(from), documents.indices.contains(to), from != to else { return rebuildTabs() }
        let showing = documents[current]
        documents.insert(documents.remove(at: from), at: to)
        current = documents.firstIndex { $0 === showing } ?? 0
        rebuildTabs()
    }
}

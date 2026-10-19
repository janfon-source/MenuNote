import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// The popover's content: a toolbar, a plain-text editor, and a status line.
final class EditorViewController: NSViewController, NSTextViewDelegate,
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
            if showingPreview { renderPreview() }
        }
    }

    private enum Keys {
        static let pinned = "menunote.pinned"
        static let fontSize = "menunote.fontSize"
        static let defaultFontSize = 14.0
        static let size = "menunote.size"
        static let markdownPreview = "menunote.markdownPreview"
    }

    static let defaultSize = NSSize(width: 440, height: 520)
    static let minSize = NSSize(width: 340, height: 240)

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
    /// Toolbar buttons with their Chinese and English tooltips, relabeled when the language changes.
    private var localizedToolTips: [(view: NSView, zh: String, en: String)] = []
    private var shareButton: NSButton!
    private var pinButton: NSButton!
    private var markdownButton: NSButton!

    /// A read-only rendering of a Markdown file, shown in place of the editor.
    private let previewScrollView = NSTextView.scrollableTextView()
    private var previewView: NSTextView { previewScrollView.documentView as! NSTextView }

    private var isMarkdown: Bool {
        fileURL.map { MarkdownRenderer.fileExtensions.contains($0.pathExtension.lowercased()) } ?? false
    }

    /// Whether the Markdown preview is showing. Remembered, so the next Markdown file opens the same way.
    private var showingPreview = false {
        didSet {
            if isMarkdown { UserDefaults.standard.set(showingPreview, forKey: Keys.markdownPreview) }
            if showingPreview { renderPreview() }
            scrollView.isHidden = showingPreview
            previewScrollView.isHidden = !showingPreview
            updateMarkdownButton()
            focusText()
        }
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

        markdownButton = toolButton("doc.richtext", "切換 Markdown 預覽（⇧⌘M）", "Toggle Markdown Preview (⇧⌘M)", #selector(toggleMarkdownPreview(_:)))
        let spacer = NSView()
        let toolbar = NSStackView(views: [
            toolButton("doc.badge.plus", "新增（⌘N）", "New (⌘N)", #selector(newDocument(_:))),
            toolButton("folder", "開啟（⌘O）", "Open (⌘O)", #selector(openDocument(_:))),
            toolButton("square.and.arrow.down", "儲存（⌘S）", "Save (⌘S)", #selector(saveDocument(_:))),
            divider(),
            shareButton,
            toolButton("printer", "列印（⌘P）", "Print (⌘P)", #selector(printDocument(_:))),
            markdownButton,
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

        let column = NSStackView(views: [header, separatorTop, scrollView, previewScrollView, separatorBottom, footer])
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
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
            previewScrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
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
    }

    private func configurePreview() {
        previewScrollView.isHidden = true
        previewScrollView.drawsBackground = true
        previewScrollView.backgroundColor = .textBackgroundColor
        previewScrollView.hasVerticalScroller = true
        previewScrollView.borderType = .noBorder
        let pv = previewView
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

    private func renderPreview() {
        // Keep the scroll position, so ticking a checkbox halfway down doesn't jump to the top.
        let origin = previewScrollView.contentView.bounds.origin
        previewView.textStorage?.setAttributedString(MarkdownRenderer.render(
            textView.string, fontSize: fontSize, baseURL: fileURL?.deletingLastPathComponent()))
        previewView.layoutManager?.ensureLayout(for: previewView.textContainer!)
        previewScrollView.contentView.scroll(to: origin)
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    /// A checkbox in the preview flips its "[ ]" / "[x]" in the source, as an ordinary undoable edit.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard textView === previewView, let url = link as? URL, url.scheme == MarkdownRenderer.taskScheme,
              let index = url.host.flatMap({ Int($0) }) else { return false }
        let markers = MarkdownRenderer.taskMarkerRanges(in: self.textView.string)
        guard markers.indices.contains(index) else { return true }
        let range = markers[index]
        let mark = (self.textView.string as NSString).substring(with: range) == " " ? "x" : " "
        if self.textView.shouldChangeText(in: range, replacementString: mark) {
            self.textView.textStorage?.replaceCharacters(in: range, with: mark)
            self.textView.didChangeText()
        }
        return true
    }

    /// Shown only for Markdown files; tinted while the preview is up.
    private func updateMarkdownButton() {
        // May run before the view loads (a file opened from Finder), when there's no button yet.
        markdownButton?.isHidden = !isMarkdown
        markdownButton?.contentTintColor = showingPreview ? .controlAccentColor : .secondaryLabelColor
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        guard isMarkdown else { return }
        showingPreview.toggle()
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
        view.window?.makeFirstResponder(showingPreview ? previewView : textView)
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
    }

    func textDidChange(_ notification: Notification) {
        isDirty = true
        updateStats()
        // Checkbox clicks, and undoing them, change the source while the preview is up.
        if showingPreview { renderPreview() }
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
        showingPreview = isMarkdown && UserDefaults.standard.bool(forKey: Keys.markdownPreview)
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
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard keepingPopoverOpen({ panel.runModal() }) == .OK, let url = panel.url else { return }
        load(url)
    }

    /// Opens a file handed over by Finder, asking about unsaved changes first.
    func open(_ url: URL) {
        guard url != fileURL || isDirty, confirmDiscardChanges() else { return }
        load(url)
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
            fileURL = url
            if !isMarkdown && showingPreview { showingPreview = false }
            updateMarkdownButton()
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

    @objc func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        // Listed with their shortcuts so ⌘N / ⌘O / ⌘S are discoverable; the main menu handles the keys.
        add(menu, tr("新增", "New"), #selector(newDocument(_:)), key: "n")
        add(menu, tr("開啟…", "Open…"), #selector(openDocument(_:)), key: "o")
        add(menu, tr("儲存", "Save"), #selector(saveDocument(_:)), key: "s")
        add(menu, tr("另存新檔…", "Save As…"), #selector(saveDocumentAs(_:)), key: "S")
        menu.addItem(.separator())
        add(menu, tr("放大字體", "Larger Font"), #selector(biggerFont(_:)))
        add(menu, tr("縮小字體", "Smaller Font"), #selector(smallerFont(_:)))
        add(menu, tr("預設字體大小", "Default Font Size"), #selector(resetFont(_:)))
        add(menu, tr("恢復預設視窗大小", "Restore Default Window Size"), #selector(resetSize(_:)))
        if isMarkdown {
            add(menu, tr("Markdown 預覽", "Markdown Preview"), #selector(toggleMarkdownPreview(_:)), key: "M")
                .state = showingPreview ? .on : .off
        }
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

extension EditorViewController: NSMenuItemValidation {
    /// Greys out the Markdown preview shortcut for files that aren't Markdown.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(toggleMarkdownPreview(_:)) || isMarkdown
    }
}

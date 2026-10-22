import AppKit
import ServiceManagement

/// Menu bar app: no Dock icon, just a status item that toggles a popover editor.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // NSApplication holds its delegate weakly, so keep it alive here.
    private static var instance: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        instance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // Accessory apps still need a main menu for ⌘C / ⌘V / ⌘Z / ⌘S to reach the text view;
    // applyLanguage() installs it.
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let editor = EditorViewController()
    /// Holds the editor while it's pinned. Made the first time it's needed.
    private var panel: NSPanel?
    private static let panelFrameName = "MenuNotePinnedWindow"

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.contentViewController = editor
        popover.behavior = .transient
        editor.popover = popover
        editor.onPinChange = { [weak self] pinned in pinned ? self?.pin() : self?.unpin() }
        Theme.apply(to: popover)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        applyLanguage()
        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }

        // Opened by hand: show the editor so people see where it lives.
        // Started at login: stay quietly in the menu bar.
        // The status item has no on-screen frame until the menu bar lays it out, hence the delay.
        if SMAppService.mainApp.status != .enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }

    private func applyLanguage() {
        NSApp.mainMenu = MainMenu.build(editor: editor)
        statusItem.button?.toolTip = tr("隨手記", "MenuNote")
        statusItem.button?.setAccessibilityLabel(tr("隨手記", "MenuNote"))
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if editor.pinned {
            panel?.isVisible == true ? panel?.orderOut(nil) : showPopover()
        } else {
            popover.isShown ? popover.performClose(nil) : showPopover()
        }
    }

    func showPopover() {
        if editor.pinned { return showPanel() }
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        editor.focusText()
        editor.checkFileOnDisk()   // it may have changed while the window was closed
    }

    // MARK: Pinned window

    /// Moves the editor out of the popover into a window of its own, at the same place and size,
    /// which can then be dragged anywhere and stays up when other apps are used.
    private func pin() {
        var rect: NSRect?
        if popover.isShown, let window = editor.view.window {
            rect = window.convertToScreen(editor.view.convert(editor.view.bounds, to: nil))
            popover.animates = false
            popover.close()
            popover.animates = true
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Where the popover was, or else where the window was left. The view goes in as the content
        // view, not as a content view controller, whose preferred size the window would keep to
        // and so refuse to be resized.
        let frame = rect.map { panel.frameRect(forContentRect: $0) } ?? panel.frame
        popover.contentViewController = nil
        panel.contentView = editor.view
        editor.preferredContentSize = panel.contentRect(forFrameRect: frame).size
        holdPreferredSize(false)
        panel.setFrame(frame, display: false)
        editor.pinnedWindow = panel
        if rect != nil { showPanel() }
    }

    /// Puts the editor back in the popover under the menu bar icon, at the size it had before.
    private func unpin() {
        let wasShowing = panel?.isVisible ?? false
        panel?.orderOut(nil)
        panel?.contentView = NSView()
        holdPreferredSize(true)
        editor.pinnedWindow = nil
        popover.contentViewController = editor
        editor.restorePopoverSize()
        if wasShowing { showPopover() }
    }

    private func showPanel() {
        if panel == nil || editor.pinnedWindow == nil { pin() }
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        editor.focusText()
        editor.checkFileOnDisk()   // it may have changed while the window was hidden
    }

    /// A window that looks much like the popover: no title bar to speak of, dragged by its top edge
    /// or any empty background, and floating above other apps' windows as the popover did.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: editor.view.frame.size),
                            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: EditorViewController.minSize)).size
        // Where it was left last time; the first time, just under the menu bar icon.
        if !panel.setFrameUsingName(Self.panelFrameName), let button = statusItem.button?.window?.frame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: button.midX - size.width / 2, y: button.minY - size.height - 6))
        }
        panel.setFrameAutosaveName(Self.panelFrameName)
        return panel
    }

    /// The popover holds the view to the controller's preferred size with constraints just above
    /// the priority at which a window keeps its size, and a window held like that can't be resized
    /// by its edges. While pinned they're set just below it, so the window decides the size.
    private func holdPreferredSize(_ hold: Bool) {
        for constraint in editor.view.constraints where constraint.identifier?.hasPrefix("NSViewController.preferredContentSize") == true {
            constraint.priority = hold ? .init(501) : .init(499)
        }
    }

    /// The preferred size follows the pinned window's, so nothing pulls the window back.
    func windowDidResize(_ notification: Notification) {
        guard let panel, notification.object as? NSPanel === panel, editor.pinnedWindow === panel else { return }
        editor.preferredContentSize = panel.contentRect(forFrameRect: panel.frame).size
    }

    /// Right-click menu on the status item.
    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("開啟隨手記", "Open MenuNote"), action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("結束隨手記", "Quit MenuNote"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() { showPopover() }

    /// Files opened from Finder (Open With, or dropped on the app icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showPopover()
            self.editor.open(url)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editor.isDirty else { return .terminateNow }
        showPopover()
        return editor.confirmDiscardChanges() ? .terminateNow : .terminateCancel
    }
}

import AppKit
import ServiceManagement

/// Menu bar app: no Dock icon, just a status item that toggles a popover editor.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.contentViewController = editor
        popover.behavior = .transient
        editor.popover = popover
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
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        editor.focusText()
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

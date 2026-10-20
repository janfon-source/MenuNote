import AppKit

/// The main menu is never shown (accessory app), but its key equivalents still work
/// while the popover is key — that is what makes ⌘S, ⌘C, ⌘Z and friends function.
/// Rebuilt when the language changes.
enum MainMenu {
    static func build(editor: EditorViewController) -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, tr("隨手記", "MenuNote"))
        app.addItem(withTitle: tr("結束隨手記", "Quit MenuNote"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, tr("檔案", "File"))
        add(file, tr("新增", "New"), #selector(EditorViewController.newDocument(_:)), "n", target: editor)
        add(file, tr("開啟…", "Open…"), #selector(EditorViewController.openDocument(_:)), "o", target: editor)
        file.addItem(.separator())
        add(file, tr("儲存", "Save"), #selector(EditorViewController.saveDocument(_:)), "s", target: editor)
        add(file, tr("另存新檔…", "Save As…"), #selector(EditorViewController.saveDocumentAs(_:)), "S", target: editor)
        file.addItem(.separator())
        add(file, tr("以郵件寄出…", "Email…"), #selector(EditorViewController.emailDocument(_:)), "E", target: editor)
        file.addItem(.separator())
        add(file, tr("列印…", "Print…"), #selector(EditorViewController.printDocument(_:)), "p", target: editor)
        add(file, tr("關閉視窗", "Close Window"), #selector(EditorViewController.closePopover(_:)), "w", target: editor)

        let edit = submenu(in: main, tr("編輯", "Edit"))
        add(edit, tr("還原", "Undo"), Selector(("undo:")), "z")
        add(edit, tr("重做", "Redo"), Selector(("redo:")), "Z")
        edit.addItem(.separator())
        add(edit, tr("剪下", "Cut"), #selector(NSText.cut(_:)), "x")
        add(edit, tr("拷貝", "Copy"), #selector(NSText.copy(_:)), "c")
        add(edit, tr("貼上", "Paste"), #selector(NSText.paste(_:)), "v")
        add(edit, tr("全選", "Select All"), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = add(edit, tr("尋找…", "Find…"), #selector(NSTextView.performFindPanelAction(_:)), "f")
        find.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        let next = add(edit, tr("找下一個", "Find Next"), #selector(NSTextView.performFindPanelAction(_:)), "g")
        next.tag = Int(NSTextFinder.Action.nextMatch.rawValue)

        let format = submenu(in: main, tr("格式", "Format"))
        add(format, tr("放大字體", "Larger Font"), #selector(EditorViewController.biggerFont(_:)), "+", target: editor)
        add(format, tr("縮小字體", "Smaller Font"), #selector(EditorViewController.smallerFont(_:)), "-", target: editor)
        add(format, tr("預設字體大小", "Default Font Size"), #selector(EditorViewController.resetFont(_:)), "0", target: editor)
        add(format, tr("顯示行號", "Show Line Numbers"), #selector(EditorViewController.toggleLineNumbers(_:)), "l", target: editor)
            .keyEquivalentModifierMask = [.command, .option]
        format.addItem(.separator())
        add(format, tr("整頁 Markdown 預覽", "Full Markdown Preview"), #selector(EditorViewController.toggleMarkdownPreview(_:)), "M", target: editor)
        add(format, tr("左右分割 Markdown 預覽", "Side-by-Side Markdown Preview"), #selector(EditorViewController.toggleSplitPreview(_:)), "M", target: editor)
            .keyEquivalentModifierMask = [.command, .option, .shift]

        return main
    }

    private static func submenu(in main: NSMenu, _ title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                            target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}

# 隨手記 MenuNote

住在 macOS 選單列的輕量純文字筆記。點一下選單列圖示就能寫，按 Esc 就收起來。

A lightweight plain-text notepad that lives in the macOS menu bar. [English below](#english).

## 功能

- **選單列小視窗**：不佔 Dock，可拖曳右下角調整大小，可釘選讓它不自動關閉。
- **純文字檔**：開啟、儲存、另存新檔、列印、分享到備忘錄或訊息。
- **自動判斷編碼**：讀得懂 UTF-8、UTF-16、Big5、GB2312 / GBK / GB18030。非 UTF-8 的檔案存檔時，可以選擇保留原編碼或改存 UTF-8。
- **Markdown 預覽**：`.md` 檔可切換成排版後的預覽（⇧⌘M），待辦清單的勾選框可以直接點選，會同步改回原始文字。
- **繁體中文 / English 介面**：在「更多」選單切換，立即生效。
- 淺色、深色或跟隨系統的外觀，登入時自動開啟。

## 安裝

需要 macOS 13 以上，以及 Xcode 或 Command Line Tools（`xcode-select --install`）。

```sh
git clone https://github.com/<你的帳號>/MenuNote.git
cd MenuNote
./build.sh install   # 編譯並安裝到 /Applications/隨手記.app
```

只想編譯不安裝就執行 `./build.sh`，結果在 `build/隨手記.app`。也可以用 Xcode 開啟 `MenuNote.xcodeproj`。

---

## English

### Features

- **Menu bar popover**: no Dock icon, resizable from the corner, can be pinned open.
- **Plain-text files**: open, save, save as, print, and share to Notes or Messages.
- **Encoding detection**: reads UTF-8, UTF-16, Big5 and GB2312 / GBK / GB18030. When saving a file that wasn't UTF-8, you choose whether to keep its encoding or convert to UTF-8.
- **Markdown preview**: toggle `.md` files into a rendered preview (⇧⌘M). Task-list checkboxes are clickable and update the source text.
- **Traditional Chinese / English UI**, switchable live from the More menu.
- Light, dark or system appearance, and an option to open at login.

### Install

Requires macOS 13 or later and Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/<your-account>/MenuNote.git
cd MenuNote
./build.sh install   # builds and installs /Applications/隨手記.app
```

Run `./build.sh` alone to build into `build/隨手記.app` without installing, or open `MenuNote.xcodeproj` in Xcode.

## License

[MIT](LICENSE) © 2026 Jeff Lee

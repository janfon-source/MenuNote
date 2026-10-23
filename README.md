# MenuNote 隨手記

A lightweight plain-text notepad that lives in the macOS menu bar. Click the menu bar icon to write; press Esc to put it away.

住在 macOS 選單列的輕量純文字筆記。[中文說明在下方](#中文說明)。

## Features

- **Menu bar popover**, resizable from the corner. Show it in the Dock, the menu bar, or both (at least one stays on); with no menu bar icon, the window stays pinned and opens from the Dock.
- **Pinning**: the pin turns the window into a floating one you can drag anywhere (by its top edge or any empty space) and resize by its edges; it stays up while you use other apps and comes back where you left it. Unpin and it returns under the menu bar icon at the size it had before.
- **Plain-text files**: open, save, save as, print, and share to Notes or Messages.
- **Email** (⇧⌘E or the More menu): opens a new message in the default mail app with the text as its body, and the file name or first line as the subject.
- **Insert emoji** from the smiley toolbar button or the right-click menu: common GitHub emoji by category, inserted as shortcodes such as `:smile:` (hold ⌥ for the emoji itself), with recent ones first.
- **Line numbers** beside the editor, toggled with ⌥⌘L or from the More menu. A wrapped line keeps a single number. The setting is remembered.
- **Live updates**: when another app changes the open file, the new text loads automatically; if there are unsaved changes here too, you're asked which to keep.
- **Encoding detection**: reads UTF-8, UTF-16, Big5 and GB2312 / GBK / GB18030. When saving a file that wasn't UTF-8, you choose whether to keep its encoding or convert to UTF-8.
- **Markdown preview**: full-window or side by side as you type, with syntax-colored code blocks. See [below](#markdown-preview).
- **Traditional Chinese / Simplified Chinese / English UI**, switchable live from the More menu.
- Light, dark or system appearance, and an option to open at login.

## Markdown preview

Any document can be previewed while you edit it, not only `.md` files. [MarkDown.md](MarkDown.md) (in Chinese) lists every supported syntax with examples; open it in MenuNote and switch to the preview to see each one rendered.

| Mode | Shortcut | Toolbar button |
|---|---|---|
| Full: the preview replaces the editor | ⇧⌘M | Document icon |
| Side by side: text on the left, preview on the right | ⌥⇧⌘M | Split icon |

Press the same shortcut or button again to close the preview. Both modes are also in the More menu.

- **Live updates**: side by side, the preview updates as you type.
- **Scroll sync**: side by side, scrolling either half scrolls the other to the same relative position. Around headings, tables and code, which differ a lot in height between the two halves, they can be a few lines apart.
- **Line breaks**: a new line in the text is a new line in the preview, as in GitHub comments. No need for two trailing spaces.
- **Text styles**: besides the standard `*italic*`, `**bold**` and `~~strikethrough~~`, HackMD's `==highlight==`, `++underline++`, `^superscript^` and `~subscript~`. Italics are drawn slanted, so Chinese text (whose fonts have no italics) slants too.
- **Task lists**: `- [ ]` / `- [x]` show as checkboxes. Clicking one updates the source text, and ⌘Z undoes it.
- **Tables**: drawn with grid lines, columns sized to their content, and a bold, shaded header. `:--`, `--:` and `:--:` align a column left, right or center.
- **Images**: `![alt](url)` shows the image, from a file beside the document (relative path), an absolute path, or an `https://` address. Wide images shrink to fit, and HackMD's `=200x` sets the size.
- **HTML tags**: most common tags work, such as `<b>`, `<span style="color: red">`, `<kbd>`, `<br>`, `<div align="center">`, `<details>`, `<table>` (with `colspan` and `rowspan`) and `<img>`. Unknown tags show as typed.
- **Definition lists**: a line starting with `: ` or `~ ` under a term is its definition (PHP Markdown Extra / Pandoc syntax). Terms show in bold with definitions indented below.
- **Horizontal rules**: `---` draws a thin line across the full width.
- **Remembered mode**: `.md` files open in the preview mode last used on a `.md` file. Other files always open in the editor. Start typing in the full preview to go back to the editor.

### HackMD syntax

| Syntax | In the preview |
|---|---|
| `:::info`, `:::success`, `:::warning`, `:::danger` … `:::` | Blue, green, orange and red callout boxes |
| `:::spoiler Title` … `:::` | Collapsed; click the title to open or close it |
| `[TOC]` | A table of contents from the headings; click one to scroll to it |
| `[^1]` with `[^1]: note`, or inline `^[note]` | A superscript number linking to the note, listed at the end |
| `*[HTML]: Hyper Text Markup Language` | A dotted underline on HTML in the text, with the meaning as a tooltip |
| `:smile:`, `:+1:`, `:tada:` and other common shortcodes | Emoji |
| `{%youtube ID %}`, `{%vimeo %}`, `{%gist %}`, `{%pdf %}` and so on | A link, since the preview can't play them |
| Front matter between `---` lines at the top, `<!-- comments -->` | Hidden |

HackMD's `==highlight==`, `++underline++`, `^superscript^`, `~subscript~`, definition lists and ```` ```js= ```` line numbers are covered above. Math (`$…$`) and diagrams such as mermaid aren't supported and show as typed.

### Code syntax coloring

Put the language name after the opening ```` ``` ```` of a code block:

````markdown
```python
def greet(name):
    print(f"Hello, {name}!")
```
````

| Language | Also accepted |
|---|---|
| Python | `py` |
| JavaScript | `js`, `jsx`, `ts`, `tsx`, `typescript` |
| Java | |
| C | `h` |
| C++ | `cpp`, `c++`, `cc`, `hpp` |
| PHP | |
| SQL | `mysql`, `postgres`, `sqlite` |
| Bash | `sh`, `zsh`, `shell` |
| HTML | `xml`, `svg` |
| CSS | `scss`, `less` |
| JSON | |

Keywords, strings, comments, numbers, types and function calls each get a color, plus parts specific to each language, such as:
- `@` annotations
- C / C++ preprocessor directives such as `#include`
- `$variables`
- HTML tags and attributes
- CSS property names
- JSON keys

Add `=` after the language name to show line numbers (HackMD syntax): `=` starts at 1, `=101` at 101, and `=+` continues from the previous code block.

Colors follow Xcode's defaults, with a set for light and one for dark appearance. Code blocks with no language, or one not listed, stay in one color.

Coloring is done with pattern rules rather than a full parser, so unusual code may occasionally be colored wrongly. These are not colored separately:
- the contents of `<script>` and `<style>` in HTML
- PHP heredoc strings

## Install

Requires macOS 13 or later, on Intel or Apple silicon.

### Download

Paste this into Terminal to download the latest version, install it in Applications and open it:

```sh
curl -L https://github.com/janfon-source/MenuNote/releases/latest/download/MenuNote.zip -o /tmp/MenuNote.zip && ditto -x -k /tmp/MenuNote.zip /Applications && open /Applications/隨手記.app
```

Or download the zip from [Releases](https://github.com/janfon-source/MenuNote/releases/latest), unzip it and move 隨手記 to Applications. The app isn't notarized, so a browser download is blocked the first time: try to open it, click Done at the warning, then click Open Anyway in System Settings → Privacy & Security. The Terminal command above avoids this.

### Build from source

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/janfon-source/MenuNote.git
cd MenuNote
./build.sh install   # builds and installs /Applications/隨手記.app
```

Run `./build.sh` alone to build into `build/隨手記.app` without installing, or open `MenuNote.xcodeproj` in Xcode.

---

## 中文說明

點一下選單列圖示就能寫，按 Esc 就收起來。

### 功能

- **選單列小視窗**：可拖曳右下角調整大小。可設定顯示在 Dock、選單列或兩者（至少要顯示一個）；不顯示在選單列時，視窗固定為釘選，從 Dock 開啟。
- **釘選視窗**：按圖釘後，視窗變成可自由拖曳（拖上緣或空白處）、可拖曳邊緣調整大小的浮動視窗，切換到其他 App 也不會收起，下次顯示仍在原處；再按一次解除釘選，視窗回到選單列圖示下方、釘選前的大小。
- **純文字檔**：開啟、儲存、另存新檔、列印、分享到備忘錄或訊息。
- **以郵件寄出**（⇧⌘E 或「更多」選單）：在預設的郵件軟體開一封新郵件，內文是編輯中的文字，主旨是檔名或第一行。
- **插入 Emoji**：工具列的笑臉按鈕或右鍵選單，依分類列出常用的 GitHub emoji，插入 `:smile:` 這樣的代碼（按住 ⌥ 則插入 emoji 本身），最近用過的排在最前面。
- **行號**：在編輯區左側顯示行號（⌥⌘L 或「更多」選單開關），自動換行的續行不另外編號，設定會記住。
- **自動更新**：開著的檔案在其他 App 被修改時，自動載入新內容；隨手記裡也有未儲存的修改時，會先問要保留哪一邊。
- **自動判斷編碼**：讀得懂 UTF-8、UTF-16、Big5、GB2312 / GBK / GB18030。非 UTF-8 的檔案存檔時，可以選擇保留原編碼或改存 UTF-8。
- **Markdown 預覽**：整頁預覽或左右分割、邊打字邊看，程式碼區塊會語法上色，詳見[下方說明](#markdown-預覽)。
- **繁體中文／简体中文／English 介面**：在「更多」選單切換，立即生效。
- 淺色、深色或跟隨系統的外觀，登入時自動開啟。

### Markdown 預覽

任何文件都能在編輯中切換預覽，不限 `.md` 檔。所有支援的語法和範例整理在 [MarkDown.md](MarkDown.md)，用隨手記開啟它並切到預覽，就能對照寫法和效果。

| 模式 | 快捷鍵 | 工具列按鈕 |
|---|---|---|
| 整頁預覽：預覽取代編輯區 | ⇧⌘M | 文件圖示 |
| 左右分割：左邊編輯、右邊預覽 | ⌥⇧⌘M | 分割圖示 |

再按一次同一個快捷鍵或按鈕就關掉預覽，兩種模式也都列在「更多」選單裡。

- **即時更新**：分割模式下，打字時右邊的預覽會跟著更新。
- **同步捲動**：分割模式下，捲動任一邊，另一邊會捲到相同的比例位置。標題、表格、程式碼這類高度差很多的段落，兩邊可能差幾行。
- **換行**：編輯區按 Enter 換行，預覽也會換行（跟 GitHub 留言一樣），不必在行尾加兩個空格。
- **文字樣式**：除了標準的 `*斜體*`、`**粗體**`、`~~刪除線~~`，也支援 HackMD 的 `==螢光標記==`、`++底線++`、`^上標^`、`~下標~`。中文斜體以傾斜效果呈現（中文字體沒有斜體）。
- **待辦清單**：`- [ ]` / `- [x]` 會顯示成勾選框，點一下就會改回原始文字，可以用 ⌘Z 還原。
- **表格**：有格線，欄寬依內容調整，表頭粗體並加淡底色；`:--`、`--:`、`:--:` 分別設定靠左、靠右、置中。
- **圖片**：`![說明](網址)` 會顯示圖片，支援文件旁的本機檔案（相對路徑）、絕對路徑和 `https://` 網路圖片；太寬會等比例縮小，也可以用 HackMD 的 `=200x` 指定大小。
- **HTML 標籤**：支援大部分常用標籤，例如 `<b>`、`<span style="color: red">`、`<kbd>`、`<br>`、`<div align="center">`、`<details>`、`<table>`（含 `colspan`、`rowspan` 合併儲存格）、`<img>`；不認得的標籤照原樣顯示。
- **定義清單**：名詞下一行以 `: ` 或 `~ ` 開頭就是它的解釋（PHP Markdown Extra / Pandoc 的寫法），名詞顯示成粗體、解釋縮排在下方。
- **分隔線**：`---` 畫成整欄寬的細線。
- **記住模式**：`.md` 檔會用上次在 `.md` 檔用的預覽模式開啟，其他檔案一律從編輯模式開始。整頁預覽時直接打字，就會回到編輯區繼續輸入。

#### HackMD 語法

| 語法 | 預覽效果 |
|---|---|
| `:::info`、`:::success`、`:::warning`、`:::danger` … `:::` | 藍、綠、橘、紅色的提示框 |
| `:::spoiler 標題` … `:::` | 預設收合，點標題展開或收合 |
| `[TOC]` | 依標題產生目錄，點一下捲到該段 |
| `[^1]` 和 `[^1]: 說明`、行內 `^[說明]` | 上標編號，說明列在文末，點編號捲過去 |
| `*[HTML]: Hyper Text Markup Language` | 文中的 HTML 加虛線底線，滑鼠移上去顯示全名 |
| `:smile:`、`:+1:`、`:tada:` 等 | 常用的 emoji 代碼換成 emoji |
| `{%youtube ID %}`、`{%vimeo %}`、`{%gist %}`、`{%pdf %}` 等 | 預覽不能播放，改成可點的連結 |
| 開頭的 `---` 設定區、`<!-- 註解 -->` | 隱藏 |

文字樣式的 `==螢光==`、`++底線++`、`^上標^`、`~下標~`，定義清單，以及程式碼行號 ```` ```js= ```` 也都是 HackMD 語法，見上方說明。數學式（`$…$`）和 mermaid 等圖表不支援，會顯示原始文字。

#### 程式碼語法上色

在程式碼區塊開頭的 ```` ``` ```` 後面寫上語言名稱，就會依語言上色，例如：

````markdown
```python
def greet(name):
    print(f"Hello, {name}!")
```
````

| 語言 | 也認得的寫法 |
|---|---|
| Python | `py` |
| JavaScript | `js`、`jsx`、`ts`、`tsx`、`typescript` |
| Java | |
| C | `h` |
| C++ | `cpp`、`c++`、`cc`、`hpp` |
| PHP | |
| SQL | `mysql`、`postgres`、`sqlite` |
| Bash | `sh`、`zsh`、`shell` |
| HTML | `xml`、`svg` |
| CSS | `scss`、`less` |
| JSON | |

關鍵字、字串、註解、數字、型別、函式呼叫各有顏色，另外也標出各語言特有的部分，例如：
- `@` 標註
- C / C++ 的 `#include` 等前置處理指令
- `$變數`
- HTML 標籤與屬性
- CSS 屬性名稱
- JSON 的 key

語言名稱後面加上 `=` 會顯示行號（HackMD 的寫法）：`=` 從 1 開始，`=101` 從 101 開始，`=+` 接續上一個程式碼區塊的行號。

配色採用 Xcode 預設，淺色、深色模式各一組。沒寫語言或不在表裡的程式碼區塊會單色顯示。

上色是用規則比對，不是完整解析程式碼，少見的寫法偶爾會上錯顏色。以下內容也不會分開上色：
- HTML 裡 `<script>`、`<style>` 的內容
- PHP 的 heredoc 多行字串

### 安裝

需要 macOS 13 以上，Intel 和 Apple 晶片的 Mac 都可以。

#### 直接下載

在「終端機」貼上這一行，會下載最新版、安裝到「應用程式」並打開：

```sh
curl -L https://github.com/janfon-source/MenuNote/releases/latest/download/MenuNote.zip -o /tmp/MenuNote.zip && ditto -x -k /tmp/MenuNote.zip /Applications && open /Applications/隨手記.app
```

也可以到 [Releases](https://github.com/janfon-source/MenuNote/releases/latest) 下載壓縮檔，解壓縮後把「隨手記」拖到「應用程式」。隨手記沒有經過 Apple 公證，用瀏覽器下載的版本第一次打開會被擋下：先打開一次，出現警告後按「完成」，再到「系統設定」→「隱私權與安全性」，在下方按「強制打開」。用上面的終端機指令安裝則不會被擋。

#### 從原始碼編譯

需要 Xcode 或 Command Line Tools（`xcode-select --install`）。

```sh
git clone https://github.com/janfon-source/MenuNote.git
cd MenuNote
./build.sh install   # 編譯並安裝到 /Applications/隨手記.app
```

只想編譯不安裝就執行 `./build.sh`，結果在 `build/隨手記.app`。也可以用 Xcode 開啟 `MenuNote.xcodeproj`。

## License

[MIT](LICENSE) © 2026 Jeff Lee

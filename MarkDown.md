# 隨手記支援的 Markdown 語法

這份文件列出隨手記預覽支援的所有語法：標準 Markdown、GitHub 的擴充語法，以及 HackMD 的特殊語法。每一節先列「寫法」，再接著示範實際效果。用隨手記開啟這份文件，按 ⇧⌘M（整頁預覽）或 ⌥⇧⌘M（左右分割）就能對照原始文字和顯示結果。

[TOC]

## 標題

```markdown
# 一級標題
## 二級標題
### 三級標題
#### 四級標題
##### 五級標題
###### 六級標題

一級標題的另一種寫法
===

二級標題的另一種寫法
---
```

一級和二級標題下方會自動加一條分隔線。文字下一行緊接 `===` 或 `---`，也會變成一級或二級標題。只想要分隔線的話，`---` 前面要空一行。

## 段落與換行

```markdown
同一段的第一行
按 Enter 就換行，不必在行尾加兩個空格

空一行就是新的段落。
行尾加反斜線也能換行\
這是下一行
```

效果：

同一段的第一行
按 Enter 就換行，不必在行尾加兩個空格

空一行就是新的段落。
行尾加反斜線也能換行\
這是下一行

## 文字樣式

| 寫法 | 效果 | 來源 |
|---|---|---|
| `*斜體*` 或 `_斜體_` | *斜體* | 標準 |
| `**粗體**` 或 `__粗體__` | **粗體** | 標準 |
| `***斜體加粗體***` | ***斜體加粗體*** | 標準 |
| `~~刪除線~~` | ~~刪除線~~ | GitHub |
| `` `行內程式碼` `` | `行內程式碼` | 標準 |
| `==螢光標記==` | ==螢光標記== | HackMD |
| `++底線++` | ++底線++ | HackMD |
| `2^10^`（上標） | 2^10^ | HackMD |
| `H~2~O`（下標） | H~2~O | HackMD |

- 中文斜體以傾斜效果呈現，因為中文字體沒有斜體。
- 上標、下標裡不能有空格。
- 單一個 `~` 包起來是下標，兩個 `~~` 才是刪除線。
- 要顯示 `*`、`#` 這類符號本身，在前面加反斜線：`\*不是斜體\*` 會顯示成 \*不是斜體\*。

## 清單

```markdown
- 項目，也可以用 * 或 +
- 另一個項目
  - 縮排兩格成為下一層
    - 再下一層

1. 編號清單
2. 第二項
   1. 巢狀編號
```

效果：

- 項目，也可以用 * 或 +
- 另一個項目
  - 縮排兩格成為下一層
    - 再下一層

1. 編號清單
2. 第二項
   1. 巢狀編號

編號清單的數字照第一項開始，例如第一項寫 `3.`，清單就從 3 開始，後面的項目自動接著編號。

## 待辦清單

```markdown
- [ ] 還沒做
- [x] 已完成
```

效果：

- [ ] 還沒做
- [x] 已完成

在預覽裡點勾選框，會直接改回原始文字，可以用 ⌘Z 還原。已完成的項目會加上刪除線。

## 引用

```markdown
> 外層引用
>> 巢狀引用
>>> 深層巢狀
```

效果：

> 外層引用
>> 巢狀引用
>>> 深層巢狀

引用裡也能放清單、程式碼、表格等其他內容。

## 連結

```markdown
[文字連結](https://www.apple.com)
[有提示的連結](https://www.apple.com "滑鼠提示")
<https://www.apple.com>
直接貼上網址 https://www.apple.com
[寄信給我](mailto:me@example.com)
[參考式連結][apple]

[apple]: https://www.apple.com
```

效果：

[文字連結](https://www.apple.com)
[有提示的連結](https://www.apple.com "滑鼠提示")
<https://www.apple.com>
直接貼上網址 https://www.apple.com
[寄信給我](mailto:me@example.com)
[參考式連結][apple]

[apple]: https://www.apple.com

## 圖片

```markdown
![GitHub 圖示](https://github.githubassets.com/favicons/favicon.png)
![同資料夾的圖片](photo.png)
![子資料夾的圖片](images/photo.png)
![指定寬度](photo.png =200x)
![指定寬高](photo.png =200x100)
[![點圖片開連結](photo.png)](https://www.apple.com)
```

效果（第一張是網路圖片，其他幾張要在這份文件旁邊放一張 `photo.png` 才看得到）：

![GitHub 圖示](https://github.githubassets.com/favicons/favicon.png)

- 本機圖片的相對路徑以文件所在的資料夾為準，也可以寫絕對路徑。未命名的新文件沒有所在資料夾，只能用絕對路徑或網路圖片。
- 網路圖片只支援 `https://`，在背景下載，下載完預覽會自動更新。
- 比欄寬還寬的圖片會等比例縮小。`=200x` 只指定寬度（HackMD 寫法），高度依比例；`=200x100` 指定寬高。
- 找不到或載入失敗的圖片，會顯示 🖼 和圖片說明，滑鼠移上去會顯示圖片位址。

## 分隔線

```markdown
---
***
- - -
* * *
```

以上四種寫法效果相同：

---

## 表格

```markdown
| 靠左 | 靠右 | 置中 |
| :-- | --: | :--: |
| 蘋果 | 30 | 紅 |
| 香蕉 | 12 | 黃 |
```

效果：

| 靠左 | 靠右 | 置中 |
| :-- | --: | :--: |
| 蘋果 | 30 | 紅 |
| 香蕉 | 12 | 黃 |

第二行的冒號決定對齊方式：`:--` 靠左、`--:` 靠右、`:--:` 置中。欄寬會依內容自動調整。

## 程式碼區塊

````markdown
```python
def greet(name):
    print(f"Hello, {name}!")
```
````

效果：

```python
def greet(name):
    print(f"Hello, {name}!")
```

在開頭的 ```` ``` ```` 後面寫上語言名稱，就會依語言上色：

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

沒寫語言或不在表裡的程式碼區塊會單色顯示。也可以用 `~~~` 代替 ```` ``` ````。

### 行號（HackMD）

語言名稱後面加 `=` 會顯示行號，`=101` 從 101 開始，`=+` 接續上一個程式碼區塊：

````markdown
```js=
const a = 1;
const b = 2;
```

```js=+
console.log(a + b);
```
````

效果：

```js=
const a = 1;
const b = 2;
```

```js=+
console.log(a + b);
```

## 定義清單（HackMD）

```markdown
蘋果
: 一種水果
: 也是一家公司

香蕉
~ 黃色的水果
```

效果：

蘋果
: 一種水果
: 也是一家公司

香蕉
~ 黃色的水果

## 提示框（HackMD）

```markdown
:::info
資訊
:::

:::success
成功
:::

:::warning
警告
:::

:::danger
危險
:::
```

效果：

:::info
資訊
:::

:::success
成功
:::

:::warning
警告
:::

:::danger
危險
:::

提示框裡可以放清單、程式碼等任何內容。

## 摺疊區塊（HackMD）

```markdown
:::spoiler 點我展開
摺疊起來的內容
:::
```

效果：

:::spoiler 點我展開
摺疊起來的內容
:::

預設是收合的，點標題展開或收合。

## 目錄（HackMD）

```markdown
[TOC]
```

在這一行的位置，依文件裡的標題產生目錄，點目錄裡的標題會捲到該段。這份文件開頭的目錄就是這樣產生的。

## 註腳（HackMD）

```markdown
這句話需要說明[^note]，也可以把說明直接寫在句子裡^[這是行內註腳]。

[^note]: 這是註腳的說明。
```

效果：

這句話需要說明[^note]，也可以把說明直接寫在句子裡^[這是行內註腳]。

[^note]: 這是註腳的說明。

註腳的說明會依序列在文件最後，點上標的編號會捲過去。

## 縮寫（HackMD）

```markdown
CPU 是電腦的核心。

*[CPU]: Central Processing Unit，中央處理器
```

效果：

CPU 是電腦的核心。

*[CPU]: Central Processing Unit，中央處理器

文中的縮寫會加上虛線底線，滑鼠移上去會顯示全名。定義那一行不會顯示。

## Emoji（HackMD）

```markdown
:smile: :+1: :tada: :heart: :fire: :rocket: :warning: :white_check_mark:
```

效果：

:smile: :+1: :tada: :heart: :fire: :rocket: :warning: :white_check_mark:

支援常用的 GitHub emoji 代碼，不認得的代碼會照原樣顯示。

不記得代碼的話，按工具列的笑臉按鈕，或在編輯區按右鍵選「插入 Emoji」，從分類選單挑選就會插入代碼；按住 ⌥ 再選，會插入 emoji 本身。

## 嵌入內容（HackMD）

```markdown
{%youtube dQw4w9WgXcQ %}
```

效果：

{%youtube dQw4w9WgXcQ %}

預覽不能播放影片，會改成可點的連結。也支援 `vimeo`、`gist`、`slideshare`、`speakerdeck`、`pdf`、`figma`。

## 隱藏的內容（HackMD）

```markdown
<!-- 這是註解，預覽不會顯示 -->
```

HTML 註解在預覽裡會隱藏，可以跨多行。

文件最開頭用 `---` 包起來的設定區（front matter）也會隱藏：

```markdown
---
title: 文件標題
tags: 筆記
---
```

## HTML 標籤

Markdown 裡可以直接寫大部分常用的 HTML 標籤。

### 行內標籤

| 寫法 | 效果 |
|---|---|
| `<b>粗體</b>`、`<strong>` | <b>粗體</b> |
| `<i>斜體</i>`、`<em>` | <i>斜體</i> |
| `<u>底線</u>`、`<ins>` | <u>底線</u> |
| `<s>刪除</s>`、`<del>` | <s>刪除</s> |
| `<mark>螢光</mark>` | <mark>螢光</mark> |
| `H<sub>2</sub>O`、`2<sup>10</sup>` | H<sub>2</sub>O、2<sup>10</sup> |
| `<code>程式碼</code>` | <code>程式碼</code> |
| `<kbd>⌘</kbd>+<kbd>S</kbd>` | <kbd>⌘</kbd>+<kbd>S</kbd> |
| `<small>小字</small>`、`<big>大字</big>` | <small>小字</small>、<big>大字</big> |
| `<span style="color: red">紅字</span>` | <span style="color: red">紅字</span> |
| `<font color="green">綠字</font>` | <font color="green">綠字</font> |
| `<span style="background: yellow">黃底</span>` | <span style="background: yellow">黃底</span> |
| `<a href="https://www.apple.com">連結</a>` | <a href="https://www.apple.com">連結</a> |
| `<abbr title="全名">縮寫</abbr>` | <abbr title="全名">縮寫</abbr> |
| `第一行<br>第二行` | 第一行<br>第二行 |

`style` 支援 `color`、`background-color`、`font-weight`、`font-style`、`text-decoration`、`font-size`。顏色可以寫英文名稱、`#rgb`、`#rrggbb` 或 `rgb()`。

### 區塊標籤

```html
<div align="center">

**置中的內容，裡面可以寫 Markdown**

</div>

<p align="right">靠右的段落</p>

<details>
<summary>點我展開</summary>

摺疊起來的內容
</details>
```

效果：

<div align="center">

**置中的內容，裡面可以寫 Markdown**

</div>

<p align="right">靠右的段落</p>

<details>
<summary>點我展開</summary>

摺疊起來的內容
</details>

其他支援的區塊標籤：

| 標籤 | 顯示成 |
|---|---|
| `<h1>`～`<h6>` | 標題 |
| `<p>`、`<div>`、`<center>` | 段落；`align="center"`、`align="right"` 或 `style="text-align: …"` 設定對齊 |
| `<ul>`、`<ol>`、`<li>` | 清單，可以巢狀 |
| `<table>`、`<tr>`、`<th>`、`<td>` | 表格，`align` 設定對齊，`colspan`、`rowspan` 合併儲存格（見下方範例） |
| `<pre>`、`<pre><code class="language-python">` | 程式碼區塊，標了語言會上色 |
| `<blockquote>` | 引用 |
| `<dl>`、`<dt>`、`<dd>` | 定義清單 |
| `<hr>` | 分隔線 |
| `<img src="…" width="200">` | 圖片 |
| `<input type="checkbox" checked>` | ☑ 或 ☐ |
| `<iframe>`、`<video>`、`<audio>` | 可點的連結 |
| `<script>`、`<style>` | 連同內容一起隱藏 |

### 合併儲存格

```html
<table>
  <tr><th colspan="3">季度業績</th></tr>
  <tr><th>地區</th><th>Q1</th><th>Q2</th></tr>
  <tr><td rowspan="2">北部</td><td align="right">100</td><td align="right">120</td></tr>
  <tr><td align="right">90</td><td align="right">110</td></tr>
  <tr><td>南部</td><td colspan="2" align="center">合計 <b>300</b></td></tr>
</table>
```

效果：

<table>
  <tr><th colspan="3">季度業績</th></tr>
  <tr><th>地區</th><th>Q1</th><th>Q2</th></tr>
  <tr><td rowspan="2">北部</td><td align="right">100</td><td align="right">120</td></tr>
  <tr><td align="right">90</td><td align="right">110</td></tr>
  <tr><td>南部</td><td colspan="2" align="center">合計 <b>300</b></td></tr>
</table>

`colspan` 是橫跨幾欄，`rowspan` 是往下跨幾列。`<th>` 是粗體加底色的標題格，可以放在任何位置。沒有合併儲存格的 HTML 表格，第一列會當成表頭。

不認得的標籤會照原樣顯示，所以像 `List<T>` 這樣的文字不受影響；程式碼裡的 HTML 也不會轉換。

## 不支援的語法

- 數學式：`$E = mc^2$`、`$$…$$` 會照原始文字顯示。
- 圖表：mermaid、graphviz、sequence、flow 等程式碼區塊會當成一般程式碼顯示。
- `style` 裡上面沒列到的 CSS 屬性會被忽略。
- 勾選框以外的表單元件不會顯示。

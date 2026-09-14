# Using SwiftNote

[简体中文](GUIDE.md) · **English**

## Installation

1. Download `SwiftNote-1.0.0-macOS-arm64.zip` from [GitHub Releases](https://github.com/flaricy/SwiftNote/releases/tag/v1.0.0). Requires Apple Silicon and macOS 14 or later.
2. Unzip it and drag **随记.app** into Applications. 随记 is SwiftNote’s name in Finder; the app’s menus are currently in Chinese.
3. This release is ad-hoc signed and not Apple-notarized. If macOS blocks it, verify that you downloaded it from this repository and follow [Apple’s Open Anyway instructions](https://support.apple.com/102445) in System Settings → Privacy & Security. Do not disable Gatekeeper.

No Accessibility or Screen Recording permission is required. `⌃⌥N` creates a note while the app is running. If another app uses this shortcut, use the menu bar compose button.

## Writing and formatting

Open the app to return to your last note. The first line is ordinary text; type `# ` through `#### ` at the start of a line to create a heading. Type `/` on an empty line for the insert menu; use arrow keys and Return to choose, or Escape to close it.

Select text for the nearby formatting toolbar. When space is tight, use **Aa** at the top. It contains paragraph styles, fonts, and sizes. `⌘B`, `⌘I`, and `⌘U` toggle bold, italic, and underline. Inline shortcuts include `**bold**`, `*italic*`, and backticks for code. Common Markdown paste is supported.

Type `- ` for a list, `1. ` for a numbered list, or `[] ` for a checklist. Return continues a list; Return on an empty item ends it. Backspace at the start of an empty heading or list restores body text. Click a checkbox to change its state.

Paste, drop, or insert an image with the toolbar. Select it and use the bottom slider to resize it proportionally. Imported images are converted to PNG, with a maximum long edge of 2,400 pixels.

The table button lets you choose an initial row and column count. Use Tab / Shift-Tab between cells; right-click to insert or delete a row.

## Edit times

Click in the text to reveal the active visual line’s latest edit time. If the line is full, a small clock appears instead. Hover for the complete date. Times are hidden when you first open or switch notes.

If you record a purchase when ordering, this gives you a useful time reference. **Editing the line updates its timestamp.** It is not an immutable order date or an integration with a merchant.

Times are stored per paragraph, so naturally wrapped lines share a timestamp. A visual table row shows the latest time among its corresponding cells. This is not character-by-character history or version recovery.

## Saving, export, and backup

Notes save automatically. Switching notes, closing the window, or quitting also flushes pending edits. Export an RTFD document using **文件 → 导出富文本…** (File → Export Rich Text).

Data is stored in `~/Library/Application Support/LocalNotes/`. Open it with **文件 → 显示本地数据** (File → Show Local Data). The directory name is retained for compatibility. Each note has an RTFD document, with metadata in a JSON index. To back up, quit the app and copy the entire directory.

Documents and the index are written atomically as separate files, not as a single transaction. Save errors preserve unsaved content and display a message. Deleted source documents remain in the `Deleted/` subdirectory; there is no in-app trash view. Files have no additional app-level encryption.

[Back to the English overview](../README.en.md) · [Website](https://flaricy.github.io/SwiftNote/en.html)

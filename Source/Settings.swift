import AppKit

extension AppController {
    @objc func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 144), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("设置"); panel.appearance = NSAppearance(named: .aqua); panel.backgroundColor = MemoTheme.paper; panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: L("语言")); label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 28, y: 66, width: 90, height: 20)
        let popup = NSPopUpButton(frame: NSRect(x: 130, y: 60, width: 220, height: 30))
        popup.addItems(withTitles: ["English", "中文"])
        popup.selectItem(at: Localization.language == .english ? 0 : 1)
        popup.target = self; popup.action = #selector(changeLanguage(_:)); popup.setAccessibilityLabel(L("语言"))
        panel.contentView?.addSubview(label); panel.contentView?.addSubview(popup)
        settingsWindow = panel; languagePopup = popup; languageLabel = label
        panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    @objc func changeLanguage(_ sender: NSPopUpButton) {
        Localization.language = sender.indexOfSelectedItem == 0 ? .english : .chinese
        applyLanguage()
    }
    func applyLanguage() {
        buildMenu()
        window.title = L("随记")
        settingsWindow?.title = L("设置"); languageLabel?.stringValue = L("语言")
        languagePopup?.setAccessibilityLabel(L("语言"))
        search.placeholderString = L("搜索"); search.setAccessibilityLabel(L("搜索备忘录"))
        imageLabel.stringValue = L("图片宽度"); sizePopup.toolTip = L("字号（8–96）")
        for (button, key) in localizedButtons { button.toolTip = L(key); button.setAccessibilityLabel(L(key)) }
        for (label, key) in localizedLabels { label.stringValue = L(key) }
        for (index, key) in ["正文", "标题 1", "标题 2", "标题 3", "标题 4"].enumerated() { blockPopup.item(at: index)?.title = L(key) }
        for (index, key) in ["系统字体", "苹方", "宋体", "Helvetica", "Georgia", "Menlo"].enumerated() { fontPopup.item(at: index)?.title = L(key) }
        for case let button as NSButton in editor.selectionTools.subviews {
            let key = ["粗体 ⌘B", "斜体 ⌘I", "下划线 ⌘U", "删除线"][button.tag]
            button.toolTip = L(key); button.setAccessibilityLabel(L(key))
        }
        statusItem.button?.toolTip = L("随记 · 点击立即新建  ⌃⌥N\n右键打开菜单")
        statusItem.button?.setAccessibilityLabel(L("快速新建备忘录"))
        if let draft = editor.formulaDraft {
            draft.input.placeholderString = "LaTeX"
            draft.input.setAccessibilityLabel(L(draft.block ? "独立公式源码" : "行内公式源码"))
            MainActor.assumeIsolated { draft.refresh() }
        } else { editor.updateCommandPalette() }
        editor.view.needsDisplay = true; editor.view.timeOverlay.needsDisplay = true
        reloadList()
    }
}

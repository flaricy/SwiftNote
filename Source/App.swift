import AppKit
import Carbon

final class MemoSidebar: NSView {
    override func draw(_ dirtyRect: NSRect) { MemoTheme.sidebar.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
final class MemoRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        MemoTheme.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 3), xRadius: 9, yRadius: 9).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class MemoCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let preview = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 14, weight: .semibold); title.lineBreakMode = .byTruncatingTail
        preview.font = .systemFont(ofSize: 12); preview.textColor = .secondaryLabelColor; preview.lineBreakMode = .byTruncatingTail
        for v in [title, preview] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); title.frame = NSRect(x: 18, y: 32, width: bounds.width-36, height: 20); preview.frame = NSRect(x: 18, y: 12, width: bounds.width-36, height: 18) }
}
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var store: NoteStore!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hotkey: EventHotKeyRef?
    let editor = EditorController()
    let table = NSTableView()
    let search = NSSearchField()
    let status = NSTextField(labelWithString: "")
    let imageSlider = NSSlider(value: 400, minValue: 80, maxValue: 900, target: nil, action: nil)
    let imageLabel = NSTextField(labelWithString: "图片宽度")
    let blockPopup = NSPopUpButton()
    let fontPopup = NSPopUpButton()
    let sizePopup = NSComboBox()
    let formatPopover = NSPopover()
    var selectedID: UUID?
    var filtered: [NoteInfo] = []
    var saving: DispatchWorkItem?
    var dirty = false
    var suppressSelection = false
    var sidebar: NSView!
    var documentHost: NSView!
    var split: NSSplitView!
    let dates: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f }()
    let launched = ProcessInfo.processInfo.systemUptime
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        buildMenu(); buildWindow(); buildQuickEntry()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        do {
            let root = ProcessInfo.processInfo.environment["LOCALNOTES_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            store = try NoteStore(root: root)
            if store.notes.isEmpty { selectedID = try store.create() }
            else { selectedID = UserDefaults.standard.string(forKey: "lastNote").flatMap(UUID.init(uuidString:)) ?? store.notes.sorted { $0.modified > $1.modified }.first?.id }
            if !store.notes.contains(where: { $0.id == selectedID }) { selectedID = store.notes.first?.id }
            reloadList(); if let id = selectedID { select(id) }
        } catch { showError(error); editor.view.isEditable = false }
        NSLog("LocalNotes ready in %.3f seconds", ProcessInfo.processInfo.systemUptime-launched)
    }
    func buildMenu() {
        let main = NSMenu(); NSApp.mainMenu = main
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        add(app, "关于随记", #selector(about), "")
        app.addItem(.separator()); add(app, "隐藏随记", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        app.addItem(.separator()); add(app, "退出随记", #selector(quit), "q")
        let file = NSMenu(title: "文件"); let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); fileItem.submenu = file; main.addItem(fileItem)
        add(file, "新建备忘录", #selector(newNote), "n")
        add(file, "插入图片…", #selector(insertImage), "")
        add(file, "插入表格…", #selector(insertTable), "")
        file.addItem(.separator()); add(file, "导出富文本…", #selector(exportNote), "")
        add(file, "显示本地数据", #selector(showData), "")
        file.addItem(.separator()); add(file, "关闭窗口", #selector(closeWindow), "w")
        let edit = NSMenu(title: "编辑"); let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("重做", Selector(("redo:")), "Z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { let i = NSMenuItem(title: title, action: selector, keyEquivalent: key); edit.addItem(i) }
        let format = NSMenu(title: "格式"); let formatItem = NSMenuItem(title: "格式", action: nil, keyEquivalent: ""); formatItem.submenu = format; main.addItem(formatItem)
        add(format, "粗体", #selector(bold), "b"); add(format, "斜体", #selector(italic), "i"); add(format, "下划线", #selector(underline), "u"); add(format, "切换待办状态", #selector(toggleChecklist), "")
        for i in 0...4 { let item = NSMenuItem(title: i == 0 ? "正文" : "标题 \(i)", action: #selector(headingMenu(_:)), keyEquivalent: "\(i)"); item.keyEquivalentModifierMask = [.command, .option]; item.tag = i; item.target = self; format.addItem(item) }
        let display = NSMenu(title: "显示"); let displayItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: ""); displayItem.submenu = display; main.addItem(displayItem)
        add(display, "显示／隐藏修改时间", #selector(toggleTimes), "")
        add(display, "显示／隐藏列表", #selector(toggleSidebar), "")
    }
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = target ?? self; menu.addItem(item) }
    func button(_ symbol: String, _ help: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage(), target: self, action: action)
        b.bezelStyle = .texturedRounded; b.isBordered = false; b.contentTintColor = .secondaryLabelColor; b.toolTip = help; b.setAccessibilityLabel(help)
        if symbol == "square.and.pencil" { b.contentTintColor = MemoTheme.accent }
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true; b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }
    func buildWindow() {
        NSApp.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = MemoTheme.paper
        window.title = "随记"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.acceptsMouseMovedEvents = true
        window.minSize = NSSize(width: 740, height: 420); window.delegate = self; window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LocalNotesMain"); if !window.setFrameUsingName("LocalNotesMain") { window.center() }
        let root = NSView(); window.contentView = root
        split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin; split.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(split)
        NSLayoutConstraint.activate([split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor), split.topAnchor.constraint(equalTo: root.topAnchor), split.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        let side = MemoSidebar(); sidebar = side
        side.frame = NSRect(x: 0, y: 0, width: 244, height: 740)
        let right = NSView(frame: NSRect(x: 0, y: 0, width: 799, height: 740)); documentHost = right
        split.addArrangedSubview(side); split.addArrangedSubview(right); split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        side.widthAnchor.constraint(greaterThanOrEqualToConstant: 205).isActive = true
        let new = button("square.and.pencil", "新建备忘录  ⌘N", #selector(newNote))
        let head = NSStackView(views: [search, new]); head.orientation = .horizontal; head.spacing = 8
        head.translatesAutoresizingMaskIntoConstraints = false; side.addSubview(head)
        search.placeholderString = "搜索"; search.delegate = self; search.font = .systemFont(ofSize: 12); search.controlSize = .small; search.translatesAutoresizingMaskIntoConstraints = false; search.setAccessibilityLabel("搜索备忘录")
        let list = NSScrollView(); list.hasVerticalScroller = true; list.drawsBackground = true; list.backgroundColor = MemoTheme.sidebar; list.contentView.drawsBackground = true; list.contentView.backgroundColor = MemoTheme.sidebar; list.translatesAutoresizingMaskIntoConstraints = false; side.addSubview(list)
        table.headerView = nil; table.backgroundColor = MemoTheme.sidebar; table.rowHeight = 62; table.intercellSpacing = NSSize(width: 0, height: 2); table.selectionHighlightStyle = .regular
        table.style = .plain; table.delegate = self; table.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")); column.resizingMask = .autoresizingMask; table.addTableColumn(column)
        list.documentView = table
        NSLayoutConstraint.activate([head.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 16), head.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -12), head.topAnchor.constraint(equalTo: side.topAnchor, constant: 39), head.heightAnchor.constraint(equalToConstant: 32), list.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 16), list.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 6), list.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -6), list.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -12)])
        blockPopup.addItems(withTitles: ["正文", "标题 1", "标题 2", "标题 3", "标题 4"]); blockPopup.target = self; blockPopup.action = #selector(blockChanged)
        blockPopup.bezelStyle = .texturedRounded; blockPopup.isBordered = false; blockPopup.font = .systemFont(ofSize: 12); blockPopup.widthAnchor.constraint(equalToConstant: 88).isActive = true
        fontPopup.addItems(withTitles: ["系统字体", "苹方", "宋体", "Helvetica", "Georgia", "Menlo"]); fontPopup.target = self; fontPopup.action = #selector(fontChanged)
        fontPopup.bezelStyle = .texturedRounded; fontPopup.isBordered = false; fontPopup.font = .systemFont(ofSize: 12); fontPopup.widthAnchor.constraint(equalToConstant: 96).isActive = true
        sizePopup.addItems(withObjectValues: [12,14,16,18,20,24,28,32,40,48]); sizePopup.stringValue = "16"; sizePopup.target = self; sizePopup.action = #selector(sizeChanged)
        sizePopup.isBordered = false; sizePopup.drawsBackground = false; sizePopup.font = .systemFont(ofSize: 12)
        sizePopup.widthAnchor.constraint(equalToConstant: 52).isActive = true; sizePopup.toolTip = "字号（8–96）"
        let formatController = NSViewController()
        let formatView = NSView(frame: NSRect(x: 0, y: 0, width: 252, height: 164))
        formatController.view = formatView
        func formatRow(_ title: String, _ control: NSView) -> NSStackView {
            let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let row = NSStackView(views: [label, control, NSView()]); row.spacing = 12
            row.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return row
        }
        let styles = NSStackView(views: [button("bold", "粗体  ⌘B", #selector(bold)), button("italic", "斜体  ⌘I", #selector(italic))]); styles.spacing = 6
        let form = NSStackView(views: [formatRow("段落", blockPopup), formatRow("字体", fontPopup), formatRow("字号", sizePopup), formatRow("样式", styles)])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 8; form.translatesAutoresizingMaskIntoConstraints = false; formatView.addSubview(form)
        NSLayoutConstraint.activate([form.leadingAnchor.constraint(equalTo: formatView.leadingAnchor, constant: 16), form.trailingAnchor.constraint(equalTo: formatView.trailingAnchor, constant: -16), form.topAnchor.constraint(equalTo: formatView.topAnchor, constant: 14)])
        formatPopover.contentViewController = formatController; formatPopover.behavior = .transient; formatPopover.contentSize = formatView.frame.size; formatPopover.animates = false
        status.font = .systemFont(ofSize: 10); status.textColor = .tertiaryLabelColor
        let toolbar = NSStackView(views: [button("sidebar.left", "显示或隐藏列表", #selector(toggleSidebar)), button("textformat", "文字格式", #selector(showFormat(_:))), button("photo", "插入图片", #selector(insertImage)), button("tablecells", "插入表格", #selector(insertTable)), NSView(), status, button("trash", "删除当前备忘录", #selector(deleteNote))])
        toolbar.orientation = .horizontal; toolbar.spacing = 10; toolbar.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(toolbar)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = MemoTheme.paper
        scroll.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(scroll)
        editor.view.frame = NSRect(x: 0, y: 0, width: 790, height: 600); scroll.documentView = editor.view
        imageSlider.target = self; imageSlider.action = #selector(imageResized); imageSlider.isContinuous = false
        imageLabel.font = .systemFont(ofSize: 11); imageLabel.textColor = .secondaryLabelColor
        let resizeBar = NSStackView(views: [imageLabel, imageSlider]); resizeBar.translatesAutoresizingMaskIntoConstraints = false; resizeBar.isHidden = true; right.addSubview(resizeBar)
        editor.onImageSelected = { [weak self, weak resizeBar] visible in
            resizeBar?.isHidden = !visible
            if let self, let a = self.editor.selectedImage { self.imageSlider.maxValue = max(120, Double(self.editor.view.textContainer?.containerSize.width ?? 700)-18); self.imageSlider.doubleValue = Double(a.bounds.width > 0 ? a.bounds.width : a.attachmentCell?.cellSize().width ?? 400) }
        }
        NSLayoutConstraint.activate([toolbar.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 16), toolbar.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12), toolbar.topAnchor.constraint(equalTo: right.topAnchor, constant: 39), toolbar.heightAnchor.constraint(equalToConstant: 32), scroll.leadingAnchor.constraint(equalTo: right.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: right.trailingAnchor), scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12), scroll.bottomAnchor.constraint(equalTo: right.bottomAnchor), resizeBar.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 28), resizeBar.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -14), resizeBar.widthAnchor.constraint(equalToConstant: 300), resizeBar.heightAnchor.constraint(equalToConstant: 30)])
        editor.requestImage = { [weak self] in self?.insertImage() }
        editor.didEdit = { [weak self] in self?.edited() }
        editor.onFormatChanged = { [weak self] level, font in
            self?.blockPopup.selectItem(at: min(4,max(0,level)))
            self?.sizePopup.stringValue = String(format: "%g", font.pointSize)
            let names = ["PingFang", "Songti", "Helvetica", "Georgia", "Menlo"]
            self?.fontPopup.selectItem(at: names.firstIndex(where: { font.fontName.contains($0) }).map { $0+1 } ?? 0)
        }
    }
    func buildQuickEntry() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "快速新建备忘录")
        statusItem.button?.toolTip = "随记 · 点击立即新建  ⌃⌥N\n右键打开菜单"
        statusItem.button?.target = self; statusItem.button?.action = #selector(quickEntry)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppController>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { app.newNote() }; return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        let keyID = EventHotKeyID(signature: 0x4D454D4F, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey|optionKey), keyID, GetApplicationEventTarget(), 0, &hotkey)
    }
    @objc func quickEntry() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu(); add(menu, "新建备忘录  ⌃⌥N", #selector(newNote), ""); add(menu, "打开随记", #selector(showWindow), ""); menu.addItem(.separator()); add(menu, "退出", #selector(quit), "")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { newNote() }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(editor.view) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { return flush() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { flush() ? .terminateNow : .terminateCancel }
    func reloadList() {
        guard store != nil else { return }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = store.notes.filter { query.isEmpty || $0.searchable.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }.sorted { $0.modified > $1.modified }
        suppressSelection = true; table.reloadData()
        if let row = filtered.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        suppressSelection = false
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { MemoRow() }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let cell = MemoCell(); let note = filtered[row]
        cell.title.stringValue = note.title; cell.preview.stringValue = note.preview.isEmpty ? "空白备忘录" : note.preview
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, filtered.indices.contains(table.selectedRow) else { return }
        let id = filtered[table.selectedRow].id
        if id != selectedID { select(id) }
    }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === search { reloadList() } }
    func select(_ id: UUID) {
        guard flush() else { reloadList(); return }
        do {
            let doc = try store.load(id)
            guard let note = store.notes.first(where: { $0.id == id }) else { return }
            selectedID = id; UserDefaults.standard.set(id.uuidString, forKey: "lastNote")
            // RTFD may normalize attribute runs. Preserve dates by paragraph position on load.
            let hashes = fingerprints(doc)
            let lines = hashes.enumerated().map { i, h in LineRecord(fingerprint: h, modified: note.lines.indices.contains(i) ? note.lines[i].modified : note.modified) }
            editor.load(doc, lines: lines); status.stringValue = "\(dates.string(from: note.modified))"
            editor.view.isEditable = true; window.makeFirstResponder(editor.view)
        } catch { showError(error); reloadList() }
    }
    @objc func newNote() {
        guard store != nil, flush() else { return }
        do {
            let id = try store.create(); search.stringValue = ""; selectedID = nil
            select(id); reloadList(); showWindow()
        } catch { showError(error) }
    }
    func edited() {
        guard selectedID != nil else { return }
        let now = Date(); editor.view.records = reconcile(editor.view.records, fingerprints(editor.view.attributedString()), now: now)
        editor.view.recordRanges = paragraphRanges(editor.view.string); editor.view.needsDisplay = true
        dirty = true; saving?.cancel()
        let task = DispatchWorkItem { [weak self] in _ = self?.flush() }; saving = task
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3, execute: task)
    }
    @discardableResult func flush() -> Bool {
        saving?.cancel(); saving = nil
        guard dirty, let id = selectedID, store != nil else { return true }
        do {
            try store.update(id: id, text: editor.view.attributedString(), lines: editor.view.records, date: Date())
            dirty = false; status.stringValue = "\(dates.string(from: Date()))"; reloadList(); return true
        } catch { status.stringValue = "保存失败，内容仍保留在窗口中"; showError(error); return false }
    }
    func showError(_ error: Error) { let alert = NSAlert(error: error); if window != nil { alert.beginSheetModal(for: window) } else { alert.runModal() } }
    @objc func showFormat(_ sender: NSButton) {
        if formatPopover.isShown { formatPopover.performClose(sender) }
        else {
            formatPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            formatPopover.contentViewController?.view.window?.makeFirstResponder(nil)
        }
    }
    @objc func blockChanged() { editor.applyParagraph(level: blockPopup.indexOfSelectedItem) }
    @objc func headingMenu(_ item: NSMenuItem) { editor.applyParagraph(level: item.tag); blockPopup.selectItem(at: item.tag) }
    @objc func fontChanged() { let fonts = [".AppleSystemUIFont", "PingFangSC-Regular", "SongtiSC-Regular", "Helvetica", "Georgia", "Menlo-Regular"]; editor.formatFont(family: fonts[fontPopup.indexOfSelectedItem]) }
    @objc func sizeChanged() { guard let value = Double(sizePopup.stringValue), (8...96).contains(value) else { sizePopup.stringValue = "16"; return }; editor.formatFont(size: value) }
    @objc func bold() { editor.formatFont(trait: .boldFontMask) }
    @objc func underline() { editor.toggleAttribute(.underlineStyle) }
    @objc func toggleChecklist() { editor.toggleChecklist() }
    @objc func italic() { editor.formatFont(trait: .italicFontMask) }
    @objc func toggleTimes() { editor.view.showTimes.toggle() }
    @objc func toggleSidebar() { sidebar.isHidden.toggle(); split.adjustSubviews() }
    @objc func imageResized() { editor.resizeImage(width: imageSlider.doubleValue) }
    @objc func insertImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] result in guard result == .OK else { return }; for url in panel.urls { if let image = NSImage(contentsOf: url) { self?.editor.insertImage(image) } } }
    }
    func makeTableInsertionAlert() -> (NSAlert, NSPopUpButton, NSPopUpButton) {
        let alert = NSAlert()
        alert.messageText = "插入表格"
        alert.informativeText = "第一行为表头，单元格可直接编辑。"
        alert.addButton(withTitle: "插入"); alert.addButton(withTitle: "取消")
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        let rows = NSPopUpButton(frame: NSRect(x: 88, y: 44, width: 176, height: 28))
        let cols = NSPopUpButton(frame: NSRect(x: 88, y: 4, width: 176, height: 28))
        rows.addItems(withTitles: (2...20).map { "\($0) 行" })
        cols.addItems(withTitles: (2...8).map { "\($0) 列" })
        rows.selectItem(at: 1); cols.selectItem(at: 1)
        rows.setAccessibilityLabel("行数，包含表头"); cols.setAccessibilityLabel("列数")
        for (title, y) in [("行数", CGFloat(48)), ("列数", CGFloat(8))] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 0, y: y, width: 72, height: 20)
            form.addSubview(label)
        }
        form.addSubview(rows); form.addSubview(cols)
        rows.nextKeyView = cols
        alert.accessoryView = form
        alert.window.appearance = NSAppearance(named: .aqua)
        alert.window.initialFirstResponder = rows
        return (alert, rows, cols)
    }
    @objc func insertTable() {
        let (alert, rows, cols) = makeTableInsertionAlert()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.editor.insertTable(rows: rows.indexOfSelectedItem+2, columns: cols.indexOfSelectedItem+2)
            self.window.makeFirstResponder(self.editor.view)
        }
    }
    @objc func deleteNote() {
        guard let id = selectedID else { return }
        let alert = NSAlert(); alert.messageText = "删除这条备忘录？"; alert.informativeText = ""; alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.flush() else { return }
            do { try self.store.delete(id); self.selectedID = nil; if self.store.notes.isEmpty { self.newNote() } else if let id = self.store.notes.sorted(by: { $0.modified > $1.modified }).first?.id { self.select(id); self.reloadList() } } catch { self.showError(error) }
        }
    }
    @objc func exportNote() {
        guard let id = selectedID, flush() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = (store.notes.first { $0.id == id }?.title ?? "备忘录")+".rtfd"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { let doc = self.editor.view.attributedString(); let wrapper = try doc.fileWrapper(from: NSRange(location: 0, length: doc.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]); try wrapper.write(to: url, options: .atomic, originalContentsURL: nil) } catch { self.showError(error) }
        }
    }
    @objc func showData() { if store != nil { NSWorkspace.shared.open(store.root) } }
    @objc func closeWindow() { window.performClose(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() { let alert = NSAlert(); alert.messageText = "随记"; alert.informativeText = "随手记下，即开即写。\n\n⌘N 新建 · ⌃⌥N 随时快速新建\n# 到 #### 加空格：标题\n**粗体**、*斜体*、`代码`：即时排版\n图片可粘贴、拖入或从工具栏插入；点击图片可调整宽度。"; alert.runModal() }
}

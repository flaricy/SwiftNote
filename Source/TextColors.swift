import AppKit

struct TextColorChoice: Equatable {
    let index: Int
    let background: Bool
    static let names = ["默认", "灰色", "棕色", "橙色", "黄色", "绿色", "蓝色", "紫色", "粉色", "红色"]
    static let foreground = ["37352F", "787774", "976D57", "B46A32", "9D7B28", "448361", "337EA9", "9065B0", "AD5C85", "C4554D"]
    static let backgrounds = ["FFFFFF", "ECEBE7", "EEE0D5", "FADEC9", "F6E9B8", "DDEBDF", "DCEAF5", "EAE0F1", "F3DEEA", "F7DEDA"]
    var key: NSAttributedString.Key { background ? .backgroundColor : .foregroundColor }
    var color: NSColor? {
        if index == 0 { return background ? nil : .textColor }
        let hex = UInt32((background ? Self.backgrounds : Self.foreground)[index], radix: 16)!
        return NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    static var last: TextColorChoice {
        get {
            let defaults = Localization.preferences
            let index = defaults.object(forKey: "lastTextColorIndex") as? Int ?? 4
            return TextColorChoice(index: (0..<names.count).contains(index) ? index : 4, background: defaults.object(forKey: "lastTextColorBackground") as? Bool ?? true)
        }
        set {
            Localization.preferences.set(newValue.index, forKey: "lastTextColorIndex")
            Localization.preferences.set(newValue.background, forKey: "lastTextColorBackground")
        }
    }
}

final class ColorSwatch: NSButton {
    let choice: TextColorChoice
    var current = false
    init(choice: TextColorChoice, target: AnyObject, action: Selector) {
        self.choice = choice
        super.init(frame: .zero)
        self.target = target; self.action = action; isBordered = false
        title = L(TextColorChoice.names[choice.index])
        toolTip = L(choice.background ? "背景高亮" : "文字颜色") + " · " + title
        setAccessibilityLabel(toolTip); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic control") }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (choice.background ? choice.color ?? MemoTheme.paper : MemoTheme.paper).setFill(); path.fill()
        (current || isHighlighted || window?.firstResponder === self ? MemoTheme.accent : NSColor.separatorColor.withAlphaComponent(0.35)).setStroke()
        path.lineWidth = current ? 1.5 : 0.5; path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: choice.background ? NSColor.labelColor : choice.color ?? .labelColor]
        let text = "A" as NSString; let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attributes)
        if choice.index == 0 && choice.background {
            let slash = NSBezierPath(); slash.move(to: NSPoint(x: rect.minX+4, y: rect.minY+4)); slash.line(to: NSPoint(x: rect.maxX-4, y: rect.maxY-4)); slash.lineWidth = 1
            NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke(); slash.stroke()
        }
    }
}

extension EditorController {
    @objc func showColors(_ sender: NSView? = nil) {
        guard MainActor.assumeIsolated({ finishFormulaEditing(cancel: false) }) else { return }
        if colorPopover.isShown { colorPopover.performClose(nil); return }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 286))
        root.wantsLayer = true; root.layer?.backgroundColor = MemoTheme.paper.cgColor
        for (section, background) in [false, true].enumerated() {
            let top = CGFloat(262-section*126)
            let label = NSTextField(labelWithString: L(background ? "背景高亮" : "文字颜色"))
            label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 16, y: top, width: 210, height: 17); root.addSubview(label)
            for index in 0..<TextColorChoice.names.count {
                let choice = TextColorChoice(index: index, background: background)
                let swatch = ColorSwatch(choice: choice, target: self, action: #selector(pickColor(_:)))
                let range = view.selectedRange()
                let attrs = range.location < (view.textStorage?.length ?? 0) ? view.textStorage!.attributes(at: range.location, effectiveRange: nil) : view.typingAttributes
                swatch.current = colorsMatch(attrs[choice.key] as? NSColor, choice.color)
                if range.length > 0 {
                    view.textStorage?.enumerateAttribute(choice.key, in: range) { value, _, stop in
                        if !self.colorsMatch(value as? NSColor, choice.color) { swatch.current = false; stop.pointee = true }
                    }
                }
                swatch.frame = NSRect(x: 13+CGFloat(index%5)*45, y: top-45-CGFloat(index/5)*40, width: 40, height: 36)
                root.addSubview(swatch)
            }
        }
        let hint = NSTextField(labelWithString: L("重复上次颜色") + "  ⌘⇧H")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 10, width: 220, height: 16); root.addSubview(hint)
        let controller = NSViewController(); controller.view = root
        colorPopover.contentViewController = controller; colorPopover.contentSize = root.frame.size
        colorPopover.behavior = .transient; colorPopover.animates = false
        if let sender { colorPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY) }
        else { colorPopover.show(relativeTo: caretRect(), of: view, preferredEdge: .maxY) }
    }
    func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard let a = lhs.usingColorSpace(.sRGB), let b = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent-b.redComponent)+abs(a.greenComponent-b.greenComponent)+abs(a.blueComponent-b.blueComponent) < 0.02
    }
    @objc func pickColor(_ sender: ColorSwatch) { colorPopover.performClose(nil); applyColor(sender.choice) }
    func applyColor(_ choice: TextColorChoice, remember: Bool = true) {
        guard MainActor.assumeIsolated({ finishFormulaEditing(cancel: false) }), !view.hasMarkedText() else { return }
        if remember { TextColorChoice.last = choice }
        let selection = view.selectedRange()
        let range = selection.length > 0 ? selection : (view.string as NSString).paragraphRange(for: selection)
        var typing = view.typingAttributes
        if let color = choice.color { typing[choice.key] = color } else { typing.removeValue(forKey: choice.key) }
        if range.length > 0 {
            let value = NSMutableAttributedString(attributedString: view.textStorage!.attributedSubstring(from: range))
            if let color = choice.color { value.addAttribute(choice.key, value: color, range: NSRange(location: 0, length: value.length)) }
            else { value.removeAttribute(choice.key, range: NSRange(location: 0, length: value.length)) }
            replace(range, with: value); view.setSelectedRange(selection)
        }
        view.window?.makeFirstResponder(view)
        view.typingAttributes = typing
        updateSelectionTools()
    }
    @objc func repeatLastColor() { applyColor(TextColorChoice.last, remember: false) }
}

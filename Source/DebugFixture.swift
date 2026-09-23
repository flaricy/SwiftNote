#if DEBUG
import AppKit
extension AppController {
    func runVisualFixture() {
        guard ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] != nil,
              let path = ProcessInfo.processInfo.environment["LOCALNOTES_DATA_DIR"],
              let id = selectedID else { return }
        let mode = ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] ?? ""
        Localization.preferences = UserDefaults(suiteName: "SwiftNote.VisualFixture")!
        Localization.language = mode.hasSuffix("-zh") ? .chinese : .english
        applyLanguage()
        MainActor.assumeIsolated {
            editor.load(NSAttributedString(string: "随手记下，也能写公式\n\n今天的物理笔记： ", attributes: bodyAttributes()), lines: [])
            try? editor.insertFormula(MathFormula(latex: "\\frac{a+b}{c}=x^2", block: false), replacing: NSRange(location: editor.view.string.utf16.count, length: 0))
            let end = editor.view.string.utf16.count
            editor.view.setSelectedRange(NSRange(location: end, length: 0))
            editor.view.insertText("，接着记录推导。\n\n今天读到的高斯积分\n", replacementRange: editor.view.selectedRange())
            try? editor.insertFormula(MathFormula(latex: "\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx=\\sqrt{\\pi}", block: true), replacing: NSRange(location: editor.view.string.utf16.count, length: 0))
            edited(); _ = flush(); reloadList(); select(id)
            let narrow = ["narrow", "inline"].contains(ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] ?? "")
            window.setContentSize(NSSize(width: narrow ? 740 : 1060, height: narrow ? 480 : 740)); window.center()
            if narrow { split.setPosition(205, ofDividerAt: 0) }
            try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: path + "/pid", atomically: true, encoding: .utf8)
            try? String(window.windowNumber).write(toFile: path + "/window-id", atomically: true, encoding: .utf8)
            if ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] == "inline" {
                let text = editor.view.textStorage!
                var first: NSRange?
                text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, stop in
                    if value is NSTextAttachment { first = range; stop.pointee = true }
                }
                if let first { editFormula(block: false, range: first) }
            }
            if mode.hasPrefix("settings") {
                showSettings()
                // Exercise the same action as a user's language selection, without touching real preferences.
                languagePopup?.selectItem(at: mode.hasSuffix("-zh") ? 1 : 0)
                changeLanguage(languagePopup!)
                try? String(settingsWindow!.windowNumber).write(toFile: path + "/window-id", atomically: true, encoding: .utf8)
            }
            if mode.hasPrefix("slash") {
                editor.load(NSAttributedString(string: "/math", attributes: bodyAttributes()), lines: [])
                editor.view.setSelectedRange(NSRange(location: 5, length: 0))
                editor.updateCommandPalette()
            }
            if ProcessInfo.processInfo.environment["SWIFTNOTE_FIXTURE"] == "formula" {
                editFormula(block: true, range: NSRange(location: editor.view.string.utf16.count, length: 0))
                editor.formulaDraft?.input.stringValue = "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}=\\frac{\\pi^2}{6}"
                editor.formulaDraft?.refresh()
            }
        }
    }
}
#endif

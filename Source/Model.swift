import AppKit
import CryptoKit

// The app intentionally keeps its warm paper appearance in every system theme.
enum MemoTheme {
    static let paper = NSColor(srgbRed: 0.989, green: 0.977, blue: 0.949, alpha: 1)
    static let sidebar = NSColor(srgbRed: 0.911, green: 0.937, blue: 0.893, alpha: 1)
    static let surface = NSColor(srgbRed: 0.966, green: 0.959, blue: 0.919, alpha: 1)
    static let selection = NSColor(srgbRed: 0.799, green: 0.859, blue: 0.749, alpha: 1)
    static let accent = NSColor(srgbRed: 0.337, green: 0.427, blue: 0.274, alpha: 1)
}

struct LineRecord: Codable, Equatable {
    var fingerprint: String
    var modified: Date
}
struct ImageLayout: Codable { var width: Double; var height: Double }
struct NoteInfo: Codable {
    var id: UUID
    var created: Date
    var modified: Date
    var title: String
    var preview: String
    var searchable: String
    var lines: [LineRecord]
    var images: [ImageLayout]? = nil
}
func sha(_ string: String) -> String { SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined() }
func paragraphRanges(_ string: String) -> [NSRange] {
    let s = string as NSString
    if s.length == 0 { return [NSRange(location: 0, length: 0)] }
    var result: [NSRange] = []; var index = 0
    while index < s.length {
        let range = s.paragraphRange(for: NSRange(location: index, length: 0))
        result.append(range); index = NSMaxRange(range)
    }
    if string.hasSuffix("\n") { result.append(NSRange(location: s.length, length: 0)) }
    return result
}
func fingerprints(_ text: NSAttributedString) -> [String] {
    paragraphRanges(text.string).map { range in
        var parts = [(text.string as NSString).substring(with: range)]
        text.enumerateAttributes(in: range, options: []) { a, run, _ in
            var p = "\(run.location-range.location):\(run.length)"
            if let f = a[.font] as? NSFont { p += "|\(f.fontName)|\(f.pointSize)" }
            if let s = a[.paragraphStyle] as? NSParagraphStyle {
                p += "|h\(s.headerLevel)|a\(s.alignment.rawValue)|i\(s.headIndent)|\(s.firstLineHeadIndent)"
                for b in s.textBlocks { if let b = b as? NSTextTableBlock { p += "|table:\(b.startingRow),\(b.startingColumn),\(b.rowSpan),\(b.columnSpan),\(b.table.numberOfColumns)" } }
            }
            if let u = a[.underlineStyle] as? Int { p += "|u\(u)" }
            if let u = a[.strikethroughStyle] as? Int { p += "|s\(u)" }
            if let t = a[.attachment] as? NSTextAttachment {
                p += "|img:\(t.fileWrapper?.preferredFilename ?? ""):\(t.bounds.width):\(t.bounds.height)"
                if let cell = t.attachmentCell { p += "|cell:\(cell.cellSize().width):\(cell.cellSize().height)" }
            }
            parts.append(p)
        }
        return sha(parts.joined(separator: "\u{001f}"))
    }
}
func reconcile(_ old: [LineRecord], _ hashes: [String], now: Date) -> [LineRecord] {
    var result = old
    for change in hashes.difference(from: old.map(\.fingerprint)) {
        switch change {
        case .remove(let offset, _, _): result.remove(at: offset)
        case .insert(let offset, let hash, _): result.insert(LineRecord(fingerprint: hash, modified: now), at: offset)
        }
    }
    return result
}
final class NoteStore {
    let root: URL
    var notes: [NoteInfo] = []
    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LocalNotes")
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let index = self.root.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: index.path) { notes = try JSONDecoder().decode([NoteInfo].self, from: Data(contentsOf: index)) }
    }
    func documentURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".rtfd") }
    func load(_ id: UUID) throws -> NSAttributedString {
        let path = documentURL(id)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw NSError(domain: "LocalNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "笔记文件缺失，已停止载入，避免覆盖原数据。"])
        }
        let result = try NSMutableAttributedString(data: Data(contentsOf: path), options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        // RTFD stores resolved RGB values; restore semantic editor colors after reopening.
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attrs, range, _ in
            if let color = attrs[.foregroundColor] as? NSColor, let rgb = color.usingColorSpace(.deviceRGB) {
                let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                if components.allSatisfy({ $0 < 0.12 }) || components.allSatisfy({ $0 > 0.88 }) {
                    result.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
                }
            }
            if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle {
                if paragraph.headIndent == 20, paragraph.textBlocks.isEmpty { result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range) }
                for case let block as NSTextTableBlock in paragraph.textBlocks { block.setBorderColor(.separatorColor); if block.startingRow == 0 { block.backgroundColor = .controlBackgroundColor } }
            }
        }
        let layouts = notes.first(where: { $0.id == id })?.images ?? []
        var index = 0
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            defer { index += 1 }
            if layouts.indices.contains(index), let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) {
                let layout = layouts[index]
                attachment.bounds = NSRect(x: 0, y: 0, width: layout.width, height: layout.height)
                image.size = attachment.bounds.size; attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            }
        }
        return result
    }
    func persistIndex() throws {
        let data = try JSONEncoder().encode(notes)
        try data.write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }
    func create() throws -> UUID {
        let now = Date(); let id = UUID()
        let doc = NSAttributedString(string: "", attributes: bodyAttributes())
        try saveDocument(doc, id: id)
        notes.insert(NoteInfo(id: id, created: now, modified: now, title: "新备忘录", preview: "", searchable: "", lines: []), at: 0)
        try persistIndex(); return id
    }
    func saveDocument(_ text: NSAttributedString, id: UUID) throws {
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        try data.write(to: documentURL(id), options: .atomic)
    }
    func update(id: UUID, text: NSAttributedString, lines: [LineRecord], date: Date) throws {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        try saveDocument(text, id: id)
        let content = text.string.replacingOccurrences(of: "\u{fffc}", with: "[图片]")
        let paragraphs = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        notes[i].title = String((paragraphs.first ?? "新备忘录").prefix(70))
        notes[i].preview = String(paragraphs.dropFirst().joined(separator: " ").prefix(140))
        notes[i].searchable = content
        notes[i].modified = date; notes[i].lines = lines
        var layouts: [ImageLayout] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let a = value as? NSTextAttachment {
                let size = a.bounds.width > 0 ? a.bounds.size : a.attachmentCell?.cellSize() ?? .zero
                layouts.append(ImageLayout(width: size.width, height: size.height))
            }
        }
        notes[i].images = layouts
        try persistIndex()
    }
    func delete(_ id: UUID) throws {
        let trash = root.appendingPathComponent("Deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let source = documentURL(id)
        if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent("\(id)-\(Int(Date().timeIntervalSince1970)).rtfd")) }
        notes.removeAll { $0.id == id }; try persistIndex()
    }
}
func bodyAttributes(size: CGFloat = 16, family: String? = nil) -> [NSAttributedString.Key: Any] {
    let p = NSMutableParagraphStyle(); p.paragraphSpacing = 7; p.lineSpacing = 4
    let f = family.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
    return [.font: f, .foregroundColor: NSColor.textColor, .paragraphStyle: p]
}

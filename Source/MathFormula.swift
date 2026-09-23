import Foundation
import SwiftMath
import ImageIO
import AppKit

struct MathFormula: Codable, Equatable {
    var latex: String
    var block: Bool
    static let marker = "SwiftNoteFormula:"

    static func read(_ attachment: NSTextAttachment) -> MathFormula? {
        let data = attachment.fileWrapper?.regularFileContents
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any],
              let description = png[kCGImagePropertyPNGDescription as String] as? String,
              description.hasPrefix(marker), let json = Data(base64Encoded: String(description.dropFirst(marker.count))) else { return nil }
        return try? JSONDecoder().decode(MathFormula.self, from: json)
    }

    static func restoreCell(_ attachment: NSTextAttachment) {
        guard !(attachment.attachmentCell is FormulaAttachmentCell), read(attachment) != nil,
              let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) else { return }
        if attachment.bounds.width > 0 { image.size = attachment.bounds.size }
        attachment.attachmentCell = FormulaAttachmentCell(image: image, baselineRatio: baselineRatio(data))
    }

    static func baselineRatio(_ data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any],
              let comment = png[kCGImagePropertyPNGComment as String] as? String,
              comment.hasPrefix("SwiftNoteBaseline:"), let ratio = Double(comment.dropFirst("SwiftNoteBaseline:".count)), ratio.isFinite else { return 0.18 }
        return min(1, max(0, ratio))
    }

    @MainActor func attachment(fontSize: CGFloat = 18) throws -> NSTextAttachment {
        let latex = self.latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty, latex.utf8.count <= 8192 else { throw FormulaError.invalid(L("请输入公式，最多 8192 字节。")) }
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = block ? max(22, fontSize) : fontSize
        label.labelMode = block ? .display : .text
        label.textColor = .black
        label.preferredMaxLayoutWidth = 1200
        if let error = label.error { throw FormulaError.invalid(error.localizedDescription) }
        let measured = label.sizeThatFits(CGSize(width: 1200, height: 2000))
        guard measured.width.isFinite, measured.height.isFinite, measured.width > 0, measured.height > 0,
              measured.width < 4000, measured.height < 2000 else { throw FormulaError.invalid(L("公式过大，请拆分成几行。")) }
        let size = CGSize(width: ceil(measured.width)+8, height: ceil(measured.height)+6)
        label.frame = CGRect(origin: .zero, size: size)
        let image: CGImage
        label.layoutSubtreeIfNeeded()
        guard let bitmap = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { throw FormulaError.invalid(L("无法渲染公式。")) }
        label.cacheDisplay(in: label.bounds, to: bitmap)
        guard let rendered = bitmap.cgImage else { throw FormulaError.invalid(L("无法渲染公式。")) }
        image = rendered
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw FormulaError.invalid(L("无法保存公式。")) }
        let metadata = Self.marker + (try JSONEncoder().encode(self)).base64EncodedString()
        let bodyFont = NSFont.systemFont(ofSize: fontSize)
        let baseline = block ? 0 : max(0, (size.height - bodyFont.ascender - bodyFont.descender)/2) / size.height
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: CGFloat(image.width)/size.width*72, kCGImagePropertyDPIHeight: CGFloat(image.height)/size.height*72, kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: metadata, kCGImagePropertyPNGComment: "SwiftNoteBaseline:\(baseline)"]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FormulaError.invalid(L("无法保存公式。")) }
        let attachment = NSTextAttachment(data: output as Data, ofType: "public.png")
        let width = min(size.width, block ? 640 : 520)
        let scaled = CGSize(width: width, height: size.height * width / size.width)
        attachment.bounds = CGRect(x: 0, y: -scaled.height * baseline, width: scaled.width, height: scaled.height)
        let file = FileWrapper(regularFileWithContents: output as Data)
        file.preferredFilename = "formula-\(UUID().uuidString).png"
        attachment.fileWrapper = file
        let nsImage = NSImage(data: output as Data)!
        nsImage.size = scaled
        attachment.attachmentCell = FormulaAttachmentCell(image: nsImage, baselineRatio: baseline)
        return attachment
    }
}
enum FormulaError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

final class FormulaAttachmentCell: NSTextAttachmentCell {
    var naturalSize: NSSize
    let baselineRatio: CGFloat
    init(image: NSImage, baselineRatio: CGFloat) {
        self.baselineRatio = baselineRatio
        naturalSize = image.size
        super.init(imageCell: image)
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -(image?.size.height ?? 0) * baselineRatio) }
    required init(coder: NSCoder) {
        baselineRatio = coder.containsValue(forKey: "formulaBaseline") ? coder.decodeDouble(forKey: "formulaBaseline") : 0.18
        naturalSize = .zero
        super.init(coder: coder)
        naturalSize = image?.size ?? .zero
    }
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(Double(baselineRatio), forKey: "formulaBaseline")
    }
}

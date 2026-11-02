@preconcurrency import AppKit
import FormaCanvasEngine
import FormaDomain
import FormaGeometry
import UniformTypeIdentifiers

public enum DiagramExporter {
    public static func pdf(_ diagram: Diagram) throws -> Data {
        let rect = (diagram.contentBounds ?? Rect(x: 0, y: 0, width: 800, height: 600)).expanded(by: 48)
        var box = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        let result = NSMutableData()
        guard let consumer = CGDataConsumer(data: result), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw DiagramError.corruptFile }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(box)
        ctx.translateBy(x: -rect.x, y: rect.height + rect.y)
        ctx.scaleBy(x: 1, y: -1)
        DiagramRenderer.draw(diagram, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return result as Data
    }
    public static func png(_ diagram: Diagram, scale: Double = 2) throws -> Data {
        let rect = (diagram.contentBounds ?? Rect(x: 0, y: 0, width: 800, height: 600)).expanded(by: 48)
        let width = ceil(rect.width * scale)
        let height = ceil(rect.height * scale)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 16_384, height <= 16_384,
            width * height <= 40_000_000
        else { throw DiagramError.limitExceeded }
        guard
            let ctx = CGContext(
                data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DiagramError.limitExceeded }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.x, y: -rect.y)
        DiagramRenderer.draw(diagram, in: ctx)
        guard let image = ctx.makeImage() else { throw DiagramError.corruptFile }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw DiagramError.corruptFile }
        return data
    }
}

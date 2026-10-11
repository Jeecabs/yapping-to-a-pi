import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Run with: xcrun swift scripts/render-app-icon.swift [output.png]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent("assets/AppIcon.png")
let canvasSize = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255,
        1,
    ])!
}

let context = CGContext(
    data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8,
    bytesPerRow: canvasSize * 4, space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.setFillColor(color(0x181B18))
context.addPath(RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: tile).cgPath)
context.fillPath()

// Core Text supplies the actual font outlines and spacing, without font substitution.
let fontName = "HelveticaNeue-Bold"
let font = CTFontCreateWithName(fontName as CFString, 1000, nil)
precondition(CTFontCopyPostScriptName(font) as String == fontName, "HelveticaNeue-Bold is required")
let text = NSAttributedString(string: "c,", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
])
let line = CTLineCreateWithAttributedString(text)
var paths: [CGPath] = []
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    for (glyph, position) in zip(glyphs, positions) {
        var placement = CGAffineTransform(translationX: position.x, y: position.y)
        guard let path = CTFontCreatePathForGlyph(font, glyph, &placement) else {
            fatalError("The icon glyph has no outline")
        }
        paths.append(path)
    }
}
precondition(paths.count == 2, "The icon requires exactly two glyphs")

let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
let scale = min(tile.width * 0.60 / bounds.width, tile.height * 0.60 / bounds.height)
// Balance the broad c against the comma and its descender. Minimum inset stays above 18%.
let origin = CGPoint(x: tile.midX + 10 - bounds.midX * scale, y: tile.midY - 16 - bounds.midY * scale)
var placement = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y)
let inkBounds = bounds.applying(placement)
precondition(tile.insetBy(dx: tile.width * 0.18, dy: tile.height * 0.18).contains(inkBounds))
for (path, ink) in zip(paths, [UInt32(0xEDF1E8), UInt32(0xD5F66B)]) {
    context.setFillColor(color(ink))
    context.addPath(path.copy(using: &placement)!)
    context.fillPath()
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("Cannot create the icon PNG at \(output.path)") }
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination), "Cannot write the icon PNG")
print("Rendered \(output.path)")
print("Canvas: \(canvasSize) px; tile: \(tile); glyph bounds: \(inkBounds)")

import AppKit
import CoreGraphics
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0.3, 0.25, 0.5, 0.15))
let background = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 200, cornerHeight: 200, transform: nil)
context.addPath(background); context.setFillColor(color(0.93, 0.92, 0.98)); context.fillPath()
context.setShadow(offset: .zero, blur: 0)
context.saveGState(); context.addPath(background); context.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0.98, 0.98, 1), color(0.89, 0.89, 0.96)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 960), end: CGPoint(x: 900, y: 0), options: [])
context.restoreGState()
for index in 0..<8 {
    context.saveGState(); context.translateBy(x: 512, y: 512); context.rotate(by: Double(index) * .pi / 4)
    context.setBlendMode(.multiply)
    let petalColor = index % 2 == 0 ? color(0.52, 0.43, 0.84, 0.51) : color(0.54, 0.77, 0.68, 0.48)
    context.setFillColor(petalColor)
    context.fillEllipse(in: CGRect(x: -120, y: -40, width: 240, height: 405))
    context.setBlendMode(.normal); context.setStrokeColor(color(1, 1, 1, 0.65)); context.setLineWidth(2)
    context.strokeEllipse(in: CGRect(x: -120, y: -40, width: 240, height: 405))
    context.restoreGState()
}
context.setFillColor(color(0.98, 0.98, 1, 0.92)); context.fillEllipse(in: CGRect(x: 466, y: 466, width: 92, height: 92))
context.setFillColor(color(0.48, 0.38, 0.78, 0.8)); context.fillEllipse(in: CGRect(x: 501, y: 501, width: 22, height: 22))
let image = context.makeImage()!
func png(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
try png(image, to: output.appendingPathComponent("AppIcon.png"))
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let resized = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        resized.interpolationQuality = .high; resized.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        try png(resized.makeImage()!, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
print(iconset.path)

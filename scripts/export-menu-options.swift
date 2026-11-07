import AppKit
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/MenuBarOptions")
for name in ["A", "B", "C"] {
    guard let image = NSImage(contentsOf: root.appendingPathComponent(name + ".svg")) else { fatalError("Cannot load icon") }
    for size in [36, 256] {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = size == 36 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name + suffix + ".png"))
    }
}
print("Exported three transparent menu icon options at 18pt Retina and 256px.")

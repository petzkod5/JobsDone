import AppKit
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let portrait = NSImage(contentsOf: root.appendingPathComponent("Resources/Peon.gif"))!
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let scale = min(CGFloat(size) / portrait.size.width, CGFloat(size) / portrait.size.height)
let width = portrait.size.width * scale
let height = portrait.size.height * scale
portrait.draw(in: NSRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("Packaged the real Warcraft III Peon portrait for help and notification icons.")

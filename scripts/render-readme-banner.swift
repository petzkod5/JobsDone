import AppKit
let size = NSSize(width: 1600, height: 480)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.07, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(calibratedRed: 0.73, green: 0.86, blue: 0.36, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1600, height: 8)).fill()
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
 (text as NSString).draw(at: NSPoint(x:x,y:y), withAttributes: [.font: NSFont.systemFont(ofSize:size, weight:weight), .foregroundColor: color])
}
label("JOB’S DONE", x:80,y:235,size:92,color:.white,weight:.heavy)
label("Work work. Ship it.", x:84,y:163,size:38,color:NSColor(calibratedRed:0.73,green:0.86,blue:0.36,alpha:1),weight:.medium)
label("YOUR PULL REQUESTS. A LITTLE MORE ORC.", x:86,y:91,size:19,color:NSColor(calibratedWhite:0.65,alpha:1),weight:.semibold)
let portrait = NSImage(contentsOfFile:"Resources/Peon.gif")!
NSGraphicsContext.current?.imageInterpolation = .none
portrait.draw(in:NSRect(x:1150,y:100,width:280,height:280),from:.zero,operation:.sourceOver,fraction:1)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"docs/banner.png"))

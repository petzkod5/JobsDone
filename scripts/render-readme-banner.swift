import AppKit

let fm = FileManager.default
let output = CommandLine.arguments.dropFirst().first ?? "docs"
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)
let portrait = NSImage(contentsOfFile: "Resources/Peon.gif")!
func color(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32) {
    color(hex).setFill()
    NSBezierPath(rect: NSRect(x:x,y:y,width:w,height:h)).fill()
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ hex: UInt32, _ weight: NSFont.Weight = .regular, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize:size,weight:weight) : NSFont.systemFont(ofSize:size,weight:weight)
    (value as NSString).draw(at: NSPoint(x:x,y:y), withAttributes:[.font:font,.foregroundColor:color(hex)])
}
func peon(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) {
    NSGraphicsContext.current?.imageInterpolation = .none
    portrait.draw(in:NSRect(x:x,y:y,width:side,height:side),from:.zero,operation:.sourceOver,fraction:1)
}
for option in 1...6 {
    let image = NSImage(size:NSSize(width:1600,height:480))
    image.lockFocus()
    switch option {
    case 1:
        rect(0,0,1600,480,0x111b16)
        rect(0,0,1600,8,0xb9d969)
        text("JOB’S DONE",80,235,92,0xffffff,.heavy)
        text("Work work.",84,151,40,0xb9d969,.medium)
        text("GitHub PR alerts for your Mac",86,89,24,0xa4afa6)
        peon(1150,100,280)
    case 2:
        rect(0,0,1600,480,0xeee7d5)
        rect(24,24,1552,432,0xd3c6a8)
        rect(28,28,1544,424,0xeee7d5)
        text("Job’s Done",90,240,100,0x302e24,.bold)
        text("Work work.",95,158,40,0x5a6835,.medium)
        text("A Peon for your pull requests.",96,96,26,0x665f50)
        peon(1160,95,290)
    case 3:
        rect(0,0,1600,480,0x0d1311)
        rect(0,420,1600,60,0x1c2922)
        text("●  ●  ●",40,433,22,0x9bb79e,mono:true)
        text("~/JobsDone",680,433,22,0x9bb79e,mono:true)
        text("$ job’s done",70,254,79,0xd3f8c2,.bold,mono:true)
        text("PR opened. Work work.",75,165,30,0x9ddc83,mono:true)
        text("PR merged. Job’s done!",75,109,30,0x9ddc83,mono:true)
        peon(1180,90,260)
    case 4:
        rect(0,0,1600,480,0xf8f9f6)
        peon(90,105,270)
        rect(415,100,2,280,0xd6dcd0)
        text("Job’s Done",480,238,98,0x17251a,.bold)
        text("Work work.",485,157,40,0x526e39,.medium)
        text("GitHub PR alerts. Right in your menu bar.",487,96,25,0x626b60)
    case 5:
        rect(0,0,1600,480,0x111b2b)
        rect(0,0,1600,10,0xd5b870)
        rect(1030,0,570,480,0x1b2a40)
        text("JOB’S DONE",80,234,91,0xf5e6be,.heavy)
        text("Work work.",85,152,40,0xd5b870,.medium)
        text("Your pull requests have a Peon now.",87,90,26,0xb1bdcd)
        peon(1170,100,280)
    default:
        rect(0,0,1600,480,0x241b17)
        rect(80,95,6,290,0xbc8552)
        text("Job’s Done",125,244,96,0xfff4e7,.semibold)
        text("Open. Merge. Done.",130,157,40,0xd3a477,.medium)
        text("Warcraft sounds for GitHub PRs",132,96,26,0xb6a393)
        peon(1160,100,280)
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(output)/banner-\(option).png"))
}

import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/AppIcon.png"
guard let image = NSImage(contentsOfFile: source) else { fatalError("Cannot read icon: \(source)") }
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x:0,y:0,width:size,height:size), from:.zero, operation:.copy, fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using:.png,properties:[:])!
    if size <= 512 { try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}

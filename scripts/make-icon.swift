import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let v=CGFloat(size); let inset=v*0.08
    let background=NSBezierPath(roundedRect:NSRect(x:inset,y:inset,width:v-2*inset,height:v-2*inset),xRadius:v*0.2,yRadius:v*0.2)
    NSColor(calibratedRed:0.08,green:0.22,blue:0.27,alpha:1).setFill();background.fill()
    let frame=NSBezierPath(roundedRect:NSRect(x:v*0.24,y:v*0.3,width:v*0.48,height:v*0.4),xRadius:v*0.04,yRadius:v*0.04)
    NSColor(calibratedRed:0.5,green:0.91,blue:0.75,alpha:1).setStroke();frame.lineWidth=v*0.035;frame.stroke()
    let play=NSBezierPath();play.move(to:NSPoint(x:v*0.44,y:v*0.39));play.line(to:NSPoint(x:v*0.44,y:v*0.61));play.line(to:NSPoint(x:v*0.61,y:v*0.5));play.close()
    NSColor(calibratedRed:0.8,green:1,blue:0.9,alpha:1).setFill();play.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data=rep.representation(using:.png,properties:[:])!
    if size<=512 {try data.write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"))}
    if size>=32 {try data.write(to:directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}

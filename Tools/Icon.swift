import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s=CGFloat(size)/1024
    let transform=NSAffineTransform();transform.scale(by:s);transform.concat()
    let base=NSBezierPath(roundedRect:NSRect(x:26,y:26,width:972,height:972),xRadius:210,yRadius:210)
    NSGradient(starting:NSColor(calibratedRed:1,green:0.80,blue:0.27,alpha:1),ending:NSColor(calibratedRed:1,green:0.91,blue:0.52,alpha:1))!.draw(in:base,angle:90)
    let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.13);shadow.shadowBlurRadius=24;shadow.shadowOffset=NSSize(width:0,height:-12)
    NSGraphicsContext.saveGraphicsState();shadow.set()
    NSColor(calibratedWhite:1,alpha:0.98).setFill();NSBezierPath(roundedRect:NSRect(x:215,y:172,width:594,height:696),xRadius:58,yRadius:58).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (y,w) in [(680,390),(540,390),(400,265)] {
        NSColor(calibratedRed:0.38,green:0.33,blue:0.25,alpha:0.55).setStroke()
        let p=NSBezierPath();p.lineWidth=28;p.lineCapStyle = .round;p.move(to:NSPoint(x:310,y:y));p.line(to:NSPoint(x:310+w,y:y));p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    let data=bitmap.representation(using:.png,properties:[:])!
    if [16,32,128,256,512].contains(size) {try data.write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"))}
    if [32,64,256,512,1024].contains(size) {try data.write(to:directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}

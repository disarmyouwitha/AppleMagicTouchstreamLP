// Run from the repository root: swift mac/AppleMagicTouchstream/Tools/AppIcon/render.swift
import AppKit
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Artwork/AppIcon.svg")
let destination = root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/Assets.xcassets/AppIcon.appiconset")
guard let icon = NSImage(contentsOf:source) else { fatalError("Cannot read app icon SVG") }
var images: [[String:String]] = []
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
            bytesPerRow:pixels*4,bitsPerPixel:32)!
        bitmap.size = NSSize(width:pixels,height:pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(filename))
        images.append(["idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x","filename":filename])
    }
}
let contents: [String:Any] = ["images":images,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject:contents,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("Contents.json"))
print("Rendered all 10 macOS AppIcon slots from Artwork/AppIcon.svg")

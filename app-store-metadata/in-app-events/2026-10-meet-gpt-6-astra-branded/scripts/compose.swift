import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let minor = NSImage(contentsOf: root.appendingPathComponent("assets/minor-logo-original.png"))!
let openai = NSImage(contentsOf: root.appendingPathComponent("assets/openai-blossom-white.svg"))!
let white = NSColor.white
func render(_ name:String, _ w:Int, _ h:Int) throws {
 let W=CGFloat(w), H=CGFloat(h)
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState()
 let context=NSGraphicsContext(bitmapImageRep:rep)!
 NSGraphicsContext.current=context
 context.imageInterpolation = .high
 NSColor(calibratedWhite:0.07,alpha:1).setFill()
 NSRect(x:0,y:0,width:W,height:H).fill()
 let bg=NSImage(contentsOf:root.appendingPathComponent("sources/branded-\(name)-background.png"))!
 let scale=max(W/bg.size.width,H/bg.size.height)
 let bw=bg.size.width*scale,bh=bg.size.height*scale
 bg.draw(in:NSRect(x:(W-bw)/2,y:(H-bh)/2,width:bw,height:bh))
 func box(_ x:CGFloat,_ y:CGFloat,_ ww:CGFloat,_ hh:CGFloat)->NSRect {NSRect(x:x,y:H-y-hh,width:ww,height:hh)}
 func minorLogo(_ x:CGFloat,_ y:CGFloat,_ height:CGFloat) {
  let width=height*445/437
  minor.draw(in:box(x,y,width,height),from:NSRect(x:128,y:139,width:445,height:437),operation:.sourceOver,fraction:1)
 }
 func oaLogo(_ x:CGFloat,_ y:CGFloat,_ height:CGFloat) {openai.draw(in:box(x,y,height*267.198/264.812,height))}
 func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight,_ kern:CGFloat=0,_ center:Bool=false,_ color:NSColor=white) {
  let a=NSAttributedString(string:s,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.kern:kern])
  let sz=a.size();let xx=center ? x-sz.width/2:x
  a.draw(at:NSPoint(x:xx,y:H-y-sz.height))
 }
 if w>h {
  minorLogo(150,174,78)
  text("Minor AI",251,177,64,.semibold,-1.8)
  text("GPT-6",142,300,188,.bold,-6.5)
  text("Astra",142,497,188,.bold,-6.5)
  oaLogo(151,736,49)
  text("OpenAI",219,741,32,.medium,-0.5,false,NSColor(calibratedWhite:0.78,alpha:1))
 } else {
  minorLogo(323,190,76)
  text("Minor AI",422,196,58,.semibold,-1.6)
  text("GPT-6",W/2,336,156,.bold,-5.5,true)
  text("Astra",W/2,503,174,.bold,-5.5,true)
  oaLogo(433,746,48)
  text("OpenAI",500,752,32,.medium,-0.5,false,NSColor(calibratedWhite:0.78,alpha:1))
 }
 NSGraphicsContext.restoreGraphicsState()
 let converted=rep.converting(to:.sRGB,renderingIntent:.default) ?? rep
 try converted.representation(using:.jpeg,properties:[.compressionFactor:0.97])!.write(to:root.appendingPathComponent("media/event-\(name).jpg"))
 print("Rendered",name,w,h)
}
try render("card",1920,1080)
try render("details",1080,1920)

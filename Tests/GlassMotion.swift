import AppKit
import ApplicationServices
import ScreenCaptureKit
import ImageIO
import CoreImage
import CoreMedia
import UniformTypeIdentifiers

func attribute(_ e: AXUIElement,_ name: String) -> AnyObject? { var value: CFTypeRef?; AXUIElementCopyAttributeValue(e,name as CFString,&value); return value }
func text(_ e: AXUIElement,_ name: String) -> String { attribute(e,name) as? String ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func flatten(_ e: AXUIElement) -> [AXUIElement] { [e] + children(e).flatMap(flatten) }
func rectangle(_ e: AXUIElement) -> CGRect {
    var point = CGPoint.zero; var size = CGSize.zero
    if let p=attribute(e,kAXPositionAttribute) { AXValueGetValue(p as! AXValue,.cgPoint,&point) }
    if let s=attribute(e,kAXSizeAttribute) { AXValueGetValue(s as! AXValue,.cgSize,&size) }
    return CGRect(origin:point,size:size)
}

final class MotionFrames: NSObject, SCStreamOutput, @unchecked Sendable {
    private let context = CIContext()
    private let lock = NSLock()
    var crop = CGRect.zero
    private var frames:[(Double,CGImage)] = []
    func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType) {
        guard type == .screen,let buffer = sample.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer:buffer)
        let rect = CGRect(x:crop.minX,y:image.extent.height-crop.maxY,width:crop.width,height:crop.height)
        guard let cg = context.createCGImage(image,from:rect) else { return }
        lock.lock(); frames.append((ProcessInfo.processInfo.systemUptime,cg)); lock.unlock()
    }
    func captured() -> [(Double,CGImage)] { lock.lock(); defer { lock.unlock() }; return frames }
}

@main struct GlassMotionCapture {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        _ = NSScreen.main
        guard AXIsProcessTrusted(),let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.esai.wechat-timer").first else { fatalError("No accessible esai app") }
        let root=AXUIElementCreateApplication(app.processIdentifier)
        func press(_ e: AXUIElement) { precondition(AXUIElementPerformAction(e,kAXPressAction as CFString) == .success) }
        func button(_ label:String) -> AXUIElement { flatten(root).first { text($0,kAXRoleAttribute)=="AXButton" && text($0,kAXDescriptionAttribute)==label }! }
        if !flatten(root).contains(where: { text($0,kAXRoleAttribute)=="AXPopover" }),let bar=children(root).first,let item=children(bar).first { press(item); try await Task.sleep(for:.milliseconds(200)) }
        if let settings=flatten(root).first(where: { text($0,kAXRoleAttribute)=="AXButton" && text($0,kAXDescriptionAttribute)=="设置" }) { press(settings); try await Task.sleep(for:.milliseconds(200)) }
        press(button("计划"))
        try await Task.sleep(for:.milliseconds(400))
        app.activate(options:[])
        let group=flatten(root).first { text($0,kAXRoleAttribute)=="AXGroup" && text($0,kAXDescriptionAttribute)=="设置" }!
        let track=rectangle(group)
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        let window=content.windows.filter { $0.owningApplication?.processID==app.processIdentifier && $0.frame.width>350 }.max { $0.frame.width<$1.frame.width }!
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=SCStreamConfiguration(); config.width=Int(window.frame.width*2); config.height=Int(window.frame.height*2)
        config.showsCursor=false; config.ignoreShadowsSingleWindow=true; config.captureResolution = .best
        let folder=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "build/glass-motion")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let crop=CGRect(x:(track.minX-window.frame.minX)*2-8,y:(track.minY-window.frame.minY)*2-8,width:track.width*2+16,height:track.height*2+16)
        let recorder = MotionFrames(); recorder.crop = crop
        config.minimumFrameInterval = CMTime(value:1,timescale:60)
        config.queueDepth = 6
        let stream = SCStream(filter:filter,configuration:config,delegate:nil)
        try stream.addStreamOutput(recorder,type:.screen,sampleHandlerQueue:DispatchQueue(label:"esai.motion.capture"))
        try await stream.startCapture()
        try await Task.sleep(for:.milliseconds(300))
        let began = ProcessInfo.processInfo.systemUptime
        press(button("通用"))
        try await Task.sleep(for:.milliseconds(900))
        try await stream.stopCapture()
        let captured = recorder.captured()
        let baseline = captured.last { $0.0 < began }!
        let frames = [baseline] + captured.filter { $0.0 >= began && $0.0 <= began+0.7 }
        var timestamps:[Double] = []
        for (index,frame) in frames.enumerated() {
            let target=folder.appendingPathComponent(String(format:"frame-%02d.png",index))
            let writer=CGImageDestinationCreateWithURL(target as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(writer,frame.1,nil); CGImageDestinationFinalize(writer)
            timestamps.append(frame.0-began)
        }
        let json=try JSONSerialization.data(withJSONObject:["times":timestamps,"track":[track.minX,track.minY,track.width,track.height],"window":[window.frame.minX,window.frame.minY,window.frame.width,window.frame.height]],options:.prettyPrinted)
        try json.write(to:folder.appendingPathComponent("timing.json"))
        press(button("计划"))
        print("MOTION_CAPTURE",folder.path,timestamps)
    }
}

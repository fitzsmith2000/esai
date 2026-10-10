import AppKit
import ApplicationServices
func attribute(_ e: AXUIElement,_ name: String) -> AnyObject? { var value: CFTypeRef?; AXUIElementCopyAttributeValue(e,name as CFString,&value); return value }
func text(_ e: AXUIElement,_ name: String) -> String { attribute(e,name) as? String ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func flatten(_ e: AXUIElement) -> [AXUIElement] { [e] + children(e).flatMap(flatten) }
guard AXIsProcessTrusted(),let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.esai.wechat-timer").first else { exit(2) }
let root=AXUIElementCreateApplication(app.processIdentifier)
let interval = Double(ProcessInfo.processInfo.environment["ESAI_UI_INTERVAL"] ?? "0.12") ?? 0.12
let clicks = Int(ProcessInfo.processInfo.environment["ESAI_UI_CLICKS"] ?? "64") ?? 64
func press(_ e: AXUIElement) {
    let result = AXUIElementPerformAction(e,kAXPressAction as CFString)
    precondition(result == .success,"AX press failed: \(text(e,kAXTitleAttribute)) \(text(e,kAXDescriptionAttribute)) code \(result.rawValue)")
    Thread.sleep(forTimeInterval:interval)
}
func button(_ label: String) -> AXUIElement {
    guard let e=flatten(root).first(where: { text($0,kAXRoleAttribute) == "AXButton" && text($0,kAXDescriptionAttribute) == label }) else { fatalError("Missing button: \(label)") }
    return e
}
if !flatten(root).contains(where: { text($0,kAXRoleAttribute) == "AXPopover" }),let bar=children(root).first,let item=children(bar).first { press(item) }
if let settings=flatten(root).first(where: { text($0,kAXRoleAttribute) == "AXButton" && text($0,kAXDescriptionAttribute) == "设置" }) { press(settings) }
func checkDraft(_ label:String,count:Int) {
    let control=flatten(root).first { text($0,kAXRoleAttribute)=="AXMenuButton" && text($0,kAXTitleAttribute)==label }!
    let original=text(control,kAXValueAttribute)
    let expected=String(format:"%02d",((Int(original) ?? 0)+1)%count)
    press(control)
    Thread.sleep(forTimeInterval:0.3)
    let item=flatten(root).first { text($0,kAXRoleAttribute)=="AXMenuItem" && text($0,kAXTitleAttribute)==expected }!
    press(item)
    var updated:AXUIElement?
    for _ in 0..<30 {
        updated=flatten(root).first { text($0,kAXRoleAttribute)=="AXMenuButton" && text($0,kAXTitleAttribute)==label }
        if let updated=updated,text(updated,kAXValueAttribute)==expected { break }
        Thread.sleep(forTimeInterval:0.1)
    }
    precondition(text(updated!,kAXValueAttribute)==expected,"Draft selection did not update")
    press(button("返回"));press(button("设置"))
    Thread.sleep(forTimeInterval:0.5)
    let restored=flatten(root).first { text($0,kAXRoleAttribute)=="AXMenuButton" && text($0,kAXTitleAttribute)==label }!
    precondition(text(restored,kAXValueAttribute)==original,"Unsaved selection changed saved time")
    print("DRAFT_SELECT_PASS",label,"selection updates and unsaved edits reset")
}
press(button("返回"));press(button("设置"))
press(button("计划"))
Thread.sleep(forTimeInterval:0.3)
checkDraft("关闭时间的小时",count:24)
checkDraft("关闭时间的分钟",count:60)
press(button("返回"))

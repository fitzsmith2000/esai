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
// Do not select values or toggle apps: this exercises UI actions without changing settings.
if let openMenu=flatten(root).first(where: { text($0,kAXRoleAttribute) == "AXMenu" }) {
    precondition(AXUIElementPerformAction(openMenu,kAXCancelAction as CFString) == .success)
    Thread.sleep(forTimeInterval:0.12)
}
for i in 0..<clicks { press(button(["外观","通用","关闭应用","计划"][i % 4])) }
print("CLICK_CHECK_PASS \(clicks) actual tab clicks")
if ProcessInfo.processInfo.environment["ESAI_UI_APPEARANCE"] == "1" {
    let savedAppearance = UserDefaults(suiteName:"com.esai.wechat-timer")?.string(forKey:"appearance") ?? "system"
    press(button("外观"))
    for i in 0..<24 { press(button(["深色","浅色","跟随系统"][i % 3])) }
    press(button(savedAppearance == "dark" ? "深色" : savedAppearance == "light" ? "浅色" : "跟随系统"))
    print("GLASS_MODE_CHECK_PASS 24 appearance lens transitions; original appearance restored")
    press(button("计划"))
}
func rectangle(_ e:AXUIElement) -> CGRect {
    var point = CGPoint.zero; var size = CGSize.zero
    if let p=attribute(e,kAXPositionAttribute) { AXValueGetValue(p as! AXValue,.cgPoint,&point) }
    if let s=attribute(e,kAXSizeAttribute) { AXValueGetValue(s as! AXValue,.cgSize,&size) }
    return CGRect(origin:point,size:size)
}
func checkMenu(_ title: String, count: Int, expected: [String]? = nil) {
    guard let control=flatten(root).first(where: { text($0,kAXRoleAttribute) == "AXMenuButton" && text($0,kAXTitleAttribute) == title }) else { fatalError("Missing menu: \(title)") }
    let controlRect = rectangle(control)
    press(control)
    var opened:AXUIElement?
    for _ in 0..<30 {
        opened = flatten(root).first { text($0,kAXRoleAttribute) == "AXMenu" }
        if opened != nil { break }; Thread.sleep(forTimeInterval:0.03)
    }
    guard let menu = opened else { fatalError("Menu did not open") }
    let menuRect = rectangle(menu)
    precondition(abs(menuRect.minX-controlRect.minX) <= 1,"Menu left edge is not aligned")
    precondition(abs(menuRect.width-controlRect.width) <= 1,"Menu width does not match its control")
    precondition(abs(menuRect.minY-controlRect.maxY-4) <= 1,"Incorrect control/menu spacing")
    print("MENU_GEOMETRY",title,controlRect,menuRect)
    if let folder = ProcessInfo.processInfo.environment["ESAI_UI_CAPTURE"] {
        try! FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
        let crop = controlRect.union(menuRect).insetBy(dx:-8,dy:-8)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
        process.arguments = ["-x","-R", "\(Int(crop.minX)),\(Int(crop.minY)),\(Int(crop.width)),\(Int(crop.height))",folder+"/"+title+".png"]
        try! process.run(); process.waitUntilExit()
    }
    let items=children(menu).filter { text($0,kAXRoleAttribute) == "AXMenuItem" }
    precondition(items.count == count,"Incorrect direct option count: \(title) \(items.count)")
    precondition(items.allSatisfy { item in !children(item).contains(where: { text($0,kAXRoleAttribute) == "AXMenu" }) },"Unexpected nested menu")
    if let expected=expected { precondition(items.map { text($0,kAXTitleAttribute) } == expected,"Unexpected time options") }
    precondition(AXUIElementPerformAction(menu,kAXCancelAction as CFString) == .success)
    Thread.sleep(forTimeInterval:0.12)
    print("MENU_CHECK_PASS \(title) \(count) direct options; no intermediate menu")
}
checkMenu("关闭时间的小时",count:24,expected:(0..<24).map { String(format:"%02d",$0) })
checkMenu("关闭时间的分钟",count:60,expected:(0..<60).map { String(format:"%02d",$0) })
checkMenu("时区",count:6)
press(button("通用"))
checkMenu("界面语言",count:3)
press(button("返回"))
print("UI_INTERACTION_PASS; home restored, no values changed")

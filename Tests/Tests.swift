import Foundation
import CoreGraphics

func date(_ text: String) -> Date { ISO8601DateFormatter().date(from:text)! }
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    precondition(value(),label); checks += 1
}

final class FakeApp: TerminationTarget {
    let bundleIdentifier: String?
    var isTerminated: Bool
    var calls = 0
    init(_ id: String?, terminated: Bool = false) { bundleIdentifier = id; isTerminated = terminated }
    func forceTerminate() -> Bool { calls += 1; isTerminated = true; return true }
}

@main struct Tests {
    static func main() throws {
        let before = date("2026-10-10T10:39:59Z")
        let due = date("2026-10-10T10:40:00Z")
        let tomorrow = date("2026-10-11T10:40:00Z")
        expect(UTCSchedule.next(after:before) == due,"deadline before boundary")
        expect(UTCSchedule.next(after:due) == tomorrow,"checking at boundary arms next day")
        var s = ScheduleState()
        expect(s.consume(now:due) == nil,"disabled never fires")
        s.setEnabled(true,now:before)
        expect(s.nextDue == due,"enable arms future deadline")
        expect(s.consume(now:before) == nil,"no early fire")
        expect(s.consume(now:due) == due,"fires exactly at UTC 10:40")
        expect(s.nextDue == tomorrow,"advances after execution")
        expect(s.consume(now:due) == nil,"no duplicate callback")
        expect(s.consume(now:date("2026-10-10T16:00:00Z")) == nil,"no repeated kill after relaunching WeChat")
        let saved = try JSONEncoder().encode(s)
        var restored = try JSONDecoder().decode(ScheduleState.self,from:saved)
        expect(restored.enabled,"enabled survives restart")
        expect(restored.consume(now:due) == nil,"restart cannot replay consumed slot")
        expect(restored.consume(now:tomorrow) == tomorrow,"next daily task")
        s.setEnabled(false,now:before)
        expect(s.nextDue == nil,"disable clears deadline")
        expect(s.consume(now:tomorrow) == nil,"disable blocks execution")
        s.setEnabled(true,now:date("2026-10-10T12:00:00Z"))
        expect(s.nextDue == tomorrow,"enable after deadline does not kill immediately")
        s = ScheduleState(); s.setEnabled(true,now:before)
        expect(s.consume(now:date("2026-10-10T15:00:00Z")) == due,"wake catches up same UTC day")
        expect(s.consume(now:date("2026-10-10T15:00:01Z")) == nil,"wake catchup only once")
        s = ScheduleState(); s.setEnabled(true,now:before)
        expect(s.consume(now:date("2026-10-11T09:00:00Z")) == nil,"expired previous-day task skipped")
        expect(s.nextDue == tomorrow,"wake before today's time retains today")
        s = ScheduleState(); s.setEnabled(true,now:before)
        expect(s.consume(now:date("2026-10-14T18:00:00Z")) == date("2026-10-14T10:40:00Z"),"multi-day sleep coalesces today's task")
        expect(s.consume(now:date("2026-10-14T18:00:00Z")) == nil,"coalesced task once only")
        // Absolute UTC schedule survives DST jumps and repeated local hours.
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX")
        f.timeZone = TimeZone(identifier:"America/Los_Angeles")!; f.dateFormat = "HH:mm z"
        expect(f.string(from:date("2026-03-07T10:40:00Z")) == "02:40 PST","winter local time")
        expect(f.string(from:date("2026-03-08T10:40:00Z")) == "03:40 PDT","spring DST boundary")
        expect(f.string(from:date("2026-10-31T10:40:00Z")) == "03:40 PDT","summer local time")
        expect(f.string(from:date("2026-11-01T10:40:00Z")) == "02:40 PST","fall DST boundary")
        for stamp in ["2026-03-07T10:40:00Z","2026-03-08T10:40:00Z","2026-10-31T10:40:00Z","2026-11-01T10:40:00Z","2026-12-31T10:40:00Z"] {
            let deadline = UTCSchedule.next(after:date(stamp))
            let components = UTCSchedule.calendar.dateComponents([.hour,.minute],from:deadline)
            expect(components.hour == 10 && components.minute == 40,"fixed UTC across DST / year boundary")
        }
        s = ScheduleState(); s.setEnabled(true,now:before); _ = s.consume(now:due)
        expect(s.consume(now:before) == nil,"clock rollback cannot replay deadline")
        s.setEnabled(false,now:before); s.setEnabled(true,now:before)
        expect(s.nextDue == tomorrow,"clock rollback with rearm remains deduplicated")
        // Named zones follow their local wall clock, rather than a fixed UTC offset.
        let la = DailySchedule(hour:10,minute:40,timeZoneID:"America/Los_Angeles")
        expect(la.slot(on:date("2026-03-07T18:00:00Z")) == date("2026-03-07T18:40:00Z"),"LA winter wall clock")
        expect(la.slot(on:date("2026-03-08T18:00:00Z")) == date("2026-03-08T17:40:00Z"),"LA spring wall clock")
        expect(la.slot(on:date("2026-11-01T18:00:00Z")) == date("2026-11-01T18:40:00Z"),"LA fall wall clock")
        expect(la.cycleDuration(ending:date("2026-03-08T17:40:00Z")) == 23*3600,"spring countdown uses 23-hour cycle")
        expect(la.cycleDuration(ending:date("2026-11-01T18:40:00Z")) == 25*3600,"fall countdown uses 25-hour cycle")
        let ny = DailySchedule(hour:10,minute:40,timeZoneID:"America/New_York")
        expect(ny.slot(on:date("2026-03-07T18:00:00Z")) == date("2026-03-07T15:40:00Z"),"NY winter wall clock")
        expect(ny.slot(on:date("2026-03-08T18:00:00Z")) == date("2026-03-08T14:40:00Z"),"NY spring wall clock")
        let london = DailySchedule(hour:10,minute:40,timeZoneID:"Europe/London")
        expect(london.slot(on:date("2026-03-28T18:00:00Z")) == date("2026-03-28T10:40:00Z"),"London winter")
        expect(london.slot(on:date("2026-03-29T18:00:00Z")) == date("2026-03-29T09:40:00Z"),"London spring uses UK transition")
        expect(london.slot(on:date("2026-10-25T18:00:00Z")) == date("2026-10-25T10:40:00Z"),"London fall before US transition")
        let beijing = DailySchedule(hour:10,minute:40,timeZoneID:"Asia/Shanghai")
        expect(beijing.slot(on:date("2026-03-08T18:00:00Z")) == date("2026-03-09T02:40:00Z"),"Beijing follows its own date")
        expect(beijing.slot(on:date("2026-11-01T04:00:00Z")) == date("2026-11-01T02:40:00Z"),"Beijing stays UTC+8")
        let tokyo = DailySchedule(hour:0,minute:0,timeZoneID:"Asia/Tokyo")
        expect(tokyo.next(after:date("2026-12-31T14:59:59Z")) == date("2026-12-31T15:00:00Z"),"midnight and new year in Tokyo")
        expect(tokyo.next(after:date("2026-12-31T15:00:00Z")) == date("2027-01-01T15:00:00Z"),"midnight equality arms following day")
        let gap = DailySchedule(hour:2,minute:30,timeZoneID:"America/Los_Angeles")
        expect(gap.slot(on:date("2026-03-08T08:00:00Z")) == date("2026-03-08T10:30:00Z"),"missing 02:30 shifts to 03:30")
        expect(gap.next(after:date("2026-03-08T10:30:00Z")) == date("2026-03-09T09:30:00Z"),"day after gap returns to 02:30")
        let repeated = DailySchedule(hour:1,minute:30,timeZoneID:"America/Los_Angeles")
        expect(repeated.slot(on:date("2026-11-01T07:00:00Z")) == date("2026-11-01T08:30:00Z"),"fall repeated 01:30 selects first occurrence")
        s = ScheduleState(); s.setConfiguration(repeated,now:date("2026-11-01T07:00:00Z")); s.setEnabled(true,now:date("2026-11-01T07:00:00Z"))
        expect(s.consume(now:date("2026-11-01T08:30:00Z")) != nil,"first repeated hour fires")
        expect(s.consume(now:date("2026-11-01T09:30:00Z")) == nil,"second repeated hour cannot fire")
        s = ScheduleState(); s.setConfiguration(la,now:before); s.setEnabled(true,now:before)
        expect(s.consume(now:date("2026-10-11T05:00:00Z")) == date("2026-10-10T17:40:00Z"),"wake catches LA day even across UTC midnight")
        s = ScheduleState(); s.setConfiguration(beijing,now:before); s.setEnabled(true,now:before)
        expect(s.consume(now:date("2026-10-12T01:00:00Z")) == nil,"skip yesterday in selected Beijing zone")
        expect(s.nextDue == date("2026-10-12T02:40:00Z"),"retain current Beijing day deadline")
        s = ScheduleState(); s.setEnabled(true,now:before)
        let earlier = DailySchedule(hour:9,minute:0)
        s.setConfiguration(earlier,now:date("2026-10-10T12:00:00Z"))
        expect(s.nextDue == date("2026-10-11T09:00:00Z"),"save earlier time re-arms tomorrow")
        expect(s.consume(now:date("2026-10-10T12:00:00Z")) == nil,"save never causes immediate termination")
        s = ScheduleState(); s.setEnabled(true,now:before); _ = s.consume(now:due)
        s.setConfiguration(DailySchedule(hour:16,minute:0),now:date("2026-10-10T12:00:00Z"))
        expect(s.nextDue == date("2026-10-11T16:00:00Z"),"changing time after run skips already handled date")
        s.setEnabled(false,now:date("2026-10-10T12:00:00Z")); s.setEnabled(true,now:date("2026-10-10T12:00:00Z"))
        expect(s.nextDue == date("2026-10-11T16:00:00Z"),"re-enable respects handled local date")
        s = ScheduleState(); s.setConfiguration(ny,now:before)
        expect(!s.enabled && s.nextDue == nil,"saving while disabled keeps disabled")
        let customized = try JSONDecoder().decode(ScheduleState.self,from:JSONEncoder().encode(s))
        expect(customized.configuration == ny,"custom schedule survives serialization")
        let legacy = Data("{\"enabled\":true,\"nextDue\":813926400,\"lastHandled\":813840000}".utf8)
        let migrated = try JSONDecoder().decode(ScheduleState.self,from:legacy)
        expect(migrated.enabled && migrated.configuration == DailySchedule(),"legacy preferences migrate to UTC 10:40")
        expect(migrated.nextDue == Date(timeIntervalSinceReferenceDate:813926400) && migrated.lastHandled == Date(timeIntervalSinceReferenceDate:813840000),"migration retains pending deadline and history")
        expect(DailySchedule(hour:24,minute:-1,timeZoneID:"invalid") == DailySchedule(),"invalid constructor values normalize")
        let invalid = Data("{\"hour\":99,\"minute\":0,\"timeZoneID\":\"UTC\"}".utf8)
        expect((try? JSONDecoder().decode(DailySchedule.self,from:invalid)) == nil,"invalid persisted schedule rejected")
        for preset in AccentPreset.choices {
            expect(AccentRGB(hex:preset.hex)?.hex == preset.hex,"preset color round trip")
        }
        expect(AccentRGB(hex:" 2878ed ")?.hex == "#2878ED","custom HEX case and prefix normalization")
        for hex in ["", "#GG0000", "##2878ED", "#12345", "#12345678", "#１２３４５６"] {
            expect(AccentRGB(hex:hex) == nil,"invalid color rejected")
        }
        expect(AccentRGB(hex:"#FFFFFF")!.readable(onDark:false).red < 0.5,"white custom color becomes legible in light mode")
        expect(AccentRGB(hex:"#000000")!.readable(onDark:true).red > 0.5,"black custom color becomes legible in dark mode")
        let wechat = FakeApp(WeChatIdentity.bundleID)
        let wetype = FakeApp("com.tencent.inputmethod.wetype")
        let other = FakeApp("com.apple.Safari")
        let noID = FakeApp(nil)
        let alreadyGone = FakeApp(WeChatIdentity.bundleID,terminated:true)
        let chosen = WeChatTermination.request([wechat,wetype,other,noID,alreadyGone])
        expect(chosen.count == 1 && wechat.calls == 1,"force termination dispatched to WeChat")
        expect(wetype.calls == 0 && other.calls == 0 && noID.calls == 0,"no unrelated application killed")
        expect(alreadyGone.calls == 0,"already terminated instance skipped")
        expect(WeChatTermination.request([]).isEmpty,"absent WeChat no-op")
        let multiWechat = FakeApp(WeChatIdentity.bundleID)
        let safari = FakeApp("com.apple.Safari")
        let unselected = FakeApp("com.apple.Music")
        let ownApp = FakeApp(SelectedApplication.ownBundleID)
        let gone = FakeApp("com.apple.Safari",terminated:true)
        let batch = ApplicationTermination.request([multiWechat,safari,safari,unselected,ownApp,noID,gone],selectedIDs:[WeChatIdentity.bundleID,"com.apple.Safari",SelectedApplication.ownBundleID])
        expect(batch.count == 2 && multiWechat.calls == 1 && safari.calls == 1,"multi-app selection closes each captured instance once")
        expect(unselected.calls == 0 && ownApp.calls == 0 && noID.calls == 0 && gone.calls == 0,"unselected, esai, missing ID, and terminated apps remain untouched")
        expect(ApplicationTermination.request([unselected],selectedIDs:[]).isEmpty,"empty selection never terminates apps")
        let configs = [SelectedApplication.weChat,SelectedApplication(bundleID:"com.apple.Safari",name:"Safari",path:"/Applications/Safari.app")]
        let encoded = try JSONEncoder().encode(configs)
        let decodedApps = try JSONDecoder().decode([SelectedApplication].self,from:encoded)
        expect(decodedApps == configs,"multi-app selection persists with identifiers and paths")
        expect(SelectedApplication.normalized(configs + [.weChat,.init(bundleID:SelectedApplication.ownBundleID,name:"esai",path:nil),.init(bundleID:"",name:"Unknown",path:nil)]) == configs,"selection normalization deduplicates and excludes self and invalid IDs")
        expect(SelectedApplication.normalized([]).isEmpty,"explicit empty selection remains empty")
        expect(SelectedApplication.weChat.bundleID == WeChatIdentity.bundleID,"WeChat is the default identity")
        expect(SelectedApplication.from(url:URL(fileURLWithPath:"/tmp/not-an-app.txt")) == nil,"non-app selection rejected")
        expect(SelectedApplication.restored(from:nil) == [.weChat],"upgrade defaults to WeChat without resetting timer")
        expect(SelectedApplication.restored(from:Data("invalid".utf8)) == [.weChat],"corrupt app selection falls back to default")
        expect(SelectedApplication.restored(from:encoded) == configs,"saved multi-app preference restored")
        let emptySelectionData = try JSONEncoder().encode([SelectedApplication]())
        expect(SelectedApplication.restored(from:emptySelectionData).isEmpty,"saved empty selection stays empty")
        let firstGone = FakeApp(WeChatIdentity.bundleID,terminated:true)
        let secondAlive = FakeApp(WeChatIdentity.bundleID)
        let completed = FakeApp("com.apple.Safari",terminated:true)
        let missing = SelectedApplication(bundleID:"com.apple.Music",name:"Music",path:nil)
        let report = ApplicationTermination.results(for:configs + [missing],captured:[firstGone,secondAlive,completed])
        expect(report.map(\.status) == [.failed,.closed,.notRunning],"one failing instance reports failure without hiding other closed or absent apps")
        let reopened = FakeApp("com.apple.Safari")
        ApplicationTermination.request([completed],selectedIDs:["com.apple.Safari"])
        expect(reopened.calls == 0,"retry on original instances leaves newly launched app untouched")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("app")
        try FileManager.default.createDirectory(at:temp.appendingPathComponent("Contents"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let info: [String:String] = ["CFBundleIdentifier":"com.esai.testing.sample","CFBundleName":"Sample","CFBundlePackageType":"APPL"]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:temp.appendingPathComponent("Contents/Info.plist"))
        expect(SelectedApplication.from(url:temp)?.bundleID == "com.esai.testing.sample","app picker reads actual bundle identity")
        expect(SelectedApplication.from(url:temp)?.name == "Sample","app picker reads bundle display name")
        for height: CGFloat in [320,480,720,1001] {
            for width: CGFloat in [300,800,1920] {
                let available = CGSize(width:width,height:height)
                let size = PopoverLayout.size(available:available)
                expect(size.height + PopoverLayout.chromeAllowance + 2*PopoverLayout.screenMargin <= height,"popover height fits screen including chrome")
                expect(size.width + PopoverLayout.chromeAllowance + 2*PopoverLayout.screenMargin <= width,"popover width fits screen including chrome")
            }
        }
        for visible in [CGRect(x:0,y:49,width:1920,height:1001),CGRect(x:-1280,y:-200,width:1280,height:680)] {
            for origin in [CGPoint(x:visible.minX-300,y:visible.maxY+500),CGPoint(x:visible.maxX+100,y:visible.minY-300)] {
                var frame = CGRect(origin:origin,size:CGSize(width:400,height:540))
                frame.origin = PopoverLayout.origin(for:frame,inside:visible)
                expect(visible.contains(frame),"offscreen popup clamped on all display edges")
            }
        }
        for visible in [CGRect(x:0,y:49,width:1920,height:1001),CGRect(x:-1280,y:-200,width:1280,height:680)] {
            let anchor = CGRect(x:visible.midX,y:visible.maxY,width:24,height:24)
            for height: CGFloat in [320,540] {
                var frame = CGRect(x:visible.midX-200,y:visible.minY,width:426,height:height)
                frame.origin = PopoverLayout.anchoredOrigin(for:frame,inside:visible,anchor:anchor)
                expect(frame.maxY == anchor.minY,"arrow meets menu bar without artificial top margin")
                expect(visible.contains(frame),"anchored popup remains on screen")
            }
        }
        expect(AppLanguage.system.resolved(preferred:["zh-Hans-CN","en-US"]) == .chinese,"system Chinese follows preferred language")
        expect(AppLanguage.system.resolved(preferred:["zh-Hant-TW"]) == .chinese,"Chinese language variants use Chinese UI")
        expect(AppLanguage.system.resolved(preferred:["en-GB","zh-Hans"]) == .english,"system English follows first preference")
        expect(AppLanguage.system.resolved(preferred:["fr-FR","zh-Hans"]) == .english,"unsupported system language falls back to English")
        expect(AppLanguage.system.resolved(preferred:[]) == .english,"empty language list has safe fallback")
        expect(AppLanguage.chinese.resolved(preferred:["en-US"]) == .chinese,"explicit Chinese overrides system")
        expect(AppLanguage.english.resolved(preferred:["zh-Hans"]) == .english,"explicit English overrides system")
        expect(AppLanguage(rawValue:"zh-Hans") == .chinese && AppLanguage(rawValue:"en") == .english,"language preference identifiers round trip")
        expect(L10n.text("设置",language:.english) == "Settings","English translation")
        expect(L10n.text("设置",language:.chinese) == "设置","Chinese translation")
        expect(L10n.text("已强制关闭微信",language:.english) == "WeChat force quit successfully","legacy execution history translates")
        expect(L10n.dateFormat("M月d日 EEEE HH:mm",language:.english) == "EEE, MMM d HH:mm","English date order and weekdays")
        for (key,value) in L10n.english {
            let keyCount = key.components(separatedBy:"%@").count
            let valueCount = value.components(separatedBy:"%@").count
            expect(keyCount == valueCount,"translation placeholder count matches: \(key)")
            expect(!value.isEmpty,"no empty translation: \(key)")
        }
        print("Passed \(checks) checks: time zones, DST gaps and repeats, sleep, migration, colors, screen bounds, and isolated termination.")
    }
}

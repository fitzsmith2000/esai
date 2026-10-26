import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var nativeName: String {
        switch self { case .system: return "跟随系统"; case .chinese: return "简体中文"; case .english: return "English" }
    }
    func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        // Follow the first preferred system language, using English for unsupported languages.
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
    var locale: Locale { Locale(identifier:self == .chinese ? "zh_CN" : "en_US") }
}

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        language == .chinese ? key : english[key] ?? key
    }
    static func dateFormat(_ format: String, language: AppLanguage) -> String {
        guard language == .english else { return format }
        switch format {
        case "M月d日 EEEE": return "EEE, MMM d"
        case "M月d日 EEEE HH:mm": return "EEE, MMM d HH:mm"
        case "M月d日 HH:mm": return "MMM d HH:mm"
        default: return format
        }
    }
    static let english: [String:String] = [
        "软件更新":"Software updates", "检查更新…":"Check for Updates…",
        "自动检查更新":"Automatically check for updates", "自动下载并安装更新":"Automatically download and install updates",
        "每小时检查一次。自动安装默认关闭；开启后后台下载，并在退出时安装，或提示重新启动。":"Checks hourly. Automatic installation is off by default; enable to download in the background and install on quit, or be prompted to restart.",
        "预览模式不检查或安装更新。":"Preview mode does not check for or install updates.", "上次检查：":"Last checked:",
        "所选应用将按同一时间关闭。":"Selected apps share one shutdown schedule.",
        "清除搜索":"Clear search", "其他应用":"Other apps", "已选择":"Selected", "未选择":"Not selected",
        "选择即保存，可同时关闭多个应用。":"Selections are saved immediately. Multiple apps are supported.",
        "定时关闭应用":"App shutdown timer", "未选择应用":"No apps selected", "%@ 个应用":"%@ apps",
        "启用定时关闭应用":"Enable daily app shutdown", "到点强制关闭所选应用":"Force quit selected apps at scheduled time",
        "应用运行状态":"App status", "管理应用":"Manage apps", "修改关闭时间":"Edit shutdown time", "关闭应用":"Apps",
        "每天按所选地区的时间，强制关闭所有已选应用。":"Force quit all selected apps daily in this time zone.",
        "默认选择微信。可同时选择多个应用，统一按计划关闭。":"WeChat is selected by default. Choose multiple apps to close on the same schedule.",
        "已选择 %@ 个":"%@ selected", "添加应用…":"Add apps…", "添加应用":"Add apps", "搜索应用":"Search apps",
        "请至少选择一个应用，再启用关闭计划。":"Select at least one app to enable the timer.",
        "未找到应用，可从其他位置添加。":"No apps found. Add one from another location.",
        "请选择有效的应用；esai 不能关闭自身。":"Choose a valid app. esai cannot close itself.",
        "勾选即保存。更改应用不会更改关闭时间。":"Selections save immediately. Changing apps keeps your scheduled time.",
        "执行详情":"Execution details", "已关闭":"Closed", "关闭失败":"Could not close",
        "已关闭 %@ 个应用":"Closed %@ apps", "已关闭 %@ 个，%@ 个未能关闭":"Closed %@; %@ could not close",
        "所选应用均未运行":"None of the selected apps were running", "esai · 定时关闭应用":"esai · App Timer",
        "返回":"Back", "设置":"Settings", "微信":"WeChat", "刷新状态":"Refresh status",
        "已启用":"Enabled", "未启用":"Disabled", "定时关闭微信":"WeChat timer",
        "每天 %@ %@":"Daily %@ %@", "本地 %@":"Local %@", "关闭计划":"Schedule",
        "启用":"Enable", "启用定时关闭微信":"Enable daily WeChat shutdown", "每日":"Daily",
        "%@后关闭":"Closes in %@", "等待启用":"Not enabled", "到点强制关闭微信":"Force quit at scheduled time",
        "下次：%@ %@":"Next: %@ %@", "勾选后开始每日调度":"Enable to start scheduling",
        "时间换算":"Time conversion", "本机时间":"Local time", "%@ · 日期按本机时区显示":"%@ · Dates shown in local time",
        "微信运行状态":"WeChat status", "运行中":"Running", "未运行":"Not running",
        "定时任务已开启":"Timer on", "定时任务未开启":"Timer off", "上次：%@%@":"Last: %@%@",
        "睡眠错过时，唤醒后补执行当天任务。":"Missed during sleep? Runs on wake for the same day.",
        "%@ 分钟":"%@ min", "%@ 小时 %@ 分钟":"%@ hr %@ min", "计划":"Schedule", "外观":"Appearance", "通用":"General",
        "关闭时间":"Shutdown time", "每天按所选地区的时间，强制关闭微信。":"Force quit WeChat daily in the selected time zone.",
        "每天":"Daily", "小时":"Hour", "分钟":"Minute", "关闭时间的小时":"Shutdown hour", "关闭时间的分钟":"Shutdown minute",
        "时区":"Time zone", "随该地区切换夏令时，设定的当地时间保持不变。":"Follows daylight saving time. The local hour stays the same.",
        "该时区不切换夏令时，全年按设定时间执行。":"This zone has no daylight saving time. Runs at the same time year-round.",
        "下一次关闭":"Next shutdown", "启用后的首次关闭":"First shutdown when enabled", "保存后的执行预览":"Preview after saving",
        "本机 %@\nUTC %@":"Local %@\nUTC %@", "已保存":"Saved", "当前计划已保存":"Schedule saved", "尚未保存":"Unsaved changes",
        "保存时间":"Save time", "执行规则":"How it works", "睡眠后补执行":"Catch up on wake",
        "按所选时区的日期，仅补执行当天已到期任务。":"Catches up only the current day in the selected time zone.",
        "夏令时特殊时刻":"Daylight saving transitions",
        "不存在的时间顺延一小时，例如 02:30 → 03:30；重复的时间只执行一次。":"A missing hour shifts forward (02:30 → 03:30). A repeated hour runs only once.",
        "保存后重新排期":"Reschedule after saving",
        "只预约未来时间；当天已执行过的任务不会因修改时间重复执行。":"Schedules a future time. Editing does not repeat a task already handled that day.",
        "外观模式":"Appearance", "跟随系统":"Follow system", "浅色":"Light", "深色":"Dark", "强调色":"Accent color",
        "透明玻璃背景":"Transparent glass background", "面板会透出桌面背景；关闭后使用实色面板。":"The panel reveals the desktop behind it; turn off for a solid surface.",
        "选择经典颜色，或调出属于你的 esai。":"Choose a classic color or make esai your own.",
        "esai 绿":"esai", "经典蓝":"Blue", "鸢尾紫":"Violet", "琥珀橙":"Amber", "玫瑰红":"Rose", "湖水青":"Teal",
        "自定义颜色":"Custom color", "自定义强调色取色器":"Custom accent color picker", "强调色 HEX 色值":"Accent HEX color",
        "应用":"Apply", "请输入六位 HEX 色值，例如 #2878ED。":"Enter a six-digit HEX color, such as #2878ED.",
        "强调色预览":"Accent preview", "实时应用并保存；浅色和深色模式自动调整可读性。":"Applies and saves instantly. Adjusts for readability in light and dark modes.",
        "语言":"Language", "简体中文":"简体中文", "界面语言":"Interface language",
        "跟随系统会自动使用电脑的首选语言，切换立即生效。":"Follows your computer’s preferred language. Changes apply instantly.",
        "当前语言：%@":"Current language: %@", "登录时启动":"Launch at login",
        "登录电脑时自动运行 esai。定时开关会保留你的选择。":"Starts esai when you log in. Remembers your timer setting.",
        "打开登录项设置":"Open Login Items", "保持应用运行":"Keep esai running",
        "退出应用会暂停调度。取消勾选可立即停用。":"Quitting pauses scheduling. Uncheck Enable to stop the timer.",
        "esai 定时关闭":"esai App Timer", "版本 %@":"Version %@", "开源许可":"Licenses", "退出":"Quit",
        "打开设置":"Open settings", "退出 esai，暂停定时任务":"Quit esai and pause the timer",
        "UTC · 世界协调时间":"UTC · Coordinated Universal Time", "美西 · 洛杉矶":"Pacific · Los Angeles",
        "美东 · 纽约":"Eastern · New York", "英国 · 伦敦":"United Kingdom · London", "中国 · 北京":"China · Beijing", "日本 · 东京":"Japan · Tokyo",
        "美西":"Pacific", "美东":"Eastern", "伦敦":"London", "北京":"Beijing", "东京":"Tokyo",
        "尚未执行":"Never run", "微信未运行，无需关闭":"WeChat was not running", "已强制关闭微信":"WeChat force quit successfully",
        "关闭失败，请检查微信状态":"Could not close WeChat. Check its status.",
        "请在系统设置的登录项中允许启动":"Allow esai in System Settings → Login Items",
        "登录启动设置失败：%@":"Could not change login setting: %@",
        "esai · 定时关闭微信":"esai · WeChat Timer", "esai · 界面预览（未启用）":"esai · UI preview (timer inactive)"
    ]
}

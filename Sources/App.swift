import AppKit
import SwiftUI
import ServiceManagement
import Combine
import UniformTypeIdentifiers

extension NSRunningApplication: TerminationTarget {}

final class TimerModel: ObservableObject {
    @Published private(set) var state: ScheduleState
    @Published var lastResult: String
    @Published var lastRun: Date?
    @Published private(set) var selectedApplications: [SelectedApplication] = [.weChat]
    @Published private(set) var availableApplications: [SelectedApplication] = [.weChat]
    @Published private(set) var runningIDs: Set<String> = []
    @Published private(set) var applicationResults: [ApplicationExecution] = []
    @Published var applicationError: String?
    private var lastResultArguments: [String] = []
    let navigation = PanelNavigation()
    let updates: UpdateService
    @Published var loginEnabled = false
    @Published private var loginError: String?
    @Published private var loginNeedsApproval = false
    @Published var localTime = ""
    @Published var nextTime = ""
    @Published var nextDate = ""
    @Published var appearance = "system"
    @Published var glassBackground = true
    @Published private(set) var language = AppLanguage.system
    @Published private(set) var resolvedLanguage = AppLanguage.system.resolved()
    @Published private(set) var accentHex = AccentPreset.choices[0].hex
    @Published var panelSize = PopoverLayout.preferredSize
    private let defaults: UserDefaults
    private var timer: Timer?
    private var deadline: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        updates = UpdateService(enabled:!preview)
        defaults = preview ? UserDefaults(suiteName: "com.esai.wechat-timer.preview")! : .standard
        if !preview, let data = defaults.data(forKey: "schedule"), let saved = try? JSONDecoder().decode(ScheduleState.self, from: data) {
            state = saved
        } else { state = ScheduleState() }
        lastResult = preview ? "尚未执行" : (defaults.string(forKey: "lastResult") ?? "尚未执行")
        lastRun = preview ? nil : defaults.object(forKey: "lastRun") as? Date
        appearance = preview ? (CommandLine.arguments.contains("--preview-dark") ? "dark" : "light") : (defaults.string(forKey:"appearance") ?? "system")
        glassBackground = preview ? !CommandLine.arguments.contains("--preview-opaque") : (defaults.object(forKey:"glassBackground") as? Bool ?? true)
        language = AppLanguage(rawValue:preview ? (ProcessInfo.processInfo.environment["ESAI_PREVIEW_LANGUAGE"] ?? "zh-Hans") : (defaults.string(forKey:"language") ?? "system")) ?? .system
        resolvedLanguage = language.resolved()
        let savedAccent = preview ? ProcessInfo.processInfo.environment["ESAI_PREVIEW_ACCENT"] : defaults.string(forKey:"accentHex")
        accentHex = savedAccent.flatMap { AccentRGB(hex:$0)?.hex } ?? AccentPreset.choices[0].hex
        if preview, let zone = ProcessInfo.processInfo.environment["ESAI_PREVIEW_ZONE"] {
            state.setConfiguration(DailySchedule(hour:10,minute:40,timeZoneID:zone),now:Date())
        }
        if preview && CommandLine.arguments.contains("--preview-enabled") { state.setEnabled(true,now:Date()) }
        if preview, let height = ProcessInfo.processInfo.environment["ESAI_PREVIEW_HEIGHT"].flatMap(Double.init) {
            panelSize = PopoverLayout.size(available:CGSize(width:800,height:height))
        }
        if !preview { selectedApplications = SelectedApplication.restored(from:defaults.data(forKey:"selectedApplications")) }
        if !preview, let data = defaults.data(forKey:"applicationResults") { applicationResults = (try? JSONDecoder().decode([ApplicationExecution].self,from:data)) ?? [] }
        lastResultArguments = preview ? [] : defaults.stringArray(forKey:"lastResultArguments") ?? []
        if selectedApplications.isEmpty { state.setEnabled(false,now:Date()) }
        refreshLabels()
        loadApplicationCatalog()
        if preview { return }
        tick()
        timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        let nc = NotificationCenter.default
        for name in [NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.resolvedLanguage = self?.language.resolved() ?? .english
                self?.tick()
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tick() })
        }
    }

    func setEnabled(_ enabled: Bool) {
        state.setEnabled(enabled && !selectedApplications.isEmpty, now: Date())
        persist()
        tick()
    }

    func saveSchedule(_ configuration: DailySchedule) {
        state.setConfiguration(configuration,now:Date())
        persist()
        refreshLabels()
        scheduleDeadline()
    }

    func setAccent(_ value: String) {
        guard let rgb = AccentRGB(hex:value) else { return }
        accentHex = rgb.hex
        if !preview { defaults.set(accentHex,forKey:"accentHex") }
    }

    var accentColor: Color {
        let rgb = AccentRGB(hex:accentHex)!
        return Color(nsColor:NSColor(name:nil) { appearance in
            let adjusted = rgb.readable(onDark:appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua)
            return NSColor(srgbRed:adjusted.red,green:adjusted.green,blue:adjusted.blue,alpha:1)
        })
    }
    var selectedAccent: Color {
        let rgb = AccentRGB(hex:accentHex)!
        return Color(red:rgb.red,green:rgb.green,blue:rgb.blue)
    }
    func setAccentColor(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        setAccent(AccentRGB(red:rgb.redComponent,green:rgb.greenComponent,blue:rgb.blueComponent).hex)
    }

    private func persist() {
        guard !preview else { return }
        defaults.set(try? JSONEncoder().encode(state), forKey: "schedule")
    }

    func tick() {
        if !preview, state.consume(now: Date()) != nil {
            // Save the consumed slot before termination to avoid duplicate wake/restart execution.
            persist()
            terminateSelectedApplications()
        }
        persist()
        refreshLabels()
        scheduleDeadline()
    }

    private func scheduleDeadline() {
        deadline?.invalidate()
        guard !preview, state.enabled, let next = state.nextDue else { return }
        deadline = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(deadline!, forMode: .common)
    }

    var isWeChatOnly: Bool { selectedApplications.count == 1 && selectedApplications[0].bundleID == WeChatIdentity.bundleID }
    var targetSummary: String {
        if selectedApplications.isEmpty { return translate("未选择应用") }
        if selectedApplications.count == 1 { return applicationName(selectedApplications[0]) }
        return translate("%@ 个应用",arguments:[String(selectedApplications.count)])
    }
    func applicationName(_ app: SelectedApplication) -> String { app.bundleID == WeChatIdentity.bundleID ? translate("微信") : app.name }
    var lastResultText: String { translate(lastResult,arguments:lastResultArguments) }

    func setApplication(_ application: SelectedApplication, selected: Bool) {
        var updated = selectedApplications.filter { $0.id != application.id }
        if selected { updated.append(application) }
        selectedApplications = SelectedApplication.normalized(updated)
        if !preview { defaults.set(try? JSONEncoder().encode(selectedApplications),forKey:"selectedApplications") }
        if selectedApplications.isEmpty { setEnabled(false) }
        refreshLabels()
    }
    func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        panel.prompt = translate("添加应用")
        guard panel.runModal() == .OK else { return }
        applicationError = nil
        for url in panel.urls {
            guard let application = SelectedApplication.from(url:url) else {
                applicationError = translate("请选择有效的应用；esai 不能关闭自身。")
                continue
            }
            setApplication(application,selected:true)
            if !availableApplications.contains(where: { $0.id == application.id }) { availableApplications.append(application) }
        }
    }
    private func loadApplicationCatalog() {
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let manager = FileManager.default
            let roots = [URL(fileURLWithPath:"/Applications"),manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),URL(fileURLWithPath:"/System/Applications")]
            var apps: [SelectedApplication] = [.weChat]
            for root in roots {
                let paths = (try? manager.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
                for path in paths {
                    if let app = SelectedApplication.from(url:path) { apps.append(app) }
                    else if path.pathExtension.isEmpty {
                        for child in (try? manager.contentsOfDirectory(at:path,includingPropertiesForKeys:nil)) ?? [] {
                            if let app = SelectedApplication.from(url:child) { apps.append(app) }
                        }
                    }
                }
            }
            let catalog = SelectedApplication.normalized(apps).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.availableApplications = catalog }
        }
    }
    private func record(_ result: String, arguments: [String] = [], results: [ApplicationExecution] = []) {
        lastResult = result; lastResultArguments = arguments; lastRun = Date(); applicationResults = results
        defaults.set(result,forKey:"lastResult")
        defaults.set(arguments,forKey:"lastResultArguments")
        defaults.set(lastRun,forKey:"lastRun")
        defaults.set(try? JSONEncoder().encode(results),forKey:"applicationResults")
        refreshLabels()
    }
    private func terminateSelectedApplications() {
        let selection = selectedApplications
        let ids = Set(selection.map(\.bundleID))
        let applications = NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") && !$0.isTerminated }
        ApplicationTermination.request(applications,selectedIDs:ids)
        // Retry only the captured instances: reopening an app after the deadline must not close it again.
        let finish: () -> Void = { [weak self] in
            guard let self = self else { return }
            let results = ApplicationTermination.results(for:selection,captured:applications)
            let closed = results.filter { $0.status == .closed }.count
            let failed = results.filter { $0.status == .failed }.count
            if failed > 0 { self.record("已关闭 %@ 个，%@ 个未能关闭",arguments:[String(closed),String(failed)],results:results) }
            else if closed > 0 { self.record("已关闭 %@ 个应用",arguments:[String(closed)],results:results) }
            else { self.record("所选应用均未运行",results:results) }
        }
        if applications.isEmpty { finish(); return }
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            let remaining = applications.filter { !$0.isTerminated }
            if remaining.isEmpty { finish() }
            else {
                ApplicationTermination.request(remaining,selectedIDs:ids)
                DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:finish)
            }
        }
    }

    func refreshLabels() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        loginEnabled = SMAppService.mainApp.status == .enabled
        let formatter = DateFormatter()
        formatter.locale = resolvedLanguage.locale
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        let reference = state.nextDue ?? state.configuration.next(after: Date())
        localTime = formatter.string(from: reference)
        nextTime = formatter.string(from: reference)
        formatter.dateFormat = L10n.dateFormat("M月d日 EEEE",language:resolvedLanguage)
        nextDate = formatter.string(from: reference)
    }

    var timeZoneLabel: String { TimeZone.current.identifier }
    var referenceDate: Date { state.nextDue ?? state.configuration.next(after:Date()) }
    func formatted(_ date: Date, zone: String, format: String) -> String {
        let f = DateFormatter(); f.locale = resolvedLanguage.locale
        f.timeZone = TimeZone(identifier:zone); f.dateFormat = L10n.dateFormat(format,language:resolvedLanguage)
        return f.string(from:date)
    }
    var scheduleZoneDetail: String {
        formatted(referenceDate,zone:state.configuration.timeZoneID,format:"zzz '·' 'UTC'xxx")
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func setAppearance(_ value: String) {
        appearance = value
        if !preview { defaults.set(value,forKey:"appearance") }
    }
    func setGlassBackground(_ value: Bool) {
        glassBackground = value
        if !preview { defaults.set(value,forKey:"glassBackground") }
    }
    func setLanguage(_ value: AppLanguage) {
        language = value; resolvedLanguage = value.resolved()
        if !preview { defaults.set(value.rawValue,forKey:"language") }
        refreshLabels()
    }
    func translate(_ key: String, arguments: [String] = []) -> String {
        let format = L10n.text(key,language:resolvedLanguage)
        return arguments.isEmpty ? format : String(format:format,locale:resolvedLanguage.locale,arguments:arguments)
    }
    var loginMessage: String? {
        if let error = loginError { return translate("登录启动设置失败：%@",arguments:[error]) }
        return loginNeedsApproval ? translate("请在系统设置的登录项中允许启动") : nil
    }
    var lastRunText: String {
        guard let date = lastRun else { return "" }
        let f = DateFormatter(); f.locale = resolvedLanguage.locale; f.timeZone = .current; f.dateFormat = L10n.dateFormat("M月d日 HH:mm",language:resolvedLanguage)
        return f.string(from: date)
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginError = nil
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        } catch { loginError = error.localizedDescription }
        refreshLabels()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: TimerModel!
    private var screenObserver: NSObjectProtocol?
    private var languageSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    private var localPanelMonitor: Any?
    private var globalPanelMonitor: Any?
    private var panelActivationObserver: NSObjectProtocol?
    private var panelResignObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let preview = CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--ui-check") || CommandLine.arguments.contains("--focus-check")
        if preview { NSApp.appearance = NSAppearance(named:CommandLine.arguments.contains("--preview-dark") ? .darkAqua : .aqua) }
        model = TimerModel(preview:preview)
        model.updates.start()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource:"EsaiStatusTemplate",withExtension:"pdf"), let image = NSImage(contentsOf:url) {
            image.size = NSSize(width:18,height:18); image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = model.translate("esai · 定时关闭应用")
        languageSubscription = model.$resolvedLanguage.sink { [weak self] language in
            self?.statusItem.button?.toolTip = L10n.text("esai · 定时关闭应用",language:language)
        }
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePanel)
        popover = NSPopover(); popover.behavior = .applicationDefined; popover.delegate = self; popover.animates = false
        popover.contentViewController = PanelHostController(model:model)
        appearanceSubscription = model.$appearance.removeDuplicates().sink { [weak self] preference in
            self?.applyAppearance(preference)
        }
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self = self,self.popover.isShown else { return }
            self.fitPopoverToScreen()
            self.keepPopoverOnScreen()
        }
        if CommandLine.arguments.contains("--focus-check") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
                self.togglePanel()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                    let key = self.popover.contentViewController?.view.window?.isKeyWindow == true
                    let active = NSApp.isActive
                    let expected: NSAppearance.Name = CommandLine.arguments.contains("--preview-dark") ? .darkAqua : .aqua
                    let nativeAppearance = self.popover.contentViewController?.view.window?.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua])
                    let matchingAppearance = nativeAppearance == expected
                    print("FOCUS_CHECK active=\(active) key=\(key) shown=\(self.popover.isShown) appearance=\(nativeAppearance?.rawValue ?? "nil")")
                    guard active && key && self.popover.isShown && matchingAppearance else { exit(2) }
                    NSApp.terminate(nil)
                }
            }
        } else if CommandLine.arguments.contains("--ui-check") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { self.runUICheck() }
        } else if preview {
            showPreview()
        } else if CommandLine.arguments.contains("--show-panel") || !UserDefaults.standard.bool(forKey:"hasLaunched") {
            UserDefaults.standard.set(true,forKey:"hasLaunched")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { self.togglePanel() }
        }
    }

    private func applyAppearance(_ preference: String) {
        let appearance: NSAppearance?
        switch preference {
        case "dark": appearance = NSAppearance(named:.darkAqua)
        case "light": appearance = NSAppearance(named:.aqua)
        default: appearance = nil // Inherit live system appearance; never pin a snapshot.
        }
        NSApp.appearance = appearance
        popover.appearance = appearance
        if let host = popover.contentViewController, host.isViewLoaded {
            host.view.appearance = appearance
            host.view.window?.appearance = appearance
        }
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            model.refreshLabels()
            fitPopoverToScreen()
            applyAppearance(model.appearance)
            // Activate before showing so the first material frame is active.
            NSApp.activate(ignoringOtherApps:true)
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
            focusPanel()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.popover.isShown else { return }
                self.keepPopoverOnScreen()
                self.focusPanel()
            }
        }
    }

    private func focusPanel() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        window.orderFront(nil)
    }

    func popoverDidShow(_ notification: Notification) {
        focusPanel()
        stopPanelMonitors()
        // applicationDefined avoids transient dismissal racing with makeKey or
        // the second status-button click. Own only outside-click / Escape dismissal.
        localPanelMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.performClose(nil); return nil }
                return event
            }
            guard let window = self.popover.contentViewController?.view.window else { return event }
            if event.window === window || event.window === self.statusItem.button?.window || event.window?.sheetParent === window { return event }
            // Native menus and color panels remain interactive above the popover.
            if let other = event.window, other is NSPanel || other.level > .normal { return event }
            self.popover.performClose(nil)
            return event
        }
        globalPanelMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        panelActivationObserver = NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:NSApp,queue:.main) { [weak self] _ in
            self?.focusPanel()
        }
        panelResignObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) { stopPanelMonitors() }

    private func stopPanelMonitors() {
        if let monitor = localPanelMonitor { NSEvent.removeMonitor(monitor); localPanelMonitor = nil }
        if let monitor = globalPanelMonitor { NSEvent.removeMonitor(monitor); globalPanelMonitor = nil }
        if let observer = panelActivationObserver { NotificationCenter.default.removeObserver(observer); panelActivationObserver = nil }
        if let observer = panelResignObserver { NotificationCenter.default.removeObserver(observer); panelResignObserver = nil }
    }

    private func fitPopoverToScreen() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        guard let screen = screen else { return }
        var available = screen.visibleFrame.size
        if let button = statusItem.button,let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds,to:nil))
            available.height = min(available.height,anchor.minY-screen.visibleFrame.minY)
        }
        let size = PopoverLayout.size(available:available)
        model.panelSize = size
        popover.contentViewController?.preferredContentSize = size
        popover.contentSize = size
    }

    private func keepPopoverOnScreen() {
        guard let window = popover.contentViewController?.view.window,
              let button = statusItem.button,let statusWindow = button.window,
              let screen = statusWindow.screen ?? NSScreen.main else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds,to:nil))
        let origin = PopoverLayout.anchoredOrigin(for:window.frame,inside:screen.visibleFrame,anchor:anchor)
        if origin != window.frame.origin { window.setFrameOrigin(origin) }
        let view = popover.contentViewController!.view
        let content = window.convertToScreen(view.convert(view.bounds,to:nil))
        if CommandLine.arguments.contains("--ui-check"), !screen.visibleFrame.contains(content) {
            fputs("UI_CHECK_FAIL offscreen content\n",stderr); exit(2)
        }
        let report = "windowNumber=\(window.windowNumber) window=\(window.frame) visible=\(screen.visibleFrame) anchor=\(anchor) contentFrame=\(content) contentContained=\(screen.visibleFrame.contains(content)) arrowGap=\(anchor.minY-window.frame.maxY) content=\(popover.contentSize)\n"
        let folder = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("com.esai.wechat-timer")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try? report.write(to:folder.appendingPathComponent("panel-layout.txt"),atomically:true,encoding:.utf8)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePanel() }; return false
    }

    // Exercise the actual menu-bar popover with an isolated, inactive scheduler.
    private func runUICheck(step: Int = 0) {
        if step == 0 {
            model.setApplication(.init(bundleID:"com.apple.Safari",name:"Safari",path:nil),selected:true)
            model.setApplication(.init(bundleID:"com.apple.Music",name:"Music",path:nil),selected:true)
            model.setEnabled(true)
            togglePanel()
        }
        guard step < 240 else {
            print("UI_CHECK_PASS 240 transitions; 23 reopen cycles; multi-app and empty selection; fixed popover bounds")
            NSApp.terminate(nil); return
        }
        if step % 10 == 0 && step > 0 { popover.performClose(nil); togglePanel() }
        model.navigation.showingSettings = step % 5 != 4
        model.navigation.settingsTab = ["schedule","appearance","apps","general"][step % 4]
        if step % 12 == 0 { model.setLanguage(step % 24 == 0 ? .english : .chinese) }
        if step % 20 == 0 { model.setAppearance(step % 40 == 0 ? "dark" : "light") }
        if step == 100 {
            for app in model.selectedApplications { model.setApplication(app,selected:false) }
            precondition(!model.state.enabled && model.state.nextDue == nil)
            model.setEnabled(true)
            precondition(!model.state.enabled)
        }
        if step == 120 { model.setApplication(.weChat,selected:true); model.setEnabled(true) }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.08) {
            self.popover.contentViewController?.view.layoutSubtreeIfNeeded()
            guard self.popover.contentSize == self.model.panelSize, self.popover.isShown else {
                fputs("UI_CHECK_FAIL step=\(step) shown=\(self.popover.isShown) actual=\(self.popover.contentSize) expected=\(self.model.panelSize)\n",stderr); exit(2)
            }
            self.keepPopoverOnScreen()
            if step % 40 == 0 {
                print("UI_CHECK_PROGRESS \(step) bounds=\(self.popover.contentSize)")
                fflush(stdout)
            }
            self.runUICheck(step:step+1)
        }
    }

    private func showPreview() {
        let controller = PanelHostController(model:model,initialSettings:CommandLine.arguments.contains("--preview-settings"))
        let view = controller.view
        let size = model.panelSize
        view.frame = NSRect(origin:.zero,size:size)
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = model.translate("esai · 界面预览（未启用）"); window.contentViewController = controller
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let previewInfo = "PREVIEW_WINDOW \(window.windowNumber)\n"
        FileHandle.standardOutput.write(Data(previewInfo.utf8))
        let delay = min(5,max(0.7,Double(ProcessInfo.processInfo.environment["ESAI_PREVIEW_LINGER"] ?? "0.7") ?? 0.7))
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
            view.cacheDisplay(in:view.bounds,to:rep)
            if let path = ProcessInfo.processInfo.environment["ESAI_PREVIEW_PATH"], let data = rep.representation(using:.png,properties:[:]) {
                try? data.write(to:URL(fileURLWithPath:path))
            }
            NSApp.terminate(nil)
        }
    }
}

@main struct EsaiTimerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

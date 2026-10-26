import AppKit
import SwiftUI

struct TimerPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: TimerModel
    @ObservedObject private var navigation: PanelNavigation
    @State private var appSearch = ""
    @State private var draftSchedule: DailySchedule
    @State private var customHex: String
    @State private var hexError = false
    @State private var scheduleSaved = false
    private var accent: Color { model.accentColor }
    private func t(_ key: String, _ arguments: String...) -> String { model.translate(key,arguments:arguments) }
    init(model:TimerModel,initialSettings:Bool=false) {
        self.model = model
        navigation = model.navigation
        _draftSchedule = State(initialValue:model.state.configuration)
        _customHex = State(initialValue:model.accentHex)
    }

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            header.padding(.horizontal,16).padding(.top,14).padding(.bottom,12)
            EsaiHairline()
            if navigation.showingSettings {
                settingsTabs.padding(.horizontal,16).padding(.top,12).padding(.bottom,4)
            }
            ScrollView(.vertical) {
                Group {
                    if navigation.showingSettings { settingsContent.padding(.vertical,16) }
                    else { dashboard }
                }
                .padding(.horizontal,16)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(EsaiScrollChrome().allowsHitTesting(false))
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            EsaiHairline()
            footer
        }
        .frame(width:model.panelSize.width,height:model.panelSize.height,alignment:.topLeading)
        .background {
            // NSPopover supplies the native material, including its arrow.
            if !model.glassBackground || reduceTransparency { EsaiSurface.panel }
        }
        .tint(accent)
        .preferredColorScheme(model.colorScheme)
        .environment(\.locale,model.resolvedLanguage.locale)
    }

    private var header: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:8) {
                if navigation.showingSettings {
                    EsaiDetailBackButton(title:t("返回")) { navigation.showingSettings = false }
                    Text(t("设置")).font(.title3.weight(.semibold))
                } else {
                    if let url = Bundle.main.url(forResource:"EsaiStatusTemplate",withExtension:"pdf"),let image = NSImage(contentsOf:url) {
                        Image(nsImage:image).resizable().renderingMode(.template)
                            .foregroundStyle(accent).frame(width:19,height:19)
                    }
                    Text("esai").font(.title3.weight(.semibold))
                    Text(model.targetSummary).font(.callout.weight(.medium)).lineLimit(1)
                        .padding(.horizontal,10).padding(.vertical,5)
                        .background(EsaiSurface.raised,in:RoundedRectangle(cornerRadius:6,style:.continuous))
                }
                Spacer(minLength:8)
                EsaiHeaderActionButton(title:t("刷新状态"),action:{model.tick()}) { Image(systemName:"arrow.clockwise") }
            }
            if !navigation.showingSettings {
                HStack(spacing:7) {
                    Text(t(model.state.enabled ? "已启用" : "未启用"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.state.enabled ? accent : Color.secondary)
                        .padding(.horizontal,7).padding(.vertical,3)
                        .background(model.state.enabled ? accent.opacity(0.12) : EsaiSurface.sunken,in:Capsule())
                    Text(t(model.isWeChatOnly ? "定时关闭微信" : "定时关闭应用")).font(.callout.weight(.semibold)).foregroundStyle(accent)
                    Spacer()
                }
                HStack(spacing:5) {
                    Image(systemName:"clock").foregroundStyle(accent)
                    Text(t("每天 %@ %@",model.state.configuration.timeText,t(model.state.configuration.zone.shortTitle))).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(t("本地 %@",model.localTime)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal,6).padding(.vertical,3)
                .background(accent.opacity(0.04),in:RoundedRectangle(cornerRadius:5))
                .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(accent.opacity(0.24),lineWidth:1))
            }
        }
        .fixedSize(horizontal:false,vertical:true)
    }

    private func sectionTitle(_ title:String,_ symbol:String) -> some View {
        HStack(spacing:6) {
            Text(t(title)).font(.headline)
            Spacer()
        }
    }

    private var dashboard: some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Button { openSettings("schedule") } label: {
                        HStack(spacing:5) { Text(t("关闭计划")).font(.headline); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).help(t("修改关闭时间"))
                    Spacer()
                    Toggle(t("启用"),isOn:Binding(get:{model.state.enabled},set:{model.setEnabled($0)}))
                        .toggleStyle(.switch).controlSize(.mini).font(.caption.weight(.medium))
                        .accessibilityLabel(t("启用定时关闭应用")).fixedSize().disabled(model.selectedApplications.isEmpty)
                }
                VStack(alignment:.leading,spacing:6) {
                    HStack {
                        Text(t("每日")).font(.callout.weight(.semibold))
                        Spacer(minLength:8)
                        Text(model.state.enabled ? t("%@后关闭",countdown) : t("等待启用"))
                            .font(.callout.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(model.state.enabled ? accent : Color.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment:.leading) {
                            Capsule().fill(EsaiSurface.sunken)
                            if model.state.enabled {
                                Capsule().fill(LinearGradient(colors:[accent,accent.opacity(0.65)],startPoint:.leading,endPoint:.trailing))
                                    .frame(width:max(4,proxy.size.width*progress))
                            }
                        }
                    }.frame(height:5)
                    HStack(alignment:.firstTextBaseline) {
                        Text(t("到点强制关闭所选应用"))
                        Spacer(minLength:4)
                        Text(model.state.enabled ? t("下次：%@ %@",model.nextDate,model.nextTime) : t("勾选后开始每日调度"))
                            .multilineTextAlignment(.trailing)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top,16).padding(.bottom,18)
            EsaiHairline()
            VStack(alignment:.leading,spacing:10) {
                sectionTitle("时间换算", "globe")
                HStack(alignment:.firstTextBaseline) {
                    VStack(alignment:.leading,spacing:3) {
                        Text("\(t(model.state.configuration.zone.shortTitle)) · \(model.scheduleZoneDetail)").font(.caption).foregroundStyle(.secondary)
                        Text(model.formatted(model.referenceDate,zone:model.state.configuration.timeZoneID,format:"HH:mm")).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName:"arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    VStack(alignment:.trailing,spacing:3) {
                        Text(t("本机时间")).font(.caption).foregroundStyle(.secondary)
                        Text(model.localTime).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit()
                            .foregroundStyle(accent)
                    }
                }
                Text(t("%@ · 日期按本机时区显示",model.timeZoneLabel))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(.vertical,16)
            EsaiHairline()
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text(t("应用运行状态")).font(.headline)
                    Spacer()
                    Button(t("管理应用")) { openSettings("apps") }.buttonStyle(.plain).font(.caption).foregroundStyle(accent)
                }
                VStack(alignment:.leading,spacing:9) {
                    if model.selectedApplications.isEmpty {
                        Text(t("未选择应用")).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.selectedApplications) { application in
                        HStack {
                            appIcon(application).frame(width:20,height:20)
                            Text(model.applicationName(application)).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            let running = model.runningIDs.contains(application.id)
                            Circle().fill(running ? accent : Color.secondary.opacity(0.5)).frame(width:5,height:5)
                            Text(t(running ? "运行中" : "未运行")).font(.caption).foregroundStyle(running ? accent : Color.secondary)
                        }
                    }
                    EsaiHairline()
                    Text(t("上次：%@%@",model.lastResultText,model.lastRunText.isEmpty ? "" : " · " + model.lastRunText))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if !model.applicationResults.isEmpty {
                        DisclosureGroup(t("执行详情")) {
                            ForEach(model.applicationResults) { result in
                                HStack {
                                    Text(result.bundleID == WeChatIdentity.bundleID ? t("微信") : result.name).lineLimit(1)
                                    Spacer()
                                    Text(t(result.status.title)).foregroundStyle(result.status == .failed ? Color.orange : Color.secondary)
                                }.font(.caption).padding(.top,3)
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard()
                Text(t("睡眠错过时，唤醒后补执行当天任务。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top,16).padding(.bottom,16)
        }
    }

    private var countdown: String {
        guard model.state.enabled,let date = model.state.nextDue else { return t("等待启用") }
        let minutes = max(0,Int(ceil(date.timeIntervalSinceNow/60)))
        if minutes < 60 { return t("%@ 分钟",String(minutes)) }
        return t("%@ 小时 %@ 分钟",String(minutes/60),String(minutes%60))
    }
    private var progress: Double {
        guard let next = model.state.nextDue else { return 0 }
        let duration = model.state.configuration.cycleDuration(ending:next)
        return min(1,max(0,1-next.timeIntervalSinceNow/max(1,duration)))
    }

    private func statusRow(_ title:String,value:String,symbol:String,active:Bool=false) -> some View {
        HStack(spacing:8) {
            Image(systemName:symbol).font(.caption).foregroundStyle(.secondary).frame(width:14)
            Text(t(title)).font(.caption)
            Spacer()
            if active { Circle().fill(accent).frame(width:5,height:5) }
            Text(value).font(.caption.weight(.medium)).foregroundStyle(active ? accent : Color.secondary)
        }.padding(.horizontal,10).padding(.vertical,9)
    }

    private var settingsTabs: some View {
        EsaiGlassSegments(selection:$navigation.settingsTab,options:[
                .init(id:"schedule",title:t("计划")),
                .init(id:"apps",title:t("关闭应用")),
                .init(id:"appearance",title:t("外观")),
                .init(id:"general",title:t("通用"))
            ],accent:accent,label:t("设置"))
    }

    private var settingsContent: some View {
        VStack(alignment:.leading,spacing:18) {
            Group {
                if navigation.settingsTab == "schedule" { scheduleEditor }
                else if navigation.settingsTab == "appearance" { appearanceEditor }
                else if navigation.settingsTab == "apps" { applicationsEditor }
                else { generalSettings }
            }
            .animation(nil,value:navigation.settingsTab)
        }
        .onChange(of:model.accentHex) { customHex = $0; hexError = false }
        .onChange(of:draftSchedule) { _ in scheduleSaved = false }
    }

    private var scheduleEditor: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:4) {
                Text(t("关闭时间")).font(.headline)
                Text(t("每天按所选地区的时间，强制关闭所有已选应用。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text(t("每天")).font(.callout.weight(.medium))
                    Spacer()
                    HStack(spacing:8) {
                        EsaiAlignedMenu(selection:String(draftSchedule.hour),choices:(0..<24).map {
                            .init(id:String($0),title:String(format:"%02d",$0))
                        },label:t("关闭时间的小时"),accent:accent,centered:true) {
                            if let value = Int($0) { draftSchedule.hour = value }
                        }.frame(width:78,height:30).esaiGlassControl()
                        Text(":").font(.callout).foregroundStyle(.secondary).frame(width:8)
                        EsaiAlignedMenu(selection:String(draftSchedule.minute),choices:(0..<60).map {
                            .init(id:String($0),title:String(format:"%02d",$0))
                        },label:t("关闭时间的分钟"),accent:accent,centered:true) {
                            if let value = Int($0) { draftSchedule.minute = value }
                        }.frame(width:78,height:30).esaiGlassControl()
                    }.frame(width:180)
                }
                EsaiHairline()
                HStack(spacing:12) {
                    Text(t("时区")).font(.callout.weight(.medium))
                    Spacer()
                    EsaiAlignedMenu(selection:draftSchedule.timeZoneID,choices:ScheduleZone.choices.map {
                        .init(id:$0.id,title:scheduleZoneLabel($0))
                    },label:t("时区"),accent:accent) { draftSchedule.timeZoneID = $0 }
                        .frame(width:180,height:30).esaiGlassControl()
                }
                Text(t(draftSchedule.zone.followsDST ? "随该地区切换夏令时，设定的当地时间保持不变。" : "该时区不切换夏令时，全年按设定时间执行。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(12).esaiCard()
            HStack {
                Text(t("关闭应用")).font(.caption).foregroundStyle(.secondary)
                Text(model.targetSummary).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Button(t("管理应用")) { navigation.settingsTab = "apps" }.esaiGlassButton().font(.caption)
            }
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Image(systemName:"clock.arrow.circlepath").foregroundStyle(accent)
                    Text(t(draftSchedule == model.state.configuration ? (model.state.enabled ? "下一次关闭" : "启用后的首次关闭") : "保存后的执行预览"))
                        .font(.caption.weight(.semibold))
                }
                Text(model.formatted(draftNextDate,zone:draftSchedule.timeZoneID,format:"M月d日 EEEE HH:mm"))
                    .font(.callout.weight(.semibold)).foregroundStyle(accent)
                HStack(alignment:.top) {
                    Text("\(t(draftSchedule.zone.shortTitle)) · \(model.formatted(draftNextDate,zone:draftSchedule.timeZoneID,format:"zzz"))")
                    Spacer()
                    Text(t("本机 %@\nUTC %@",model.formatted(draftNextDate,zone:TimeZone.current.identifier,format:"M月d日 HH:mm"),model.formatted(draftNextDate,zone:"UTC",format:"M月d日 HH:mm")))
                        .multilineTextAlignment(.trailing).monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).esaiCard(.sunken)
            HStack(spacing:10) {
                Text(t(scheduleSaved ? "已保存" : draftSchedule == model.state.configuration ? "当前计划已保存" : "尚未保存"))
                    .font(.caption).foregroundStyle(scheduleSaved ? accent : Color.secondary)
                Spacer()
                Button(t("保存时间")) { model.saveSchedule(draftSchedule); scheduleSaved = true }
                    .esaiGlassButton(prominent:true)
                    .disabled(draftSchedule == model.state.configuration)
            }
            DisclosureGroup(t("执行规则")) {
                VStack(alignment:.leading,spacing:9) {
                    settingsRule("睡眠后补执行","按所选时区的日期，仅补执行当天已到期任务。")
                    settingsRule("夏令时特殊时刻","不存在的时间顺延一小时，例如 02:30 → 03:30；重复的时间只执行一次。")
                    settingsRule("保存后重新排期","只预约未来时间；当天已执行过的任务不会因修改时间重复执行。")
                }.padding(.top,8)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scheduleZoneLabel(_ zone:ScheduleZone) -> String {
        guard model.resolvedLanguage == .english else { return t(zone.title) }
        // Short names keep the control and its menu compact in both languages.
        let labels = ["UTC":"UTC · Universal time", "America/Los_Angeles":"Pacific · Los Angeles",
            "America/New_York":"Eastern · New York", "Europe/London":"London · UK",
            "Asia/Shanghai":"Beijing · China", "Asia/Tokyo":"Tokyo · Japan"]
        return labels[zone.id] ?? t(zone.title)
    }

    private var draftNextDate: Date {
        var state = model.state
        state.setConfiguration(draftSchedule,now:Date())
        if !state.enabled { state.setEnabled(true,now:Date()) }
        return state.nextDue ?? draftSchedule.next(after:Date())
    }

    private var appearanceEditor: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text(t("外观模式")).font(.headline)
                EsaiGlassSegments(selection:Binding(get:{model.appearance},set:{model.setAppearance($0)}),options:[
                    .init(id:"system",title:t("跟随系统")),
                    .init(id:"light",title:t("浅色")),
                    .init(id:"dark",title:t("深色"))
                ],accent:accent,label:t("外观模式"))
            }
            VStack(alignment:.leading,spacing:8) {
                EsaiSwitchRow(title:t("透明玻璃背景"),isOn:Binding(get:{model.glassBackground},set:{model.setGlassBackground($0)}))
                Text(t("面板会透出桌面背景；关闭后使用实色面板。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            .padding(12)
            .esaiCard(.sunken)
            EsaiHairline()
            VStack(alignment:.leading,spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text(t("强调色")).font(.headline)
                    Text(t("选择经典颜色，或调出属于你的 esai。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:6),spacing:8) {
                    ForEach(AccentPreset.choices) { preset in
                        Button { model.setAccent(preset.hex) } label: {
                            VStack(spacing:6) {
                                let rgb = AccentRGB(hex:preset.hex)!
                                Circle().fill(Color(red:rgb.red,green:rgb.green,blue:rgb.blue))
                                    .frame(width:29,height:29)
                                    .overlay {
                                        if model.accentHex == preset.hex {
                                            Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(model.accentHex == preset.hex ? accent : Color.clear,lineWidth:1.5))
                                Text(t(preset.name)).font(.system(size:10)).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity)
                        }.buttonStyle(.plain).help(t(preset.name))
                            .accessibilityLabel(t(preset.name)).accessibilityAddTraits(model.accentHex == preset.hex ? .isSelected : [])
                    }
                }
                HStack {
                    ColorPicker(t("自定义颜色"),selection:Binding(get:{model.selectedAccent},set:{model.setAccentColor($0)}),supportsOpacity:false)
                        .font(.caption).accessibilityLabel(t("自定义强调色取色器"))
                    Spacer(minLength:8)
                    TextField("#RRGGBB",text:$customHex)
                        .font(.system(size:11,design:.monospaced)).textFieldStyle(.plain)
                        .padding(.horizontal,10).frame(width:86,height:30)
                        .background(EsaiSurface.sunken,in:Capsule())
                        .onSubmit { applyCustomHex() }.accessibilityLabel(t("强调色 HEX 色值"))
                    Button(t("应用")) { applyCustomHex() }.font(.caption).esaiGlassButton()
                }
                if hexError { Text(t("请输入六位 HEX 色值，例如 #2878ED。")).font(.caption).foregroundStyle(.red) }
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Label(t("强调色预览"),systemImage:"checkmark.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(accent)
                        Spacer()
                        Text(t("已启用")).font(.caption.weight(.medium)).foregroundStyle(accent)
                            .padding(.horizontal,8).padding(.vertical,4).background(accent.opacity(0.12),in:Capsule())
                    }
                    Capsule().fill(accent).frame(height:5)
                    Text(t("实时应用并保存；浅色和深色模式自动调整可读性。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(12).esaiCard(.sunken)
            }
        }
    }

    private func applyCustomHex() {
        guard AccentRGB(hex:customHex) != nil else { hexError = true; return }
        model.setAccent(customHex); customHex = model.accentHex; hexError = false
    }

    private var generalSettings: some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(alignment:.leading,spacing:10) {
                Text(t("语言")).font(.headline)
                EsaiAlignedMenu(selection:model.language.rawValue,choices:AppLanguage.allCases.map {
                    .init(id:$0.rawValue,title:$0 == .system ? t("跟随系统") : $0.nativeName)
                },label:t("界面语言"),accent:accent) {
                    if let language = AppLanguage(rawValue:$0) { model.setLanguage(language) }
                }.frame(height:34).esaiGlassControl()
                Text(t("跟随系统会自动使用电脑的首选语言，切换立即生效。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text(t("当前语言：%@",model.resolvedLanguage.nativeName)).font(.caption).foregroundStyle(.secondary)
            }
            EsaiHairline()
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Text(t("通用")).font(.headline)
                    Spacer()
                    UpdateCheckButton(service:model.updates,language:model.resolvedLanguage)
                }
                VStack(alignment:.leading,spacing:12) {
                    EsaiSwitchRow(title:t("登录时启动"),isOn:Binding(get:{model.loginEnabled},set:{ if $0 != model.loginEnabled {model.toggleLogin()} }))
                    if let message = model.loginMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                        Button(t("打开登录项设置")) { model.openLoginSettings() }.font(.caption).esaiGlassButton()
                    }
                    EsaiHairline()
                    UpdateSettings(service:model.updates,language:model.resolvedLanguage)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).esaiCard()
            }
            settingsRule("保持应用运行","退出应用会暂停调度。取消勾选可立即停用。")
            EsaiHairline()
            HStack(spacing:8) {
                if let image = NSImage(named:"AppIcon") { Image(nsImage:image).resizable().frame(width:36,height:36) }
                VStack(alignment:.leading,spacing:2) {
                    Text(t("esai 定时关闭")).font(.callout.weight(.medium))
                    Text(t("版本 %@",Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.0")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("开源许可")) {
                    if let url = Bundle.main.url(forResource:"THIRD_PARTY_NOTICES",withExtension:"md") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsRule(_ title:String,_ detail:String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(t(title)).font(.caption.weight(.medium))
            Text(t(detail)).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private func openSettings(_ tab: String) {
        model.refreshLabels()
        draftSchedule = model.state.configuration
        navigation.settingsTab = tab
        navigation.showingSettings = true
    }
    private func appIcon(_ application: SelectedApplication) -> some View {
        let path = application.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier:application.bundleID)?.path
        let image = path.map { NSWorkspace.shared.icon(forFile:$0) } ?? NSImage(named:NSImage.applicationIconName)!
        return Image(nsImage:image).resizable().aspectRatio(contentMode:.fit)
    }
    private var catalog: [SelectedApplication] {
        let apps = SelectedApplication.normalized(model.selectedApplications + model.availableApplications)
        return apps.filter { appSearch.isEmpty || model.applicationName($0).localizedCaseInsensitiveContains(appSearch) || $0.bundleID.localizedCaseInsensitiveContains(appSearch) }
            .sorted { first, second in
                let left = model.selectedApplications.contains(where: { $0.id == first.id })
                let right = model.selectedApplications.contains(where: { $0.id == second.id })
                if left != right { return left }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
    }
    private var applicationsEditor: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:4) {
                Text(t("关闭应用")).font(.headline)
                Text(t("所选应用将按同一时间关闭。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing:8) {
                Image(systemName:"magnifyingglass").font(.callout).foregroundStyle(.secondary)
                TextField(t("搜索应用"),text:$appSearch).textFieldStyle(.plain).font(.callout)
                    .accessibilityLabel(t("搜索应用"))
                if !appSearch.isEmpty {
                    Button { appSearch = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel(t("清除搜索"))
                }
            }.padding(.horizontal,12).frame(height:34)
                .background(EsaiSurface.sunken,in:Capsule())
                .overlay(Capsule().strokeBorder(EsaiSurface.hairline.opacity(0.4),lineWidth:0.5))
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Text(t("已选择 %@ 个",String(model.selectedApplications.count)))
                        .font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Spacer()
                    Button { model.addApplications() } label: {
                        Label(t("添加应用…"),systemImage:"plus").font(.caption)
                    }.esaiGlassButton()
                }
                applicationList(catalog.filter { selected($0) },isSelected:true)
                if model.selectedApplications.isEmpty {
                    Text(t("请至少选择一个应用，再启用关闭计划。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = model.applicationError { Text(message).font(.caption).foregroundStyle(.orange) }
            let available = catalog.filter { !selected($0) }
            if !available.isEmpty {
                EsaiHairline()
                VStack(alignment:.leading,spacing:8) {
                    Text(t("其他应用")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    applicationList(available,isSelected:false)
                }
            }
            if catalog.isEmpty { Text(t("未找到应用，可从其他位置添加。")).font(.caption).foregroundStyle(.secondary) }
            Text(t("选择即保存，可同时关闭多个应用。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func selected(_ application: SelectedApplication) -> Bool {
        model.selectedApplications.contains { $0.id == application.id }
    }
    private func applicationList(_ applications:[SelectedApplication],isSelected:Bool) -> some View {
        LazyVStack(spacing:0) {
            ForEach(Array(applications.enumerated()),id:\.element.id) { index, application in
                Button { model.setApplication(application,selected:!isSelected) } label: {
                    HStack(spacing:10) {
                        appIcon(application).frame(width:26,height:26)
                        Text(model.applicationName(application)).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength:6)
                        if model.runningIDs.contains(application.id) {
                            Circle().fill(accent).frame(width:4,height:4)
                            Text(t("运行中")).font(.system(size:10)).foregroundStyle(.secondary)
                        }
                        Image(systemName:isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size:17,weight:.regular))
                            .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.6))
                    }.padding(.horizontal,12).frame(height:46).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(model.applicationName(application))
                    .accessibilityValue(t(isSelected ? "已选择" : "未选择"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                if index < applications.count-1 { EsaiHairline().padding(.leading,48) }
            }
        }.esaiCard(.sunken)
    }

    private var footer: some View {
        HStack {
            if !navigation.showingSettings {
                EsaiFooterGhostButton(title:t("设置"),systemImage:"slider.horizontal.3",role:.normal,help:t("打开设置")) {
                    openSettings("schedule")
                }
            } else {
                Text("esai").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
            }
            Spacer()
            EsaiFooterGhostButton(title:t("退出"),systemImage:"power",role:.destructive,help:t("退出 esai，暂停定时任务")) { NSApp.terminate(nil) }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
}

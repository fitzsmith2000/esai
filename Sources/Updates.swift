import AppKit
import SwiftUI
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement and relaunch.
/// Preview/test instances never start a scheduler or read/write real preferences.
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var automaticChecks: Bool
    @Published private(set) var automaticInstallation: Bool
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var errorMessage: String?
    let enabled: Bool
    private let defaults: UserDefaults
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    init(enabled: Bool, defaults: UserDefaults = .standard) {
        self.enabled = enabled
        self.defaults = defaults
        automaticChecks = enabled ? (defaults.object(forKey:"SUEnableAutomaticChecks") as? Bool ?? true) : true
        automaticInstallation = enabled ? (defaults.object(forKey:"SUAutomaticallyUpdate") as? Bool ?? false) : false
        super.init()
    }

    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        self.controller = controller
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = automaticChecks
        updater.automaticallyDownloadsUpdates = automaticInstallation
        updater.updateCheckInterval = 3_600
        observations = [
            updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.automaticChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.automaticInstallation = updater.automaticallyDownloadsUpdates }
            },
            updater.observe(\.lastUpdateCheckDate,options:[.initial,.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.lastCheck = updater.lastUpdateCheckDate }
            }
        ]
        do { try updater.start() }
        catch { errorMessage = error.localizedDescription }
    }

    func checkForUpdates() {
        guard enabled, canCheck else { return }
        errorMessage = nil
        NSApp.activate(ignoringOtherApps:true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ value: Bool) {
        guard enabled else { return }
        automaticChecks = value
        controller?.updater.automaticallyChecksForUpdates = value
        defaults.set(value,forKey:"SUEnableAutomaticChecks")
    }

    func setAutomaticInstallation(_ value: Bool) {
        guard enabled else { return }
        automaticInstallation = value
        controller?.updater.automaticallyDownloadsUpdates = value
        defaults.set(value,forKey:"SUAutomaticallyUpdate")
        // Automatic installation requires scheduled checks. Turning scheduled
        // checks off later pauses background activity without changing this choice.
        if value { setAutomaticChecks(true) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // 'No update available' is a successful check, not a transport failure.
        if let error = error as NSError?, !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) {
            errorMessage = error.localizedDescription
        } else { errorMessage = nil }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
}

struct UpdateSettings: View {
    @ObservedObject var service: UpdateService
    let language: AppLanguage
    private func t(_ key: String) -> String { L10n.text(key,language:language) }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(t("软件更新")).font(.headline)
                Spacer()
                Button(t("检查更新…")) { service.checkForUpdates() }
                    .font(.caption).esaiGlassButton().disabled(!service.canCheck)
            }
            VStack(alignment:.leading,spacing:10) {
                Toggle(t("自动检查更新"),isOn:Binding(get:{service.automaticChecks},set:{service.setAutomaticChecks($0)}))
                    .toggleStyle(.switch).controlSize(.small).font(.callout)
                Toggle(t("自动下载并安装更新"),isOn:Binding(get:{service.automaticInstallation},set:{service.setAutomaticInstallation($0)}))
                    .toggleStyle(.switch).controlSize(.small).font(.callout)
                Text(t("每小时检查一次。自动安装默认关闭；开启后后台下载，并在退出时安装，或提示重新启动。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !service.enabled {
                    Text(t("预览模式不检查或安装更新。")).font(.caption).foregroundStyle(.secondary)
                } else if let error = service.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                } else if let date = service.lastCheck {
                    HStack(spacing:4) {
                        Text(t("上次检查："))
                        Text(date,style:.date)
                        Text(date,style:.time)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(!service.enabled)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).esaiCard(.sunken)
    }
}

import AppKit
import SwiftUI
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement and relaunch.
/// Preview/test instances never start a scheduler or read/write real preferences.
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var automaticUpdates: Bool
    @Published private(set) var canCheck = false
    @Published private(set) var errorMessage: String?
    let enabled: Bool
    private let defaults: UserDefaults
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    init(enabled: Bool, defaults: UserDefaults = .standard) {
        self.enabled = enabled
        self.defaults = defaults
        // A single preference controls the complete background update flow.
        // Preserve an existing opt-in; checking-only preferences migrate to off.
        let checks = enabled && (defaults.object(forKey:"SUEnableAutomaticChecks") as? Bool ?? false)
        let installs = enabled && (defaults.object(forKey:"SUAutomaticallyUpdate") as? Bool ?? false)
        automaticUpdates = checks && installs
        super.init()
    }

    func start() {
        guard enabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        self.controller = controller
        let updater = controller.updater
        setAutomaticUpdates(automaticUpdates)
        updater.updateCheckInterval = 3_600
        observations = [
            updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.setAutomaticUpdates(updater.automaticallyChecksForUpdates) }
            },
            updater.observe(\.automaticallyDownloadsUpdates,options:[.new]) { [weak self] updater,_ in
                DispatchQueue.main.async { self?.setAutomaticUpdates(updater.automaticallyDownloadsUpdates) }
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

    func setAutomaticUpdates(_ value: Bool) {
        guard enabled else { return }
        if automaticUpdates != value { automaticUpdates = value }
        // Equality guards prevent KVO feedback when Sparkle's native window
        // changes its own update preference. Either entry controls both flags.
        if let updater = controller?.updater {
            if updater.automaticallyChecksForUpdates != value { updater.automaticallyChecksForUpdates = value }
            if updater.automaticallyDownloadsUpdates != value { updater.automaticallyDownloadsUpdates = value }
        }
        defaults.set(value,forKey:"SUEnableAutomaticChecks")
        defaults.set(value,forKey:"SUAutomaticallyUpdate")
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
    var body: some View {
        EsaiSwitchRow(title:L10n.text("自动更新",language:language),isOn:Binding(
            get:{service.automaticUpdates},set:{service.setAutomaticUpdates($0)}))
            .disabled(!service.enabled)
    }
}

struct UpdateCheckButton: View {
    @ObservedObject var service: UpdateService
    let language: AppLanguage
    var body: some View {
        Button(L10n.text("检查更新…",language:language)) { service.checkForUpdates() }
            .font(.caption).esaiGlassButton().disabled(!service.canCheck)
    }
}

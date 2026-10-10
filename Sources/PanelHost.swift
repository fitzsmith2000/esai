import AppKit
import SwiftUI

// AppKit owns the fixed popover size. SwiftUI must not negotiate new window constraints on tab changes.
final class PanelHostController: NSViewController {
    private let hosting: NSHostingView<TimerPanel>
    init(model: TimerModel, initialSettings: Bool = false) {
        if initialSettings { model.navigation.showingSettings = true }
        if CommandLine.arguments.contains("--preview-colors") { model.navigation.settingsTab = "appearance" }
        if CommandLine.arguments.contains("--preview-general") { model.navigation.settingsTab = "general" }
        if CommandLine.arguments.contains("--preview-apps") { model.navigation.settingsTab = "apps" }
        hosting = NSHostingView(rootView:TimerPanel(model:model,initialSettings:initialSettings))
        hosting.sizingOptions = []
        super.init(nibName:nil,bundle:nil)
        preferredContentSize = model.panelSize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame:NSRect(origin:.zero,size:preferredContentSize))
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width,.height]
        view.addSubview(hosting)
    }
}

final class PanelNavigation: ObservableObject {
    @Published var showingSettings = false
    @Published var settingsTab = "schedule"
}

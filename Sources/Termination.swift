import Foundation

protocol TerminationTarget: AnyObject {
    var bundleIdentifier: String? { get }
    var isTerminated: Bool { get }
    func forceTerminate() -> Bool
}

enum WeChatTermination {
    @discardableResult
    static func request(_ targets: [TerminationTarget]) -> [TerminationTarget] {
        let selected = targets.filter { WeChatIdentity.matches($0.bundleIdentifier) && !$0.isTerminated }
        selected.forEach { _ = $0.forceTerminate() }
        return selected
    }
}

enum ApplicationTermination {
    static func results(for selection: [SelectedApplication], captured: [TerminationTarget]) -> [ApplicationExecution] {
        selection.map { app in
            let instances = captured.filter { $0.bundleIdentifier == app.bundleID }
            let status: ApplicationExecution.Status = instances.isEmpty ? .notRunning : instances.allSatisfy { $0.isTerminated } ? .closed : .failed
            return ApplicationExecution(bundleID:app.bundleID,name:app.name,status:status)
        }
    }
    @discardableResult
    static func request(_ targets: [TerminationTarget], selectedIDs: Set<String>) -> [TerminationTarget] {
        let allowed = selectedIDs.subtracting([SelectedApplication.ownBundleID])
        var seen = Set<ObjectIdentifier>()
        let selected = targets.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return allowed.contains(id) && !$0.isTerminated && seen.insert(ObjectIdentifier($0)).inserted
        }
        selected.forEach { _ = $0.forceTerminate() }
        return selected
    }
}

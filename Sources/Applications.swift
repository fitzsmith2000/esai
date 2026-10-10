import Foundation

struct SelectedApplication: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    let path: String?
    var id: String { bundleID }
    static let weChat = SelectedApplication(bundleID:WeChatIdentity.bundleID,name:"微信",path:nil)
    static let ownBundleID = "com.esai.wechat-timer"
    static func normalized(_ applications: [SelectedApplication]) -> [SelectedApplication] {
        var seen = Set<String>()
        return applications.filter {
            !$0.bundleID.isEmpty && $0.bundleID != ownBundleID && seen.insert($0.bundleID).inserted
        }
    }
    static func restored(from data: Data?) -> [SelectedApplication] {
        guard let data = data, let saved = try? JSONDecoder().decode([SelectedApplication].self,from:data) else { return [.weChat] }
        return normalized(saved)
    }
    static func from(url: URL) -> SelectedApplication? {
        guard url.pathExtension.lowercased() == "app",let bundle = Bundle(url:url),
              let identifier = bundle.bundleIdentifier,!identifier.isEmpty,identifier != ownBundleID else { return nil }
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        return SelectedApplication(bundleID:identifier,name:name,path:url.path)
    }
}

struct ApplicationExecution: Codable, Identifiable {
    enum Status: String, Codable {
        case closed, notRunning, failed
        var title: String {
            switch self { case .closed: return "已关闭"; case .notRunning: return "未运行"; case .failed: return "关闭失败" }
        }
    }
    let bundleID: String
    let name: String
    let status: Status
    var id: String { bundleID }
}

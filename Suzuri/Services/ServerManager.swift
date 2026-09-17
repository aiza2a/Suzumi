import Foundation
import Observation

/// Telegraph API 镜像配置，并将当前选择持久化到 UserDefaults。
@Observable
final class ServerManager {
    enum Mirror: String, CaseIterable, Identifiable, Hashable {
        case telegraph
        case graph
        case legraph
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .telegraph: "telegra.ph"
            case .graph: "graph.org"
            case .legraph: "legra.ph"
            case .custom: "自定义"
            }
        }

        var apiBase: String {
            apiBase(using: .standard)
        }

        func apiBase(using defaults: UserDefaults) -> String {
            switch self {
            case .telegraph: "https://api.telegra.ph"
            case .graph: "https://api.graph.org"
            case .legraph: "https://api.legra.ph"
            case .custom:
                defaults.string(forKey: ServerManager.customAPIKey)
                    ?? Mirror.telegraph.apiBase
            }
        }
    }

    static let mirrorKey = "server_mirror"
    static let customAPIKey = "custom_api"

    @ObservationIgnored
    private let defaults: UserDefaults
    var current: Mirror {
        didSet {
            defaults.set(current.rawValue, forKey: Self.mirrorKey)
        }
    }
    var customAPIBase: String {
        didSet {
            defaults.set(customAPIBase, forKey: Self.customAPIKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Mirror(
            rawValue: defaults.string(forKey: Self.mirrorKey) ?? ""
        ) ?? .telegraph
        self.customAPIBase = defaults.string(forKey: Self.customAPIKey)
            ?? Mirror.telegraph.apiBase
    }

    /// 当前有效的 API 根地址。
    var apiBase: String {
        current == .custom ? customAPIBase : current.apiBase(using: defaults)
    }

    var apiURL: URL? {
        guard let url = URL(string: apiBase), isHTTPURL(url) else { return nil }
        return url
    }

    var configurationError: TelegraphError? {
        guard current == .custom else { return nil }
        return apiURL == nil ? .api(message: "自定义 API 地址无效") : nil
    }

    func reset() {
        current = .telegraph
        customAPIBase = Mirror.telegraph.apiBase
        defaults.removeObject(forKey: Self.customAPIKey)
    }
}

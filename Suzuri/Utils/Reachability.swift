import Network
import Observation
import SwiftUI

/// 监听网络状态；状态变化回到主线程供 SwiftUI 使用。
@Observable
@MainActor
final class Reachability {
    @ObservationIgnored
    private let monitor = NWPathMonitor()
    @ObservationIgnored
    private let queue = DispatchQueue(label: "com.suzuri.reachability")
    @ObservationIgnored
    private var isMonitoring = false

    private(set) var isConnected = true
    private(set) var isExpensive = false

    init(startImmediately: Bool = true) {
        if startImmediately {
            start()
        }
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
    }
}

/// 断网时显示在内容顶部的轻量横幅。
struct ReachabilityBanner: View {
    let isConnected: Bool

    var body: some View {
        if !isConnected {
            Label("当前离线，恢复网络后可重试", systemImage: "wifi.slash")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .appGlass(cornerRadius: 16, brandTint: true, allowsShadow: false)
                .accessibilityElement(children: .combine)
        }
    }
}

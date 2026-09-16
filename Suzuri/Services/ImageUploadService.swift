import Foundation

/// 图片上传服务。按 `hosts` 顺序尝试，失败后自动降级到下一个图床。
struct ImageUploadService: Sendable {
    var hosts: [any ImageHosting]

    init(hosts: [any ImageHosting] = [QuAxHost(), TelegraphCompatHost()]) {
        self.hosts = hosts
    }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        var lastError: Error?
        for host in hosts {
            do {
                return try await host.upload(data, filename: filename, mimeType: mimeType)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? HostError.uploadFailed("no hosts")
    }
}

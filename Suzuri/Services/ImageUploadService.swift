import Foundation

/// 图片上传服务。按 `hosts` 顺序尝试，失败后自动降级到下一个图床。
struct ImageUploadService: Sendable {
    var hosts: [any ImageHosting]

    init(hosts: [any ImageHosting] = [QuAxHost(), TelegraphCompatHost()]) {
        self.hosts = hosts
    }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        let result = try await uploadWithProvider(data, filename: filename, mimeType: mimeType)
        return result.url
    }

    /// 上传并返回实际成功的 Provider ID，供上层展示或记录降级结果。
    func uploadWithProvider(_ data: Data, filename: String, mimeType: String) async throws -> (url: URL, providerID: String) {
        var lastError: Error?
        for host in hosts {
            do {
                let url = try await host.upload(data, filename: filename, mimeType: mimeType)
                return (url: url, providerID: host.id)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? HostError.uploadFailed("no hosts")
    }
}

import Foundation

/// 图片压缩、缓存与上传的统一编排层。
struct ImagePipeline: Sendable {
    let uploadService: ImageUploadService
    /// 测试或调用方可注入缓存目录；未指定时使用 Library/Caches/Images。
    private let cacheDirectory: URL?

    init(uploadService: ImageUploadService = ImageUploadService(),
         cacheDirectory: URL? = nil) {
        self.uploadService = uploadService
        self.cacheDirectory = cacheDirectory
    }

    /// 将 PhotosPicker 原始数据压缩、缓存并上传，返回图片 URL 与实际 Provider ID。
    func processAndUpload(_ sourceData: Data) async throws -> (url: URL, providerID: String) {
        let jpegData = try ImageCompressor.compressToJPEG(sourceData)
        let directory = try imageCacheDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let filename = "\(UUID().uuidString).jpg"
        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        try jpegData.write(to: fileURL, options: .atomic)

        return try await uploadService.uploadWithProvider(
            jpegData,
            filename: filename,
            mimeType: "image/jpeg"
        )
    }

    private func imageCacheDirectory() throws -> URL {
        if let cacheDirectory {
            return cacheDirectory
        }

        guard let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw ImagePipelineError.cacheUnavailable
        }
        return cachesURL.appendingPathComponent("Images", isDirectory: true)
    }
}

enum ImagePipelineError: Error, Equatable, Sendable {
    case cacheUnavailable
}

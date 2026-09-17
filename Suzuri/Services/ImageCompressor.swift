import UIKit

/// 图片压缩错误。
enum ImageCompressorError: Error, Equatable {
    case unreadable
}

/// 将任意可解码图片统一转换为 JPEG。
enum ImageCompressor {
    /// 图片长边不会超过 `maxDimension`，且不会被放大；JPEG 质量默认为 0.85。
    static func compressToJPEG(_ source: Data, maxDimension: CGFloat = 1600,
                               quality: CGFloat = 0.85) throws -> Data {
        guard maxDimension.isFinite, maxDimension > 0,
              quality.isFinite, (0...1).contains(quality),
              let image = UIImage(data: source) else {
            throw ImageCompressorError.unreadable
        }

        let sourceSize = CGSize(width: image.size.width * image.scale,
                                height: image.size.height * image.scale)
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0 else {
            throw ImageCompressorError.unreadable
        }

        let longestSide = max(sourceSize.width, sourceSize.height)
        let resizeScale = min(1, maxDimension / longestSide)
        let targetWidth = max(1, Int(floor(sourceSize.width * resizeScale)))
        let targetHeight = max(1, Int(floor(sourceSize.height * resizeScale)))
        let targetSize = CGSize(width: targetWidth, height: targetHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let output = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = output.jpegData(compressionQuality: quality) else {
            throw ImageCompressorError.unreadable
        }
        return jpegData
    }

    /// 兼容按 `ImageCompressor.Error.unreadable` 引用错误类型的调用方。
    typealias Error = ImageCompressorError
}

import UIKit
import XCTest
@testable import Suzuri

final class ImageCompressorTests: XCTestCase {
    private func imageData(width: Int, height: Int, format: ImageFormat = .png) throws -> Data {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: rendererFormat
        )
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        switch format {
        case .png:
            return try XCTUnwrap(image.pngData())
        case .jpeg:
            return try XCTUnwrap(image.jpegData(compressionQuality: 1))
        }
    }

    private enum ImageFormat {
        case png
        case jpeg
    }

    func testLongEdgeIsLimitedTo1600WithoutChangingAspectRatio() throws {
        let source = try imageData(width: 2000, height: 1000)
        let compressed = try ImageCompressor.compressToJPEG(source)
        let image = try XCTUnwrap(UIImage(data: compressed))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1600)
        XCTAssertEqual(cgImage.height, 800)
    }

    func testSmallImageIsNotUpscaled() throws {
        let source = try imageData(width: 800, height: 600)
        let compressed = try ImageCompressor.compressToJPEG(source)
        let image = try XCTUnwrap(UIImage(data: compressed))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 800)
        XCTAssertEqual(cgImage.height, 600)
    }

    func testNonImageDataThrowsUnreadable() {
        XCTAssertThrowsError(try ImageCompressor.compressToJPEG(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImageCompressorError, .unreadable)
        }
    }

    func testOutputIsJPEGAndDecodable() throws {
        let source = try imageData(width: 320, height: 240, format: .png)
        let compressed = try ImageCompressor.compressToJPEG(source)

        XCTAssertEqual(Array(compressed.prefix(2)), [0xFF, 0xD8])
        XCTAssertNotNil(UIImage(data: compressed))
    }

    func testJPEGInputIsReencodedAsJPEG() throws {
        let source = try imageData(width: 120, height: 80, format: .jpeg)
        let compressed = try ImageCompressor.compressToJPEG(source, quality: 0.85)

        XCTAssertEqual(Array(compressed.prefix(2)), [0xFF, 0xD8])
        XCTAssertNotNil(UIImage(data: compressed))
    }
}

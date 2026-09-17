import Foundation
import UIKit
import XCTest
@testable import Suzuri

private actor ImagePipelineCapture {
    private(set) var payloads: [Data] = []
    private(set) var filenames: [String] = []
    private(set) var mimeTypes: [String] = []

    func record(data: Data, filename: String, mimeType: String) {
        payloads.append(data)
        filenames.append(filename)
        mimeTypes.append(mimeType)
    }
}

private struct ImagePipelineHost: ImageHosting {
    let id: String
    let result: Result<URL, HostError>
    let capture: ImagePipelineCapture

    var displayName: String { id }

    func upload(_ data: Data, filename: String, mimeType: String) async throws -> URL {
        await capture.record(data: data, filename: filename, mimeType: mimeType)
        return try result.get()
    }
}

final class ImagePipelineTests: XCTestCase {
    private let uploadedURL = URL(string: "https://cdn.example/image.jpg")!

    private func sourceImageData(width: Int = 2000, height: Int = 1000) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func makeCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuzuriImagePipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func testPipelineCompressesToJPEGAndWritesCacheFile() async throws {
        let capture = ImagePipelineCapture()
        let host = ImagePipelineHost(
            id: "quax",
            result: .success(uploadedURL),
            capture: capture
        )
        let service = ImageUploadService(hosts: [host])
        let cacheDirectory = try makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let pipeline = ImagePipeline(
            uploadService: service,
            cacheDirectory: cacheDirectory
        )

        let result = try await pipeline.processAndUpload(try sourceImageData())

        XCTAssertEqual(result.url, uploadedURL)
        XCTAssertEqual(result.providerID, "quax")
        let payloads = await capture.payloads
        let filenames = await capture.filenames
        let mimeTypes = await capture.mimeTypes
        let payload = try XCTUnwrap(payloads.first)
        XCTAssertEqual(Array(payload.prefix(2)), [0xFF, 0xD8])
        let image = try XCTUnwrap(UIImage(data: payload))
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 1600)
        XCTAssertEqual(filenames.count, 1)
        XCTAssertEqual(mimeTypes, ["image/jpeg"])

        let cachedFiles = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(cachedFiles.count, 1)
        XCTAssertEqual(cachedFiles[0].pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: cachedFiles[0]), payload)
    }

    func testPipelineFallsBackAndReturnsSuccessfulProviderID() async throws {
        let firstCapture = ImagePipelineCapture()
        let secondCapture = ImagePipelineCapture()
        let first = ImagePipelineHost(
            id: "first",
            result: .failure(.transport),
            capture: firstCapture
        )
        let second = ImagePipelineHost(
            id: "second",
            result: .success(uploadedURL),
            capture: secondCapture
        )
        let cacheDirectory = try makeCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let pipeline = ImagePipeline(
            uploadService: ImageUploadService(hosts: [first, second]),
            cacheDirectory: cacheDirectory
        )

        let result = try await pipeline.processAndUpload(try sourceImageData(width: 800, height: 600))

        XCTAssertEqual(result.url, uploadedURL)
        XCTAssertEqual(result.providerID, "second")
        let firstPayloads = await firstCapture.payloads
        let secondPayloads = await secondCapture.payloads
        let secondMimeTypes = await secondCapture.mimeTypes
        XCTAssertEqual(firstPayloads.count, 1)
        XCTAssertEqual(secondPayloads.count, 1)
        XCTAssertEqual(secondMimeTypes, ["image/jpeg"])
    }
}

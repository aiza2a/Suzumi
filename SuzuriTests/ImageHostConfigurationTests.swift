import XCTest
@testable import Suzuri

final class ImageHostConfigurationTests: XCTestCase {
    func testOldDefaultMigratesToPostimagesWithoutChangingCustomHost() {
        let name = "ImageConfiguration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("quax", forKey: ImageHostConfiguration.providerKey)
        ImageHostConfiguration.migrateProvider(defaults: defaults)
        XCTAssertTrue(ImageHostConfiguration.usesPostimages(defaults: defaults))
        XCTAssertThrowsError(try ImageHostConfiguration.makeUploadService(defaults: defaults))

        defaults.set("custom", forKey: ImageHostConfiguration.providerKey)
        defaults.set("https://images.example.test", forKey: ImageHostConfiguration.baseURLKey)
        ImageHostConfiguration.migrateProvider(defaults: defaults)
        XCTAssertFalse(ImageHostConfiguration.usesPostimages(defaults: defaults))
        XCTAssertNoThrow(try ImageHostConfiguration.makeUploadService(defaults: defaults))
    }

    func testInvalidCustomHostNeverFallsBackToAnotherProvider() {
        let name = "ImageConfiguration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("custom", forKey: ImageHostConfiguration.providerKey)
        for address in ["http://images.example.test", "https://user:pass@images.example.test", "not-a-url"] {
            defaults.set(address, forKey: ImageHostConfiguration.baseURLKey)
            XCTAssertNotNil(ImageHostConfiguration.configurationError(defaults: defaults))
            XCTAssertThrowsError(try ImageHostConfiguration.makeUploadService(defaults: defaults))
        }
    }
}

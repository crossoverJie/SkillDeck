import XCTest

@testable import SkillDeck

final class KeychainServiceTests: XCTestCase {

    func testSetGetDeletePasswordRoundTrip() async throws {
        let key = "proxy.password.test.\(UUID().uuidString)"
        let service = KeychainService(service: "SkillDeckTests")

        do {
            try await service.setPassword("secret", forKey: key)
            let loaded = try await service.getPassword(forKey: key)
            XCTAssertEqual(loaded, "secret")

            try await service.deletePassword(forKey: key)
            let afterDelete = try await service.getPassword(forKey: key)
            XCTAssertNil(afterDelete)
        } catch {
            try? await service.deletePassword(forKey: key)
            throw error
        }
    }
}

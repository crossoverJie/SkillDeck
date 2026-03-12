import XCTest

@testable import SkillDeck

final class ProxyEnvironmentImporterTests: XCTestCase {

    func testAllProxyTakesPrecedence() {
        let env: [String: String] = [
            "https_proxy": "http://127.0.0.1:1086",
            "all_proxy": "socks5://127.0.0.1:1080"
        ]

        let imported = ProxyEnvironmentImporter.importFromEnvironment(env)
        XCTAssertEqual(imported?.type, .socks5)
        XCTAssertEqual(imported?.host, "127.0.0.1")
        XCTAssertEqual(imported?.port, 1080)
    }

    func testHTTPSProxyParsesHostPortAndAuth() {
        let env: [String: String] = [
            "https_proxy": "http://user:pass@127.0.0.1:1086",
            "no_proxy": "localhost, 127.0.0.1\n*.internal"
        ]

        let imported = ProxyEnvironmentImporter.importFromEnvironment(env)
        XCTAssertEqual(imported?.type, .https)
        XCTAssertEqual(imported?.host, "127.0.0.1")
        XCTAssertEqual(imported?.port, 1086)
        XCTAssertEqual(imported?.username, "user")
        XCTAssertEqual(imported?.password, "pass")
        XCTAssertEqual(imported?.bypassList, ["localhost", "127.0.0.1", "*.internal"])
    }
}

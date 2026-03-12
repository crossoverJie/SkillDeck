import CFNetwork
import XCTest

@testable import SkillDeck

final class ProxyConfigurationBuilderTests: XCTestCase {

    func testBuildDisabledProxyReturnsEmptyDictionary() {
        let settings = ProxySettings.disabled
        let dict = ProxyConfigurationBuilder.build(from: settings)
        XCTAssertTrue(dict.isEmpty)
    }

    func testBuildHTTPProxySetsHTTPKeys() {
        let settings = ProxySettings(
            isEnabled: true,
            type: .http,
            host: "127.0.0.1",
            port: 8080,
            username: "user",
            bypassList: []
        )

        let dict = ProxyConfigurationBuilder.build(from: settings)

        XCTAssertEqual(dict[kCFNetworkProxiesHTTPEnable as String] as? Int, 1)
        XCTAssertEqual(dict[kCFNetworkProxiesHTTPProxy as String] as? String, "127.0.0.1")
        XCTAssertEqual(dict[kCFNetworkProxiesHTTPPort as String] as? Int, 8080)
        XCTAssertEqual(dict[kCFProxyUsernameKey as String] as? String, "user")
    }

    func testBuildHTTPSProxySetsHTTPSKeys() {
        let settings = ProxySettings(
            isEnabled: true,
            type: .https,
            host: "proxy.example.com",
            port: 8443,
            username: nil,
            bypassList: []
        )

        let dict = ProxyConfigurationBuilder.build(from: settings)

        XCTAssertEqual(dict[kCFNetworkProxiesHTTPSEnable as String] as? Int, 1)
        XCTAssertEqual(dict[kCFNetworkProxiesHTTPSProxy as String] as? String, "proxy.example.com")
        XCTAssertEqual(dict[kCFNetworkProxiesHTTPSPort as String] as? Int, 8443)
    }

    func testBuildSOCKS5ProxySetsSOCKSKeys() {
        let settings = ProxySettings(
            isEnabled: true,
            type: .socks5,
            host: "localhost",
            port: 1080,
            username: nil,
            bypassList: []
        )

        let dict = ProxyConfigurationBuilder.build(from: settings)

        XCTAssertEqual(dict[kCFNetworkProxiesSOCKSEnable as String] as? Int, 1)
        XCTAssertEqual(dict[kCFNetworkProxiesSOCKSProxy as String] as? String, "localhost")
        XCTAssertEqual(dict[kCFNetworkProxiesSOCKSPort as String] as? Int, 1080)
    }

    func testBuildBypassListSetsExceptionsList() {
        let settings = ProxySettings(
            isEnabled: true,
            type: .http,
            host: "127.0.0.1",
            port: 8080,
            username: nil,
            bypassList: ["localhost", "127.0.0.1", "*.internal"]
        )

        let dict = ProxyConfigurationBuilder.build(from: settings)

        let exceptions = dict[kCFNetworkProxiesExceptionsList as String] as? [String]
        XCTAssertEqual(exceptions, ["localhost", "127.0.0.1", "*.internal"])
    }
}

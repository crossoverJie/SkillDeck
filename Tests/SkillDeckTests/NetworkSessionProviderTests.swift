import CFNetwork
import XCTest

@testable import SkillDeck

final class NetworkSessionProviderTests: XCTestCase {

    func testSessionConfigurationLoadsProxySettingsFromInjectedSuiteName() async throws {
        let suiteName = "NetworkSessionProviderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = KeychainService(service: "SkillDeckTests.NetworkSessionProvider.\(UUID().uuidString)")

        // A dedicated suite name gives this test isolated state without passing UserDefaults
        // itself across the actor boundary, which is the concurrency issue this regression test guards.
        defaults.set(true, forKey: NetworkSessionProvider.proxyEnabledKey)
        defaults.set(ProxySettings.ProxyType.https.rawValue, forKey: NetworkSessionProvider.proxyTypeKey)
        defaults.set("127.0.0.1", forKey: NetworkSessionProvider.proxyHostKey)
        defaults.set(8888, forKey: NetworkSessionProvider.proxyPortKey)
        defaults.set("proxy-user", forKey: NetworkSessionProvider.proxyUsernameKey)
        defaults.set("localhost, *.internal\n127.0.0.1", forKey: NetworkSessionProvider.proxyBypassKey)
        try await keychain.setPassword("secret", forKey: NetworkSessionProvider.proxyPasswordKeychainKey)

        let provider = NetworkSessionProvider(defaultsSuiteName: suiteName, keychain: keychain)
        let configuration = await provider.sessionConfiguration()
        let proxyDictionary = try XCTUnwrap(configuration.connectionProxyDictionary)

        XCTAssertEqual(proxyDictionary[kCFNetworkProxiesHTTPEnable as String] as? Int, 1)
        XCTAssertEqual(proxyDictionary[kCFNetworkProxiesHTTPProxy as String] as? String, "127.0.0.1")
        XCTAssertEqual(proxyDictionary[kCFNetworkProxiesHTTPPort as String] as? Int, 8888)
        XCTAssertEqual(proxyDictionary[kCFProxyUsernameKey as String] as? String, "proxy-user")
        XCTAssertEqual(proxyDictionary[kCFProxyPasswordKey as String] as? String, "secret")
        XCTAssertEqual(
            proxyDictionary[kCFNetworkProxiesExceptionsList as String] as? [String],
            ["localhost", "*.internal", "127.0.0.1"]
        )

        defaults.removePersistentDomain(forName: suiteName)
        try await keychain.deletePassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
    }
}

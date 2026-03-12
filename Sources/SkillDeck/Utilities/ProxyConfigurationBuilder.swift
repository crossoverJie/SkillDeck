import CFNetwork
import Foundation

/// ProxyConfigurationBuilder converts ProxySettings into a CFNetwork proxy dictionary.
///
/// URLSession reads proxy settings from `URLSessionConfiguration.connectionProxyDictionary`.
/// The dictionary uses CFNetwork keys like `kCFNetworkProxiesHTTPEnable`.
enum ProxyConfigurationBuilder {

    static func build(from settings: ProxySettings) -> [AnyHashable: Any] {
        build(from: settings, password: nil)
    }

    static func build(from settings: ProxySettings, password: String?) -> [AnyHashable: Any] {
        guard settings.isEnabled else { return [:] }

        // CFNetwork expects numeric flags (0/1) for enable keys.
        let enabledFlag = 1

        var proxyDict: [AnyHashable: Any] = [:]

        switch settings.type {
        case .https:
            proxyDict[kCFNetworkProxiesHTTPEnable as String] = enabledFlag
            proxyDict[kCFNetworkProxiesHTTPProxy as String] = settings.host
            proxyDict[kCFNetworkProxiesHTTPPort as String] = settings.port
            proxyDict[kCFNetworkProxiesHTTPSEnable as String] = enabledFlag
            proxyDict[kCFNetworkProxiesHTTPSProxy as String] = settings.host
            proxyDict[kCFNetworkProxiesHTTPSPort as String] = settings.port

        case .socks5:
            proxyDict[kCFNetworkProxiesSOCKSEnable as String] = enabledFlag
            proxyDict[kCFNetworkProxiesSOCKSProxy as String] = settings.host
            proxyDict[kCFNetworkProxiesSOCKSPort as String] = settings.port
        }

        if let username = settings.username, !username.isEmpty {
            proxyDict[kCFProxyUsernameKey as String] = username
        }

        if let password, !password.isEmpty {
            proxyDict[kCFProxyPasswordKey as String] = password
        }

        if !settings.bypassList.isEmpty {
            proxyDict[kCFNetworkProxiesExceptionsList as String] = settings.bypassList
        }

        return proxyDict
    }
}

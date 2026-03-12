import Foundation

enum ProxyEnvironmentImporter {

    struct ImportedProxy: Equatable {
        var type: ProxySettings.ProxyType
        var host: String
        var port: Int
        var username: String?
        var password: String?
        var bypassList: [String]
    }

    static func importFromEnvironment(_ env: [String: String]) -> ImportedProxy? {
        let normalized = normalizeKeys(env)

        if let allProxy = normalized["all_proxy"], let imported = parseProxyURL(allProxy, preferredType: .socks5, env: normalized) {
            return imported
        }
        if let httpsProxy = normalized["https_proxy"], let imported = parseProxyURL(httpsProxy, preferredType: .https, env: normalized) {
            return imported
        }
        if let httpProxy = normalized["http_proxy"], let imported = parseProxyURL(httpProxy, preferredType: .https, env: normalized) {
            return imported
        }

        return nil
    }

    private static func parseProxyURL(_ raw: String, preferredType: ProxySettings.ProxyType, env: [String: String]) -> ImportedProxy? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }

        let port = url.port ?? defaultPort(forScheme: url.scheme, preferredType: preferredType)
        guard (1...65535).contains(port) else { return nil }

        let type = proxyType(forScheme: url.scheme, preferredType: preferredType)
        let username = url.user
        let password = url.password
        let bypassList = parseNoProxy(env["no_proxy"] ?? "")

        return ImportedProxy(
            type: type,
            host: host,
            port: port,
            username: username,
            password: password,
            bypassList: bypassList
        )
    }

    private static func proxyType(forScheme scheme: String?, preferredType: ProxySettings.ProxyType) -> ProxySettings.ProxyType {
        switch (scheme ?? "").lowercased() {
        case "socks5", "socks5h", "socks":
            return .socks5
        case "http", "https":
            return .https
        default:
            return preferredType
        }
    }

    private static func defaultPort(forScheme scheme: String?, preferredType: ProxySettings.ProxyType) -> Int {
        switch (scheme ?? "").lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        case "socks5", "socks5h", "socks":
            return 1080
        default:
            return preferredType == .socks5 ? 1080 : 443
        }
    }

    private static func parseNoProxy(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeKeys(_ env: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in env {
            out[k.lowercased()] = v
        }
        return out
    }
}

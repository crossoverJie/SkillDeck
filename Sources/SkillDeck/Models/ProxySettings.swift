import Foundation

/// ProxySettings describes how the app should route outbound HTTP(S) traffic.
///
/// We keep it as a plain data model (no IO side effects) so it is easy to persist,
/// validate, and unit test.
struct ProxySettings: Codable, Equatable, Sendable {

    enum ProxyType: String, Codable, CaseIterable, Identifiable, Sendable {
        case https
        case socks5

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .https: "HTTPS"
            case .socks5: "SOCKS5"
            }
        }
    }

    var isEnabled: Bool
    var type: ProxyType
    var host: String
    var port: Int

    /// Optional auth username (password is stored separately in Keychain).
    var username: String?

    /// Exceptions list for proxy bypass.
    ///
    /// For `URLSessionConfiguration.connectionProxyDictionary`, this maps to
    /// `kCFNetworkProxiesExceptionsList`.
    var bypassList: [String]

    static let disabled = ProxySettings(
        isEnabled: false,
        type: .https,
        host: "",
        port: 0,
        username: nil,
        bypassList: []
    )
}

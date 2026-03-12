import Foundation

/// NetworkSessionProvider centralizes URLSession creation so networking can respect app settings.
///
/// The most important use case here is proxy support: `URLSession.shared` cannot be reconfigured,
/// so services must use sessions created from a `URLSessionConfiguration` we control.
actor NetworkSessionProvider {

    static let shared = NetworkSessionProvider()

    // MARK: - UserDefaults Keys

    static let proxyEnabledKey = "proxy.enabled"
    static let proxyTypeKey = "proxy.type"
    static let proxyHostKey = "proxy.host"
    static let proxyPortKey = "proxy.port"
    static let proxyAuthEnabledKey = "proxy.auth.enabled"
    static let proxyUsernameKey = "proxy.username"
    static let proxyBypassKey = "proxy.bypass"

    /// Password is stored in Keychain under this key (never in UserDefaults).
    static let proxyPasswordKeychainKey = "proxy.password"

    private let defaults: UserDefaults
    private let keychain: KeychainService

    private var cachedSignature: String?
    private var cachedConfiguration: URLSessionConfiguration?
    private var cachedSession: URLSession?

    init(
        defaultsSuiteName: String? = nil,
        keychain: KeychainService = KeychainService(service: "SkillDeck")
    ) {
        // We store the suite name (a Sendable String) in the initializer boundary and
        // create the concrete UserDefaults instance inside the actor. This avoids passing
        // Foundation.UserDefaults (which is not Sendable) across actor isolation, which
        // becomes a Swift 6 error even though the actor itself safely serializes access.
        if let defaultsSuiteName {
            guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
                fatalError("Failed to create UserDefaults suite named \(defaultsSuiteName)")
            }
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
        self.keychain = keychain
    }

    /// Return a URLSession for data requests (JSON / HTML / markdown fetch).
    ///
    /// The provider caches the session and rebuilds it when proxy settings change.
    func dataSession() async -> URLSession {
        let (settings, password) = await loadProxySettings()
        let signature = signatureFor(settings: settings, password: password)
        if let cachedSignature, cachedSignature == signature, let cachedSession {
            return cachedSession
        }

        let configuration = buildConfiguration(settings: settings, password: password)
        let session = URLSession(configuration: configuration)

        cachedSignature = signature
        cachedConfiguration = configuration
        cachedSession = session
        return session
    }

    /// Return a URLSessionConfiguration used by delegate-based sessions.
    ///
    /// Example: UpdateChecker uses URLSessionDownloadDelegate to report download progress.
    func sessionConfiguration() async -> URLSessionConfiguration {
        let (settings, password) = await loadProxySettings()
        let signature = signatureFor(settings: settings, password: password)
        if let cachedSignature, cachedSignature == signature, let cachedConfiguration {
            return cachedConfiguration
        }

        let configuration = buildConfiguration(settings: settings, password: password)
        cachedSignature = signature
        cachedConfiguration = configuration
        cachedSession = nil
        return configuration
    }

    // MARK: - Internal

    private func buildConfiguration(settings: ProxySettings, password: String?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default

        // connectionProxyDictionary is read by CFNetwork and applies to all requests in this URLSession.
        configuration.connectionProxyDictionary = ProxyConfigurationBuilder.build(from: settings, password: password)
        return configuration
    }

    private func loadProxySettings() async -> (ProxySettings, String?) {
        let isEnabled = defaults.bool(forKey: NetworkSessionProvider.proxyEnabledKey)
        let typeRaw = defaults.string(forKey: NetworkSessionProvider.proxyTypeKey) ?? ProxySettings.ProxyType.https.rawValue
        let type = ProxySettings.ProxyType(rawValue: typeRaw) ?? .https

        let host = defaults.string(forKey: NetworkSessionProvider.proxyHostKey) ?? ""
        let port = defaults.integer(forKey: NetworkSessionProvider.proxyPortKey)

        let authEnabled = defaults.object(forKey: NetworkSessionProvider.proxyAuthEnabledKey) as? Bool ?? true
        let username = authEnabled ? defaults.string(forKey: NetworkSessionProvider.proxyUsernameKey) : nil

        let bypassRaw = defaults.string(forKey: NetworkSessionProvider.proxyBypassKey) ?? ""
        let bypassList = parseBypassList(bypassRaw)

        let settings = ProxySettings(
            isEnabled: isEnabled,
            type: type,
            host: host,
            port: port,
            username: username,
            bypassList: bypassList
        )

        let password = authEnabled ? (try? await keychain.getPassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)) : nil
        return (settings, password)
    }

    private func parseBypassList(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func signatureFor(settings: ProxySettings, password: String?) -> String {
        let bypass = settings.bypassList.joined(separator: ",")
        return [
            settings.isEnabled ? "1" : "0",
            settings.type.rawValue,
            settings.host,
            String(settings.port),
            (settings.username == nil) ? "auth:0" : "auth:1",
            settings.username ?? "",
            bypass,
            password ?? ""
        ].joined(separator: "|")
    }
}

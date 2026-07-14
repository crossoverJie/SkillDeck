import Foundation

/// SkillStorageSettings stores the canonical global skill directory selected by the user.
/// UserDefaults is suitable here because this is a small application preference, comparable to
/// a Java Preferences value rather than application data that needs a separate database.
enum SkillStorageSettings {
    private static let globalSkillsPathKey = "globalSkillsPath"

    static var globalSkillsPath: String {
        let configuredPath = UserDefaults.standard.string(forKey: globalSkillsPathKey)
        return configuredPath?.isEmpty == false ? configuredPath! : Constants.sharedSkillsPath
    }

    static var globalSkillsURL: URL {
        URL(fileURLWithPath: NSString(string: globalSkillsPath).expandingTildeInPath)
    }

    static var lockFileURL: URL {
        globalSkillsURL.deletingLastPathComponent().appendingPathComponent(".skill-lock.json")
    }

    static var cacheFileURL: URL {
        globalSkillsURL.deletingLastPathComponent().appendingPathComponent(".skilldeck-cache.json")
    }

    static func setGlobalSkillsPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: globalSkillsPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: globalSkillsPathKey)
        }
    }
}

/// AgentPathSettings manages custom directory paths for Agents
///
/// This allows users to configure non-default paths for Agent skills directories,
/// which is useful when the Agent runs in Docker with volume mounts.
/// Settings are persisted in UserDefaults.
enum AgentPathSettings {

    /// UserDefaults key for custom OpenClaw path
    private static let openClawPathKey = "customAgentPath.openclaw"

    /// Get the custom path for a specific Agent, if configured
    /// - Parameter agent: The Agent type to query
    /// - Returns: Custom path string, or nil if using default
    static func customPath(for agent: AgentType) -> String? {
        // Currently only OpenClaw supports custom path
        guard agent == .openClaw else { return nil }
        let value = UserDefaults.standard.string(forKey: openClawPathKey)
        return value?.isEmpty == false ? value : nil
    }

    /// Set or clear the custom path for a specific Agent
    /// - Parameters:
    ///   - path: Custom path string, or nil to use default
    ///   - agent: The Agent type to configure
    static func setCustomPath(_ path: String?, for agent: AgentType) {
        // Currently only OpenClaw supports custom path
        guard agent == .openClaw else { return }
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: openClawPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: openClawPathKey)
        }
    }

    /// Check if a custom path is configured for an Agent
    /// - Parameter agent: The Agent type to check
    /// - Returns: true if a custom path is set
    static func hasCustomPath(for agent: AgentType) -> Bool {
        return customPath(for: agent) != nil
    }

    /// Clear custom path for OpenClaw (reset to default)
    static func resetOpenClawPath() {
        UserDefaults.standard.removeObject(forKey: openClawPathKey)
    }
}

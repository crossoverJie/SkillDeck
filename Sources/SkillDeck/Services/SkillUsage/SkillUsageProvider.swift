import Darwin
import Foundation

/// One Agent-specific adapter that recovers best-effort skill usage from local history.
protocol SkillUsageProvider: Sendable {
    /// Agent whose local history this provider reads.
    var agentType: AgentType { get }

    /// Scan the provider's local history and return one complete index.
    func scan() async -> SkillUsageScanResult
}

/// Production provider set. Tests inject their own providers through `SkillManager.init`.
enum SkillUsageProviderFactory {
    static func makeDefaultProviders() -> [any SkillUsageProvider] {
        [
            CodexSkillUsageService(),
            ClaudeCodeSkillUsageService(),
            CopilotSkillUsageService(),
            CodeBuddySkillUsageService(),
            QoderSkillUsageService(),
            OpenCodeSkillUsageService(),
            PiSkillUsageService(),
        ]
    }
}

/// Result of inspecting a configured history path.
enum SkillUsagePathStatus: Equatable, Sendable {
    case directory
    case notDirectory
    case missing
    case inaccessible
}

/// Inspects a history path without collapsing permission errors into "not found".
///
/// `FileManager.fileExists` returns `false` for both a missing path and an unreadable parent,
/// which would incorrectly turn a permission problem into `.unavailable`.
enum SkillUsagePathProbe {
    static func status(at url: URL) -> SkillUsagePathStatus {
        var info = stat()
        // `fstatat` follows symlinks like `stat`, but avoids the `stat` struct/function name
        // collision in Swift. `AT_FDCWD` resolves a relative path against the current directory.
        guard fstatat(AT_FDCWD, url.path, &info, 0) == 0 else {
            // ENOENT/ENOTDIR mean the path truly does not exist. EACCES and other errors mean
            // it may exist but cannot be verified, so callers must report a read failure.
            switch errno {
            case ENOENT, ENOTDIR:
                return .missing
            default:
                return .inaccessible
            }
        }
        return (info.st_mode & S_IFMT) == S_IFDIR ? .directory : .notDirectory
    }
}

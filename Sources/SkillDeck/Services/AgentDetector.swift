import Foundation

/// AgentDetector is responsible for detecting installed AI code assistants (F01)
///
/// Detection logic:
/// 1. Check if CLI command exists (via `which` command)
/// 2. Check if config directory exists (e.g. ~/.claude/)
/// 3. Check if skills directory exists
///
/// In Swift, actor is a thread-safe reference type (similar to Go's struct with mutex)
/// It guarantees internal state is accessed by only one task at a time, avoiding data races
actor AgentDetector {

    /// Detect installation status of all supported Agents
    /// - Returns: Array of all Agent detection results
    ///
    /// async/await is Swift's concurrency model (similar to Go's goroutine, but with compiler-guaranteed safety)
    func detectAll() async -> [Agent] {
        // CaseIterable protocol allows iterating over all enum cases
        // Similar to Java's EnumType.values()
        var agents: [Agent] = []
        for type in AgentType.allCases {
            let agent = await detect(type: type)
            agents.append(agent)
        }
        return agents
    }

    /// Detect installation status of a single Agent
    func detect(type: AgentType) async -> Agent {
        let fm = FileManager.default

        // Check if CLI command exists
        let isInstalled = await checkCommandExists(type.detectCommand)

        // Check config directory
        let configExists: Bool
        if let configPath = type.configDirectoryPath {
            let expanded = NSString(string: configPath).expandingTildeInPath
            configExists = fm.fileExists(atPath: expanded)
        } else {
            configExists = false
        }

        // Check skills directory
        let skillsDirURL = type.skillsDirectoryURL
        let skillsExists = fm.fileExists(atPath: skillsDirURL.path)

        // Count skills
        let skillCount: Int
        if skillsExists {
            skillCount = countSkills(in: skillsDirURL)
        } else {
            skillCount = 0
        }

        return Agent(
            type: type,
            isInstalled: isInstalled,
            configDirectoryExists: configExists,
            skillsDirectoryExists: skillsExists,
            skillCount: skillCount
        )
    }

    /// Check if specified CLI command exists in system
    /// Judged by executing `which <command>`, exit code 0 means exists
    ///
    /// Process is the class for executing external commands in Swift (similar to Java's ProcessBuilder or Go's exec.Command)
    private func checkCommandExists(_ command: String) async -> Bool {
        // Special handling: Copilot needs to check `gh copilot` subcommand
        if command == "gh" {
            return await checkGhCopilot()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Check if gh copilot subcommand is available
    private func checkGhCopilot() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gh"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Count skills in directory (number of subdirectories containing SKILL.md)
    private func countSkills(in directory: URL) -> Int {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return contents.filter { url in
            var isDir: ObjCBool = false
            let skillMD = url.appendingPathComponent("SKILL.md")
            return fm.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
                && fm.fileExists(atPath: skillMD.path)
        }.count
    }
}

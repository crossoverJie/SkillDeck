import Foundation

/// AgentDetector 负责检测系统中已安装的 AI 代码助手（F01）
///
/// 检测逻辑：
/// 1. 检查 CLI 命令是否存在（通过 `which` 命令）
/// 2. 检查配置目录是否存在（如 ~/.claude/）
/// 3. 检查 skills 目录是否存在
///
/// 在 Swift 中，actor 是一种线程安全的引用类型（类似 Go 的带 mutex 的 struct）
/// 它保证内部状态同一时间只能被一个任务访问，避免数据竞争
actor AgentDetector {

    /// 检测所有支持的 Agent 的安装状态
    /// - Returns: 所有 Agent 的检测结果数组
    ///
    /// async/await 是 Swift 的并发模型（类似 Go 的 goroutine，但有编译器保证的安全性）
    func detectAll() async -> [Agent] {
        // CaseIterable 协议让我们可以遍历 enum 的所有 case
        // 类似 Java 的 EnumType.values()
        var agents: [Agent] = []
        for type in AgentType.allCases {
            let agent = await detect(type: type)
            agents.append(agent)
        }
        return agents
    }

    /// 检测单个 Agent 的安装状态
    func detect(type: AgentType) async -> Agent {
        let fm = FileManager.default

        // 检查 CLI 命令是否存在
        let isInstalled = await checkCommandExists(type.detectCommand)

        // 检查配置目录
        let configExists: Bool
        if let configPath = type.configDirectoryPath {
            let expanded = NSString(string: configPath).expandingTildeInPath
            configExists = fm.fileExists(atPath: expanded)
        } else {
            configExists = false
        }

        // 检查 skills 目录
        let skillsDirURL = type.skillsDirectoryURL
        let skillsExists = fm.fileExists(atPath: skillsDirURL.path)

        // 统计 skill 数量
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

    /// 检查系统中是否存在指定的 CLI 命令
    /// 通过执行 `which <command>` 来判断，退出码 0 表示存在
    ///
    /// Process 是 Swift 中执行外部命令的类（类似 Java 的 ProcessBuilder 或 Go 的 exec.Command）
    private func checkCommandExists(_ command: String) async -> Bool {
        // 特殊处理：Copilot 需要检查 `gh copilot` 子命令
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

    /// 检查 gh copilot 子命令是否可用
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

    /// 统计目录下的 skill 数量（包含 SKILL.md 的子目录数）
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

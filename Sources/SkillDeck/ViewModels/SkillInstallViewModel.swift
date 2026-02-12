import Foundation

/// SkillInstallViewModel 管理 F10（一键安装）弹窗的状态和逻辑
///
/// 安装流程分两步：
/// 1. 用户输入 GitHub 仓库 URL → 浅克隆 → 扫描发现 skill → 显示列表
/// 2. 用户选择要安装的 skill 和 Agent → 执行安装 → 完成
///
/// @MainActor 保证所有属性在主线程更新（UI 绑定的状态必须在主线程）
/// @Observable 让 SwiftUI 自动追踪属性变化并刷新视图
@MainActor
@Observable
final class SkillInstallViewModel {

    // MARK: - Phase Enum

    /// 安装流程的阶段（有限状态机）
    /// 类似 Java 的 enum，但 Swift 的 enum 可以有关联值（associated value）
    enum Phase: Equatable {
        /// 初始阶段：等待用户输入 URL
        case inputURL
        /// 正在克隆仓库和扫描 skill
        case fetching
        /// 已发现 skill，等待用户选择
        case selectSkills
        /// 正在安装选中的 skill
        case installing
        /// 安装完成
        case completed
        /// 发生错误，附带错误信息
        /// 关联值让 enum case 可以携带数据（Java 的 enum 无此特性）
        case error(String)

        // Equatable 手动实现：error case 只比较类型不比较消息内容
        // 默认的 Equatable 合成会自动处理，但这里显式实现以确保行为正确
        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.inputURL, .inputURL),
                 (.fetching, .fetching),
                 (.selectSkills, .selectSkills),
                 (.installing, .installing),
                 (.completed, .completed):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - State

    /// 用户输入的仓库地址（支持 "owner/repo" 或完整 URL）
    var repoURLInput = ""

    /// 当前安装流程阶段
    var phase: Phase = .inputURL

    /// 仓库中发现的所有 skill
    var discoveredSkills: [GitService.DiscoveredSkill] = []

    /// 用户选中的要安装的 skill 名称集合
    /// Set 用于 O(1) 查找，类似 Java 的 HashSet
    var selectedSkillNames: Set<String> = []

    /// 用户选中的目标 Agent 集合（默认选中 Claude Code）
    var selectedAgents: Set<AgentType> = [.claudeCode]

    /// 已安装的 skill 名称集合（用于在列表中标记"已安装"）
    var alreadyInstalledNames: Set<String> = []

    /// 进度提示信息
    var progressMessage = ""

    /// 已成功安装的 skill 数量
    var installedCount = 0

    // MARK: - Dependencies

    /// SkillManager 引用，用于执行安装和检查已安装状态
    private let skillManager: SkillManager

    /// Git 操作服务
    private let gitService = GitService()

    /// 克隆的临时目录 URL（在 fetch 和 install 之间保持，关闭 sheet 时清理）
    private var tempRepoDir: URL?

    /// 规范化后的仓库 URL 和 source 标识
    private var normalizedRepoURL: String = ""
    private var normalizedSource: String = ""

    // MARK: - Init

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    // MARK: - Actions

    /// Step 1：克隆仓库并扫描发现 skill
    ///
    /// 执行流程：
    /// 1. 规范化 URL（支持 "owner/repo" 和完整 URL 格式）
    /// 2. 检查 git 是否可用
    /// 3. 浅克隆仓库
    /// 4. 扫描 SKILL.md 文件
    /// 5. 标记已安装的 skill
    /// 6. 转到选择阶段
    func fetchRepository() async {
        phase = .fetching
        progressMessage = "Validating URL..."

        do {
            // 1. 规范化 URL
            let (repoURL, source) = try GitService.normalizeRepoURL(repoURLInput)
            normalizedRepoURL = repoURL
            normalizedSource = source

            // 2. 检查 git
            progressMessage = "Checking git..."
            let gitAvailable = await gitService.checkGitAvailable()
            guard gitAvailable else {
                phase = .error("Git is not installed. Please install git first.")
                return
            }

            // 3. 浅克隆
            progressMessage = "Cloning repository..."
            let repoDir = try await gitService.shallowClone(repoURL: repoURL)
            tempRepoDir = repoDir

            // 4. 扫描 skill
            progressMessage = "Scanning skills..."
            let discovered = await gitService.scanSkillsInRepo(repoDir: repoDir)

            guard !discovered.isEmpty else {
                phase = .error("No skills found in this repository.")
                return
            }

            discoveredSkills = discovered

            // 5. 标记已安装的 skill
            alreadyInstalledNames = Set(skillManager.skills.map(\.id))

            // 默认选中所有未安装的 skill
            selectedSkillNames = Set(discovered.map(\.id).filter { !alreadyInstalledNames.contains($0) })

            // 6. 转到选择阶段
            phase = .selectSkills
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Step 2：安装选中的 skill
    ///
    /// 逐个安装选中的 skill，更新进度信息
    func installSelected() async {
        guard !selectedSkillNames.isEmpty else { return }
        guard let repoDir = tempRepoDir else {
            phase = .error("Repository data not available. Please scan again.")
            return
        }

        phase = .installing
        installedCount = 0
        let total = selectedSkillNames.count

        for skill in discoveredSkills where selectedSkillNames.contains(skill.id) {
            progressMessage = "Installing \(skill.id) (\(installedCount + 1)/\(total))..."

            do {
                try await skillManager.installSkill(
                    from: repoDir,
                    skill: skill,
                    repoSource: normalizedSource,
                    repoURL: normalizedRepoURL,
                    targetAgents: selectedAgents
                )
                installedCount += 1
            } catch {
                // 单个 skill 安装失败不阻断其他 skill
                // 但记录错误信息（未来可以扩展为显示详细错误列表）
                continue
            }
        }

        phase = .completed
    }

    /// 清理临时目录（关闭 sheet 时调用）
    ///
    /// 使用 Task 包装 actor 方法调用，因为 cleanup 是同步调用但需要 await actor 方法
    func cleanup() {
        if let tempRepoDir {
            let dir = tempRepoDir
            self.tempRepoDir = nil
            Task {
                await gitService.cleanupTempDirectory(dir)
            }
        }
    }

    /// 切换某个 skill 的选中状态
    /// symmetricDifference 是 Set 的对称差集操作：如果元素存在则移除，不存在则添加
    /// 类似 Java Set 的 toggle 操作
    func toggleSkillSelection(_ skillName: String) {
        if selectedSkillNames.contains(skillName) {
            selectedSkillNames.remove(skillName)
        } else {
            selectedSkillNames.insert(skillName)
        }
    }

    /// 切换某个 Agent 的选中状态
    func toggleAgentSelection(_ agent: AgentType) {
        if selectedAgents.contains(agent) {
            selectedAgents.remove(agent)
        } else {
            selectedAgents.insert(agent)
        }
    }

    /// 重置到初始状态（重新开始）
    func reset() {
        cleanup()
        phase = .inputURL
        repoURLInput = ""
        discoveredSkills = []
        selectedSkillNames = []
        selectedAgents = [.claudeCode]
        alreadyInstalledNames = []
        progressMessage = ""
        installedCount = 0
    }
}

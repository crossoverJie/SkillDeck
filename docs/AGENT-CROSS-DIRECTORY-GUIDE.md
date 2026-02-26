# Agent 跨目录读取支持开发指南

> **用途**：当某个 AI Agent 能读取其他 Agent 的 skills 目录时，如何在 SkillDeck 中正确实现"继承安装"功能。
>
> **参考案例**：Copilot CLI 支持读取 `~/.claude/skills/`（[GitHub 官方文档](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)）

---

## 目录

1. [背景与概念](#1-背景与概念)
2. [需求分析模板](#2-需求分析模板)
3. [修改文件清单](#3-修改文件清单)
4. [分步实现指南](#4-分步实现指南)
5. [边界情况处理](#5-边界情况处理)
6. [验证清单](#6-验证清单)
7. [Copilot 实现全记录](#7-copilot-实现全记录)

---

## 1. 背景与概念

### 什么是跨目录读取

默认情况下，每个 Agent 只读取自身的 skills 目录：

```
Claude Code  → ~/.claude/skills/
Copilot CLI  → ~/.copilot/skills/
Gemini CLI   → ~/.gemini/skills/
Antigravity  → ~/.gemini/antigravity/skills/
Cursor       → ~/.cursor/skills/
Kiro         → ~/.kiro/skills/
```

但某些 Agent 会额外读取其他 Agent 的目录。例如 Copilot CLI 同时读取 `~/.copilot/skills/` 和 `~/.claude/skills/`，Cursor 同时读取 `~/.cursor/skills/` 和 `~/.claude/skills/`。

### 继承安装的定义

| 术语 | 含义 |
|------|------|
| **直接安装** | skill 存在于 Agent **自身**的 skills 目录（通过 symlink 或原始文件） |
| **继承安装** | skill 存在于**其他 Agent** 的目录，但当前 Agent 也能读取 |

### 设计原则

1. **直接安装优先**：同一 skill 同时存在于两个目录时，以 Agent 自身目录为准
2. **继承安装只读**：UI 上继承安装的 Toggle 不可操作，需到源 Agent 处修改
3. **删除安全**：删除 skill 时跳过继承安装的 symlink（它们属于其他 Agent 的目录）
4. **单一真实来源**：跨目录规则定义在 `AgentType.additionalReadableSkillsDirectories`

---

## 2. 需求分析模板

当发现新的跨目录读取场景时，先回答以下问题：

```
1. 哪个 Agent 能额外读取哪个目录？
   示例：Copilot CLI 能读取 ~/.claude/skills/

2. 官方文档链接或来源？
   示例：https://docs.github.com/en/copilot/concepts/agents/about-agent-skills

3. 是否有优先级规则？
   示例：~/.copilot/skills/ 中的同名 skill 覆盖 ~/.claude/skills/ 中的

4. 是否存在多级 symlink 链？
   示例：~/.copilot/skills/foo → ~/.claude/skills/foo → ~/.agents/skills/foo

5. Agent 是否能修改其他目录的内容？
   通常为只读（继承安装不可编辑），确认即可
```

---

## 3. 修改文件清单

每次添加跨目录支持，涉及以下文件（按修改顺序排列）：

| # | 文件 | 修改内容 | 类型 |
|---|------|---------|------|
| 1 | `Models/SkillInstallation.swift` | 已有 `isInherited` / `inheritedFrom` 字段 | **无需修改**（首次已完成） |
| 2 | `Models/AgentType.swift` | 在 `additionalReadableSkillsDirectories` 中添加新规则 | **配置修改** |
| 3 | `Services/SymlinkManager.swift` | 已有两遍扫描逻辑 | **无需修改**（自动读取新规则） |
| 4 | `Views/Components/AgentToggleView.swift` | 已支持继承安装 UI | **无需修改** |
| 5 | `Services/SkillManager.swift` | 已有继承安装防护逻辑 | **无需修改** |
| 6 | `Views/Sidebar/SidebarView.swift` | 已使用 `skillManager.skills(for:)` 计数 | **无需修改** |
| 7 | `Views/Dashboard/SkillRowView.swift` | 已支持继承图标区分 | **无需修改** |

**关键结论**：框架搭好后，新增跨目录规则通常只需修改 `AgentType.swift` 一个文件。

---

## 4. 分步实现指南

### 场景 A：新增跨目录规则（最常见）

例如：假设 Gemini CLI 将来也支持读取 `~/.claude/skills/`

**仅需修改 `Models/AgentType.swift`**：

```swift
var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType)] {
    switch self {
    case .copilotCLI:
        return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
    case .geminiCLI:  // ← 新增
        return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
    default:
        return []
    }
}
```

其他所有文件（SymlinkManager、SkillManager、Views）会自动适配，无需任何改动。

### 场景 B：添加全新的 Agent 类型

例如：添加一个新的 Agent "Aider"

#### Step 1: `Models/AgentType.swift` — 添加枚举值

```swift
enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"
    case copilotCLI = "copilot-cli"
    case openCode = "opencode"
    case aider = "aider"          // ← 新增
    // ...
}
```

然后补全所有 `switch` 语句中的新 case：

- `displayName` → `"Aider"`
- `brandColor` → 选一个未用的颜色
- `iconName` → 选一个 SF Symbol
- `skillsDirectoryPath` → `"~/.aider/skills"` 或对应路径
- `configDirectoryPath` → `"~/.aider"`
- `detectCommand` → `"aider"`
- `additionalReadableSkillsDirectories` → 如需跨目录，添加规则

#### Step 2: `Services/AgentDetector.swift` — 确认检测逻辑

`AgentDetector` 使用 `AgentType.allCases` 遍历，新增的枚举值会自动被扫描。检查 `detectCommand` 正确即可。

#### Step 3: `Utilities/Constants.swift` — 添加颜色

在 `AgentColors` 中为新 Agent 添加品牌色：

```swift
static func color(for agentType: AgentType) -> Color {
    switch agentType {
    // ...
    case .aider: return .orange
    }
}
```

#### Step 4: 编译验证

```bash
swift build
```

Swift 的 `switch` 穷举检查会确保你不遗漏任何 case。如果编译通过，所有视图（Sidebar、Dashboard、Detail、Toggle）都会自动显示新 Agent。

#### Step 5: 如需跨目录支持

回到场景 A，在 `additionalReadableSkillsDirectories` 中添加规则即可。

---

## 5. 边界情况处理

以下边界情况已在框架层面处理，新增规则时无需额外关注：

| 场景 | 预期行为 | 处理位置 |
|------|---------|---------|
| Skill 仅在源 Agent 目录 | 目标 Agent 显示继承安装 | `SymlinkManager.findInstallations` 第二遍扫描 |
| Skill 同时在两个目录 | 仅显示直接安装（优先级高） | `agentsWithDirectInstallation` 集合过滤 |
| 目标目录中的 symlink 指向源目录 | 视为直接安装 | 第一遍扫描已处理 |
| 多级 symlink 链 | `URL.resolvingSymlinksInPath()` 递归解析 | `SymlinkManager.resolveSymlink` |
| Toggle OFF 继承安装 | UI 禁用 + Service 层 `return` 防护 | `AgentToggleView` + `SkillManager.toggleAssignment` |
| 删除有继承安装的 skill | 跳过继承 symlink，删 canonical 目录后自然消失 | `SkillManager.deleteSkill` |
| 源 Agent 未安装 | 继承安装仍然显示（基于目录存在性，非 Agent 安装状态） | `SymlinkManager` 只检查文件存在 |

---

## 6. 验证清单

每次添加跨目录规则后，按以下步骤验证：

### 编译与测试

```bash
# 1. 编译通过
swift build

# 2. 所有测试通过
swift test
```

### 手动测试

```bash
# 准备测试数据（以 Copilot 读取 Claude 目录为例）

# 1. 在源 Agent 目录创建测试 skill
mkdir -p ~/.claude/skills/test-inherited/
cat > ~/.claude/skills/test-inherited/SKILL.md << 'EOF'
---
name: Test Inherited Skill
description: For testing cross-directory reading
---
This is a test skill.
EOF

# 2. 启动 SkillDeck
swift run SkillDeck

# 3. 验证以下内容：
#    - Sidebar: Copilot CLI 的 badge 包含继承 skill
#    - Dashboard: 该 skill 行中 Copilot 图标显示为低透明度
#    - Detail: Copilot Toggle 显示为 ON + disabled + "via Claude Code"
#    - 点击 Copilot Toggle 无反应（不会报错）

# 4. 在目标 Agent 目录也创建同名 skill（测试优先级）
mkdir -p ~/.copilot/skills/test-inherited/
cp ~/.claude/skills/test-inherited/SKILL.md ~/.copilot/skills/test-inherited/

# 5. 验证：Copilot 只显示直接安装（无继承标记）

# 6. 清理测试数据
rm -rf ~/.claude/skills/test-inherited/
rm -rf ~/.copilot/skills/test-inherited/
```

---

## 7. Copilot 实现全记录

以下是 Copilot CLI 跨目录读取功能的完整实现记录，作为未来开发的参考。

### 背景

Copilot CLI 会同时读取 `~/.copilot/skills/` 和 `~/.claude/skills/`。但 SkillDeck 此前只检查 Agent 自身目录，导致仅存在于 `~/.claude/skills/` 的 skill 不会显示为 Copilot 可用。

### 修改文件与关键代码

#### 1. `Models/SkillInstallation.swift` — 添加继承标记

新增两个字段，使用默认参数保持向后兼容：

```swift
struct SkillInstallation: Identifiable, Hashable {
    let agentType: AgentType
    let path: URL
    let isSymlink: Bool
    let isInherited: Bool          // 新增：是否为继承安装
    let inheritedFrom: AgentType?  // 新增：继承来源

    // 带默认参数的 init，现有代码不需要修改
    init(agentType: AgentType, path: URL, isSymlink: Bool,
         isInherited: Bool = false, inheritedFrom: AgentType? = nil) { ... }
}
```

**设计决策**：用默认参数而非新建子类型，因为 Swift struct 不支持继承，且默认参数让现有调用点无需改动。

#### 2. `Models/AgentType.swift` — 跨目录规则

新增计算属性作为跨目录规则的唯一真实来源：

```swift
var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType)] {
    switch self {
    case .copilotCLI:
        return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
    default:
        return []
    }
}
```

**设计决策**：放在 `AgentType` 而非 `SymlinkManager`，因为这是 Agent 的固有属性（"我能读取哪些目录"），遵循信息专家原则。

#### 3. `Services/SymlinkManager.swift` — 核心逻辑改造

**3a. `resolveSymlink` 改用递归解析：**

```swift
// 旧：单级解析
let resolved = try? fm.destinationOfSymbolicLink(atPath: url.path)

// 新：递归解析（处理多级 symlink 链）
return url.resolvingSymlinksInPath()
```

**3b. `findInstallations` 改为两遍扫描：**

```
第一遍：扫描每个 Agent 自身目录 → 记录到 agentsWithDirectInstallation 集合
第二遍：对于无直接安装的 Agent → 检查 additionalReadableSkillsDirectories
        → 找到则添加 isInherited: true 的安装记录
```

关键优先级逻辑：第二遍用 `guard !agentsWithDirectInstallation.contains(agentType)` 跳过已有直接安装的 Agent。

#### 4. `Views/Components/AgentToggleView.swift` — UI 层

```swift
// 查找安装记录以获取 isInherited 信息
let installation = skill.installations.first { $0.agentType == agentType }
let isInherited = installation?.isInherited ?? false

// 继承安装显示来源提示
if isInherited, let sourceAgent = installation?.inheritedFrom {
    Text("via \(sourceAgent.displayName)")
}

// Toggle 禁用继承安装
.disabled(isInherited || (!isAgentAvailable && !isInstalled))
```

#### 5. `Services/SkillManager.swift` — 防护逻辑

```swift
// toggleAssignment: 继承安装直接返回
if let installation, installation.isInherited { return }

// deleteSkill: 跳过继承安装的 symlink
for installation in skill.installations where installation.isSymlink && !installation.isInherited { ... }
```

#### 6. `Views/Sidebar/SidebarView.swift` — badge 计数

```swift
// 旧：只统计 Agent 自身目录
.badge(agent?.skillCount ?? 0)

// 新：通过 SkillManager 统计（自动包含继承安装）
.badge(skillManager.skills(for: agentType).count)
```

#### 7. `Views/Dashboard/SkillRowView.swift` — 图标区分

```swift
// 旧：用 AgentType 数组，无法区分继承
ForEach(skill.installedAgents, id: \.self) { agentType in ... }

// 新：用 SkillInstallation 数组，获取 isInherited 信息
ForEach(skill.installations) { installation in
    Image(systemName: installation.agentType.iconName)
        .opacity(installation.isInherited ? 0.4 : 1.0)
        .help(installation.isInherited ? "... (via ...)" : "...")
}
```

### 数据流总结

```
AgentType.additionalReadableSkillsDirectories  (规则定义)
        ↓
SymlinkManager.findInstallations               (两遍扫描，生成 [SkillInstallation])
        ↓
SkillScanner.scanAll → Skill.installations      (挂载到 Skill 模型)
        ↓
┌───────────────────────────────────────────────┐
│  AgentToggleView    → 读取 isInherited 控制 UI │
│  SkillRowView       → 读取 isInherited 区分图标 │
│  SidebarView        → 通过 SkillManager 计数   │
│  SkillManager       → 防护 toggle/delete 操作   │
└───────────────────────────────────────────────┘
```

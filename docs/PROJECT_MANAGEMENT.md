# 项目技能管理

## 2026-07-14 当前实现

SkillDeck 的全局技能目录由“设置 > 全局技能目录”配置，默认值是 `~/.agents/skills`。全局同步与安装、扫描、锁文件、缓存都读取该配置；全局同步的目标工具严格复用左侧“代理”栏的 `AgentType` 列表和工具配置路径。项目管理功能新增了一个独立的“项目”侧栏入口，不会把项目技能混入全局仪表盘，也不会递归扫描磁盘。项目与全局同步页均可管理统一规则，规则不会混入技能目录同步。

用户通过“项目”列表工具栏手动选择项目根目录。根目录会保存到 `UserDefaults` 的 `SkillDeck.managedProjects`；应用重启后仍会显示存在的目录。移除项目只移除 SkillDeck 的记录，不会删除项目文件。

## 目录与范围

每个项目以以下目录作为唯一源：

```text
<project>/.agents/skills
```

统一规则的唯一源为：

```text
<project>/.agents/AGENTS.md
```

全局同步使用“设置 > 全局技能目录”的父目录下的 `AGENTS.md`，默认是：

```text
~/.agents/AGENTS.md
```

只读取其中包含 `SKILL.md` 的一级技能目录。支持审计和同步的项目目标为：

```text
.claude/skills
.codex/skills
.gemini/skills
.cursor/skills
.qoder/skills
.trae/skills
.kiro/skills
.joycode/skills
.reasonix/skills
.qwen/skills
.copilot/skills
.config/opencode/skills
.gemini/antigravity/skills
.codebuddy/skills
.openclaw/skills
.qclaw/skills
.workbuddy/skills
```

### 2026-07-14 已知工具目录创建

应用会为上表中已明确支持的工具创建缺失的项目配置目录和 `skills` 软链，例如 `.codex/skills`。不会对上表之外的未知工具路径写入。项目选择和扫描只处理显式添加的根目录，不会递归发现其它仓库。

## 界面工作流

1. 左侧选择“项目”。
2. 中间栏列出所有已添加项目，显示源技能数和已完全同步的目标工具数。
3. 选择项目后，右侧顶部的工具状态条显示每个目标工具是否已整体同步；点击任意工具查看项目源技能清单。
4. 点击“同步全部工具”可一次同步该源的所有 AI 工具；也可点击“同步整个 skills 目录”只同步当前工具。预览弹窗是唯一可写入文件系统的确认入口。
5. 右侧“统一规则”区域可新建或编辑唯一规则源，并同步全部规则入口。项目会创建 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md`、`.claude/rules/skilldeck.md`、`.github/copilot-instructions.md`、`.kiro/steering/skilldeck.md`，以及会在 Cursor Rules 面板显示的 `.cursor/rules/skilldeck.mdc`；全局会创建 Codex、Claude、Gemini、Claude Rules、Kiro Steering 的对应用户级入口。

项目页保持与全局仪表盘相同的三栏导航结构：左侧导航、中间对象列表、右侧详情，而不是通过下拉框切换项目。

## 同步规则

### 2026-07-14 整目录迁移

项目同步始终迁移完整的 `.agents/skills` 目录；全局同步迁移“设置”中配置的全局源目录，目标使用整目录软链：

```text
<project>/.claude/skills -> <project>/.agents/skills
```

目标不存在时创建该目录软链。目标已经是其它软链或真实目录时，预览会显示“备份后整体替换”；确认后会备份整个目标 `skills` 目录，再替换为指向项目 `.agents/skills` 的软链。项目页不支持单技能选择或部分同步。

### 已有内容与备份

目标是其它软链、真实目录或文件时默认“跳过”。选择“备份后替换”后，原目标项目会移动到：

```text
~/Library/Application Support/SkillDeck/ProjectSyncBackups/<ISO-8601 时间>/
```

随后才创建新的 `.agents` 软链。移除操作只删除由当前同步关系管理的软链，不会删除源技能。

### 2026-07-14 统一规则

规则同步始终以一份 `AGENTS.md` 为内容源；大多数目标是规则文件软链，不复制规则内容。Cursor 项目规则会生成 `.cursor/rules/skilldeck.mdc`，其中只包含 `alwaysApply` 元数据和对统一源的 `@../../.agents/AGENTS.md` 引用，因此会出现在 Cursor 的 Rules 列表且不产生第二份规则正文。Cursor User Rules 由 Cursor 内部配置存储，未提供可安全同步的文件入口。源不存在时只能通过“新建统一规则”创建，不会自动用空文件写入目标。已有真实规则文件或外部软链会先在预览中列为冲突，确认后备份到：

```text
~/Library/Application Support/SkillDeck/RuleSyncBackups/<ISO-8601 时间>/
```

移除规则链接只会删除仍指向该统一规则源的软链，不会删除源文件或外部规则。

## 关键实现位置

- `Sources/SkillDeck/ViewModels/ProjectManager.swift`
  - `ProjectSyncFileSystem`：扫描、变更规划、备份、软链创建与移除。
  - `ProjectManager`：持久化项目根目录、选中状态、变更预览和执行日志。
- `Sources/SkillDeck/Services/RuleSyncFileSystem.swift`
  - 统一规则源、规则入口扫描、冲突备份、软链创建与移除。
- `Sources/SkillDeck/Views/Projects/ProjectManagementView.swift`
  - 项目列表、中间栏项目行、右侧工具状态条、技能明细和变更确认弹窗。
- `Sources/SkillDeck/Views/ContentView.swift`
  - 将项目管理加入现有三栏导航。
- `Sources/SkillDeck/Views/Sidebar/SidebarView.swift`
  - 新增“项目”导航入口。
- `Tests/SkillDeckTests/ProjectSyncFileSystemTests.swift`
  - 覆盖整目录链接创建、已同步识别、真实目录/外部软链的整体备份替换，以及受管理目录链接移除。

## 验证

```bash
swift test --filter ProjectSyncFileSystemTests
swift test --filter RuleSyncFileSystemTests
swift build
bash scripts/package-app.sh --version 0.1.0-local
```

本机构建后的应用安装位置：`/Applications/SkillDeck.app`。

## 当前边界

- 规则同步只覆盖文档化的规则入口，不会同步命令、MCP、模型设置或其他 Agent 配置。
- 只支持用户手动添加项目根目录。
- 只支持整目录 `.agents` 软链；不支持部分选择或单技能软链。
- 应用不会自动将既有 `.ai-global/skills` 等非 `.agents` 目录视为已同步；它们会作为冲突显示，避免静默改变项目配置。

### 2026-07-14 项目级更新

项目技能详情可关联 GitHub 仓库、检查更新并更新。关联成功会立即同步远端内容；检查完成后会明确显示“发现可用更新”或“当前已是最新版本”，更新完成后会显示成功反馈。项目更新记录写入项目自身的 `<project>/.agents/.skill-lock.json`，更新只替换该项目的技能目录，不会读写全局 `~/.agents` 的锁文件或技能文件。

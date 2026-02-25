<p align="center">
  <img src="Assets/AppIcon.svg" width="200" alt="SkillDeck App Icon" />
</p>

<h1 align="center">SkillDeck</h1>

<p align="center">
  <em>macOS 桌面端 AI 代码代理技能管理工具</em>
</p>

<p align="center">
  <a href="https://github.com/crossoverJie/SkillDeck/actions/workflows/ci.yml"><img src="https://github.com/crossoverJie/SkillDeck/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/crossoverJie/SkillDeck/releases/latest"><img src="https://img.shields.io/github/v/release/crossoverJie/SkillDeck?include_prereleases" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
</p>

<p align="center">
  <a href="README.md">English</a> | 中文
</p>

---

**SkillDeck** 是首个用于管理多个 AI 代码代理技能的桌面 GUI 工具，支持 [Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://github.com/openai/codex)、[Gemini CLI](https://github.com/google-gemini/gemini-cli)、[Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line) 和 [Antigravity](https://antigravity.google)。告别手动编辑文件、管理符号链接和手工解析 YAML。

## 截图

<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213123118.png" alt="仪表盘概览" width="800" />
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260216200457.png" alt="仪表盘概览" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/skill-detail.png" alt="技能详情" width="300" height="240"/>
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213122805.png" alt="安装" width="300" height="240"/>
</p>

## 功能特性

- **多代理支持** — Claude Code、Codex、Gemini CLI、Copilot CLI、OpenCode、Antigravity
- **技能市场浏览** — 浏览 [skills.sh](https://skills.sh) 排行榜（全部时间、趋势、热门）并搜索技能目录
- **统一仪表盘** — 所有技能集中在一个 macOS 原生三栏视图中
- **一键安装** — 从 GitHub 克隆，自动创建符号链接并更新锁文件
- **更新检测** — 检测远程更改，一键拉取更新
- **SKILL.md 编辑器** — 分栏式表单 + Markdown 编辑器，支持实时预览
- **代理分配** — 通过符号链接管理，切换技能安装到指定代理
- **自动刷新** — 文件系统监控，即时响应 CLI 端的变更

> 完整功能列表和路线图请参阅 [docs/FEATURES.md](docs/FEATURES.md)。

## 安装

### 下载安装（推荐）

从 [GitHub Releases](https://github.com/crossoverJie/SkillDeck/releases) 下载最新的通用二进制包：

1. 下载 `SkillDeck-vX.Y.Z-universal.zip`
2. 解压并将 `SkillDeck.app` 移动到 `/Applications/`
3. 首次启动时，macOS 会阻止未签名的应用。请执行以下命令：
   ```bash
   xattr -cr /Applications/SkillDeck.app
   ```
   或者：右键点击 → 打开 → 在弹出对话框中点击"打开"

### Homebrew

```bash
brew tap crossoverJie/skilldeck && brew install --cask skilldeck
```

### 从源码构建

需要 macOS 14.0+（Sonoma）、Xcode 15.0+、Swift 5.9+。

```bash
git clone https://github.com/crossoverJie/SkillDeck.git
cd SkillDeck
swift run SkillDeck

# 或在 Xcode 中打开
open Package.swift    # 然后按 Cmd+R
```

运行测试：

```bash
swift test
```

## 支持的代理

| 代理 | 技能目录 | 检测方式 |
|------|---------|---------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `~/.claude/skills/` | `claude` 二进制文件 + `~/.claude/` 目录 |
| [Codex](https://github.com/openai/codex) | `~/.agents/skills/`（共享） | `codex` 二进制文件 |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `~/.gemini/skills/` | `gemini` 二进制文件 + `~/.gemini/` 目录 |
| [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line) | `~/.copilot/skills/` | `gh` 二进制文件 |
| [Antigravity](https://antigravity.google) | `~/.gemini/antigravity/skills/` | `antigravity` 二进制文件 |

## 架构

基于 `@Observable`（macOS 14+）的 MVVM 架构。文件系统即数据库 — 技能以包含 `SKILL.md` 文件的目录形式存在。服务层使用 Swift `actor` 确保线程安全的文件系统访问。

```
Views → ViewModels (@Observable) → SkillManager → Services (actor)
```

详细的架构指南、设计决策和开发环境配置请参阅 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 贡献

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feat/my-feature`）
3. 运行测试（`swift test`）
4. 提交 Pull Request

环境配置和编码规范请参阅 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 许可证

[MIT](LICENSE)

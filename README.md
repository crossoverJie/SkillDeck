<p align="center">
  <img src="Assets/AppIcon.svg" width="200" alt="SkillDeck App Icon" />
</p>

<h1 align="center">SkillDeck</h1>

<p align="center">
  <em>The desktop GUI for managing AI code agent skills on macOS.</em>
</p>

<p align="center">
  <a href="https://github.com/crossoverJie/SkillDeck/actions/workflows/ci.yml"><img src="https://github.com/crossoverJie/SkillDeck/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/crossoverJie/SkillDeck/releases/latest"><img src="https://img.shields.io/github/v/release/crossoverJie/SkillDeck?include_prereleases" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
</p>

<p align="center">
  English | <a href="README_CN.md">中文</a>
</p>

---

**SkillDeck** is the first desktop GUI for managing skills across multiple AI code agents — [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line), [OpenCode](https://opencode.ai), [Antigravity](https://antigravity.google), [Cursor](https://cursor.com), [Kiro](https://kiro.dev), [CodeBuddy](https://www.codebuddy.ai), [OpenClaw](https://openclaw.ai), [Trae](https://www.trae.ai), and [Qoder](https://qoder.ai). No more manual file editing, symlink juggling, or YAML parsing by hand.

## Screenshots

<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/imagesdashboard.png" alt="Dashboard Overview" width="800" />
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/imagesregistry.png" alt="Registry Browser" width="800" />
</p>

## Features

- **Multi-Agent Support** — Claude Code, Codex, Copilot CLI, OpenCode, Pi, Cursor, Kiro, CodeBuddy, Trae, Qoder, QClaw, WorkBuddy, Gemini CLI, Antigravity, OpenClaw
- **Registry & Marketplace Browser** — Browse [skills.sh](https://skills.sh) leaderboard plus the ClawHub catalog for OpenClaw with search, sorting, and filters
- **Unified Dashboard** — All skills in one three-pane macOS-native view
- **Usage Insights** — Track invocation counts per skill across Codex, Claude Code, and Copilot CLI, then sort the dashboard by usage to spot and clean up skills you no longer use
- **Flexible Imports** — Install from GitHub or import from a local folder, then auto-create symlinks and update the lock file
- **Update Checker** — Detect remote changes and pull updates with one click
- **SKILL.md Editor** — Split-pane form + markdown editor with live preview
- **Agent Assignment** — Toggle which agents a skill is installed to via symlink management
- **Global Disable / Enable** — One switch hides a skill from all 15 agents at once (renames `SKILL.md` → `.SKILL.md.disabled`), preserving assignments for quick A/B testing and fully restoring them on re-enable. v1 limits: only canonical `~/.agents/skills/<id>` skills (external symlink targets, agent-directory skills, and real duplicate copies are refused); the hidden marker is the only copy of the content — don't delete it; avoid `npx skills update` while disabled. See [docs/FEATURES.md](docs/FEATURES.md#global-disable--enable--v1-limitations).
- **App Settings** — Configure global app fonts and proxy networking (HTTPS / SOCKS5, Keychain-backed credentials, bypass list)
- **Localization** — Full English and Simplified Chinese interface support with in-app language switching
- **Inline Translation** — Automatic Chinese translation of skill documentation paragraphs when UI language is set to Chinese (requires macOS 26+)
- **Auto-Refresh** — File system monitoring picks up CLI-side changes instantly

- **Built-in `skilldeck` Skill** — Manage skills via natural language in any AI agent. Install, update, delete, and assign skills to agents without leaving your terminal. See [`skills/skilldeck/SKILL.md`](skills/skilldeck/SKILL.md).

> See the full feature list and roadmap in [docs/FEATURES.md](docs/FEATURES.md).

## Installation

### Download (Recommended)

Download the latest universal binary from [GitHub Releases](https://github.com/crossoverJie/SkillDeck/releases):

1. Download `SkillDeck-vX.Y.Z-universal.zip`
2. Unzip and move `SkillDeck.app` to `/Applications/`
3. On first launch, macOS will block unsigned apps. To open:
   ```bash
   xattr -cr /Applications/SkillDeck.app
   ```
   Or: Right-click → Open → "Open" in the dialog

### Homebrew

```bash
brew tap crossoverJie/skilldeck && brew install --cask skilldeck
```

### Build from Source

Requires macOS 14.0+ (Sonoma), Xcode 15.0+, Swift 5.9+.

```bash
git clone https://github.com/crossoverJie/SkillDeck.git
cd SkillDeck
swift run SkillDeck

# Or open in Xcode
open Package.swift    # then press Cmd+R
```

Run tests:

```bash
swift test
```

## Supported Agents

| Agent | Skills Directory | Detection | Skills Reading Priority |
|-------|-----------------|-----------|------------------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `~/.claude/skills/` | `claude` binary + `~/.claude/` dir | Own directory only |
| [Codex](https://github.com/openai/codex) | `~/.codex/skills/` | `codex` binary | Own → `~/.agents/skills/` (shared global) |
| [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line) | `~/.copilot/skills/` | `gh` binary | Own → `~/.claude/skills/` |
| [OpenCode](https://opencode.ai) | `~/.config/opencode/skills/` | `opencode` binary | Own → `~/.claude/skills/` → `~/.agents/skills/` |
| [Pi](https://pi.dev) | `~/.pi/agent/skills/` | `pi` binary | Own → `~/.agents/skills/` (Agent Skills location) |
| [Cursor](https://cursor.com) | `~/.cursor/skills/` | `cursor` binary | Own → `~/.claude/skills/` |
| [Kiro](https://kiro.dev) | `~/.kiro/skills/` | `kiro` binary | Own directory only |
| [CodeBuddy](https://www.codebuddy.ai) | `~/.codebuddy/skills/` | `codebuddy` binary | Own directory only |
| [Trae](https://www.trae.ai) | `~/.trae/skills/` | `trae` binary | Own directory only |
| [Qoder](https://qoder.ai) | `~/.qoder/skills/` | `qoder` binary | Own → `~/.agents/skills/` (legacy compat) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `~/.gemini/skills/` | `gemini` binary + `~/.gemini/` dir | Own directory only |
| [Antigravity](https://antigravity.google) | `~/.gemini/antigravity/skills/` | `antigravity` binary | Own directory only |
| [OpenClaw](https://openclaw.ai) | `~/.openclaw/skills/` | `openclaw` binary | Own directory only |

## Architecture

MVVM with `@Observable` (macOS 14+). The filesystem is the database — skills are directories containing `SKILL.md` files. Services use Swift `actor` for thread-safe file system access.

```
Views → ViewModels (@Observable) → SkillManager → Services (actor)
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full architecture guide, design decisions, and development setup.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Run tests (`swift test`)
4. Open a Pull Request

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for environment setup and coding conventions.

## License

[MIT](LICENSE)

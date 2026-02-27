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

**SkillDeck** is the first desktop GUI for managing skills across multiple AI code agents — [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line), [Antigravity](https://antigravity.google), [Cursor](https://cursor.com), [Kiro](https://kiro.dev), [CodeBuddy](https://www.codebuddy.ai), and [OpenClaw](https://openclaw.ai). No more manual file editing, symlink juggling, or YAML parsing by hand.

## Screenshots

<!-- Replace the placeholder images below with actual screenshots -->

<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213123118.png" alt="Dashboard Overview" width="800" />
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260224114425.png" alt="Dashboard Registry" width="800" />
</p>

<p align="center">
  <img src="docs/screenshots/skill-detail.png" alt="Skill Detail" width="300" height="240"/>
  <img src="https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213122805.png" alt="skill install" width="300" height="240"/>
</p>

## Features

- **Multi-Agent Support** — Claude Code, Codex, Gemini CLI, Copilot CLI, OpenCode, Antigravity, Cursor, Kiro, CodeBuddy, OpenClaw
- **Registry Browser** — Browse [skills.sh](https://skills.sh) leaderboard (All Time, Trending, Hot) and search the catalog
- **Unified Dashboard** — All skills in one three-pane macOS-native view
- **One-Click Install** — Clone from GitHub, auto-create symlinks and update lock file
- **Update Checker** — Detect remote changes and pull updates with one click
- **SKILL.md Editor** — Split-pane form + markdown editor with live preview
- **Agent Assignment** — Toggle which agents a skill is installed to via symlink management
- **Auto-Refresh** — File system monitoring picks up CLI-side changes instantly

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
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `~/.gemini/skills/` | `gemini` binary + `~/.gemini/` dir | Own directory only |
| [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line) | `~/.copilot/skills/` | `gh` binary | Own → `~/.claude/skills/` |
| [OpenCode](https://opencode.ai) | `~/.config/opencode/skills/` | `opencode` binary | Own → `~/.claude/skills/` → `~/.agents/skills/` |
| [Antigravity](https://antigravity.google) | `~/.gemini/antigravity/skills/` | `antigravity` binary | Own directory only |
| [Cursor](https://cursor.com) | `~/.cursor/skills/` | `cursor` binary | Own → `~/.claude/skills/` |
| [Kiro](https://kiro.dev) | `~/.kiro/skills/` | `kiro` binary | Own directory only |
| [CodeBuddy](https://www.codebuddy.ai) | `~/.codebuddy/skills/` | `codebuddy` binary | Own directory only |
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

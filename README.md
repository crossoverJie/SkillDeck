# SkillDeck

> Native macOS application for visual management of AI code agent skills.

**SkillDeck** is the first desktop GUI for managing skills across multiple AI code agents — [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), and [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line). No more manual file editing, symlink juggling, or YAML parsing by hand.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-NavigationSplitView-purple)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Highlights

- **Multi-Agent Support** — Claude Code, Codex, Gemini CLI, Copilot CLI, OpenCode
- **Unified Dashboard** — All skills in one three-pane macOS-native view
- **One-Click Install** — Clone from GitHub, auto-create symlinks and update lock file
- **Update Checker** — Detect remote changes and pull updates with one click
- **SKILL.md Editor** — Split-pane form + markdown editor with live preview
- **Agent Assignment** — Toggle which agents a skill is installed to via symlink management
- **Auto-Refresh** — File system monitoring picks up CLI-side changes instantly

> See the full feature list and roadmap in [docs/FEATURES.md](docs/FEATURES.md).

---

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

```bash
git clone https://github.com/crossoverJie/SkillDeck.git
cd SkillDeck
swift run SkillDeck
```

---

## Quick Start

### Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+ (for building)
- Swift 5.9+

### Build & Run

```bash
# Build and run
swift run SkillDeck

# Or open in Xcode
open Package.swift
# Then press Cmd+R to run
```

### Run Tests

```bash
swift test
```

---

## Architecture

```
MVVM + @Observable (macOS 14+)

View (SwiftUI)  ──►  ViewModel (@Observable)  ──►  Service (actor)
                                                      │
                                         ┌────────────┼────────────┐
                                         ▼            ▼            ▼
                                    SkillScanner  LockFileMgr  AgentDetector
                                         │            │            │
                                         ▼            ▼            ▼
                                    File System   .skill-lock   which/CLI
                                    (SKILL.md)     (.json)      binaries
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| SwiftUI + @Observable | Modern declarative UI with automatic state tracking |
| No embedded database | The filesystem IS the database — skills are directories |
| Shell out to `git` | Avoids bundling libgit2; skills ecosystem requires git |
| Yams for YAML | Most popular Swift YAML parser for SKILL.md frontmatter |
| Actor-based services | Compiler-enforced thread safety for file system operations |

### Agent Skill Paths

| Agent | Skills Directory | Detection |
|-------|-----------------|-----------|
| Claude Code | `~/.claude/skills/` | `claude` binary + `~/.claude/` dir |
| Codex | `~/.agents/skills/` (shared) | `codex` binary |
| Gemini CLI | `~/.gemini/skills/` | `gemini` binary + `~/.gemini/` dir |
| Copilot CLI | `~/.copilot/skills/` | `gh` binary |

### Symlink Pattern

```
~/.agents/skills/my-skill/          ← CANONICAL (real files)
    ├── symlink ← ~/.claude/skills/my-skill
    ├── symlink ← ~/.gemini/skills/my-skill
    └── symlink ← ~/.copilot/skills/my-skill
```

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (macOS 14+) |
| Architecture | MVVM + @Observable |
| YAML | [Yams](https://github.com/jpsim/Yams) ~5.0 |
| Markdown | [swift-markdown](https://github.com/apple/swift-markdown) ~0.4 |
| Collections | [swift-collections](https://github.com/apple/swift-collections) ~1.1 |
| File Watching | DispatchSource (FSEvents) |
| Git | System `git` via Process |

---

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for a comprehensive development guide covering:
- Environment setup
- Building and running
- Swift quick start for Java/Go/Python developers
- SwiftUI concepts
- Testing
- Packaging and distribution

---

## License

MIT

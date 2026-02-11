# SkillDeck

> Native macOS application for visual management of AI code agent skills.

**SkillDeck** is the first desktop GUI for managing skills across multiple AI code agents — [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), and [Copilot CLI](https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-in-the-command-line). No more manual file editing, symlink juggling, or YAML parsing by hand.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-NavigationSplitView-purple)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features (v0.1 MVP)

- [x] **F01 — Agent Detection**: Auto-detect installed agents (Claude Code, Codex, Gemini CLI, Copilot CLI) by checking config directories and CLI binaries
- [x] **F02 — Unified Dashboard**: Single view of all skills across agents and scopes, with symlink deduplication
- [x] **F03 — Skill Detail View**: Parse and render SKILL.md (YAML frontmatter + markdown body)
- [x] **F04 — Skill Deletion**: Delete skill directory + remove symlinks + update `.skill-lock.json`
- [x] **F05 — SKILL.md Editor**: Edit frontmatter fields (form) + markdown body (split-pane with preview)
- [x] **F06 — Agent Assignment**: Toggle which agents a skill is symlinked to via checkboxes
- [x] **F07 — Lock File Management**: Read/write `~/.agents/.skill-lock.json` preserving all fields
- [x] **F08 — File System Watching**: DispatchSource/FSEvents to react to external changes from CLI tools

## TODO — Planned Features

### P1 (v1.0)

- [ ] **F09 — Registry Browser**: Browse [skills.sh](https://skills.sh) catalog (all-time, trending, hot) with search
- [ ] **F10 — One-Click Install**: Clone from GitHub, place in `~/.agents/skills/`, create symlinks, update lock file
- [ ] **F11 — Project Skills**: Open a project directory, manage its `.agents/skills/`
- [ ] **F12 — Update Checker**: Compare local `skillFolderHash` against remote repo HEAD
- [ ] **F13 — Create Skill Wizard**: Scaffold new skill with SKILL.md template
- [ ] **F14 — Search & Filter**: Filter by agent, scope, author; full-text search across skill content
- [ ] **F15 — Menu Bar Quick Access**: Menu bar icon for quick skill management actions

### P2 (Future)

- [ ] **F16 — Plugins Viewer**: Read-only view of Claude Code plugins (`installed_plugins.json`)
- [ ] **F17 — Skill Dependency Graph**: Visualize skill relationships and dependencies
- [ ] **F18 — Marketplace Manager**: Full marketplace integration for discovering and installing skills
- [ ] **F19 — Bulk Operations**: Multi-select delete, assign, and other batch actions
- [ ] **F20 — Skill Export/Import**: Zip bundle export and import for skill sharing
- [ ] **F21 — Settings Sync**: iCloud or git-based settings synchronization across machines
- [ ] **App Icon**: Custom app icon design
- [ ] **Notarized DMG**: Signed and notarized distribution package
- [ ] **Homebrew Cask**: `brew install --cask skilldeck` distribution
- [ ] **Markdown Rendering**: Rich markdown rendering in detail view (currently shows source)
- [ ] **Dark Mode Polish**: Fine-tuned dark mode color adjustments

---

## Quick Start

### Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+ (for building)
- Swift 5.9+

### Build & Run

```bash
# Clone the repository
git clone <repo-url>
cd SkillDeck

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

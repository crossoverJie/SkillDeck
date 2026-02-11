# SkillDeck — Native macOS Agent Skills Manager

## Context

AI code agent skills (Claude Code, Codex, Gemini CLI, Copilot CLI) are currently managed entirely through CLI tools and manual file editing. Developers using multiple agents must navigate fragmented directory structures, parse YAML frontmatter by hand, manage symlinks, and keep lock files in sync — all without any visual interface. Despite having 5+ CLI-based skill managers (skills-supply, Vercel Skills CLI, Skillport, etc.), **no native desktop GUI exists**. SkillDeck fills this gap as the first native macOS application for unified visual management of AI code agent skills.

---

## Original Requirements Feedback

### Issue 1: "Global skills" needs clearer scoping
The filesystem actually has **three** distinct scopes:
- **Shared global**: `~/.agents/skills/` — canonical store, symlinked into agent directories
- **Agent-local**: e.g., `~/.claude/skills/auto-blog-cover/` — only in one agent
- **Project-level**: `.agents/skills/` within a project directory

**Recommendation**: The UI must explicitly show these scopes as badges, not treat everything as flat.

### ~~Issue 2: Copilot CLI~~ (Resolved)
~~Copilot CLI uses hooks-based plugins, not SKILL.md.~~
**Update**: As of Dec 2025, Copilot fully supports SKILL.md format. It reads from `~/.copilot/skills` (personal) and `.github/skills` or `.claude/skills` (project). Copilot is now a **first-class agent** in the MVP alongside Claude Code, Codex, and Gemini CLI.

### Issue 3: Missing "update/sync" workflow
Skills from GitHub repos (tracked in `.skill-lock.json` with `skillFolderHash`) can become outdated. The user mentions "update" but not a diff/sync mechanism.

**Recommendation**: Add an explicit "Check for Updates" feature comparing local hashes against remote repo HEAD.

### Issue 4: No mention of skill authoring
All CLI tools include `init` commands for creating new skills. A "Create New Skill" wizard should be a P1 feature.

### Issue 5: Plugins vs Skills distinction
Claude Code has a separate **plugins** system (`~/.claude/plugins/`) that bundles skills. This should at least be visible read-only.

---

## Feature Set

### P0 — MVP (v0.1)

| ID | Feature | Description |
|----|---------|-------------|
| F01 | Agent Detection | Auto-detect installed agents by checking `~/.claude/`, `~/.gemini/`, `~/.agents/`, CLI binaries |
| F02 | Unified Dashboard | Single view of all skills across agents/scopes, with symlink deduplication |
| F03 | Skill Detail View | Parse & render SKILL.md (YAML frontmatter + markdown body) |
| F04 | Skill Deletion | Delete skill directory + remove symlinks + update `.skill-lock.json` |
| F05 | SKILL.md Editor | Edit frontmatter fields (form) + markdown body (split-pane with preview) |
| F06 | Agent Assignment | Toggle which agents a skill is symlinked to via checkboxes |
| F07 | Lock File Management | Read/write `~/.agents/.skill-lock.json` preserving all fields |
| F08 | File System Watching | FSEvents to react to external changes from CLI tools |

### P1 — v1.0

| ID | Feature | Description |
|----|---------|-------------|
| F09 | Registry Browser | Browse skills.sh (all-time, trending, hot) with search |
| F10 | One-Click Install | Clone from GitHub, place in `~/.agents/skills/`, create symlinks, update lock file |
| F11 | Project Skills | Open a project directory, manage its `.agents/skills/` |
| F12 | Update Checker | Compare local `skillFolderHash` against remote repo HEAD |
| F13 | Create Skill Wizard | Scaffold new skill with SKILL.md template |
| F14 | Search & Filter | Filter by agent, scope, author; full-text search |
| F15 | Menu Bar Quick Access | Menu bar icon for quick actions |

### P2 — Future

| ID | Feature |
|----|---------|
| F16 | Plugins viewer (Claude Code `installed_plugins.json`) |
| F17 | Skill dependency graph visualization |
| F18 | Marketplace manager |
| F19 | Bulk operations (multi-select delete/assign) |
| F20 | Skill export/import (zip bundles) |
| F21 | Settings sync (iCloud/git) |

---

## Architecture

```
SkillDeck.app (SwiftUI, macOS 14+, MVVM + @Observable)

Presentation ──── Views (SwiftUI)
    │               ├── ContentView (NavigationSplitView)
    │               ├── DashboardView + SkillRowView
    │               ├── SkillDetailView
    │               ├── SkillEditorView + MarkdownEditorView
    │               ├── RegistryBrowserView (P1)
    │               └── SettingsView
    │
ViewModel ──── @Observable ViewModels
    │               ├── DashboardViewModel
    │               ├── SkillDetailViewModel
    │               └── RegistryViewModel
    │
Domain ──── Business Logic
    │               ├── SkillManager (CRUD orchestrator)
    │               ├── AgentDetector (detect installed agents)
    │               ├── SkillScanner (walk dirs, resolve symlinks, deduplicate)
    │               ├── SkillMDParser (YAML frontmatter + markdown)
    │               ├── SymlinkResolver (create/remove/resolve symlinks)
    │               ├── LockFileManager (read/write .skill-lock.json)
    │               └── UpdateChecker (hash comparison)
    │
Infra ──── Infrastructure
                    ├── FileSystemWatcher (FSEvents)
                    ├── GitClient (shell out to system git)
                    ├── RegistryClient (fetch skills.sh)
                    └── ProcessRunner (generic Process wrapper)
```

### Key Architectural Decisions

1. **Distribute outside App Store** — App needs `~/` access to hidden directories. Notarized DMG + Homebrew Cask.
2. **No embedded database** — The filesystem IS the database. Skills = directories. Lock file = index. In-memory cache + FSEvents keeps it fresh.
3. **Shell out to `git`** — Avoids bundling libgit2. Skills ecosystem already requires git.
4. **Yams for YAML** — Most popular Swift YAML parser for SKILL.md frontmatter.

---

## Core Data Models

```swift
struct Agent {
    let type: AgentType           // .claudeCode, .codex, .geminiCLI, .copilotCLI
    let displayName: String
    let userSkillsPath: URL       // e.g., ~/.claude/skills/
    let isInstalled: Bool
}

struct Skill {
    let id: String                // directory name
    let directoryURL: URL         // canonical (symlink-resolved) path
    var metadata: SkillMetadata   // from SKILL.md frontmatter
    var markdownBody: String      // below frontmatter
    var scope: SkillScope         // .sharedGlobal / .agentLocal / .project
    var installations: [SkillInstallation]  // which agents have it
    var lockEntry: LockEntry?     // from .skill-lock.json
}

enum SkillScope { case sharedGlobal, agentLocal(AgentType), project(URL) }
```

### Agent Detection Paths

| Agent | Config Dir | Skills Dir | Lock File | Detection |
|-------|-----------|------------|-----------|-----------|
| Claude Code | `~/.claude/` | `~/.claude/skills/` | `~/.agents/.skill-lock.json` | Dir exists + `claude` binary |
| Codex | — | `~/.agents/skills/` (shared) | `~/.agents/.skill-lock.json` | `codex` binary |
| Gemini CLI | `~/.gemini/` | `~/.gemini/skills/` | `~/.agents/.skill-lock.json` | Dir exists + `gemini` binary |
| Copilot CLI | `~/.copilot/` | `~/.copilot/skills/` | `~/.agents/.skill-lock.json` | `gh copilot` subcommand |

**Key insight**: Codex reads directly from `~/.agents/skills/` — the shared store IS its skills directory (no symlink needed).

### Symlink Graph (Real Filesystem Pattern)

```
~/.agents/skills/agent-notifier/        ← CANONICAL
    ├── symlink ← ~/.claude/skills/agent-notifier
    ├── symlink ← ~/.gemini/skills/agent-notifier
    └── symlink ← ~/.copilot/skills/agent-notifier
```

Toggling "Enable for Gemini CLI" creates/removes the symlink at `~/.gemini/skills/{name}`.

---

## UI Structure

```
Sidebar (NavigationSplitView)
├── Dashboard          ← unified skills list (default view)
├── Agents
│   ├── Claude Code
│   ├── Gemini CLI
│   ├── Codex
│   └── Copilot CLI
├── Projects
│   ├── Recent Project 1
│   └── Recent Project 2
├── Registry           ← browse skills.sh (P1)
└── Settings
```

### Design Language
- Apple HIG compliant, SF Symbols for icons
- Agent color coding: Claude=coral, Gemini=blue, Codex=green, Copilot=purple
- Scope badges: "Global"(blue), "Local"(gray), "Project"(green+folder)

---

## Implementation Phases (MVP)

### Phase 1 (Week 1-2): Foundation
- Xcode project setup, SwiftUI, macOS 14 target
- `Agent`, `Skill`, `SkillMetadata` models
- `AgentDetector`, `SkillMDParser` (using Yams), `LockFileManager`
- `SkillScanner` — walk dirs, resolve symlinks, deduplicate
- Unit tests for parsers and scanners

### Phase 2 (Week 3-4): Core UI
- `NavigationSplitView` shell with sidebar
- `DashboardView` with skill list, sorting, filtering
- `SkillDetailView` with rendered markdown
- Agent badges, scope tags, ViewModel wiring

### Phase 3 (Week 5): CRUD Operations
- `SkillEditorView` — form fields + split-pane markdown editor
- Save-to-SKILL.md serialization
- Skill deletion with confirmation dialog
- Agent assignment toggle (symlink create/remove)
- Lock file write-back with atomic writes

### Phase 4 (Week 6): Polish
- `FileSystemWatcher` with FSEvents + debounce
- Error handling (permissions, missing files, corrupted YAML)
- "Open in Finder" / "Open in Terminal" actions
- App icon, notarized DMG build

---

## Technical Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (macOS 14+) |
| Architecture | MVVM + @Observable |
| YAML | [Yams](https://github.com/jpsim/Yams) ~5.0 |
| Markdown | [swift-markdown](https://github.com/apple/swift-markdown) ~0.4 |
| Collections | [swift-collections](https://github.com/apple/swift-collections) ~1.1 |
| File Watching | FSEvents / DispatchSource |
| Git | System `git` via Process |
| Distribution | Notarized DMG + Homebrew Cask |

---

## Key Files to Reference

- `~/.agents/.skill-lock.json` — Central registry, defines lock file schema (version 3)
- `~/.agents/skills/*/SKILL.md` — Reference SKILL.md examples for parser
- `~/.claude/settings.json` — Claude Code hooks config
- `~/.claude/plugins/installed_plugins.json` — Plugin metadata for future viewer

---

## Project Name Candidates

| Name | Rationale |
|------|-----------|
| **SkillDeck** | A "deck" of skill cards. Short, memorable, maps to card-based dashboard UI. Already the repo name. |
| **SkillForge** | Where skills are crafted. Evokes workshop/tooling. Strong creation connotation. |
| **Aptitude** | Elegant synonym for "skill". Fits macOS single-word naming (like Finder, Safari). |
| **SkillHarbor** | A port where skills dock across agents. Hub metaphor for cross-agent value. |
| **SkillBridge** | Bridges skills across multiple agents. Clear cross-agent metaphor. |
| **Artificer** | One who crafts tools/artifacts. Fantasy/gaming appeal for developers. |

**Recommendation**: **SkillDeck** — descriptive, unique, the "deck" metaphor maps perfectly to a card-based dashboard, and it's already the repo name.

---

## Verification Plan

1. **Unit tests**: `SkillMDParser`, `LockFileManager`, `SymlinkResolver`, `AgentDetector`
2. **Integration test**: Scan real `~/.claude/skills/` and `~/.agents/skills/`, verify deduplication
3. **Manual test**: Create/edit/delete a test skill, verify file changes on disk
4. **Symlink test**: Toggle agent assignment, verify symlinks with `readlink`
5. **File watching test**: Run `npx skills add` in terminal, verify app refreshes
6. **Build test**: Archive, notarize, install DMG on clean machine

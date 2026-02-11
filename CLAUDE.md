# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Code Style: Comments Required

The author has extensive Java/Golang/Python experience but is new to Swift and macOS app development. All generated code must include detailed comments in Chinese explaining:
- Swift-specific syntax and language features (e.g., `@Observable`, `actor`, `some View`, property wrappers)
- SwiftUI concepts and view lifecycle (e.g., `.task`, `.environment()`, `NavigationSplitView`)
- macOS/Apple platform APIs (e.g., `NSWorkspace`, `DispatchSource`, `FileManager`)
- Why a particular Swift pattern is used when it differs from the Java/Go/Python equivalent

## Build & Run Commands

```bash
swift build                  # Development build
swift build -c release       # Optimized release build
swift run SkillDeck          # Build and launch the app
open Package.swift           # Open in Xcode (Cmd+R to run)
swift test                   # Run all tests
swift test --filter SkillMDParserTests                    # Run one test class
swift test --filter SkillMDParserTests/testParseStandardSkillMD  # Run one test method
swift package clean          # Clean build artifacts
```

First build downloads dependencies (Yams, swift-markdown, swift-collections).

## Architecture

MVVM with `@Observable` (macOS 14+). The filesystem is the database — skills are directories containing `SKILL.md` files.

```
Views → ViewModels (@Observable) → SkillManager (@Observable) → Services (actor)
```

**SkillManager** (`Services/SkillManager.swift`) is the central orchestrator — injected into the view tree via `.environment()`. It coordinates all sub-services and exposes the public API that ViewModels call.

**Services** use Swift `actor` for thread-safe file system access:
- **SkillScanner** — scans `~/.agents/skills/` and per-agent directories, deduplicates via symlink resolution
- **LockFileManager** — reads/writes `~/.agents/.skill-lock.json` with atomic writes and caching
- **AgentDetector** — detects installed agents by checking CLI binaries (`which`) and config directories
- **SymlinkManager** — static methods for creating/removing symlinks between canonical and agent directories
- **FileSystemWatcher** — DispatchSource/FSEvents monitoring with 0.5s debounce, publishes via Combine

**ViewModels** are `@MainActor @Observable` classes: `DashboardViewModel`, `SkillDetailViewModel`, `SkillEditorViewModel`.

**Views** use `NavigationSplitView` (3-pane macOS layout): Sidebar → Dashboard list → Detail pane.

## Key Data Patterns

**Skill storage**: canonical files live in `~/.agents/skills/<name>/SKILL.md`. Each agent gets a symlink: `~/.claude/skills/<name>` → canonical path. The lock file at `~/.agents/.skill-lock.json` (version 3) tracks metadata.

**SKILL.md format**: YAML frontmatter (between `---` delimiters) + markdown body. Parsed by `SkillMDParser` (enum namespace with static methods). Metadata struct is `Codable` for Yams serialization.

**Deduplication**: `SkillScanner` resolves all symlinks to canonical paths, then merges installations for the same canonical skill into a single `Skill` model.

## Swift/SwiftUI Gotchas

- `actor` properties require `await` when accessed from outside the actor
- `@Observable` requires `class`, not `struct`; pair with `@MainActor` for UI state
- `NSWorkspace` needs explicit `import AppKit` in non-View files (SwiftUI re-exports it implicitly)
- Tilde paths must be expanded: `NSString(string: "~/.agents").expandingTildeInPath`
- When checking if a path is a symlink, use `attributesOfItem` — `fileExists` follows symlinks

## Supported Agents

| Agent | Skills Directory | CLI Detection |
|-------|-----------------|---------------|
| Claude Code | `~/.claude/skills/` | `claude` binary |
| Codex | `~/.agents/skills/` | `codex` binary |
| Gemini CLI | `~/.gemini/skills/` | `gemini` binary |
| Copilot CLI | `~/.copilot/skills/` | `gh` binary |

## Testing

Tests are in `Tests/SkillDeckTests/`. Three test files exist: `SkillMDParserTests`, `LockFileManagerTests`, `SymlinkManagerTests`. Tests use `@testable import SkillDeck` for internal access.

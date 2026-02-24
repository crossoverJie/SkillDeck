# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Code Style: Comments Required

The author has extensive Java/Golang/Python experience but is new to Swift and macOS app development. All generated code must include detailed comments in **English** explaining:
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

## Branching & Code Change Policy

- **Documentation-only changes** (README, CLAUDE.md, docs/, comments) may be committed directly to `main`.
- **All other code changes** (source files, tests, configs, scripts) **must** be made on a feature/bugfix branch and merged via Pull Request. Never commit code changes directly to `main`.
- Branch naming convention: `feature/<short-description>`, `bugfix/<short-description>`, or `refactor/<short-description>`.

## Testing

Tests are in `Tests/SkillDeckTests/`. Three test files exist: `SkillMDParserTests`, `LockFileManagerTests`, `SymlinkManagerTests`. Tests use `@testable import SkillDeck` for internal access.

**Testing requirements for code changes:**

- All code modifications should include unit tests to cover the new or changed logic. Add tests to existing test files or create new test files as appropriate.
- Run `swift test` before submitting a PR to ensure all existing tests still pass — no regressions allowed.
- If a change is difficult to unit test (e.g., pure UI layout), explain why in the PR description.

## Pull Requests

When creating PRs with `gh pr create`, always use **English** for the title, body, and all content.

**Every PR must include the following sections in the body:**

- **Manual Verification Required**: List the specific logic or behaviors that cannot be fully covered by automated tests and need the reviewer to manually verify (e.g., UI rendering, drag-and-drop interactions, system permission prompts).
- **Regression Checklist**: Based on the files and modules changed, list the existing features that should be regression-tested to confirm they still work correctly. Be specific — reference concrete user-facing functionality (e.g., "Skill creation flow", "Symlink sync to ~/.claude/skills/", "Lock file read/write").

## Release

Use `scripts/release.sh` to publish a new version:

```bash
bash scripts/release.sh <version> --dry   # Dry run to verify checks
bash scripts/release.sh <version>          # Create and push tag (confirm with y)
```

**Version bump rules:**

- **"升级一个小版本" (patch release)**: bump patch +1 (e.g. v0.0.3 → v0.0.4 → v0.0.5)
- **"发布一个大版本" (minor release)**: bump minor +1, reset patch to 0 (e.g. v0.1.0 → v0.2.0 → v0.3.0)

Before releasing, run `git tag --sort=-creatordate | head -5` to find the latest tag and determine the next version number.

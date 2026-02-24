---
title: "I Built a Native macOS App to Manage AI Code Agent Skills — Here's Why"
published: false
description: "SkillDeck is the first desktop GUI for managing skills across Claude Code, Codex, Gemini CLI, Copilot CLI, and OpenCode. No more YAML editing, symlink juggling, or lock file headaches."
tags: ai, macos, swift, devtools
cover_image: https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213123118.png
---

## The Problem: Skill Sprawl Across AI Agents

If you're using AI code agents in your daily workflow, you probably have more than one. Claude Code for deep reasoning, Codex for quick edits, Gemini CLI when you want a second opinion, Copilot for inline completions. Each agent supports **skills** — markdown-based instruction files that customize agent behavior for specific tasks.

The catch? Every agent stores skills in its own directory:

```
~/.claude/skills/
~/.agents/skills/
~/.gemini/skills/
~/.copilot/skills/
```

Want to install a skill across all your agents? You'll need to:

1. Clone a GitHub repo
2. Parse YAML frontmatter in `SKILL.md` files
3. Copy or symlink the skill directory into each agent's folder
4. Update the JSON lock file at `~/.agents/.skill-lock.json`
5. Repeat for every skill, every agent, every update

I was doing this manually for weeks. One wrong symlink and an agent silently ignores the skill. One stale lock file entry and your metadata drifts. It's the kind of tedious plumbing that shouldn't exist in 2026.

So I built **SkillDeck**.

## What is SkillDeck?

[SkillDeck](https://github.com/crossoverJie/SkillDeck) is a native macOS app that gives you a unified GUI for managing AI code agent skills. It's the first desktop interface for this workflow — everything else is CLI-only.

![SkillDeck Dashboard](https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260216200457.png)

One window. All your agents. All your skills. No terminal required.

### Supported Agents

| Agent | Skills Directory | Auto-Detection |
|-------|-----------------|----------------|
| Claude Code | `~/.claude/skills/` | `claude` binary |
| Codex | `~/.agents/skills/` | `codex` binary |
| Gemini CLI | `~/.gemini/skills/` | `gemini` binary |
| Copilot CLI | `~/.copilot/skills/` | `gh` binary |
| OpenCode | Agent-specific dir | `opencode` binary |

SkillDeck auto-detects which agents you have installed and shows their status at a glance.

## Key Features

### Unified Dashboard

All installed skills appear in one list, deduplicated across agents. A skill that's symlinked to Claude Code, Gemini, and Copilot shows up once — with badges indicating where it's installed.

You can search across name, description, author, and source repo. Sort by name, scope, or agent count.

### One-Click Install from GitHub

Enter a repo URL (or just `owner/repo`), and SkillDeck clones it, scans for `SKILL.md` files, and lets you batch-install skills to whichever agents you choose.

![Install from GitHub](https://cdn.jsdelivr.net/gh/crossoverJie/images@main/images/images20260213122805.png)

It handles the symlinks, updates the lock file, and prevents duplicates — all in one click.

### Registry Browser

Browse the [skills.sh](https://skills.sh) leaderboard directly inside the app. Filter by All Time, Trending, or Hot. Search as you type. Install with one click.

### SKILL.md Editor

Edit skill metadata and markdown content in a split-pane view — form fields on the left, markdown preview on the right. Save with `Cmd+S`. No more hand-editing YAML frontmatter.

### Agent Assignment Toggles

For any skill, toggle which agents have access to it. SkillDeck creates or removes symlinks under the hood. Cross-agent inheritance (e.g., Copilot reading Claude's directory) is handled gracefully with read-only indicators.

### Update Checker

SkillDeck compares your local skill's git tree hash against the remote. When updates are available, you get an orange badge with the count. One click to pull the latest, and a link to view the exact diff on GitHub.

### Live File System Sync

Changed something from the CLI? SkillDeck watches the filesystem with FSEvents and auto-refreshes within 500ms. The GUI and CLI never go out of sync.

## Architecture: The Filesystem Is the Database

SkillDeck doesn't use SQLite, Core Data, or any embedded database. The filesystem **is** the database:

```
~/.agents/skills/agent-notifier/         ← Canonical location (real files)
    ├── symlink ← ~/.claude/skills/agent-notifier
    ├── symlink ← ~/.gemini/skills/agent-notifier
    └── symlink ← ~/.copilot/skills/agent-notifier

~/.agents/.skill-lock.json               ← Central metadata registry
```

This means SkillDeck is fully interoperable with CLI tools. Install a skill from the terminal, and SkillDeck picks it up immediately. Delete one in SkillDeck, and the CLI sees the change. Zero lock-in.

### Tech Stack

- **SwiftUI** with `NavigationSplitView` for the three-pane macOS layout
- **@Observable** (macOS 14+) for reactive state management — no Combine boilerplate
- **Swift actors** for thread-safe filesystem access
- **Yams** for YAML parsing, **swift-markdown** for rendering
- **FSEvents/DispatchSource** for filesystem monitoring with 0.5s debounce

The codebase is ~7,500 lines of Swift, structured as clean MVVM:

```
Views → ViewModels (@Observable) → SkillManager → Services (actor)
```

## Installation

**Homebrew** (recommended):

```bash
brew tap crossoverJie/skilldeck
brew install --cask skilldeck
```

**Download DMG**: Grab the latest universal binary from [GitHub Releases](https://github.com/crossoverJie/SkillDeck/releases).

**Build from source**:

```bash
git clone https://github.com/crossoverJie/SkillDeck.git
cd SkillDeck
swift run SkillDeck
```

Requires macOS 14 (Sonoma) or later.

## Why Native macOS?

I considered Electron and Tauri. But for a tool that watches filesystems, manages symlinks, and lives in your menubar, a native app makes sense:

- **Performance**: Instant launch, ~30MB memory footprint
- **Integration**: Finder reveal, Terminal open, system notifications
- **UX**: Follows Apple HIG — keyboard shortcuts, three-pane navigation, native controls
- **No runtime**: No Node.js, no Chromium, no WebView overhead

If you're on macOS and managing AI agent skills, this should feel like it belongs on your machine.

## What's Next

SkillDeck is under active development. Here's what's coming:

- **Create Skill Wizard** — scaffold a new `SKILL.md` from a template
- **Project-Level Skills** — manage `.agents/skills/` within project directories
- **Menu Bar Quick Access** — check skill status without opening the full app
- **Skill Dependency Graph** — visualize relationships between skills
- **Bulk Operations** — multi-select skills for batch install/update/delete

## Try It Out

If you're juggling skills across multiple AI code agents, give SkillDeck a try:

**GitHub**: [github.com/crossoverJie/SkillDeck](https://github.com/crossoverJie/SkillDeck)

Stars, issues, and PRs are all welcome. If you find a bug or want a feature, [open an issue](https://github.com/crossoverJie/SkillDeck/issues).

---

*SkillDeck is MIT-licensed and open source. Built with Swift and SwiftUI for macOS 14+.*

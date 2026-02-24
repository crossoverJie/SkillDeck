**Title:** SkillDeck — a free app I made for managing AI code agent skills (Claude Code, Codex, Gemini CLI, etc.)

**Body:**

Hey everyone. I've been using multiple AI code agents (Claude Code, Codex, Gemini CLI, Copilot) for a while now, and one thing that kept bugging me was managing skills across all of them.

For those unfamiliar — skills are basically markdown instruction files that tell your AI agent how to behave for specific tasks. The problem is each agent stores them in a different directory, and if you want the same skill available in multiple agents, you're creating symlinks by hand, editing YAML frontmatter, updating JSON lock files... it gets old fast.

I broke a few things along the way (wrong symlink, stale lock file, agent silently ignoring a skill with no error), so I figured I'd just build a proper GUI for it.

**What it does:**

- Shows all your installed skills in one place, across all agents
- Auto-detects which agents you have (Claude Code, Codex, Gemini CLI, Copilot CLI, OpenCode)
- Install skills from GitHub repos or browse the skills.sh registry
- Toggle which agents get access to which skills (handles symlinks for you)
- Edit SKILL.md files with a split-pane editor
- Check for updates and pull them in one click
- Watches the filesystem so CLI changes show up instantly

It's a native SwiftUI app, not Electron. Runs on macOS 14+.

**Install:**

```
brew tap crossoverJie/skilldeck
brew install --cask skilldeck
```

Or grab the DMG from GitHub releases.

GitHub: https://github.com/crossoverJie/SkillDeck

Free and open source (MIT). Would love to hear feedback or feature requests.

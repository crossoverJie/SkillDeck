# Features & Roadmap

## Current Features

### Browsing & Search

| Feature | Description |
|---------|-------------|
| Unified Dashboard | View all installed skills in one place, aggregated across agents |
| Three-Pane Layout | Native macOS NavigationSplitView: Sidebar → List → Detail |
| Multi-Field Search | Search by name, description, author, and repository source |
| Filter by Agent | Click a specific agent in the sidebar to view its installed skills |
| Sorting | Sort by name, scope, or agent count with ascending/descending toggle |
| Symlink Deduplication | Automatically resolves symlinks so each canonical skill appears only once |

### Agent Detection & Management

| Feature | Description |
|---------|-------------|
| Auto-Detect Agents | Detects installed agents via CLI binaries and config directories |
| Multi-Agent Support | Claude Code, Codex, Gemini CLI, Copilot CLI, OpenCode |
| Agent Status Indicators | Sidebar shows skill count per agent; uninstalled agents shown dimmed |
| Agent Assignment | Toggle switches to install/uninstall a skill to specific agents (auto-manages symlinks) |
| Inherited Installation Protection | Inherited cross-agent installations are labeled with their source and toggle-disabled |

### Skill Detail & Editing

| Feature | Description |
|---------|-------------|
| Full Metadata Display | Shows name, description, author, version, license, scope, and more |
| Lock File Info | Displays source repo, commit hash, install/update timestamps from the lock file |
| Copy Path | One-click copy of the skill directory path to clipboard with visual feedback |
| Open in Finder | Reveal the skill directory in macOS Finder |
| Open in Terminal | Launch Terminal with the skill directory as the working directory |
| SKILL.md Editor | Split-pane editor: metadata form + markdown editing on the left, live preview on the right |
| Keyboard Shortcuts | Cmd+S to save, Esc to cancel in the editor |

### Skill Installation & Deletion

| Feature | Description |
|---------|-------------|
| Install from GitHub | Enter a repo URL or `owner/repo`, auto-clones and scans for skills |
| Batch Install | Select multiple skills and multiple agents in a single installation |
| Already-Installed Badge | Installation UI marks skills that are already installed to prevent duplicates |
| Installation Progress | Real-time progress for cloning, scanning, and installing |
| Delete with Confirmation | Confirmation dialog before deletion; auto-cleans symlinks, directories, and lock entries |

### Update Checking

| Feature | Description |
|---------|-------------|
| Per-Skill Update Check | Compares local vs. remote tree hash to detect available updates |
| Batch Update Check | Toolbar button to check all skills for updates at once |
| Update Available Indicator | Skills with updates show an orange badge with update count |
| One-Click Update | Pull latest remote content and update local files |
| GitHub Compare Link | Generates a GitHub compare URL to view exact changes |
| Manual Repo Linking | Link untracked skills to a GitHub repository to enable update checking |

### Lock File & Data Management

| Feature | Description |
|---------|-------------|
| Lock File Read/Write | Reads and writes `~/.agents/.skill-lock.json`, preserving all existing fields |
| Cache Management | Maintains `~/.agents/.skilldeck-cache.json` for commit hash caching |
| Atomic Writes | File writes use atomic operations to prevent data corruption |

### File System Monitoring

| Feature | Description |
|---------|-------------|
| Auto-Refresh | Monitors skill directories via DispatchSource/FSEvents; syncs automatically after external CLI changes |
| Debouncing | 0.5-second debounce to avoid excessive refreshes from rapid file changes |
| Manual Refresh | Toolbar refresh button to manually rescan all skill directories |

### Preferences

| Feature | Description |
|---------|-------------|
| General Settings | Displays shared skills path and lock file path (Cmd+, to open) |
| About | Shows app name, version, and description |

---

## Roadmap

### v0.1 MVP (Done)

- [x] **F01 — Agent Detection**: Auto-detect installed agents (Claude Code, Codex, Gemini CLI, Copilot CLI) by checking config directories and CLI binaries
- [x] **F02 — Unified Dashboard**: Single view of all skills across agents and scopes, with symlink deduplication
- [x] **F03 — Skill Detail View**: Parse and render SKILL.md (YAML frontmatter + markdown body)
- [x] **F04 — Skill Deletion**: Delete skill directory + remove symlinks + update `.skill-lock.json`
- [x] **F05 — SKILL.md Editor**: Edit frontmatter fields (form) + markdown body (split-pane with preview)
- [x] **F06 — Agent Assignment**: Toggle which agents a skill is symlinked to via checkboxes
- [x] **F07 — Lock File Management**: Read/write `~/.agents/.skill-lock.json` preserving all fields
- [x] **F08 — File System Watching**: DispatchSource/FSEvents to react to external changes from CLI tools

### P1 — v1.0

- [ ] **F09 — Registry Browser**: Browse [skills.sh](https://skills.sh) catalog (all-time, trending, hot) with search
- [x] **F10 — One-Click Install**: Clone from GitHub, place in `~/.agents/skills/`, create symlinks, update lock file
- [ ] **F11 — Project Skills**: Open a project directory, manage its `.agents/skills/`
- [x] **F12 — Update Checker**: Compare local `skillFolderHash` against remote repo HEAD
- [ ] **F13 — Create Skill Wizard**: Scaffold new skill with SKILL.md template
- [ ] **F14 — Search & Filter**: Filter by agent, scope, author; full-text search across skill content
- [ ] **F15 — Menu Bar Quick Access**: Menu bar icon for quick skill management actions

### P2 — Future

- [ ] **F16 — Plugins Viewer**: Read-only view of Claude Code plugins (`installed_plugins.json`)
- [ ] **F17 — Skill Dependency Graph**: Visualize skill relationships and dependencies
- [ ] **F18 — Marketplace Manager**: Full marketplace integration for discovering and installing skills
- [ ] **F19 — Bulk Operations**: Multi-select delete, assign, and other batch actions
- [ ] **F20 — Skill Export/Import**: Zip bundle export and import for skill sharing
- [ ] **F21 — Settings Sync**: iCloud or git-based settings synchronization across machines
- [x] **App Icon**: Custom app icon design
- [ ] **Notarized DMG**: Signed and notarized distribution package
- [x] **Homebrew Cask**: `brew install --cask skilldeck` distribution
- [ ] **Markdown Rendering**: Rich markdown rendering in detail view (currently shows source)
- [ ] **Dark Mode Polish**: Fine-tuned dark mode color adjustments

# Add New Code Agent Playbook

> Reference implementation: Antigravity agent (PR #9, branch `feature/add-antigravity-agent`)

## Prerequisites

Before starting, collect the following information for the new agent:

| Property | Example (Antigravity) |
|----------|----------------------|
| Enum case name | `antigravity` |
| Raw value (for JSON serialization) | `"antigravity"` |
| Display name | `"Antigravity"` |
| Skills directory | `~/.gemini/antigravity/skills` |
| Config directory | `~/.gemini/antigravity` |
| CLI detection command | `antigravity` |
| Brand color name | `"indigo"` |
| Brand color RGB | `Color(red: 0.36, green: 0.42, blue: 0.75)` / `#5C6BC0` |
| SF Symbol icon | `arrow.up.circle` |
| Cross-directory reading | None (or specify which directories) |
| Official URL | `https://antigravity.google` |

## File Change Checklist

Thanks to `CaseIterable` architecture, adding a basic agent (no cross-directory reading) only requires **2 source files + 1 test file + 6 doc files = 9 files total**.

### Source Files (2 files)

#### 1. `Sources/SkillDeck/Models/AgentType.swift`

Add new `case` after the last existing case:

```swift
case antigravity = "antigravity"   // Antigravity: Google's AI coding agent
```

Then update **6 switch statements** (the 7th — `additionalReadableSkillsDirectories` — has a `default: return []` that covers agents with no cross-directory reading):

| Property | What to add |
|----------|-------------|
| `displayName` | `case .antigravity: "Antigravity"` |
| `brandColor` | `case .antigravity: "indigo"` |
| `iconName` | `case .antigravity: "arrow.up.circle"` |
| `skillsDirectoryPath` | `case .antigravity: "~/.gemini/antigravity/skills"` |
| `configDirectoryPath` | `case .antigravity: "~/.gemini/antigravity"` |
| `detectCommand` | `case .antigravity: "antigravity"` |

> If the new agent has cross-directory reading, also add a case in `additionalReadableSkillsDirectories`. See `docs/AGENT-CROSS-DIRECTORY-GUIDE.md` for details.

#### 2. `Sources/SkillDeck/Utilities/Constants.swift`

Add brand color in `AgentColors.color(for:)`:

```swift
case .antigravity: Color(red: 0.36, green: 0.42, blue: 0.75)  // Indigo #5C6BC0
```

### No Changes Needed (auto-adapts via CaseIterable)

These files use `AgentType.allCases` and pick up new agents automatically:

- `Services/AgentDetector.swift`
- `Services/SkillScanner.swift`
- `Services/SymlinkManager.swift`
- `Services/SkillManager.swift`
- All Views (SidebarView, DashboardView, AgentToggleView, AgentBadgeView, SkillRowView)

### Test File (1 new file)

#### 3. `Tests/SkillDeckTests/AgentTypeTests.swift`

Create (or extend if it already exists) with:

- `testXxxProperties()` — verify rawValue, displayName, detectCommand, skillsDirectoryPath, configDirectoryPath, iconName, brandColor, empty additionalReadableSkillsDirectories
- `testAllCasesCount()` — update expected count (was 5 → became 6 for Antigravity)

### Documentation Files (6 files)

#### 4. `CLAUDE.md` (~line 67)

Add row to the "Supported Agents" table:

```markdown
| Antigravity | `~/.gemini/antigravity/skills/` | `antigravity` binary |
```

#### 5. `README.md`

Three locations:
- **Intro text** (line ~25): add agent name + link to the agent list
- **Features bullet** (line ~43): add agent name to "Multi-Agent Support"
- **Supported Agents table** (line ~100): add new row

#### 6. `README_CN.md`

Same three locations as README.md (Chinese version).

#### 7. `docs/FEATURES.md`

Two locations:
- **Multi-Agent Support row** (line ~22): add agent name
- **F01 roadmap item** (line ~89): add agent name

#### 8. `docs/AGENT-CROSS-DIRECTORY-GUIDE.md`

- **Agent directory listing** (~line 28): add `AgentName → ~/.path/to/skills/`

#### 9. `docs/index.html` (landing page)

Three locations:
- **Stats section**: update supported agents count (e.g. `6` → `7`)
- **Feature card text**: add agent name to Multi-Agent Support description
- **Agents grid**: add new `<div class="agent-card">` with emoji + name
- **Hero description**: add agent name to the list

## Verification Steps

```bash
# 1. Compile — Swift exhaustive switch catches any missed case
swift build

# 2. Run all tests — should be 0 failures
swift test

# 3. Manual: launch app and verify new agent appears in sidebar, toggles, badges
swift run SkillDeck
```

## Git Workflow

```bash
git checkout main && git pull origin main
git checkout -b feature/add-xxx-agent

# ... make changes ...

swift build && swift test
git add <files>
git commit -m "feat: add Xxx agent support"
git push -u origin feature/add-xxx-agent
gh pr create --title "feat: add Xxx agent support" --body "..."
```

## Common Pitfalls

1. **Forgetting a switch statement** — Swift compiler will catch this with "Switch must be exhaustive" error. Just run `swift build` early.
2. **Wrong `testAllCasesCount`** — Remember to bump the expected count in `AgentTypeTests.testAllCasesCount()`.
3. **Landing page stat number** — Easy to forget updating the number in `docs/index.html`.
4. **README_CN.md** — Don't forget the Chinese README has the same 3 locations to update as README.md.
5. **Config directory confusion** — Some agents share parent directories (e.g. Antigravity's `~/.gemini/antigravity/` is under Gemini CLI's `~/.gemini/`). This is safe because each agent scans its own distinct `skillsDirectoryURL`.

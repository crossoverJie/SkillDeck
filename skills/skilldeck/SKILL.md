---
name: skilldeck
description: Manage AI agent skills via natural language — install, update, delete, and assign skills to agents using SkillDeck's filesystem conventions.
metadata:
  author: crossoverJie
  version: "1.0"
allowed-tools: Bash, Read, Write
---

# SkillDeck Manager

Manage AI coding agent skills through natural language. This skill teaches you how to install, update, delete, and assign skills using SkillDeck's filesystem conventions.

SkillDeck is a macOS GUI app that manages skills across 14 AI agents. Skills are stored as directories containing `SKILL.md` files. This skill lets you perform the same operations from the terminal.

## Filesystem Layout

```
~/.agents/
├── skills/                    # Canonical storage (real files live here)
│   ├── my-skill/
│   │   ├── SKILL.md           # Skill definition (YAML frontmatter + markdown)
│   │   └── ...                # Other files (scripts, templates, etc.)
│   └── another-skill/
│       └── SKILL.md
├── .skill-lock.json           # Lock file (v3, shared with npx skills)
└── .skilldeck-cache.json      # SkillDeck's private cache (do not modify)

~/.claude/skills/              # Claude Code skills (symlinks → canonical)
~/.codex/skills/               # Codex skills (symlinks → canonical, also reads ~/.agents/skills/)
~/.gemini/skills/              # Gemini CLI skills
~/.copilot/skills/             # Copilot CLI skills (also reads ~/.claude/skills/)
~/.config/opencode/skills/     # OpenCode skills (also reads ~/.claude/skills/ and ~/.agents/skills/)
~/.cursor/skills/              # Cursor skills (also reads ~/.claude/skills/)
~/.kiro/skills/                # Kiro skills
~/.codebuddy/skills/           # CodeBuddy skills
~/.openclaw/skills/            # OpenClaw skills
~/.trae/skills/                # Trae skills
~/.qoder/skills/               # Qoder skills
~/.qclaw/skills/               # QClaw skills
~/.workbuddy/skills/           # WorkBuddy skills
~/.gemini/antigravity/skills/  # Antigravity skills
```

**Key rules:**
- The real copy of every skill lives in `~/.agents/skills/<name>/`
- Each agent gets a **symlink** pointing to the canonical directory
- Example: `~/.claude/skills/my-skill` → `~/.agents/skills/my-skill`
- Some agents can read other agents' directories (cross-directory inheritance):
  - **Codex** reads `~/.agents/skills/` natively (no symlink needed)
  - **Copilot** reads `~/.claude/skills/`
  - **OpenCode** reads `~/.claude/skills/` and `~/.agents/skills/`
  - **Cursor** reads `~/.claude/skills/`

## Default Agent Configuration

When installing a skill, you need to decide which agents to assign it to. The recommended approach:

1. **Auto-detect installed agents** — check which CLI commands exist on the system
2. **Assign to all detected agents** — unless the user specifies a subset

The following script detects installed agents and builds a list of their skills directories:

```bash
# Agent detection map: CLI command → skills directory
declare -A AGENT_DIRS=(
  ["claude"]="$HOME/.claude/skills"
  ["codex"]="$HOME/.codex/skills"
  ["gemini"]="$HOME/.gemini/skills"
  ["opencode"]="$HOME/.config/opencode/skills"
  ["antigravity"]="$HOME/.gemini/antigravity/skills"
  ["cursor"]="$HOME/.cursor/skills"
  ["kiro"]="$HOME/.kiro/skills"
  ["codebuddy"]="$HOME/.codebuddy/skills"
  ["openclaw"]="$HOME/.openclaw/skills"
  ["trae"]="$HOME/.trae/skills"
  ["qoder"]="$HOME/.qoder/skills"
  ["qclaw"]="$HOME/.qclaw/skills"
  ["workbuddy"]="$HOME/.workbuddy/skills"
)

# Detect which agents are installed
INSTALLED_DIRS=()
for CMD in "${!AGENT_DIRS[@]}"; do
  if which "$CMD" &>/dev/null; then
    INSTALLED_DIRS+=("${AGENT_DIRS[$CMD]}")
    echo "Detected: $CMD → ${AGENT_DIRS[$CMD]}"
  fi
done

# Copilot CLI is a GitHub CLI extension (gh copilot), not a standalone binary.
# `which gh` only confirms GitHub CLI is installed, not Copilot specifically.
# Check for the copilot extension explicitly.
if which gh &>/dev/null && gh extension list 2>/dev/null | grep -q copilot; then
  INSTALLED_DIRS+=("$HOME/.copilot/skills")
  echo "Detected: copilot → $HOME/.copilot/skills"
fi

echo "Found ${#INSTALLED_DIRS[@]} installed agents"
```

Use `INSTALLED_DIRS` as the default target when installing. If the user says "only install for Claude Code", filter to just `$HOME/.claude/skills`.

## Lock File Format

Location: `~/.agents/.skill-lock.json` (version 3)

```json
{
  "version": 3,
  "skills": {
    "skill-name": {
      "source": "owner/repo",
      "sourceType": "github",
      "sourceUrl": "https://github.com/owner/repo.git",
      "skillPath": "skills/skill-name/SKILL.md",
      "skillFolderHash": "abc123...",
      "installedAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
  },
  "dismissed": {},
  "lastSelectedAgents": []
}
```

**Fields:**
- `source`: Repository identifier (e.g., `"crossoverJie/skills"`) or local path
- `sourceType`: `"github"`, `"local"`, or `"clawhub"`
- `sourceUrl`: Full git URL
- `skillPath`: Relative path to SKILL.md within the source
- `skillFolderHash`: Git tree hash for update detection (can be empty string for local)
- `installedAt` / `updatedAt`: ISO 8601 timestamps

## Helper Functions

These reusable snippets are referenced in the operations below.

### List all agent skills directories

```bash
# All 14 agent skills directories (for symlink scanning)
ALL_AGENT_SKILLS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.gemini/skills"
  "$HOME/.copilot/skills"
  "$HOME/.config/opencode/skills"
  "$HOME/.gemini/antigravity/skills"
  "$HOME/.cursor/skills"
  "$HOME/.kiro/skills"
  "$HOME/.codebuddy/skills"
  "$HOME/.openclaw/skills"
  "$HOME/.trae/skills"
  "$HOME/.qoder/skills"
  "$HOME/.qclaw/skills"
  "$HOME/.workbuddy/skills"
)
```

### Find which agents have a skill installed

```bash
# Usage: find_skill_agents "my-skill" "$HOME/.agents/skills/my-skill"
find_skill_agents() {
  local SKILL_NAME="$1"
  local CANONICAL="$2"
  for DIR in "${ALL_AGENT_SKILLS[@]}"; do
    local LINK="$DIR/$SKILL_NAME"
    if [ -L "$LINK" ]; then
      local RESOLVED=$(python3 -c "import os; print(os.path.realpath('$LINK'))")
      if [ "$RESOLVED" = "$CANONICAL" ]; then
        echo "$DIR"
      fi
    fi
  done
}
```

### Create symlinks for multiple agents

```bash
# Usage: create_symlinks "my-skill" "$HOME/.agents/skills/my-skill" "${TARGET_DIRS[@]}"
create_symlinks() {
  local SKILL_NAME="$1"
  local CANONICAL="$2"
  shift 2
  local TARGET_DIRS=("$@")
  for DIR in "${TARGET_DIRS[@]}"; do
    mkdir -p "$DIR"
    if [ ! -L "$DIR/$SKILL_NAME" ]; then
      ln -s "$CANONICAL" "$DIR/$SKILL_NAME"
      echo "  Symlink: $DIR/$SKILL_NAME"
    fi
  done
}
```

### Remove symlinks from multiple agents

```bash
# Usage: remove_symlinks "my-skill" "$HOME/.agents/skills/my-skill"
remove_symlinks() {
  local SKILL_NAME="$1"
  local CANONICAL="$2"
  for DIR in "${ALL_AGENT_SKILLS[@]}"; do
    local LINK="$DIR/$SKILL_NAME"
    if [ -L "$LINK" ]; then
      local RESOLVED=$(python3 -c "import os; print(os.path.realpath('$LINK'))")
      if [ "$RESOLVED" = "$CANONICAL" ]; then
        rm "$LINK"
        echo "  Removed: $LINK"
      fi
    fi
  done
}
```

## Operations

### 1. Install a Skill from GitHub

**Steps:**
1. Clone the repository to a temporary directory
2. Locate the SKILL.md file and the skill directory
3. Detect installed agents (or use user-specified targets)
4. Copy the skill directory to `~/.agents/skills/<name>/`
5. Create symlinks for target agents
6. Update the lock file

```bash
# === Configuration ===
SKILL_NAME="my-skill"
REPO_SOURCE="owner/repo"
REPO_URL="https://github.com/owner/repo.git"
SKILL_FOLDER_PATH="skills/$SKILL_NAME"  # path to skill directory within repo

# === 1. Clone repo ===
TMPDIR=$(mktemp -d)
git clone --depth 1 "$REPO_URL" "$TMPDIR/repo"

# === 2. Locate skill directory ===
# Two path concepts (matching SkillManager's convention):
#   SKILL_FOLDER_PATH — directory containing SKILL.md (for git tree hash)
#   SKILL_FILE_PATH   — path to SKILL.md itself (for lock file's skillPath)
# Examples:
#   Sub-directory: folder="skills/foo", file="skills/foo/SKILL.md"
#   Root-level:    folder="",            file="SKILL.md"
SOURCE_DIR="$TMPDIR/repo/$SKILL_FOLDER_PATH"
if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
  # Fallback: search for SKILL.md
  FOUND=$(find "$TMPDIR/repo" -name "SKILL.md" -maxdepth 3 | head -1)
  if [ -n "$FOUND" ]; then
    SOURCE_DIR=$(dirname "$FOUND")
    # Derive folder path as relative path from repo root (empty string for root-level)
    SKILL_FOLDER_PATH="${SOURCE_DIR#$TMPDIR/repo/}"
    # Remove trailing slash if present (root case: "$TMPDIR/repo/" → "")
    SKILL_FOLDER_PATH="${SKILL_FOLDER_PATH%/}"
  else
    echo "❌ SKILL.md not found in repository"
    rm -rf "$TMPDIR"
    exit 1
  fi
fi

# Derive SKILL_FILE_PATH for lock entry: folder path + "/SKILL.md", or just "SKILL.md" at root
if [ -z "$SKILL_FOLDER_PATH" ]; then
  SKILL_FILE_PATH="SKILL.md"
else
  SKILL_FILE_PATH="$SKILL_FOLDER_PATH/SKILL.md"
fi

# === 3. Check not already installed ===
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"
if [ -d "$CANONICAL" ]; then
  echo "❌ Skill '$SKILL_NAME' already exists. Use update instead."
  rm -rf "$TMPDIR"
  exit 1
fi

# === 4. Detect target agents (auto-detect all installed) ===
declare -A AGENT_DIRS=(
  ["claude"]="$HOME/.claude/skills"
  ["codex"]="$HOME/.codex/skills"
  ["gemini"]="$HOME/.gemini/skills"
  ["opencode"]="$HOME/.config/opencode/skills"
  ["antigravity"]="$HOME/.gemini/antigravity/skills"
  ["cursor"]="$HOME/.cursor/skills"
  ["kiro"]="$HOME/.kiro/skills"
  ["codebuddy"]="$HOME/.codebuddy/skills"
  ["openclaw"]="$HOME/.openclaw/skills"
  ["trae"]="$HOME/.trae/skills"
  ["qoder"]="$HOME/.qoder/skills"
  ["qclaw"]="$HOME/.qclaw/skills"
  ["workbuddy"]="$HOME/.workbuddy/skills"
)

TARGET_DIRS=()
for CMD in "${!AGENT_DIRS[@]}"; do
  if which "$CMD" &>/dev/null; then
    TARGET_DIRS+=("${AGENT_DIRS[$CMD]}")
  fi
done

# Copilot CLI is a gh extension, not a standalone binary — check explicitly
if which gh &>/dev/null && gh extension list 2>/dev/null | grep -q copilot; then
  TARGET_DIRS+=("$HOME/.copilot/skills")
fi

echo "Installing for ${#TARGET_DIRS[@]} agents: ${TARGET_DIRS[*]}"

# === 5. Copy to canonical directory ===
mkdir -p "$HOME/.agents/skills"
cp -R "$SOURCE_DIR" "$CANONICAL"

# === 6. Create symlinks ===
for DIR in "${TARGET_DIRS[@]}"; do
  mkdir -p "$DIR"
  ln -s "$CANONICAL" "$DIR/$SKILL_NAME"
  echo "  Symlink: $DIR/$SKILL_NAME"
done

# === 7. Update lock file ===
cd "$TMPDIR/repo"
# SKILL_FOLDER_PATH is empty for root-level skills; git rev-parse HEAD: returns root tree hash
TREE_HASH=$(git rev-parse HEAD:$SKILL_FOLDER_PATH 2>/dev/null || echo "")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Export variables so python3 can read them via os.environ
export SKILL_NAME REPO_SOURCE REPO_URL SKILL_FILE_PATH TREE_HASH NOW
python3 << 'PYEOF'
import json, os

lock_path = os.path.expanduser("~/.agents/.skill-lock.json")
os.makedirs(os.path.dirname(lock_path), exist_ok=True)

lock = {}
if os.path.exists(lock_path):
    with open(lock_path) as f:
        lock = json.load(f)

lock.setdefault("version", 3)
lock.setdefault("skills", {})
lock.setdefault("dismissed", {})
lock.setdefault("lastSelectedAgents", [])

skill_name = os.environ["SKILL_NAME"]
repo_source = os.environ["REPO_SOURCE"]
repo_url = os.environ["REPO_URL"]
# SKILL_FILE_PATH is the relative path to SKILL.md (e.g. "skills/foo/SKILL.md" or "SKILL.md")
skill_file_path = os.environ["SKILL_FILE_PATH"]
tree_hash = os.environ["TREE_HASH"]
now = os.environ["NOW"]

lock["skills"][skill_name] = {
    "source": repo_source,
    "sourceType": "github",
    "sourceUrl": repo_url,
    "skillPath": skill_file_path,
    "skillFolderHash": tree_hash,
    "installedAt": now,
    "updatedAt": now
}

with open(lock_path, "w") as f:
    json.dump(lock, f, indent=2, sort_keys=True)
PYEOF

# === 8. Cleanup ===
rm -rf "$TMPDIR"
echo "✅ Installed '$SKILL_NAME'"
```

### 2. Delete a Skill

**⚠️ IMPORTANT: Always confirm with the user before deleting. Deletion removes the skill from ALL agents.**

```bash
SKILL_NAME="my-skill"
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"

# 1. Check existence
if [ ! -d "$CANONICAL" ]; then
  echo "❌ Skill '$SKILL_NAME' not found"
  exit 1
fi

# 2. Show which agents have this skill
ALL_AGENT_SKILLS=(
  "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"
  "$HOME/.copilot/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/antigravity/skills"
  "$HOME/.cursor/skills" "$HOME/.kiro/skills" "$HOME/.codebuddy/skills"
  "$HOME/.openclaw/skills" "$HOME/.trae/skills" "$HOME/.qoder/skills"
  "$HOME/.qclaw/skills" "$HOME/.workbuddy/skills"
)

echo "Skill '$SKILL_NAME' is assigned to:"
for DIR in "${ALL_AGENT_SKILLS[@]}"; do
  LINK="$DIR/$SKILL_NAME"
  if [ -L "$LINK" ]; then
    RESOLVED=$(python3 -c "import os; print(os.path.realpath('$LINK'))")
    if [ "$RESOLVED" = "$CANONICAL" ]; then
      echo "  ✓ $(basename $(dirname $DIR)) ($(dirname $DIR))"
    fi
  fi
done

# 3. ⚠️ MUST ask user to confirm before proceeding!
#    Prompt: "Are you sure you want to delete '$SKILL_NAME' from all agents? [y/N]"

# 4. Remove symlinks
for DIR in "${ALL_AGENT_SKILLS[@]}"; do
  LINK="$DIR/$SKILL_NAME"
  if [ -L "$LINK" ]; then
    RESOLVED=$(python3 -c "import os; print(os.path.realpath('$LINK'))")
    if [ "$RESOLVED" = "$CANONICAL" ]; then
      rm "$LINK"
    fi
  fi
done

# 5. Delete canonical directory
rm -rf "$CANONICAL"

# 6. Update lock file
export SKILL_NAME
python3 << 'PYEOF'
import json, os

lock_path = os.path.expanduser("~/.agents/.skill-lock.json")
if os.path.exists(lock_path):
    with open(lock_path) as f:
        lock = json.load(f)
    lock.get("skills", {}).pop(os.environ["SKILL_NAME"], None)
    with open(lock_path, "w") as f:
        json.dump(lock, f, indent=2, sort_keys=True)
PYEOF

echo "✅ Deleted '$SKILL_NAME'"
```

### 3. Update a Skill

Pull latest from GitHub, overwrite local copy, preserve symlinks.

```bash
SKILL_NAME="my-skill"
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"

# 1. Check installed
if [ ! -d "$CANONICAL" ]; then
  echo "❌ Not installed. Use install instead."
  exit 1
fi

# 2. Read lock entry — use python3 to safely extract values and write to a
#    unique temp file (avoids shell injection from untrusted lock file content,
#    and mktemp avoids race conditions between concurrent updates)
VARS_FILE=$(mktemp /tmp/skilldeck_vars.XXXXXX)
export SKILL_NAME VARS_FILE
python3 << 'PYEOF'
import json, os

lock_path = os.path.expanduser("~/.agents/.skill-lock.json")
with open(lock_path) as f:
    lock = json.load(f)

entry = lock.get("skills", {}).get(os.environ["SKILL_NAME"])
if not entry:
    print("ERROR: No lock entry found")
    exit(1)

source_url = entry.get("sourceUrl", "")
skill_path = entry.get("skillPath", "")

# deriveFolderPath: "SKILL.md" → "", "skills/foo/SKILL.md" → "skills/foo"
if skill_path == "SKILL.md":
    folder_path = ""
elif skill_path.endswith("/SKILL.md"):
    folder_path = skill_path[:-len("/SKILL.md")]
else:
    folder_path = skill_path

# Write values using declare -x syntax to avoid shell injection.
# Single-quote each value so metacharacters are not interpreted by bash.
vars_file = os.environ["VARS_FILE"]
with open(vars_file, "w") as f:
    for key, val in [("REPO_URL", source_url),
                     ("SKILL_FILE_PATH", skill_path),
                     ("SKILL_FOLDER_PATH", folder_path)]:
        # Escape single quotes within the value: ' → '\''
        safe = val.replace("'", "'\\''")
        f.write(f"declare -x {key}='{safe}'\n")
PYEOF

if [ ! -s "$VARS_FILE" ]; then
  echo "❌ Failed to read lock entry"
  rm -f "$VARS_FILE"
  exit 1
fi

# Source the safely-declared variables, then remove the temp file immediately
source "$VARS_FILE"
rm -f "$VARS_FILE"

# 3. Clone latest
TMPDIR=$(mktemp -d)
git clone --depth 1 "$REPO_URL" "$TMPDIR/repo"

# 4. Verify
SOURCE_DIR="$TMPDIR/repo/$SKILL_FOLDER_PATH"
if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
  echo "❌ SKILL.md not found at $SOURCE_DIR"
  rm -rf "$TMPDIR"
  exit 1
fi

# 4. Record existing symlinks
ALL_AGENT_SKILLS=(
  "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"
  "$HOME/.copilot/skills" "$HOME/.config/opencode/skills" "$HOME/.gemini/antigravity/skills"
  "$HOME/.cursor/skills" "$HOME/.kiro/skills" "$HOME/.codebuddy/skills"
  "$HOME/.openclaw/skills" "$HOME/.trae/skills" "$HOME/.qoder/skills"
  "$HOME/.qclaw/skills" "$HOME/.workbuddy/skills"
)

EXISTING_LINKS=()
for DIR in "${ALL_AGENT_SKILLS[@]}"; do
  LINK="$DIR/$SKILL_NAME"
  if [ -L "$LINK" ]; then
    RESOLVED=$(python3 -c "import os; print(os.path.realpath('$LINK'))")
    if [ "$RESOLVED" = "$CANONICAL" ]; then
      EXISTING_LINKS+=("$DIR")
      rm "$LINK"
    fi
  fi
done

# 5. Replace
rm -rf "$CANONICAL"
cp -R "$SOURCE_DIR" "$CANONICAL"

# 6. Restore symlinks
for DIR in "${EXISTING_LINKS[@]}"; do
  ln -s "$CANONICAL" "$DIR/$SKILL_NAME"
done
echo "Restored ${#EXISTING_LINKS[@]} symlinks"

# 7. Update lock file
cd "$TMPDIR/repo"
# SKILL_FOLDER_PATH is empty for root-level skills; git rev-parse HEAD: returns root tree hash
TREE_HASH=$(git rev-parse HEAD:$SKILL_FOLDER_PATH 2>/dev/null || echo "")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export SKILL_NAME SKILL_FILE_PATH TREE_HASH NOW
python3 << 'PYEOF'
import json, os

lock_path = os.path.expanduser("~/.agents/.skill-lock.json")
if not os.path.exists(lock_path):
    exit(0)

with open(lock_path) as f:
    lock = json.load(f)

skill_name = os.environ["SKILL_NAME"]
existing = lock.get("skills", {}).get(skill_name)

if existing:
    # Update existing entry — preserve all fields, only change hash and timestamp
    existing["skillFolderHash"] = os.environ["TREE_HASH"]
    existing["updatedAt"] = os.environ["NOW"]
    lock["skills"][skill_name] = existing
else:
    # No existing entry (e.g., manually installed skill) — write a complete entry
    # so LockEntry decoding doesn't fail on missing required fields
    print("⚠️ No existing lock entry found — creating a new one")
    now = os.environ["NOW"]
    lock["skills"][skill_name] = {
        "source": "",
        "sourceType": "local",
        "sourceUrl": "",
        "skillPath": os.environ["SKILL_FILE_PATH"],
        "skillFolderHash": os.environ["TREE_HASH"],
        "installedAt": now,
        "updatedAt": now
    }

with open(lock_path, "w") as f:
    json.dump(lock, f, indent=2, sort_keys=True)
PYEOF

rm -rf "$TMPDIR"
echo "✅ Updated '$SKILL_NAME'"
```

### 4. List Installed Skills

```bash
echo "Installed skills:"
for DIR in "$HOME/.agents/skills"/*/; do
  [ -f "$DIR/SKILL.md" ] || continue
  NAME=$(basename "$DIR")
  DESC=$(sed -n '/^---$/,/^---$/{ /^description:/{ s/^description: *//; p; q; } }' "$DIR/SKILL.md" 2>/dev/null)
  echo "  - $NAME: $DESC"
done
```

### 5. Assign / Unassign Skill to Agent

```bash
SKILL_NAME="my-skill"
AGENT_SKILLS_DIR="$HOME/.claude/skills"  # change to target agent
CANONICAL="$HOME/.agents/skills/$SKILL_NAME"

# Assign
mkdir -p "$AGENT_SKILLS_DIR"
[ -L "$AGENT_SKILLS_DIR/$SKILL_NAME" ] || ln -s "$CANONICAL" "$AGENT_SKILLS_DIR/$SKILL_NAME"

# Unassign
[ -L "$AGENT_SKILLS_DIR/$SKILL_NAME" ] && rm "$AGENT_SKILLS_DIR/$SKILL_NAME"
```

### 6. Search for Skills

```bash
# skills.sh registry
curl -s "https://skills.sh/api/search?q=your-query" | python3 -m json.tool

# ClawHub
curl -s "https://api.clawhub.com/v1/skills/search?q=your-query" | python3 -m json.tool
```

## Important Notes

1. **SkillDeck auto-refreshes**: The GUI watches `~/.agents/skills/` and all agent directories. Changes via shell are reflected in the GUI within 0.5s.

2. **Lock file compatibility**: Format is v3 (shared with `npx skills`). Always preserve `version: 3` and existing entries.

3. **Cross-directory inheritance**: Symlinks in `~/.claude/skills/` are also visible to Copilot, OpenCode, and Cursor. Don't create redundant symlinks.

4. **Codex special case**: Reads `~/.agents/skills/` natively. Symlink in `~/.codex/skills/` is optional but consistent.

5. **Never modify**: `~/.agents/.skilldeck-cache.json` (SkillDeck private cache)

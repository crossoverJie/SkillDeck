import Foundation

/// SkillDisableManager is the single source of truth for the "global disable" feature.
///
/// The mechanism is a single atomic rename of the real `SKILL.md` file:
///
///   disable:  ~/.agents/skills/<id>/SKILL.md             ──rename──▶ .SKILL.md.disabled
///   enable:   ~/.agents/skills/<id>/.SKILL.md.disabled  ──rename──▶ SKILL.md
///
/// Why a rename (and not a directory move or unlinking symlinks)?
/// - Every sharedGlobal skill has exactly ONE real `SKILL.md`, living at the canonical URL.
///   All 15 agents read that single file — either through their own symlink (e.g. Claude Code)
///   or by reading the shared canonical directory natively (Codex / OpenCode / Qoder / Pi).
///   Renaming this one file therefore hides the skill from *all* agents at once.
/// - A `FileManager.moveItem` on the same volume is a single atomic `rename(2)`. There is no
///   intermediate state, so unlike `applySkillUpdate` we do NOT need staging dirs, backup
///   manifests, or crash recovery. The state is fully self-describing on disk.
/// - We never touch any symlink and never touch `~/.agents/.skill-lock.json`, so assignment
///   information and `npx skills` interop are preserved byte-for-byte.
///
/// The marker filename `.SKILL.md.disabled` is deliberately chosen:
/// - leading dot  → hidden, so `contentsOfDirectory(options: [.skipsHiddenFiles])` ignores it;
/// - `.disabled` suffix → never matches `*.md` / `SKILL.md*` globs used by agents or `npx skills`;
/// - it is NOT a `.md` document, so it must not be opened/renamed by editors (documented in docs).
///
/// This is an `enum` namespace with only `static` members (the same pattern as `SymlinkManager`).
/// Swift has no packages in the Java sense, so an enum with no cases is the idiomatic way to group
/// pure helpers. All methods are synchronous: the caller is the `@MainActor` `SkillManager`, which
/// performs the read-decide-write sequence in one call so no stale `Skill` snapshot can leak in.
enum SkillDisableManager {

    // MARK: - Constants

    /// The canonical skill filename. Shared with `SkillScanner` so the string is not duplicated.
    static let skillFilename = "SKILL.md"

    /// The hidden marker filename that holds the content while a skill is disabled.
    /// It is the ONLY copy of the content in the disabled state (see the class doc comment).
    static let disabledMarkerFilename = ".SKILL.md.disabled"

    // MARK: - Path helpers

    /// Full URL of the active `SKILL.md` inside a canonical skill directory.
    static func skillMDURL(for canonicalURL: URL) -> URL {
        canonicalURL.appendingPathComponent(skillFilename)
    }

    /// Full URL of the disabled marker file inside a canonical skill directory.
    static func markerURL(for canonicalURL: URL) -> URL {
        canonicalURL.appendingPathComponent(disabledMarkerFilename)
    }

    /// Returns the file that currently holds the skill's content, or nil when neither exists.
    ///
    /// CONVENTION (write this down in `SkillScanner` too): this helper is for the **scanner only**,
    /// to parse frontmatter/body while a skill is disabled or to detect a broken skill. It must
    /// NEVER be used as a write target — writing through it would corrupt the hidden marker file.
    /// Priority: real `SKILL.md` wins (broken/conflict states are reported by `isDisabled`/scanner).
    static func skillContentURL(for canonicalURL: URL) -> URL? {
        let fm = FileManager.default
        let skillMD = skillMDURL(for: canonicalURL)
        if fm.fileExists(atPath: skillMD.path) {
            return skillMD
        }
        let marker = markerURL(for: canonicalURL)
        if fm.fileExists(atPath: marker.path) {
            return marker
        }
        return nil
    }

    /// Filesystem-level disabled check: marker present AND `SKILL.md` absent.
    ///
    /// This is intentional FS-level (not based on a `Skill` snapshot) because
    /// `persistInstalledSkillDirectory` calls it before it has a fully-built model in hand.
    /// A broken skill (both files missing) reports `false` here, which correctly allows a
    /// reinstall to proceed.
    static func isDisabled(at canonicalURL: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: markerURL(for: canonicalURL).path)
            && !fm.fileExists(atPath: skillMDURL(for: canonicalURL).path)
    }

    // MARK: - Location classification

    /// Where a canonical skill actually lives on disk.
    ///
    /// Used to produce precise, actionable errors. It deliberately replaces "is the parent a
    /// managed directory?" as the admission check: `SkillScanner.scanAll()` may upgrade an
    /// agent-directory skill's scope to `.sharedGlobal`, but such a skill is NOT in the canonical
    /// shared store and must not be renameable here.
    enum SkillLocation {
        /// The canonical shared store: `~/.agents/skills/`.
        case canonicalShared
        /// A real directory inside one specific agent's own skills folder.
        case agentDirectory(AgentType)
        /// Anything else (e.g. an external symlink target such as `~/dev/foo`).
        case external
    }

    /// Classify a canonical URL by comparing its parent against the shared store and every
    /// agent's skills directory. All comparisons go through `AgentType.isSameDirectory`, which
    /// compares standardized path strings and is stable regardless of trailing slashes / whether
    /// the directory already exists on disk (important on CI).
    static func classifyLocation(_ canonicalURL: URL) -> SkillLocation {
        let parent = canonicalURL.deletingLastPathComponent()
        if AgentType.isCanonicalSharedDirectory(parent) {
            return .canonicalShared
        }
        for agent in AgentType.allCases {
            if AgentType.isSameDirectory(parent, agent.skillsDirectoryURL) {
                return .agentDirectory(agent)
            }
        }
        return .external
    }

    // MARK: - Admission

    /// Whether a skill is eligible for global disable. Three conditions must all hold:
    /// 1. `scope == .sharedGlobal` (agent-local / project skills are out of scope).
    /// 2. Its canonical parent IS the canonical shared directory `~/.agents/skills/`.
    ///    This is stricter than "parent is any managed directory": a real directory that lives in
    ///    an agent's folder but was inherited by several agents is upgraded to `.sharedGlobal` by
    ///    `scanAll()`, yet renaming it would only hide it from that agent and its inheritors —
    ///    not from ALL agents — and would write into another agent's directory. An external
    ///    symlink target (`~/.agents/skills/foo -> ~/dev/foo`) resolves to a parent that is neither
    ///    canonical nor an agent directory, so it is rejected by this same check as `.external`.
    /// 3. No real (non-symlink, non-inherited) duplicate copy exists in any agent directory.
    static func canDisable(_ skill: Skill) -> Bool {
        guard skill.scope == .sharedGlobal else { return false }
        guard AgentType.isCanonicalSharedDirectory(skill.canonicalURL.deletingLastPathComponent()) else {
            return false
        }
        return !hasRealDuplicate(skill)
    }

    /// Whether a disabled skill can be re-enabled.
    ///
    /// Admission is deliberately DIRECTION-AWARE (see `canToggle`). Enabling renames the marker
    /// BACK to `SKILL.md` *inside the canonical store*. That single rename cannot affect any
    /// other directory, so the `scope` and `hasRealDuplicate` checks that are essential for
    /// disabling are WRONG here: a real duplicate copy that appears while the skill is off must
    /// NOT strand it in the disabled state with no UI path back. All we need is that the marker
    /// still lives at the canonical location.
    static func canEnable(_ skill: Skill) -> Bool {
        AgentType.isCanonicalSharedDirectory(skill.canonicalURL.deletingLastPathComponent())
    }

    /// Admission for a toggle, chosen by the CURRENT direction.
    ///
    /// Reading `isDisabled` from the model (derived by the scanner from the filesystem) matches
    /// the direction `SkillManager.toggleSkillDisabled(id:)` is about to take. Callers such as
    /// the detail switch / toolbar / context menu all gate on this single value, so getting it
    /// wrong would make the "Enable" control disappear exactly when the user needs it.
    static func canToggle(_ skill: Skill) -> Bool {
        skill.isDisabled ? canEnable(skill) : canDisable(skill)
    }

    /// Detects a "fake global disable": the same id also exists as a REAL directory inside an
    /// agent's own skills folder. Renaming the canonical copy would not hide that real copy, so
    /// the user would wrongly believe the skill is globally off.
    ///
    /// We must NOT use `isTrulyInherited` here. The 4 agents that natively read
    /// `~/.agents/skills/` produce entries with `isSymlink == false, isInherited == true`, and
    /// `isTrulyInherited` is false for them; the precise signal for "an agent has its own real
    /// copy" is exactly `!isSymlink && !isInherited`.
    static func hasRealDuplicate(_ skill: Skill) -> Bool {
        skill.installations.contains { !$0.isSymlink && !$0.isInherited }
    }

    // MARK: - Errors

    /// All failures surfaced by the disable feature.
    ///
    /// `LocalizedError.errorDescription` has no access to the SwiftUI environment, so it resolves
    /// the persisted language preference via `LanguageSettings.currentResolution()` + `L10n.string`
    /// (the same pattern as `SkillManager.SkillUpdateError`). Using `String(localized:)` here
    /// would break live language switching. Parameterized messages use
    /// `String(format: L10n.string(...), arg)` because the repo has no `L10n.format` helper.
    enum DisableError: Error, LocalizedError {
        /// Both `SKILL.md` and the marker exist (external tampering) — refuse to overwrite.
        case conflict
        /// Neither content file exists: the skill content is unrecoverable from this directory.
        case skillIsBroken
        /// The skill is not a `.sharedGlobal` skill.
        case unsupportedScope
        /// The canonical URL resolves outside any managed directory (external symlink target).
        case externalLocation(URL)
        /// The skill lives in an agent directory (scope was upgraded but is not canonical).
        case agentDirectoryLocation(AgentType)
        /// A real duplicate copy exists; disabling the shared copy would not hide it.
        case duplicateRealCopy(AgentType)
        /// A write operation was attempted on an already-disabled skill.
        case skillIsDisabled
        /// A reinstall was attempted while a disabled skill with the same name exists.
        case installOnDisabled
        /// A broken skill has no github `lockEntry`, so it cannot be auto-rebuilt.
        case brokenNeedsManualReinstall

        var errorDescription: String? {
            let resolution = LanguageSettings.currentResolution()
            // Small local helper: look up one key with the already-resolved bundle/locale.
            func tr(_ key: String) -> String {
                L10n.string(key, bundle: resolution.bundle, locale: resolution.locale)
            }
            switch self {
            case .conflict:
                return tr(L10nKeys.skillDisableErrorConflict)
            case .skillIsBroken:
                // Reuse the UI help string: after this failure the correct action IS "delete or
                // reinstall", so the suggestion doubles as the failure explanation.
                return tr(L10nKeys.skillBrokenHelp)
            case .unsupportedScope:
                return tr(L10nKeys.skillDisableErrorUnsupportedScope)
            case .externalLocation(let url):
                return String(format: tr(L10nKeys.skillDisableErrorExternalLocation), url.path)
            case .agentDirectoryLocation:
                return tr(L10nKeys.skillDisableErrorAgentDirectory)
            case .duplicateRealCopy(let agent):
                return String(format: tr(L10nKeys.skillDisableErrorDuplicateRealCopy), agent.displayName)
            case .skillIsDisabled:
                return tr(L10nKeys.skillDisableErrorDisabled)
            case .installOnDisabled:
                return tr(L10nKeys.skillDisableErrorInstallOnDisabled)
            case .brokenNeedsManualReinstall:
                return tr(L10nKeys.skillBrokenManualReinstall)
            }
        }
    }

    // MARK: - Atomic state change

    /// Atomically disable or enable a skill by renaming its single content file.
    ///
    /// Idempotent by design: re-disabling an already-disabled skill (or re-enabling an active one)
    /// is a no-op, so a double-click or a watcher-triggered retry can never corrupt state.
    ///
    /// Truth table (H = `SKILL.md` exists, M = marker exists):
    ///
    ///   disable:  H&&!M → move   |  !H&&M → no-op  |  H&&M → .conflict  |  !H&&!M → .skillIsBroken
    ///   enable :  M&&!H → move   |  H&&!M → no-op  |  H&&M → .conflict  |  !H&&!M → .skillIsBroken
    ///
    /// - Parameters:
    ///   - disabled: `true` to disable, `false` to re-enable.
    ///   - canonicalURL: the skill's canonical directory URL.
    /// - Throws: `DisableError.conflict` / `.skillIsBroken`, or a `FileManager` error on I/O failure.
    static func setDisabled(_ disabled: Bool, at canonicalURL: URL) throws {
        let fm = FileManager.default
        let skillMD = skillMDURL(for: canonicalURL)
        let marker = markerURL(for: canonicalURL)

        let hasSkillMD = fm.fileExists(atPath: skillMD.path)
        let hasMarker = fm.fileExists(atPath: marker.path)

        // Both present can only come from external tampering. Report it instead of silently
        // overwriting one of the two files (which would lose data).
        if hasSkillMD && hasMarker {
            throw DisableError.conflict
        }
        // Neither present: the content is gone. Reuse the broken case/message so the UI and the
        // error agree on the suggested recovery action.
        if !hasSkillMD && !hasMarker {
            throw DisableError.skillIsBroken
        }

        if disabled {
            // Active (H&&!M) → move to marker; already disabled (!H&&M) → idempotent no-op.
            if hasSkillMD {
                try fm.moveItem(at: skillMD, to: marker)
            }
        } else {
            // Disabled (M&&!H) → move back; already active (H&&!M) → idempotent no-op.
            if hasMarker {
                try fm.moveItem(at: marker, to: skillMD)
            }
        }
    }
}

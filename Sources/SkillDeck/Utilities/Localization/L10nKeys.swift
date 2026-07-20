import Foundation

enum L10nKeys {
    static let appName = "app.name"

    static let settingsTabGeneral = "settings.tab.general"
    static let settingsTabProxy = "settings.tab.proxy"

    static let settingsTabAbout = "settings.tab.about"

    static let settingsProxySectionEnable = "settings.proxy.section.enable"
    static let settingsProxyEnableProxy = "settings.proxy.enableProxy"

    static let settingsProxySectionServer = "settings.proxy.section.server"
    static let settingsProxyImportFromEnvironment = "settings.proxy.importFromEnvironment"
    static let settingsProxyFieldTypeLabel = "settings.proxy.field.type.label"
    static let settingsProxyFieldTypeHint = "settings.proxy.field.type.hint"
    static let settingsProxyFieldHostLabel = "settings.proxy.field.host.label"
    static let settingsProxyFieldHostHint = "settings.proxy.field.host.hint"
    static let settingsProxyFieldPortLabel = "settings.proxy.field.port.label"
    static let settingsProxyFieldPortHint = "settings.proxy.field.port.hint"
    static let settingsProxyValidationInvalidHostPort = "settings.proxy.validation.invalidHostPort"

    static let settingsProxySectionAuthentication = "settings.proxy.section.authentication"
    static let settingsProxyEnableAuthentication = "settings.proxy.enableAuthentication"
    static let settingsProxyFieldUsernameLabel = "settings.proxy.field.username.label"
    static let settingsProxyFieldUsernameHint = "settings.proxy.field.username.hint"
    static let settingsProxyFieldPasswordLabel = "settings.proxy.field.password.label"
    static let settingsProxyFieldPasswordHint = "settings.proxy.field.password.hint"
    static let settingsProxySavePassword = "settings.proxy.savePassword"
    static let settingsProxyClearPassword = "settings.proxy.clearPassword"

    static let settingsProxySectionBypass = "settings.proxy.section.bypass"
    static let settingsProxyBypassDescription = "settings.proxy.bypass.description"
    static let settingsProxyBypassExamples = "settings.proxy.bypass.examples"

    static let settingsProxyStatusImportNoneFound = "settings.proxy.status.import.noneFound"
    static let settingsProxyStatusImportImported = "settings.proxy.status.import.imported"
    static let settingsProxyStatusImportImportedPasswordSaveFailed = "settings.proxy.status.import.importedPasswordSaveFailed"

    static let settingsProxyStatusPasswordSaved = "settings.proxy.status.password.saved"
    static let settingsProxyStatusPasswordSaveFailed = "settings.proxy.status.password.saveFailed"
    static let settingsProxyStatusPasswordCleared = "settings.proxy.status.password.cleared"
    static let settingsProxyStatusPasswordClearFailed = "settings.proxy.status.password.clearFailed"

    static let settingsSectionPaths = "settings.section.paths"
    static let settingsSectionPathsSharedSkills = "settings.section.paths.sharedSkills"
    static let settingsSectionPathsLockFile = "settings.section.paths.lockFile"

    static let settingsSectionLanguage = "settings.section.language"
    static let settingsLanguageAppLanguage = "settings.language.appLanguage"
    static let settingsLanguageSystemDefault = "settings.language.systemDefault"
    static let settingsLanguageEnglish = "settings.language.english"
    static let settingsLanguageChineseHans = "settings.language.chineseHans"

    static let settingsSectionFont = "settings.section.font"
    static let settingsFontFamily = "settings.font.family"
    static let settingsFontSize = "settings.font.size"
    static let settingsFontPreviewSentence = "settings.font.previewSentence"

    static let settingsAboutAppName = "settings.about.appName"
    static let settingsAboutTagline = "settings.about.tagline"
    static let settingsAboutGitHub = "settings.about.github"

    static let settingsUpdateChecking = "settings.update.checking"
    static let settingsUpdateDownloading = "settings.update.downloading"
    static let settingsUpdateRetry = "settings.update.retry"
    static let settingsUpdateAvailablePrefix = "settings.update.availablePrefix"
    static let settingsUpdateNow = "settings.update.now"
    static let settingsUpdateViewOnGitHub = "settings.update.viewOnGitHub"
    static let settingsUpdateCheckForUpdates = "settings.update.checkForUpdates"

    static let sidebarSectionOverview = "sidebar.section.overview"
    static let sidebarSectionAgents = "sidebar.section.agents"
    static let sidebarDashboard = "sidebar.dashboard"
    static let sidebarRegistry = "sidebar.registry"
    static let sidebarClawHub = "sidebar.clawhub"
    static let sidebarHelpUpdateAvailable = "sidebar.help.updateAvailable"
    static let sidebarInstallFromGitHub = "sidebar.install.fromGitHub"
    static let sidebarInstallFromLocalFolder = "sidebar.install.fromLocalFolder"
    static let sidebarHelpInstallSkill = "sidebar.help.installSkill"
    static let sidebarHelpCheckAllUpdates = "sidebar.help.checkAllUpdates"
    static let sidebarHelpRefreshSkills = "sidebar.help.refreshSkills"

    static let emptySelectSkillTitle = "empty.selectSkill.title"
    static let emptySelectSkillSubtitleList = "empty.selectSkill.subtitle.list"
    static let emptySelectSkillSubtitleRegistry = "empty.selectSkill.subtitle.registry"
    static let emptySelectSkillSubtitleClawHub = "empty.selectSkill.subtitle.clawhub"

    static let dashboardLanguageMenuLabel = "dashboard.language.menuLabel"
    static let dashboardLanguageMenuHelp = "dashboard.language.menuHelp"

    static let commonCancel = "common.cancel"
    static let commonClose = "common.close"
    static let commonDone = "common.done"
    static let commonOK = "common.ok"
    static let commonSourcePath = "common.sourcePath"
    static let commonShowInFinder = "common.showInFinder"
    static let sidebarGlobalSync = "sidebar.globalSync"
    static let sidebarProjects = "sidebar.projects"
    static let contentPreparingGlobalSync = "content.preparingGlobalSync"
    static let contentPreparingProjects = "content.preparingProjects"
    static let projectsTitle = "projects.title"
    static let projectsEmptyTitle = "projects.empty.title"
    static let projectsEmptyDescription = "projects.empty.description"
    static let projectsAdd = "projects.add"
    static let projectsRescan = "projects.rescan"
    static let projectsChooseRoot = "projects.chooseRoot"
    static let projectsRemove = "projects.remove"
    static let projectsSkillCount = "projects.skillCount"
    static let projectsSyncedToolsCount = "projects.syncedToolsCount"
    static let projectsSelectTitle = "projects.select.title"
    static let projectsSelectDescription = "projects.select.description"
    static let projectsRulesTitle = "projects.rules.title"
    static let projectsRulesSyncedCount = "projects.rules.syncedCount"
    static let projectsRulesEdit = "projects.rules.edit"
    static let projectsRulesSyncAll = "projects.rules.syncAll"
    static let projectsRulesRemove = "projects.rules.remove"
    static let projectsRulesCreate = "projects.rules.create"
    static let projectsSkillsMissingTitle = "projects.skills.missing.title"
    static let projectsSkillsMissingDescription = "projects.skills.missing.description"
    static let projectsSkillsEmptyTitle = "projects.skills.empty.title"
    static let projectsSkillsEmptyDescription = "projects.skills.empty.description"
    static let projectsSkillDetailProject = "projects.skillDetail.project"
    static let projectsSkillDetailGlobal = "projects.skillDetail.global"
    static let projectsSkillDetailHelp = "projects.skillDetail.help"
    static let projectsSyncAllTools = "projects.sync.allTools"
    static let projectsSyncDirectory = "projects.sync.directory"
    static let projectsRemoveDirectory = "projects.sync.removeDirectory"
    static let projectsSourceSkillCount = "projects.sync.sourceSkillCount"
    static let projectsChangeTitle = "projects.change.title"
    static let projectsChangeDestination = "projects.change.destination"
    static let projectsChangeContainsSkills = "projects.change.containsSkills"
    static let projectsSyncFailed = "projects.sync.failed"
    static let projectsSyncResult = "projects.sync.result"
    static let projectsRulesChangeTitle = "projects.rules.change.title"
    static let projectsRulesChangeDescription = "projects.rules.change.description"
    static let projectsRulesFailed = "projects.rules.failed"
    static let projectsRulesResult = "projects.rules.result"
    static let globalSyncRescan = "globalSync.rescan"
    static let projectDetailUpdate = "projectDetail.update"
    static let projectDetailSource = "projectDetail.source"
    static let projectDetailRepository = "projectDetail.repository"
    static let projectDetailUpdatedAt = "projectDetail.updatedAt"
    static let projectDetailUpdateFound = "projectDetail.updateFound"
    static let projectDetailUpdateNow = "projectDetail.updateNow"
    static let projectDetailCheckUpdate = "projectDetail.checkUpdate"
    static let projectDetailLinkRepository = "projectDetail.linkRepository"
    static let projectDetailReadFailed = "projectDetail.readFailed"
    static let projectDetailOpenTerminal = "projectDetail.openTerminal"
    static let projectDetailOpenEditor = "projectDetail.openEditor"
    static let dashboardScope = "dashboard.scope"
    static let dashboardProject = "dashboard.project"
    static let dashboardAllProjects = "dashboard.allProjects"
    static let dashboardDisabledTitle = "dashboard.disabled.title"
    static let dashboardDisabledCount = "dashboard.disabled.count"
    static let dashboardDisabledHelp = "dashboard.disabled.help"
    static let dashboardDisable = "dashboard.disable"
    static let dashboardDisableDescription = "dashboard.disable.description"
    static let dashboardDisabledEmpty = "dashboard.disabled.empty"
    static let dashboardRestore = "dashboard.restore"
    static let dashboardAll = "dashboard.scope.all"
    static let dashboardGlobal = "dashboard.scope.global"
    static let dashboardProjectScope = "dashboard.scope.project"
    static let syncStateLinked = "sync.state.linked"
    static let syncStateDirectoryLinked = "sync.state.directoryLinked"
    static let syncStateMissing = "sync.state.missing"
    static let syncStateBroken = "sync.state.broken"
    static let syncStateForeignLink = "sync.state.foreignLink"
    static let syncStateOccupied = "sync.state.occupied"
    static let syncStateRootConflict = "sync.state.rootConflict"
    static let syncChangeCreateDirectory = "sync.change.createDirectory"
    static let syncChangeReplaceDirectory = "sync.change.replaceDirectory"
    static let syncChangeRemoveDirectory = "sync.change.removeDirectory"
    static let syncSummaryReplaceDirectory = "sync.summary.replaceDirectory"
    static let syncSummaryCreateDirectory = "sync.summary.createDirectory"
    static let syncSummaryRemoveDirectory = "sync.summary.removeDirectory"
    static let syncResultKeepDirectory = "sync.result.keepDirectory"
    static let syncResultBackup = "sync.result.backup"
    static let syncResultApplied = "sync.result.applied"
    static let ruleTargetClaudeDirectory = "rule.target.claudeDirectory"
    static let ruleTargetCursor = "rule.target.cursor"
    static let ruleTargetCodex = "rule.target.codex"
    static let ruleChangeCreate = "rule.change.create"
    static let ruleChangeReplace = "rule.change.replace"
    static let ruleChangeRemove = "rule.change.remove"
    static let ruleSummaryReplace = "rule.summary.replace"
    static let ruleSummaryCursorCreate = "rule.summary.cursorCreate"
    static let ruleSummaryCreate = "rule.summary.create"
    static let ruleSummaryRemove = "rule.summary.remove"
    static let ruleResultKeep = "rule.result.keep"
    static let ruleResultBackup = "rule.result.backup"
    static let ruleResultApplied = "rule.result.applied"
    static let syncActionBackupAll = "sync.action.backupAll"
    static let syncActionAll = "sync.action.all"
    static let syncActionBackupReplace = "sync.action.backupReplace"
    static let syncActionRemoveLink = "sync.action.removeLink"
    static let syncActionCreateLink = "sync.action.createLink"
    static let ruleActionBackup = "rule.action.backup"
    static let ruleActionRemove = "rule.action.remove"
    static let ruleActionSync = "rule.action.sync"
    static let projectDetailLinkedAndSynced = "projectDetail.status.linkedAndSynced"
    static let projectDetailUpdateAvailable = "projectDetail.status.updateAvailable"
    static let projectDetailUpToDate = "projectDetail.status.upToDate"
    static let projectDetailUpdated = "projectDetail.status.updated"
    static let projectDetailLinkRequired = "projectDetail.error.linkRequired"
    static let projectDetailNotFound = "projectDetail.error.notFound"
    static let dashboardDisabledReadFailed = "dashboard.error.disabledReadFailed"
    static let dashboardDisableFailed = "dashboard.error.disableFailed"
    static let dashboardRestoreConflict = "dashboard.error.restoreConflict"

    static let allKeys: [String] = [
        appName,
        settingsTabGeneral,
        settingsTabProxy,
        settingsTabAbout,
        settingsProxySectionEnable,
        settingsProxyEnableProxy,
        settingsProxySectionServer,
        settingsProxyImportFromEnvironment,
        settingsProxyFieldTypeLabel,
        settingsProxyFieldTypeHint,
        settingsProxyFieldHostLabel,
        settingsProxyFieldHostHint,
        settingsProxyFieldPortLabel,
        settingsProxyFieldPortHint,
        settingsProxyValidationInvalidHostPort,
        settingsProxySectionAuthentication,
        settingsProxyEnableAuthentication,
        settingsProxyFieldUsernameLabel,
        settingsProxyFieldUsernameHint,
        settingsProxyFieldPasswordLabel,
        settingsProxyFieldPasswordHint,
        settingsProxySavePassword,
        settingsProxyClearPassword,
        settingsProxySectionBypass,
        settingsProxyBypassDescription,
        settingsProxyBypassExamples,
        settingsProxyStatusImportNoneFound,
        settingsProxyStatusImportImported,
        settingsProxyStatusImportImportedPasswordSaveFailed,
        settingsProxyStatusPasswordSaved,
        settingsProxyStatusPasswordSaveFailed,
        settingsProxyStatusPasswordCleared,
        settingsProxyStatusPasswordClearFailed,
        settingsSectionPaths,
        settingsSectionPathsSharedSkills,
        settingsSectionPathsLockFile,
        settingsSectionLanguage,
        settingsLanguageAppLanguage,
        settingsLanguageSystemDefault,
        settingsLanguageEnglish,
        settingsLanguageChineseHans,
        settingsSectionFont,
        settingsFontFamily,
        settingsFontSize,
        settingsFontPreviewSentence,
        settingsAboutAppName,
        settingsAboutTagline,
        settingsAboutGitHub,
        settingsUpdateChecking,
        settingsUpdateDownloading,
        settingsUpdateRetry,
        settingsUpdateAvailablePrefix,
        settingsUpdateNow,
        settingsUpdateViewOnGitHub,
        settingsUpdateCheckForUpdates,
        sidebarSectionOverview,
        sidebarSectionAgents,
        sidebarDashboard,
        sidebarRegistry,
        sidebarClawHub,
        sidebarHelpUpdateAvailable,
        sidebarInstallFromGitHub,
        sidebarInstallFromLocalFolder,
        sidebarHelpInstallSkill,
        sidebarHelpCheckAllUpdates,
        sidebarHelpRefreshSkills,
        emptySelectSkillTitle,
        emptySelectSkillSubtitleList,
        emptySelectSkillSubtitleRegistry,
        emptySelectSkillSubtitleClawHub,
        dashboardLanguageMenuLabel,
        dashboardLanguageMenuHelp,
        commonCancel, commonClose, commonDone, commonOK, commonSourcePath, commonShowInFinder,
        sidebarGlobalSync, sidebarProjects, contentPreparingGlobalSync, contentPreparingProjects,
        projectsTitle, projectsEmptyTitle, projectsEmptyDescription, projectsAdd, projectsRescan, projectsChooseRoot, projectsRemove, projectsSkillCount, projectsSyncedToolsCount, projectsSelectTitle, projectsSelectDescription, projectsRulesTitle, projectsRulesSyncedCount, projectsRulesEdit, projectsRulesSyncAll, projectsRulesRemove, projectsRulesCreate, projectsSkillsMissingTitle, projectsSkillsMissingDescription, projectsSkillsEmptyTitle, projectsSkillsEmptyDescription, projectsSkillDetailProject, projectsSkillDetailGlobal, projectsSkillDetailHelp, projectsSyncAllTools, projectsSyncDirectory, projectsRemoveDirectory, projectsSourceSkillCount, projectsChangeTitle, projectsChangeDestination, projectsChangeContainsSkills, projectsSyncFailed, projectsSyncResult, projectsRulesChangeTitle, projectsRulesChangeDescription, projectsRulesFailed, projectsRulesResult,
        globalSyncRescan, projectDetailUpdate, projectDetailSource, projectDetailRepository, projectDetailUpdatedAt, projectDetailUpdateFound, projectDetailUpdateNow, projectDetailCheckUpdate, projectDetailLinkRepository, projectDetailReadFailed, projectDetailOpenTerminal, projectDetailOpenEditor,
        dashboardScope, dashboardProject, dashboardAllProjects, dashboardDisabledTitle, dashboardDisabledCount, dashboardDisabledHelp, dashboardDisable, dashboardDisableDescription, dashboardDisabledEmpty, dashboardRestore, dashboardAll, dashboardGlobal, dashboardProjectScope,
        syncStateLinked, syncStateDirectoryLinked, syncStateMissing, syncStateBroken, syncStateForeignLink, syncStateOccupied, syncStateRootConflict, syncChangeCreateDirectory, syncChangeReplaceDirectory, syncChangeRemoveDirectory, syncSummaryReplaceDirectory, syncSummaryCreateDirectory, syncSummaryRemoveDirectory, syncResultKeepDirectory, syncResultBackup, syncResultApplied, ruleTargetClaudeDirectory, ruleTargetCursor, ruleTargetCodex, ruleChangeCreate, ruleChangeReplace, ruleChangeRemove, ruleSummaryReplace, ruleSummaryCursorCreate, ruleSummaryCreate, ruleSummaryRemove, ruleResultKeep, ruleResultBackup, ruleResultApplied,
        syncActionBackupAll, syncActionAll, syncActionBackupReplace, syncActionRemoveLink, syncActionCreateLink, ruleActionBackup, ruleActionRemove, ruleActionSync,
        projectDetailLinkedAndSynced, projectDetailUpdateAvailable, projectDetailUpToDate, projectDetailUpdated, projectDetailLinkRequired, projectDetailNotFound, dashboardDisabledReadFailed, dashboardDisableFailed, dashboardRestoreConflict,
    ]
}

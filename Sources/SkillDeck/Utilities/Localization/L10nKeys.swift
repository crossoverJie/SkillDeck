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
    ]
}

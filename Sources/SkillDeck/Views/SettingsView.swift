import SwiftUI

/// SettingsView is the app settings page (opened via Cmd+,)
///
/// TabView renders as system standard preferences window style (with tab bar) on macOS
struct SettingsView: View {

    /// @AppStorage is a SwiftUI property wrapper that syncs values with UserDefaults.
    @AppStorage(FontSettings.sizeKey) private var uiFontSize = FontSettings.defaultFontSize

    @AppStorage(LanguageSettings.appLanguageKey) private var appLanguageRaw: String = LanguageSettings.defaultLanguage.rawValue
    @State private var tabViewReloadToken = UUID()
    @State private var lastRenderedLanguageRaw: String = ""

    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    var body: some View {
        let minSize = SettingsWindowSizing.minSize(forFontSize: uiFontSize)
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text(L10n.string(L10nKeys.settingsTabGeneral, bundle: localizationBundle, locale: locale))
                }

            ProxySettingsView()
                .tabItem {
                    Image(systemName: "network")
                    Text(L10n.string(L10nKeys.settingsTabProxy, bundle: localizationBundle, locale: locale))
                }

            AboutSettingsView()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text(L10n.string(L10nKeys.settingsTabAbout, bundle: localizationBundle, locale: locale))
                }
        }
        .id(tabViewReloadToken)
        .onAppear {
            if lastRenderedLanguageRaw != appLanguageRaw {
                lastRenderedLanguageRaw = appLanguageRaw
                tabViewReloadToken = UUID()
            }
        }
        .onChange(of: appLanguageRaw) { _, newValue in
            lastRenderedLanguageRaw = newValue
            tabViewReloadToken = UUID()
        }
        // Increased height to accommodate update status UI (from 250 to 350).
        .frame(minWidth: minSize.width, minHeight: minSize.height)
    }
}

/// General settings
struct GeneralSettingsView: View {

    /// @AppStorage keeps UI preferences in UserDefaults and updates the view automatically.
    @AppStorage(FontSettings.familyKey) private var uiFontFamily = FontSettings.systemFontFamily
    @AppStorage(FontSettings.sizeKey) private var uiFontSize = FontSettings.defaultFontSize

    @AppStorage(LanguageSettings.appLanguageKey) private var appLanguageRaw: String = LanguageSettings.defaultLanguage.rawValue

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(Constants.sharedSkillsPath)
                        .textSelection(.enabled)  // Allow users to select and copy
                        .foregroundStyle(.secondary)
                } label: {
                    LText(key: L10nKeys.settingsSectionPathsSharedSkills)
                }

                LabeledContent {
                    Text(Constants.lockFilePath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } label: {
                    LText(key: L10nKeys.settingsSectionPathsLockFile)
                }
            } header: {
                LText(key: L10nKeys.settingsSectionPaths)
            }

            Section {
                LabeledContent {
                    Picker(selection: $appLanguageRaw, label: EmptyView()) {
                        LText(key: L10nKeys.settingsLanguageSystemDefault).tag("system")
                        LText(key: L10nKeys.settingsLanguageEnglish).tag("en")
                        LText(key: L10nKeys.settingsLanguageChineseHans).tag("zh-Hans")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    LText(key: L10nKeys.settingsLanguageAppLanguage)
                }
            } header: {
                LText(key: L10nKeys.settingsSectionLanguage)
            }

            Section {
                LabeledContent {
                    Picker(selection: $uiFontFamily, label: EmptyView()) {
                        ForEach(FontSettings.availableFontFamilies, id: \.self) { family in
                            Text(family)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    LText(key: L10nKeys.settingsFontFamily)
                }

                LabeledContent {
                    Stepper(value: $uiFontSize, in: FontSettings.minFontSize...FontSettings.maxFontSize, step: 1) {
                        Text("\(Int(uiFontSize)) pt")
                            .monospacedDigit()
                    }
                } label: {
                    LText(key: L10nKeys.settingsFontSize)
                }

                LText(key: L10nKeys.settingsFontPreviewSentence)
                    .font(FontSettings.font(family: uiFontFamily, size: uiFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                LText(key: L10nKeys.settingsSectionFont)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// About page (with app update check UI)
///
/// @Environment(SkillManager.self) gets SkillManager instance from View tree.
/// Injected via Settings { ... .environment(skillManager) } in SkillDeckApp.
struct AboutSettingsView: View {

    /// Get SkillManager from View environment
    /// @Environment is similar to React's useContext or Android's dependency injection
    @Environment(SkillManager.self) private var skillManager

    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            LText(key: L10nKeys.settingsAboutAppName).appFont(.title)
                .fontWeight(.bold)

            LText(key: L10nKeys.settingsAboutTagline)
                .foregroundStyle(.secondary)

            // Read version number from Info.plist, Bundle.main contains Info.plist when running as .app bundle
            // CFBundleShortVersionString is the user-visible version number (e.g., "1.0.0")
            // Falls back to "dev" if running via swift run (no .app bundle)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").appFont(.caption)
                .foregroundStyle(.tertiary)

            // Link is SwiftUI built-in hyperlink component, calls system default browser to open URL when clicked
            // Renders as blue clickable text on macOS, similar to HTML's <a> tag
            Link(
                L10n.string(L10nKeys.settingsAboutGitHub, bundle: localizationBundle, locale: locale),
                destination: URL(string: "https://github.com/crossoverjie/SkillDeck")!
            )
            .appFont(.caption)

            // Divider is horizontal separator line (similar to HTML's <hr>), used to visually separate app info and update status area
            Divider()
                .padding(.horizontal)

            // Update status area: shows different UI based on SkillManager state
            updateStatusView
        }
        .padding()
        // .task automatically triggers update check when View first appears (subject to 4-hour interval limit)
        // This way when user opens settings page, if more than 4 hours since last check, it will automatically check
        .task {
            await skillManager.checkForAppUpdate()
        }
    }

    /// Update status view: dynamically displays different UI based on SkillManager's update-related state properties
    ///
    /// @ViewBuilder allows using if-else in computed properties to return different View types
    /// (Swift's View is strongly typed, different branches returning different types need @ViewBuilder to wrap uniformly)
    @ViewBuilder
    private var updateStatusView: some View {
        if skillManager.isCheckingAppUpdate {
            // Checking state: show spinning indicator
            HStack(spacing: 8) {
                // ProgressView() without arguments shows indeterminate spinning indicator (spinner)
                // controlSize(.small) controls size to small
                ProgressView()
                    .controlSize(.small)
                LText(key: L10nKeys.settingsUpdateChecking).appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skillManager.isDownloadingUpdate {
            // Downloading state: show determinate progress bar
            VStack(spacing: 6) {
                // ProgressView(value:total:) shows determinate horizontal progress bar
                // value is current value, total is maximum value (default 1.0)
                ProgressView(value: skillManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                // Show percentage (multiply by 100 and keep integer)
                // Int() truncates Double to integer (similar to Java's (int) cast)
                Text(
                    String(
                        format: L10n.string(L10nKeys.settingsUpdateDownloading, bundle: localizationBundle, locale: locale),
                        Int(skillManager.downloadProgress * 100)
                    )
                )
                .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()  // Monospaced digit font, avoids text jitter when percentage changes
            }
        } else if let error = skillManager.updateError {
            // Error state: show red error message and retry button
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).appFont(.caption)
                    Text(error).appFont(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)  // Limit error message to max 2 lines
                }

                Button(L10n.string(L10nKeys.settingsUpdateRetry, bundle: localizationBundle, locale: locale)) {
                    Task { await skillManager.checkForAppUpdate(force: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if let updateInfo = skillManager.appUpdateInfo {
            // Has available update state: show new version number, update button and GitHub link
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    // Use orange arrow icon to indicate update is available
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                    Text(
                        String(
                            format: L10n.string(L10nKeys.settingsUpdateAvailablePrefix, bundle: localizationBundle, locale: locale),
                            updateInfo.version
                        )
                    )
                    .appFont(.caption)
                        .fontWeight(.medium)
                }

                HStack(spacing: 12) {
                    // "Update Now" button triggers download and install update
                    // .borderedProminent is filled prominent button style (similar to Material Design's Filled Button)
                    Button(L10n.string(L10nKeys.settingsUpdateNow, bundle: localizationBundle, locale: locale)) {
                        Task { await skillManager.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // "View on GitHub" link opens Release page in browser
                    // Uses Link component instead of Button because it's external navigation (opens browser)
                    if let url = URL(string: updateInfo.htmlUrl) {
                        Link(
                            L10n.string(L10nKeys.settingsUpdateViewOnGitHub, bundle: localizationBundle, locale: locale),
                            destination: url
                        )
                        .appFont(.caption)
                    }
                }
            }
        } else {
            // No update/not checked state: show manual check button
            // force: true ignores 4-hour interval limit, executes check immediately
            Button(L10n.string(L10nKeys.settingsUpdateCheckForUpdates, bundle: localizationBundle, locale: locale)) {
                Task { await skillManager.checkForAppUpdate(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

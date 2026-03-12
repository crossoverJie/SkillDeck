import SwiftUI

/// SettingsView is the app settings page (opened via Cmd+,)
///
/// TabView renders as system standard preferences window style (with tab bar) on macOS
struct SettingsView: View {

    /// @AppStorage is a SwiftUI property wrapper that syncs values with UserDefaults.
    @AppStorage(FontSettings.sizeKey) private var uiFontSize = FontSettings.defaultFontSize

    var body: some View {
        let minSize = SettingsWindowSizing.minSize(forFontSize: uiFontSize)
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ProxySettingsView()
                .tabItem {
                    Label("Proxy", systemImage: "network")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
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

    var body: some View {
        Form {
            Section("Paths") {
                LabeledContent("Shared Skills") {
                    Text(Constants.sharedSkillsPath)
                        .textSelection(.enabled)  // Allow users to select and copy
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Lock File") {
                    Text(Constants.lockFilePath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Font") {
                LabeledContent("Family") {
                    Picker("Family", selection: $uiFontFamily) {
                        ForEach(FontSettings.availableFontFamilies, id: \.self) { family in
                            Text(family)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                LabeledContent("Size") {
                    Stepper(value: $uiFontSize, in: FontSettings.minFontSize...FontSettings.maxFontSize, step: 1) {
                        Text("\(Int(uiFontSize)) pt")
                            .monospacedDigit()
                    }
                }

                Text("Preview: The quick brown fox jumps over the lazy dog")
                    .font(FontSettings.font(family: uiFontFamily, size: uiFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SkillDeck").appFont(.title)
                .fontWeight(.bold)

            Text("Native macOS Agent Skills Manager")
                .foregroundStyle(.secondary)

            // Read version number from Info.plist, Bundle.main contains Info.plist when running as .app bundle
            // CFBundleShortVersionString is the user-visible version number (e.g., "1.0.0")
            // Falls back to "dev" if running via swift run (no .app bundle)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").appFont(.caption)
                .foregroundStyle(.tertiary)

            // Link is SwiftUI built-in hyperlink component, calls system default browser to open URL when clicked
            // Renders as blue clickable text on macOS, similar to HTML's <a> tag
            Link("GitHub", destination: URL(string: "https://github.com/crossoverjie/SkillDeck")!).appFont(.caption)

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
                Text("Checking for updates...").appFont(.caption)
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
                Text("Downloading... \(Int(skillManager.downloadProgress * 100))%").appFont(.caption)
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

                Button("Retry") {
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
                    Text("Update available: v\(updateInfo.version)").appFont(.caption)
                        .fontWeight(.medium)
                }

                HStack(spacing: 12) {
                    // "Update Now" button triggers download and install update
                    // .borderedProminent is filled prominent button style (similar to Material Design's Filled Button)
                    Button("Update Now") {
                        Task { await skillManager.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // "View on GitHub" link opens Release page in browser
                    // Uses Link component instead of Button because it's external navigation (opens browser)
                    if let url = URL(string: updateInfo.htmlUrl) {
                        Link("View on GitHub", destination: url).appFont(.caption)
                    }
                }
            }
        } else {
            // No update/not checked state: show manual check button
            // force: true ignores 4-hour interval limit, executes check immediately
            Button("Check for Updates") {
                Task { await skillManager.checkForAppUpdate(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

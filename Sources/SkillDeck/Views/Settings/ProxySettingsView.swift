import SwiftUI

/// ProxySettingsView lets users configure a per-app network proxy.
///
/// Settings are persisted via UserDefaults (through @AppStorage), while the password is stored in
/// Keychain (never in UserDefaults).
struct ProxySettingsView: View {

    @AppStorage(NetworkSessionProvider.proxyEnabledKey) private var proxyEnabled = false
    @AppStorage(NetworkSessionProvider.proxyTypeKey) private var proxyTypeRaw = ProxySettings.ProxyType.https.rawValue
    @AppStorage(NetworkSessionProvider.proxyHostKey) private var proxyHost = ""
    @AppStorage(NetworkSessionProvider.proxyPortKey) private var proxyPort = 0
    @AppStorage(NetworkSessionProvider.proxyAuthEnabledKey) private var proxyAuthEnabled = true
    @AppStorage(NetworkSessionProvider.proxyUsernameKey) private var proxyUsername = ""
    @AppStorage(NetworkSessionProvider.proxyBypassKey) private var proxyBypassRaw = ""

    @State private var proxyPassword = ""
    @State private var passwordStatusKey: String?
    @State private var importStatusKey: String?

    private let keychain = KeychainService(service: "SkillDeck")

    private var isValid: Bool {
        guard proxyEnabled else { return true }
        let trimmedHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedHost.isEmpty && (1...65535).contains(proxyPort)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $proxyEnabled) {
                    LText(key: L10nKeys.settingsProxyEnableProxy)
                }
            } header: {
                LText(key: L10nKeys.settingsProxySectionEnable)
            }

            Section {
                Button {
                    Task {
                        await importFromEnvironment()
                    }
                } label: {
                    LText(key: L10nKeys.settingsProxyImportFromEnvironment)
                }

                if let importStatusKey {
                    LText(key: importStatusKey)
                        .foregroundStyle(.secondary)
                        .appFont(.caption)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        HStack(spacing: 6) {
                            LText(key: L10nKeys.settingsProxyFieldTypeLabel)
                            LText(key: L10nKeys.settingsProxyFieldTypeHint)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(width: 170, alignment: .leading)

                        HStack {
                            Spacer(minLength: 0)
                            Picker("", selection: $proxyTypeRaw) {
                                ForEach(ProxySettings.ProxyType.allCases) { type in
                                    Text(type.displayName).tag(type.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    GridRow {
                        HStack(spacing: 6) {
                            LText(key: L10nKeys.settingsProxyFieldHostLabel)
                            LText(key: L10nKeys.settingsProxyFieldHostHint)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(width: 170, alignment: .leading)

                        HStack {
                            Spacer(minLength: 0)
                            TextField("", text: $proxyHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                    }

                    GridRow {
                        HStack(spacing: 6) {
                            LText(key: L10nKeys.settingsProxyFieldPortLabel)
                            LText(key: L10nKeys.settingsProxyFieldPortHint)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .frame(width: 170, alignment: .leading)

                        HStack {
                            Spacer(minLength: 0)
                            TextField("", value: $proxyPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                }

                if proxyEnabled, !isValid {
                    LText(key: L10nKeys.settingsProxyValidationInvalidHostPort)
                        .foregroundStyle(.red)
                        .appFont(.caption)
                }
            } header: {
                LText(key: L10nKeys.settingsProxySectionServer)
            }
            .disabled(!proxyEnabled)

            Section {
                Toggle(isOn: $proxyAuthEnabled) {
                    LText(key: L10nKeys.settingsProxyEnableAuthentication)
                }

                Group {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            HStack(spacing: 6) {
                                LText(key: L10nKeys.settingsProxyFieldUsernameLabel)
                                LText(key: L10nKeys.settingsProxyFieldUsernameHint)
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)

                            HStack {
                                Spacer(minLength: 0)
                                TextField("", text: $proxyUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                            }
                        }

                        GridRow {
                            HStack(spacing: 6) {
                                LText(key: L10nKeys.settingsProxyFieldPasswordLabel)
                                LText(key: L10nKeys.settingsProxyFieldPasswordHint)
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)

                            HStack {
                                Spacer(minLength: 0)
                                SecureField("", text: $proxyPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await savePassword()
                            }
                        } label: {
                            LText(key: L10nKeys.settingsProxySavePassword)
                        }

                        Button {
                            Task {
                                await clearPassword()
                            }
                        } label: {
                            LText(key: L10nKeys.settingsProxyClearPassword)
                        }

                        if let passwordStatusKey {
                            LText(key: passwordStatusKey)
                                .foregroundStyle(.secondary)
                                .appFont(.caption)
                        }
                    }
                }
                .disabled(!proxyAuthEnabled)
            } header: {
                LText(key: L10nKeys.settingsProxySectionAuthentication)
            }
            .disabled(!proxyEnabled)

            Section {
                LText(key: L10nKeys.settingsProxyBypassDescription)
                    .foregroundStyle(.secondary)

                TextEditor(text: $proxyBypassRaw)
                    .frame(height: 90)
                    .border(Color(nsColor: .separatorColor))

                LText(key: L10nKeys.settingsProxyBypassExamples)
                    .foregroundStyle(.secondary)
                    .appFont(.caption)
            } header: {
                LText(key: L10nKeys.settingsProxySectionBypass)
            }
            .disabled(!proxyEnabled)
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadPassword()
        }
    }

    private func importFromEnvironment() async {
        importStatusKey = nil

        let env = ProcessInfo.processInfo.environment
        guard let imported = ProxyEnvironmentImporter.importFromEnvironment(env) else {
            importStatusKey = L10nKeys.settingsProxyStatusImportNoneFound
            return
        }

        proxyEnabled = true
        proxyTypeRaw = imported.type.rawValue
        proxyHost = imported.host
        proxyPort = imported.port
        proxyAuthEnabled = imported.username != nil || imported.password != nil
        proxyUsername = imported.username ?? ""
        proxyBypassRaw = imported.bypassList.joined(separator: ", ")

        if let password = imported.password {
            proxyPassword = password
            do {
                try await keychain.setPassword(password, forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            } catch {
                importStatusKey = L10nKeys.settingsProxyStatusImportImportedPasswordSaveFailed
                return
            }
        }

        importStatusKey = L10nKeys.settingsProxyStatusImportImported
    }

    private func loadPassword() async {
        proxyPassword = (try? await keychain.getPassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)) ?? ""
    }

    private func savePassword() async {
        passwordStatusKey = nil
        do {
            if proxyPassword.isEmpty {
                try await keychain.deletePassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            } else {
                try await keychain.setPassword(proxyPassword, forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            }
            passwordStatusKey = L10nKeys.settingsProxyStatusPasswordSaved
        } catch {
            passwordStatusKey = L10nKeys.settingsProxyStatusPasswordSaveFailed
        }
    }

    private func clearPassword() async {
        proxyPassword = ""
        passwordStatusKey = nil
        do {
            try await keychain.deletePassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            passwordStatusKey = L10nKeys.settingsProxyStatusPasswordCleared
        } catch {
            passwordStatusKey = L10nKeys.settingsProxyStatusPasswordClearFailed
        }
    }
}

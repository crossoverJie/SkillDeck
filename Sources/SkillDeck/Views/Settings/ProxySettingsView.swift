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
    @State private var passwordStatusMessage: String?
    @State private var importStatusMessage: String?

    private let keychain = KeychainService(service: "SkillDeck")

    private var isValid: Bool {
        guard proxyEnabled else { return true }
        let trimmedHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedHost.isEmpty && (1...65535).contains(proxyPort)
    }

    var body: some View {
        Form {
            Section("Enable") {
                Toggle("Enable Proxy", isOn: $proxyEnabled)
            }

            Section("Server") {
                Button("Import from Environment") {
                    Task {
                        await importFromEnvironment()
                    }
                }

                if let importStatusMessage {
                    Text(importStatusMessage)
                        .foregroundStyle(.secondary)
                        .appFont(.caption)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        HStack(spacing: 6) {
                            Text("Type")
                            Text("HTTPS / SOCKS5")
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
                            Text("Host")
                            Text("e.g. 127.0.0.1")
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
                            Text("Port")
                            Text("1–65535")
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
                    Text("Host must be non-empty and port must be between 1 and 65535.")
                        .foregroundStyle(.red)
                        .appFont(.caption)
                }
            }
            .disabled(!proxyEnabled)

            Section("Authentication") {
                Toggle("Enable Authentication", isOn: $proxyAuthEnabled)

                Group {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            HStack(spacing: 6) {
                                Text("Username")
                                Text("optional")
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
                                Text("Password")
                                Text("Keychain")
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
                        Button("Save Password") {
                            Task {
                                await savePassword()
                            }
                        }

                        Button("Clear Password") {
                            Task {
                                await clearPassword()
                            }
                        }

                        if let passwordStatusMessage {
                            Text(passwordStatusMessage)
                                .foregroundStyle(.secondary)
                                .appFont(.caption)
                        }
                    }
                }
                .disabled(!proxyAuthEnabled)
            }
            .disabled(!proxyEnabled)

            Section("Bypass") {
                Text("Requests matching these hosts will NOT use the proxy. Separate items with commas or new lines.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $proxyBypassRaw)
                    .frame(height: 90)
                    .border(Color(nsColor: .separatorColor))

                Text("Examples: localhost, 127.0.0.1, *.internal")
                    .foregroundStyle(.secondary)
                    .appFont(.caption)
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
        importStatusMessage = nil

        let env = ProcessInfo.processInfo.environment
        guard let imported = ProxyEnvironmentImporter.importFromEnvironment(env) else {
            importStatusMessage = "No proxy environment variables found."
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
                importStatusMessage = "Imported (password save failed)"
                return
            }
        }

        importStatusMessage = "Imported"
    }

    private func loadPassword() async {
        proxyPassword = (try? await keychain.getPassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)) ?? ""
    }

    private func savePassword() async {
        passwordStatusMessage = nil
        do {
            if proxyPassword.isEmpty {
                try await keychain.deletePassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            } else {
                try await keychain.setPassword(proxyPassword, forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            }
            passwordStatusMessage = "Saved"
        } catch {
            passwordStatusMessage = "Save failed"
        }
    }

    private func clearPassword() async {
        proxyPassword = ""
        passwordStatusMessage = nil
        do {
            try await keychain.deletePassword(forKey: NetworkSessionProvider.proxyPasswordKeychainKey)
            passwordStatusMessage = "Cleared"
        } catch {
            passwordStatusMessage = "Clear failed"
        }
    }
}

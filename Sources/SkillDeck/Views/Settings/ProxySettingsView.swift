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
    @AppStorage(NetworkSessionProvider.proxyUsernameKey) private var proxyUsername = ""
    @AppStorage(NetworkSessionProvider.proxyBypassKey) private var proxyBypassRaw = ""

    @State private var proxyPassword = ""
    @State private var passwordStatusMessage: String?

    private let keychain = KeychainService(service: "SkillDeck")

    private var isValid: Bool {
        guard proxyEnabled else { return true }
        let trimmedHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedHost.isEmpty && (1...65535).contains(proxyPort)
    }

    var body: some View {
        Form {
            Section("Proxy") {
                Toggle("Enable Proxy", isOn: $proxyEnabled)

                LabeledContent("Type") {
                    Picker("Type", selection: $proxyTypeRaw) {
                        ForEach(ProxySettings.ProxyType.allCases) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                LabeledContent("Host") {
                    TextField("Proxy host", text: $proxyHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                LabeledContent("Port") {
                    TextField("Port", value: $proxyPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                LabeledContent("Username") {
                    TextField("Optional", text: $proxyUsername)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                LabeledContent("Password") {
                    SecureField("Stored in Keychain", text: $proxyPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                HStack(spacing: 12) {
                    Button("Save Password") {
                        Task {
                            await savePassword()
                        }
                    }
                    .disabled(!proxyEnabled)

                    Button("Clear Password") {
                        Task {
                            await clearPassword()
                        }
                    }
                    .disabled(!proxyEnabled)

                    if let passwordStatusMessage {
                        Text(passwordStatusMessage)
                            .foregroundStyle(.secondary)
                            .appFont(.caption)
                    }
                }

                if proxyEnabled, !isValid {
                    Text("Host must be non-empty and port must be between 1 and 65535.")
                        .foregroundStyle(.red)
                        .appFont(.caption)
                }
            }

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
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadPassword()
        }
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

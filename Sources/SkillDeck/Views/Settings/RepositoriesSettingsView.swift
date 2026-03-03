import SwiftUI

/// RepositoriesSettingsView — Settings tab for managing custom Git repositories.
///
/// Displays a list of user-configured repositories (SSH or HTTPS+Token) and
/// allows adding new ones or removing existing ones.
///
/// Accessed via Settings (Cmd+,) → "Repositories" tab.
struct RepositoriesSettingsView: View {

    @Environment(SkillManager.self) private var skillManager

    /// Controls visibility of the "Add Repository" sheet
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repository list or empty state
            if skillManager.repositories.isEmpty {
                // Empty state: centered message with add button
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text("No Custom Repositories")
                        .font(.headline)

                    Text("Add a GitHub or GitLab repository to use as a custom Skills source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    Button("Add Repository") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Repository list
                List {
                    ForEach(skillManager.repositories) { repo in
                        RepositoryRowView(repo: repo)
                    }
                    .onDelete { indexSet in
                        // SwiftUI's onDelete provides the index set of rows to remove
                        for idx in indexSet {
                            let id = skillManager.repositories[idx].id
                            Task { await skillManager.removeRepository(id: id) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Bottom toolbar: "+" add button
            HStack {
                // "+" button: shows add repository sheet
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a custom repository")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // Add Repository sheet
        .sheet(isPresented: $showAddSheet) {
            AddRepositorySheet(isPresented: $showAddSheet)
                .environment(skillManager)
        }
    }
}

// MARK: - Repository Row

/// Displays a single repository row in the settings list.
private struct RepositoryRowView: View {

    @Environment(SkillManager.self) private var skillManager
    let repo: SkillRepository
    @State private var showDeleteConfirmation = false
    @State private var isRemoving = false

    var body: some View {
        HStack(spacing: 10) {
            // Platform icon (GitHub or GitLab)
            Image(systemName: repo.platform.iconName)
                .foregroundStyle(repo.platform == .github ? Color.primary : Color.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Display name
                Text(repo.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(repo.authType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(repo.repoURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Last synced timestamp or "Never"
            VStack(alignment: .trailing, spacing: 2) {
                if let date = repo.lastSyncedAt {
                    Text("Synced")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Never synced")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Sync status indicator
            syncStatusView

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .help("Remove repository")
            .disabled(isRemoving)
        }
        .padding(.vertical, 2)
        .alert("Remove Repository?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                Task { await removeRepository() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the repository config from SkillDeck. Local clone files are kept.")
        }
    }

    /// Small inline sync status indicator
    @ViewBuilder
    private var syncStatusView: some View {
        let status = skillManager.repoSyncStatuses[repo.id] ?? .idle
        switch status {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func removeRepository() async {
        isRemoving = true
        await skillManager.removeRepository(id: repo.id)
        isRemoving = false
    }
}

// MARK: - Add Repository Sheet

/// Sheet for adding a new custom repository.
///
/// User fills in:
/// - Repository URL (required): SSH or HTTPS
/// - Optional HTTPS credentials (username + token)
/// - Display name (optional, auto-derived from URL if empty)
///
/// On confirm: creates a SkillRepository, calls SkillManager.addRepository(), then syncs.
struct AddRepositorySheet: View {

    @Environment(SkillManager.self) private var skillManager
    @Binding var isPresented: Bool

    // Form state
    @State private var repoURL = ""
    @State private var authType: SkillRepository.AuthType = .ssh
    @State private var httpUsername = "git"
    @State private var accessToken = ""
    @State private var displayName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    /// Whether the form input is valid enough to enable the Add button
    private var canAdd: Bool {
        let urlValid = !repoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tokenValid = authType == .ssh || !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return urlValid && tokenValid && !isAdding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sheet title
            Text("Add Custom Repository")
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Authentication")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                Picker("Authentication", selection: $authType) {
                    ForEach(SkillRepository.AuthType.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: authType) { _, _ in
                    errorMessage = nil
                }
            }

            // Repository URL field
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                // TextField is SwiftUI's single-line text input
                TextField(
                    authType == .ssh ? "git@host:org/repo.git" : "https://host/org/repo.git",
                    text: $repoURL
                )
                    .textFieldStyle(.roundedBorder)
                    // Detect platform on URL change to update the help text
                    .onChange(of: repoURL) { _, _ in
                        errorMessage = nil
                        // Auto-fill display name from URL if user hasn't typed one yet
                        if displayName.isEmpty {
                            let slug = SkillRepository.slugFrom(repoURL: repoURL)
                            if !slug.isEmpty && slug != repoURL {
                                displayName = slug
                            }
                        }
                    }

                Text(authType == .ssh
                     ? "SSH requires keys configured in ~/.ssh"
                     : "Use HTTPS URL with a Personal Access Token")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if authType == .httpsToken {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HTTPS Username")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    TextField("git", text: $httpUsername)
                        .textFieldStyle(.roundedBorder)

                    Text("For GitHub, 'x-access-token' or your username both work; enterprise Git may require account username.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    SecureField("Enter PAT token", text: $accessToken)
                        .textFieldStyle(.roundedBorder)

                    Text("Token is stored securely in macOS Keychain, not in config files.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Display name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                TextField("e.g. team-skills", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                Text("How this repository appears in the sidebar.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Error message (shown if add fails)
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)  // Esc key dismisses

                Spacer()

                Button(isAdding ? "Adding…" : "Add Repository") {
                    Task { await addRepository() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)  // Enter key confirms
            }
        }
        .padding(20)
        .frame(width: 500, height: authType == .ssh ? 360 : 470)
    }

    /// Validate input, create SkillRepository, add via SkillManager, then trigger sync.
    private func addRepository() async {
        let url = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let validationError = SkillRepository.validate(repoURL: url, authType: authType) {
            errorMessage = validationError
            return
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if authType == .httpsToken && token.isEmpty {
            errorMessage = "Access Token is required for HTTPS mode"
            return
        }

        isAdding = true
        errorMessage = nil

        // Derive display name from URL if user left it blank
        let name: String
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = SkillRepository.slugFrom(repoURL: url)
        } else {
            name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let repoID = UUID()
        let credentialKey = authType == .httpsToken ? repoID.uuidString : nil
        let username = httpUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build the SkillRepository model
        let repo = SkillRepository(
            id: repoID,
            name: name,
            repoURL: url,
            authType: authType,
            platform: SkillRepository.platformFrom(repoURL: url),
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: SkillRepository.slugFrom(repoURL: url),
            httpUsername: authType == .httpsToken ? (username.isEmpty ? nil : username) : nil,
            credentialKey: credentialKey
        )

        do {
            try await skillManager.addRepository(
                repo,
                token: authType == .httpsToken ? token : nil
            )
            // Dismiss sheet on success, then trigger initial sync in background
            isPresented = false
            Task { await skillManager.syncRepository(id: repo.id) }
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }
}

import Foundation
import AppKit

/// AppUpdateInfo represents GitHub Release information
///
/// Codable protocol enables bidirectional conversion between this struct and JSON (similar to Java's Jackson @JsonProperty or Go's json tag).
/// CodingKeys enum maps Swift's camelCase property names to snake_case JSON keys returned by GitHub API.
struct AppUpdateInfo: Codable, Sendable {
    /// GitHub Release tag name (e.g. "v1.2.0")
    let tagName: String
    /// Release page URL (for opening in browser)
    let htmlUrl: String
    /// Release title (e.g. "SkillDeck v1.2.0")
    let name: String?
    /// Release description (Markdown format changelog)
    let body: String?
    /// Release publish time (ISO 8601 format)
    let publishedAt: String?
    /// List of release asset files (zip, dmg, etc.)
    /// GitHub API returns assets as an array, each element contains filename and download URL
    let assets: [Asset]?

    /// Release asset file information
    struct Asset: Codable, Sendable {
        /// Filename (e.g. "SkillDeck-v1.0.0-universal.zip")
        let name: String
        /// Browser download URL (direct download link, no API authentication required)
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    /// CodingKeys enum maps Swift property names to JSON keys
    /// Swift convention uses camelCase, but GitHub API returns snake_case,
    /// mapping via CodingKeys (similar to Go struct tag `json:"tag_name"`)
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }

    /// Version number with "v" prefix removed
    /// Computed property executes calculation on each access, similar to Java's getter
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Get download URL for zip file
    ///
    /// Priority: look for real download URL of .zip file in assets (most reliable),
    /// fallback to constructing URL by naming convention if assets is empty.
    /// Benefit of getting URL from assets: works regardless of zip filename changes
    /// (e.g. from SkillDeck.zip to SkillDeck-v1.0.0-universal.zip).
    var downloadURL: String {
        // first(where:) finds first asset ending with .zip (similar to Java Stream's findFirst + filter)
        // hasSuffix checks string suffix (similar to Java's endsWith)
        if let zipAsset = assets?.first(where: { $0.name.hasSuffix(".zip") }) {
            return zipAsset.browserDownloadUrl
        }
        // Fallback: construct URL according to Release workflow naming convention
        // Format: /releases/download/v1.0.0/SkillDeck-v1.0.0-universal.zip
        return "https://github.com/crossoverJie/SkillDeck/releases/download/\(tagName)/SkillDeck-\(tagName)-universal.zip"
    }
}

/// UpdateChecker is responsible for checking and executing app updates
///
/// actor is Swift's concurrency-safe type (similar to a struct with mutex protection in Go, or Erlang's Actor model).
/// Mutable state inside actor is automatically protected from concurrent access, external access to properties/methods must use await.
/// actor is used here because network requests and file operations are asynchronous and require thread safety.
actor UpdateChecker {

    /// GitHub API endpoint: get latest Release
    /// Fixed to SkillDeck repository's releases/latest endpoint
    private let apiURL = "https://api.github.com/repos/crossoverJie/SkillDeck/releases/latest"

    /// UserDefaults key for storing last check time
    /// UserDefaults is macOS/iOS lightweight key-value storage (similar to Android's SharedPreferences)
    private static let lastCheckKey = "lastAppUpdateCheckTime"

    // MARK: - Get Latest Release

    /// Get latest Release info from GitHub API
    ///
    /// - Returns: Release info
    /// - Throws: Network error or JSON parsing error (caller decides how to handle)
    ///
    /// Changed to throws instead of silently returning nil, allowing caller (SkillManager) to distinguish
    /// between "silently ignore during automatic check" and "show specific error when user manually triggers" scenarios
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        // guard let is Swift's null-checking syntax (similar to Go's if err != nil { return })
        // If URL construction fails (invalid format), throw badURL error
        guard let url = URL(string: apiURL) else {
            throw URLError(.badURL)
        }

        // URLRequest encapsulates HTTP request (similar to Java's HttpURLConnection or Go's http.Request)
        var request = URLRequest(url: url)
        // Set 10-second timeout to avoid UI waiting too long due to network issues
        request.timeoutInterval = 10
        // GitHub API requires Accept header to specify JSON format
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        // URLSession.shared is the globally shared network session (similar to Java's HttpClient or Python's requests.Session)
        // data(for:) sends request and returns (Data, URLResponse) tuple
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status code (URLResponse needs downcasting to HTTPURLResponse to access statusCode)
        // as? is Swift's conditional type casting (similar to Java's instanceof + cast)
        // GitHub API returns non-200 status codes in cases like rate limit, 404, etc.,
        // but URLSession doesn't treat HTTP error status codes as errors (only network-level errors throw)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // Try to extract GitHub API error message from response body (JSON format {"message": "..."})
            // e.g. rate limit returns "API rate limit exceeded for ..."
            let message: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiMessage = json["message"] as? String {
                message = apiMessage
            } else {
                message = "HTTP \(httpResponse.statusCode)"
            }
            throw NSError(
                domain: "UpdateChecker",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        // JSONDecoder decodes JSON Data to Swift struct (similar to Java's ObjectMapper or Go's json.Unmarshal)
        let decoder = JSONDecoder()
        return try decoder.decode(AppUpdateInfo.self, from: data)
    }

    // MARK: - Check Interval Control

    /// Determine whether automatic update check should run (4-hour interval)
    ///
    /// nonisolated marker means this method doesn't need actor isolation protection,
    /// can be called directly on any thread (no await needed).
    /// Because UserDefaults itself is thread-safe, no extra actor protection needed.
    nonisolated func shouldAutoCheck() -> Bool {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: UpdateChecker.lastCheckKey)

        // If never checked (lastCheck == 0), should check
        guard lastCheck > 0 else { return true }

        // Date().timeIntervalSince1970 returns current Unix timestamp in seconds, similar to Java's System.currentTimeMillis()/1000
        let now = Date().timeIntervalSince1970
        let fourHours: TimeInterval = 4 * 60 * 60  // 4 hours = 14400 seconds

        // Only allow automatic check if more than 4 hours since last check
        // GitHub unauthenticated API limit is 60/hour, 4-hour interval means max 6/day, well below limit
        return (now - lastCheck) >= fourHours
    }

    /// Record current check time to UserDefaults
    ///
    /// nonisolated for same reason as shouldAutoCheck()
    nonisolated func recordCheckTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UpdateChecker.lastCheckKey)
    }

    // MARK: - Download Update

    /// Download update zip file to temporary directory
    ///
    /// Uses URLSessionDownloadDelegate to report download progress via callback to caller.
    ///
    /// - Parameters:
    ///   - url: Download URL for zip file
    ///   - progressHandler: Progress callback, parameter is 0.0~1.0 progress value
    /// - Returns: Path to downloaded temporary file
    /// - Throws: Network error or file operation error
    func downloadUpdate(from url: String, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let downloadURL = URL(string: url) else {
            throw URLError(.badURL)
        }

        // DownloadDelegate is internal helper class implementing URLSessionDownloadDelegate protocol to track download progress
        // Defined inside actor to maintain encapsulation (similar to Java's inner class)
        let delegate = DownloadDelegate(progressHandler: progressHandler)

        // URLSession(configuration:delegate:delegateQueue:) creates session with delegate
        // .default uses default configuration (similar to OkHttp's default Builder)
        // delegateQueue: nil lets system choose queue automatically
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // download(from:) starts download task, returns temporary file path and response when complete
        let (tempURL, _) = try await session.download(from: downloadURL)

        // Downloaded file is in system temp directory, but URLSession may auto-clean it,
        // so we need to move it to our own temp directory
        let fm = FileManager.default
        // NSTemporaryDirectory() returns system temp directory path (e.g. /tmp/ or ~/Library/Caches/TemporaryItems/)
        let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillDeckUpdate")

        // Create destination directory (withIntermediateDirectories: true similar to mkdir -p)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent("SkillDeck.zip")
        // Remove any leftover from previous download
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        // moveItem atomically moves file (similar to mv command)
        try fm.moveItem(at: tempURL, to: destURL)

        return destURL
    }

    // MARK: - Install Update

    /// Execute update installation: extract zip → replace .app bundle → restart app
    ///
    /// Core principle: Running macOS apps cannot directly replace their own binary files (files are locked),
    /// so replacement must be done by external process (shell script) after app exits.
    /// This is the standard approach for macOS self-updates (Sparkle framework uses similar approach).
    ///
    /// Flow:
    /// 1. Use ditto to extract zip (macOS built-in tool, handles macOS resource forks better than unzip)
    /// 2. Get current app's Bundle.main.bundlePath
    /// 3. Write a shell script: wait for current process to exit → delete old .app → move new .app → launch new app
    /// 4. Launch script using Process (similar to Java's ProcessBuilder)
    /// 5. Call NSApplication.shared.terminate() to exit current app
    ///
    /// - Parameter zipPath: Path to downloaded zip file
    /// - Throws: Extraction failed or script creation failed
    func installUpdate(zipPath: URL) async throws {
        let fm = FileManager.default

        // 1. Create extraction target directory
        let extractDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillDeckExtract")
        // Clean up old extraction directory if exists
        if fm.fileExists(atPath: extractDir.path) {
            try fm.removeItem(at: extractDir)
        }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // 2. Use ditto to extract zip
        // ditto is macOS-specific file copy tool, better than unzip at handling:
        // - macOS resource forks
        // - File permissions and ACLs
        // - Symbolic links
        // Process similar to Java's ProcessBuilder or Go's exec.Command
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // -xk flags: x=extract, k=from zip format
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]

        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        // Check ditto exit status (0 means success)
        guard unzipProcess.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateChecker",
                code: Int(unzipProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract update archive"]
            )
        }

        // 3. Find extracted .app bundle
        // enumerator recursively traverses directory contents (similar to Python's os.walk or Java's Files.walk)
        let contents = try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        // first(where:) finds first element matching condition (similar to Java Stream's findFirst)
        // pathExtension gets file extension (e.g. "SkillDeck.app" → "app")
        guard let newAppBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            // If .app not at top level, search subdirectories
            var foundApp: URL?
            if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
                // enumerator is NSDirectoryEnumerator implementing IteratorProtocol
                // Use while let to extract elements one by one (similar to Java's Iterator.hasNext/next loop)
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" {
                        foundApp = fileURL
                        break
                    }
                }
            }
            guard let appURL = foundApp else {
                throw NSError(
                    domain: "UpdateChecker",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in the update archive"]
                )
            }
            // Found nested .app, continue using it
            try await executeUpdate(newAppPath: appURL, extractDir: extractDir)
            return
        }

        try await executeUpdate(newAppPath: newAppBundle, extractDir: extractDir)
    }

    /// Execute actual replacement and restart operation
    ///
    /// Extracted replacement logic into separate method to avoid code duplication in installUpdate
    ///
    /// - Parameters:
    ///   - newAppPath: Path to extracted new .app bundle
    ///   - extractDir: Extraction temp directory (for cleanup)
    private func executeUpdate(newAppPath: URL, extractDir: URL) async throws {
        // 4. Get current app path
        // Bundle.main.bundlePath returns full path of currently running .app
        // e.g. "/Applications/SkillDeck.app"
        // Note: When launched via swift run, bundlePath points to executable directory, not .app
        let currentAppPath = Bundle.main.bundlePath

        // Get current process PID (Process IDentifier)
        // ProcessInfo.processInfo is process info singleton (similar to Java's Runtime)
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // 5. Generate shell update script
        // Script logic:
        // - Loop waiting for current PID to exit (kill -0 checks if process exists, check every 0.5s, max 30s)
        // - Delete old .app bundle
        // - Move new .app bundle to original location
        // - Launch new app
        // - Clean up temp files
        //
        // Uses Swift's multi-line string literal (triple quotes """), similar to Python's triple quotes or Java's text block
        let script = """
        #!/bin/bash
        # Wait for current process to exit (max 30 seconds)
        # kill -0 only checks if process exists, doesn't send any signal
        TIMEOUT=60
        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 0.5
            TIMEOUT=$((TIMEOUT - 1))
            if [ $TIMEOUT -le 0 ]; then
                exit 1
            fi
        done

        # Replace .app bundle
        rm -rf "\(currentAppPath)"
        mv "\(newAppPath.path)" "\(currentAppPath)"

        # Restart app
        # open command is macOS general launch tool, correctly handles .app bundle
        open "\(currentAppPath)"

        # Clean up temp files
        rm -rf "\(extractDir.path)"
        rm -rf "\(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SkillDeckUpdate").path)"
        """

        // Write script to temp file
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skilldeck_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Set script executable permissions (chmod +x)
        // 0o755 is octal file permission (similar to Unix rwxr-xr-x)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        // 6. Launch shell script (run in background)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // Redirect stdout and stderr to /dev/null (discard output)
        // FileHandle.nullDevice similar to /dev/null
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // 7. Exit current app
        // Must call NSApplication.terminate on main thread (UI operations must be on main thread)
        // @MainActor closure ensures execution on main thread (similar to DispatchQueue.main.async)
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - URLSession Download Delegate

/// DownloadDelegate is responsible for tracking download progress
///
/// URLSessionDownloadDelegate is Apple's download task delegate protocol (similar to Java's callback interface).
/// Inherits from NSObject because Objective-C runtime requires delegate objects to inherit from NSObject.
/// @Sendable marker indicates this class can be safely passed in concurrent contexts (similar to Java's ThreadSafe annotation).
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// Progress callback closure, receives progress value from 0.0~1.0
    let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @Sendable @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    /// Called when download completes (required protocol method)
    /// No additional handling needed here because URLSession.download(from:) async version returns results directly
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Download complete, async/await version handles automatically
    }

    /// Called when download progress updates
    ///
    /// - Parameters:
    ///   - bytesWritten: Bytes written in this operation
    ///   - totalBytesWritten: Total bytes downloaded so far
    ///   - totalBytesExpectedToWrite: Total file size (if server provides Content-Length)
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // totalBytesExpectedToWrite > 0 ensures server returned file size information
        // NSURLSessionTransferSizeUnknown (-1) indicates unknown size
        guard totalBytesExpectedToWrite > 0 else { return }

        // Double() converts Int64 to Double for floating point division
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
}

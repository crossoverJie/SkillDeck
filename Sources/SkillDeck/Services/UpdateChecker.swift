import Foundation
import AppKit

/// AppUpdateInfo 表示 GitHub Release 的信息
///
/// Codable 协议使该结构体可以与 JSON 互转（类似 Java 的 Jackson @JsonProperty 或 Go 的 json tag）。
/// CodingKeys 枚举将 Swift 的 camelCase 属性名映射到 GitHub API 返回的 snake_case JSON 键。
struct AppUpdateInfo: Codable, Sendable {
    /// GitHub Release 的 tag 名称（如 "v1.2.0"）
    let tagName: String
    /// Release 页面的 URL（用于在浏览器中打开）
    let htmlUrl: String
    /// Release 的标题（如 "SkillDeck v1.2.0"）
    let name: String?
    /// Release 的描述（Markdown 格式的 changelog）
    let body: String?
    /// Release 的发布时间（ISO 8601 格式）
    let publishedAt: String?
    /// Release 附带的资产文件列表（zip、dmg 等）
    /// GitHub API 返回的 assets 是一个数组，每个元素包含文件名和下载 URL
    let assets: [Asset]?

    /// Release 资产文件信息
    struct Asset: Codable, Sendable {
        /// 文件名（如 "SkillDeck-v1.0.0-universal.zip"）
        let name: String
        /// 浏览器下载 URL（直接下载链接，不需要 API 认证）
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    /// CodingKeys 枚举将 Swift 属性名映射到 JSON 键
    /// Swift 约定使用 camelCase，但 GitHub API 返回 snake_case，
    /// 通过 CodingKeys 做映射（类似 Go struct tag 的 `json:"tag_name"`）
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }

    /// 去掉 "v" 前缀的版本号
    /// 计算属性（computed property）每次访问时执行计算，类似 Java 的 getter
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// 获取 zip 文件的下载 URL
    ///
    /// 优先从 assets 中查找 .zip 文件的真实下载 URL（最可靠），
    /// 如果 assets 为空则按命名约定拼接 URL 作为 fallback。
    /// 从 assets 取 URL 的好处：无论 zip 文件名怎么改（如从 SkillDeck.zip 改为
    /// SkillDeck-v1.0.0-universal.zip），都能正确下载。
    var downloadURL: String {
        // first(where:) 查找第一个 .zip 结尾的 asset（类似 Java Stream 的 findFirst + filter）
        // hasSuffix 检查字符串后缀（类似 Java 的 endsWith）
        if let zipAsset = assets?.first(where: { $0.name.hasSuffix(".zip") }) {
            return zipAsset.browserDownloadUrl
        }
        // Fallback：按 Release 工作流的命名约定拼接
        // 格式：/releases/download/v1.0.0/SkillDeck-v1.0.0-universal.zip
        return "https://github.com/crossoverJie/SkillDeck/releases/download/\(tagName)/SkillDeck-\(tagName)-universal.zip"
    }
}

/// UpdateChecker 负责检查和执行应用更新
///
/// actor 是 Swift 的并发安全类型（类似 Go 中带 mutex 保护的 struct，或 Erlang 的 Actor 模型）。
/// actor 内部的可变状态自动受并发保护，外部访问属性/方法必须使用 await。
/// 这里使用 actor 因为网络请求和文件操作是异步的，需要线程安全。
actor UpdateChecker {

    /// GitHub API 地址：获取最新 Release
    /// 固定指向 SkillDeck 仓库的 releases/latest 端点
    private let apiURL = "https://api.github.com/repos/crossoverJie/SkillDeck/releases/latest"

    /// UserDefaults 中存储上次检查时间的 key
    /// UserDefaults 是 macOS/iOS 的轻量级键值存储（类似 Android 的 SharedPreferences）
    private static let lastCheckKey = "lastAppUpdateCheckTime"

    // MARK: - 获取最新 Release

    /// 从 GitHub API 获取最新 Release 信息
    ///
    /// - Returns: Release 信息
    /// - Throws: 网络错误或 JSON 解析错误（调用方决定如何处理）
    ///
    /// 改为 throws 而非静默返回 nil，让调用方（SkillManager）可以区分
    /// "自动检查时静默忽略" 和 "用户手动触发时显示具体错误" 两种场景
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        // guard let 是 Swift 的空值检查语法（类似 Go 的 if err != nil { return }）
        // 如果 URL 构造失败（格式无效），抛出 badURL 错误
        guard let url = URL(string: apiURL) else {
            throw URLError(.badURL)
        }

        // URLRequest 封装 HTTP 请求（类似 Java 的 HttpURLConnection 或 Go 的 http.Request）
        var request = URLRequest(url: url)
        // 设置 10 秒超时，避免网络问题导致 UI 长时间等待
        request.timeoutInterval = 10
        // GitHub API 要求 Accept header 指定 JSON 格式
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        // URLSession.shared 是全局共享的网络会话（类似 Java 的 HttpClient 或 Python 的 requests.Session）
        // data(for:) 发送请求并返回 (Data, URLResponse) 元组
        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查 HTTP 状态码（URLResponse 需要向下转型为 HTTPURLResponse 才能访问 statusCode）
        // as? 是 Swift 的条件类型转换（类似 Java 的 instanceof + 强制转换）
        // GitHub API 在 rate limit、404 等情况下会返回非 200 状态码，
        // 但 URLSession 不会将 HTTP 错误状态码视为 error（只有网络层错误才 throw）
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // 尝试从响应 body 中提取 GitHub API 的错误消息（JSON 格式 {"message": "..."}）
            // 比如 rate limit 时返回 "API rate limit exceeded for ..."
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

        // JSONDecoder 将 JSON Data 解码为 Swift struct（类似 Java 的 ObjectMapper 或 Go 的 json.Unmarshal）
        let decoder = JSONDecoder()
        return try decoder.decode(AppUpdateInfo.self, from: data)
    }

    // MARK: - 检查间隔控制

    /// 判断是否应该自动检查更新（4 小时间隔）
    ///
    /// nonisolated 标记表示该方法不需要 actor 的隔离保护，
    /// 可以在任何线程直接调用（不需要 await）。
    /// 因为 UserDefaults 本身是线程安全的，不需要 actor 的额外保护。
    nonisolated func shouldAutoCheck() -> Bool {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: UpdateChecker.lastCheckKey)

        // 如果从未检查过（lastCheck == 0），应该检查
        guard lastCheck > 0 else { return true }

        // Date().timeIntervalSince1970 返回当前时间的 Unix 时间戳（秒），类似 Java 的 System.currentTimeMillis()/1000
        let now = Date().timeIntervalSince1970
        let fourHours: TimeInterval = 4 * 60 * 60  // 4 小时 = 14400 秒

        // 距离上次检查超过 4 小时才允许自动检查
        // GitHub 未认证 API 限制 60 次/小时，4 小时间隔每天最多 6 次，远低于限制
        return (now - lastCheck) >= fourHours
    }

    /// 记录当前检查时间到 UserDefaults
    ///
    /// nonisolated 理由同 shouldAutoCheck()
    nonisolated func recordCheckTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UpdateChecker.lastCheckKey)
    }

    // MARK: - 下载更新

    /// 下载更新 zip 文件到临时目录
    ///
    /// 使用 URLSessionDownloadDelegate 报告下载进度，通过回调函数传递给调用方。
    ///
    /// - Parameters:
    ///   - url: zip 文件的下载 URL
    ///   - progressHandler: 进度回调，参数为 0.0~1.0 的进度值
    /// - Returns: 下载完成的临时文件路径
    /// - Throws: 网络错误或文件操作错误
    func downloadUpdate(from url: String, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let downloadURL = URL(string: url) else {
            throw URLError(.badURL)
        }

        // DownloadDelegate 是内部辅助类，实现 URLSessionDownloadDelegate 协议来跟踪下载进度
        // 在 actor 内部定义辅助类保持封装性（类似 Java 的内部类）
        let delegate = DownloadDelegate(progressHandler: progressHandler)

        // URLSession(configuration:delegate:delegateQueue:) 创建带代理的会话
        // .default 使用默认配置（类似 OkHttp 的默认 Builder）
        // delegateQueue: nil 让系统自动选择队列
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // download(from:) 启动下载任务，完成后返回临时文件路径和响应
        let (tempURL, _) = try await session.download(from: downloadURL)

        // 下载完成后的文件在系统临时目录中，但 URLSession 可能会自动清理，
        // 所以需要移动到我们自己的临时目录中
        let fm = FileManager.default
        // NSTemporaryDirectory() 返回系统临时目录路径（如 /tmp/ 或 ~/Library/Caches/TemporaryItems/）
        let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillDeckUpdate")

        // 创建目标目录（withIntermediateDirectories: true 类似 mkdir -p）
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent("SkillDeck.zip")
        // 如果之前的下载残留还在，先删除
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        // moveItem 原子地移动文件（类似 mv 命令）
        try fm.moveItem(at: tempURL, to: destURL)

        return destURL
    }

    // MARK: - 安装更新

    /// 执行更新安装：解压 zip → 替换 .app bundle → 重启应用
    ///
    /// 核心原理：运行中的 macOS 应用无法直接替换自身的二进制文件（文件被锁定），
    /// 因此必须通过外部进程（shell 脚本）在应用退出后执行替换操作。
    /// 这是 macOS 自更新的标准做法（Sparkle 框架也使用类似方案）。
    ///
    /// 流程：
    /// 1. 使用 ditto 解压 zip（macOS 内置工具，比 unzip 更好地处理 macOS 资源分支）
    /// 2. 获取当前 app 的 Bundle.main.bundlePath
    /// 3. 写一个 shell 脚本：等待当前进程退出 → 删除旧 .app → 移动新 .app → 启动新 .app
    /// 4. 用 Process（类似 Java 的 ProcessBuilder）启动该脚本
    /// 5. 调用 NSApplication.shared.terminate() 退出当前应用
    ///
    /// - Parameter zipPath: 已下载的 zip 文件路径
    /// - Throws: 解压失败或脚本创建失败
    func installUpdate(zipPath: URL) async throws {
        let fm = FileManager.default

        // 1. 创建解压目标目录
        let extractDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillDeckExtract")
        // 清理旧的解压目录（如果存在）
        if fm.fileExists(atPath: extractDir.path) {
            try fm.removeItem(at: extractDir)
        }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // 2. 使用 ditto 解压 zip
        // ditto 是 macOS 专用的文件拷贝工具，比 unzip 更好地处理：
        // - macOS 资源分支（resource fork）
        // - 文件权限和 ACL
        // - 符号链接
        // Process 类似 Java 的 ProcessBuilder 或 Go 的 exec.Command
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // -xk 参数：x=解压, k=从 zip 格式
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]

        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        // 检查 ditto 退出状态（0 表示成功）
        guard unzipProcess.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateChecker",
                code: Int(unzipProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract update archive"]
            )
        }

        // 3. 查找解压出的 .app bundle
        // enumerator 递归遍历目录内容（类似 Python 的 os.walk 或 Java 的 Files.walk）
        let contents = try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        // first(where:) 查找第一个满足条件的元素（类似 Java Stream 的 findFirst）
        // pathExtension 获取文件扩展名（如 "SkillDeck.app" → "app"）
        guard let newAppBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            // 如果 .app 不在顶层，搜索子目录
            var foundApp: URL?
            if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
                // enumerator 是 NSDirectoryEnumerator，实现了 IteratorProtocol
                // 使用 while let 逐个取出元素（类似 Java 的 Iterator.hasNext/next 循环）
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
            // 找到了嵌套的 .app，继续使用它
            try await executeUpdate(newAppPath: appURL, extractDir: extractDir)
            return
        }

        try await executeUpdate(newAppPath: newAppBundle, extractDir: extractDir)
    }

    /// 执行实际的替换和重启操作
    ///
    /// 将替换逻辑抽取为独立方法，避免 installUpdate 中的代码重复
    ///
    /// - Parameters:
    ///   - newAppPath: 解压出的新 .app bundle 路径
    ///   - extractDir: 解压临时目录（用于清理）
    private func executeUpdate(newAppPath: URL, extractDir: URL) async throws {
        // 4. 获取当前应用的路径
        // Bundle.main.bundlePath 返回当前运行的 .app 的完整路径
        // 例如 "/Applications/SkillDeck.app"
        // 注意：通过 swift run 启动时，bundlePath 指向可执行文件所在目录，不是 .app
        let currentAppPath = Bundle.main.bundlePath

        // 获取当前进程的 PID（Process IDentifier）
        // ProcessInfo.processInfo 是进程信息的单例（类似 Java 的 Runtime）
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // 5. 生成 shell 更新脚本
        // 脚本逻辑：
        // - 循环等待当前 PID 退出（kill -0 检测进程是否存在，每 0.5 秒检查一次，最多 30 秒）
        // - 删除旧的 .app bundle
        // - 移动新的 .app bundle 到原位置
        // - 启动新的应用
        // - 清理临时文件
        //
        // 使用 Swift 的多行字符串字面量（三引号 """），类似 Python 的三引号或 Java 的 text block
        let script = """
        #!/bin/bash
        # 等待当前进程退出（最多 30 秒）
        # kill -0 只检查进程是否存在，不发送任何信号
        TIMEOUT=60
        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 0.5
            TIMEOUT=$((TIMEOUT - 1))
            if [ $TIMEOUT -le 0 ]; then
                exit 1
            fi
        done

        # 替换 .app bundle
        rm -rf "\(currentAppPath)"
        mv "\(newAppPath.path)" "\(currentAppPath)"

        # 重新启动应用
        # open 命令是 macOS 的通用启动工具，会正确处理 .app bundle
        open "\(currentAppPath)"

        # 清理临时文件
        rm -rf "\(extractDir.path)"
        rm -rf "\(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SkillDeckUpdate").path)"
        """

        // 将脚本写入临时文件
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skilldeck_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // 设置脚本的可执行权限（chmod +x）
        // 0o755 是八进制文件权限（类似 Unix 的 rwxr-xr-x）
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        // 6. 启动 shell 脚本（后台运行）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // 标准输出和标准错误重定向到 /dev/null（丢弃输出）
        // FileHandle.nullDevice 类似 /dev/null
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // 7. 退出当前应用
        // 必须在主线程上调用 NSApplication.terminate（UI 操作必须在主线程）
        // @MainActor 闭包确保在主线程上执行（类似 DispatchQueue.main.async）
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - URLSession Download Delegate

/// DownloadDelegate 负责跟踪下载进度
///
/// URLSessionDownloadDelegate 是 Apple 的下载任务代理协议（类似 Java 的回调接口）。
/// 继承 NSObject 是因为 Objective-C 运行时要求代理对象继承自 NSObject。
/// @Sendable 标记表示这个类可以安全地在并发上下文中传递（类似 Java 的 ThreadSafe 注解）。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// 进度回调闭包，接收 0.0~1.0 的进度值
    let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @Sendable @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    /// 下载完成时调用（协议必须实现的方法）
    /// 这里不需要额外处理，因为 URLSession.download(from:) 的 async 版本会直接返回结果
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 下载完成，async/await 版本会自动处理
    }

    /// 下载进度更新时调用
    ///
    /// - Parameters:
    ///   - bytesWritten: 本次写入的字节数
    ///   - totalBytesWritten: 已下载的总字节数
    ///   - totalBytesExpectedToWrite: 文件总大小（如果服务器提供了 Content-Length）
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // totalBytesExpectedToWrite > 0 确保服务器返回了文件大小信息
        // NSURLSessionTransferSizeUnknown（-1）表示未知大小
        guard totalBytesExpectedToWrite > 0 else { return }

        // Double() 将 Int64 转为 Double 进行浮点除法
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
}

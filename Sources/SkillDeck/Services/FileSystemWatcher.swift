import Foundation
import Combine

/// FileSystemWatcher 使用 macOS 的 DispatchSource 监控文件系统变化（F08）
///
/// 当外部工具（如 `npx skills add`）修改了 skills 目录时，
/// 这个 watcher 会通知应用刷新数据。
///
/// 技术选型说明：
/// - macOS 提供了 FSEvents API（C API）和 DispatchSource.FileSystemObject（Swift 友好的封装）
/// - 我们使用 DispatchSource 因为它更现代，且与 GCD（Grand Central Dispatch）集成更好
/// - GCD 是 Apple 的并发框架，类似 Go 的 goroutine 调度器
///
/// Combine 框架提供响应式编程支持（类似 RxJava / Go 的 channel）
/// @Observable 类让 SwiftUI 能自动响应数据变化
@Observable
final class FileSystemWatcher {

    /// 当文件系统变化时发送通知
    /// PassthroughSubject 类似 Go 的无缓冲 channel，事件发出后如果没有订阅者就丢弃
    let onChange = PassthroughSubject<Void, Never>()

    /// 当前是否正在监控
    private(set) var isWatching = false

    /// 监控的目录列表
    private var watchedPaths: [URL] = []

    /// DispatchSource 监控器数组（需要保持强引用，否则会被释放）
    /// DispatchSource 是 GCD 中的事件源，可以监控文件描述符、定时器等
    private var sources: [any DispatchSourceFileSystemObject] = []

    /// 文件描述符数组（需要在停止监控时关闭）
    private var fileDescriptors: [Int32] = []

    /// 防抖定时器：文件系统变化可能在短时间内触发多次，
    /// 我们用防抖（debounce）来合并，避免频繁刷新
    /// 类似前端 JavaScript 的 debounce 函数
    private var debounceTimer: DispatchWorkItem?

    /// 防抖延迟（秒）
    private let debounceInterval: TimeInterval = 0.5

    /// 开始监控指定的目录列表
    func startWatching(paths: [URL]) {
        stopWatching()  // 先停止之前的监控

        watchedPaths = paths
        isWatching = true

        for path in paths {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            watchDirectory(path)
        }
    }

    /// 停止所有监控
    func stopWatching() {
        // 取消所有 DispatchSource
        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        // 关闭所有文件描述符
        // 文件描述符（fd）是 Unix 系统中对打开文件的整数引用
        // 类似 Java 的 FileInputStream 或 Go 的 os.File，用完必须关闭
        for fd in fileDescriptors {
            close(fd)
        }
        fileDescriptors.removeAll()

        debounceTimer?.cancel()
        debounceTimer = nil
        isWatching = false
        watchedPaths = []
    }

    /// 监控单个目录
    private func watchDirectory(_ url: URL) {
        // open() 是 POSIX 系统调用，返回文件描述符
        // O_EVTONLY: 只用于事件通知，不用于读写（最小权限原则）
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        fileDescriptors.append(fd)

        // 创建 DispatchSource 监控文件系统事件
        // .write 表示目录内容变化（文件增删改）
        // .global() 表示在全局并发队列上触发回调
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .global()
        )

        // [weak self] 是 Swift 的弱引用捕获，防止循环引用（内存泄漏）
        // 类似 Java 的 WeakReference，当 self 被释放时自动变为 nil
        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        // 当 source 被取消时关闭文件描述符
        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
    }

    /// 处理文件系统变化事件（带防抖）
    private func handleChange() {
        debounceTimer?.cancel()

        let timer = DispatchWorkItem { [weak self] in
            // 在主线程上发送通知（UI 更新必须在主线程）
            // DispatchQueue.main 类似 Android 的 runOnUiThread 或 Go 的主 goroutine
            DispatchQueue.main.async {
                self?.onChange.send()
            }
        }

        debounceTimer = timer
        // asyncAfter: 延迟执行，实现防抖效果
        DispatchQueue.global().asyncAfter(deadline: .now() + debounceInterval, execute: timer)
    }

    /// 析构函数（类似 Java 的 finalize 或 Go 的 defer cleanup）
    /// 在对象被内存管理器回收时自动调用
    deinit {
        stopWatching()
    }
}

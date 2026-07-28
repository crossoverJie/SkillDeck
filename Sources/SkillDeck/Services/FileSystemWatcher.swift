import Foundation
import Combine

/// FileSystemWatcher monitors file system changes using macOS DispatchSource (F08)
///
/// When external tools (like `npx skills add`) modify the skills directory,
/// this watcher notifies the app to refresh data.
///
/// Technical Choice:
/// - macOS provides FSEvents API (C API) and DispatchSource.FileSystemObject (Swift-friendly wrapper)
/// - We use DispatchSource because it is more modern and integrates better with GCD (Grand Central Dispatch)
/// - GCD is Apple's concurrency framework, similar to Go's goroutine scheduler
///
/// Combine framework provides reactive programming support (similar to RxJava / Go's channel)
/// @Observable class allows SwiftUI to automatically respond to data changes
@Observable
final class FileSystemWatcher {

    /// Send notification when file system changes
    /// PassthroughSubject is similar to Go's unbuffered channel, events are dropped if no subscribers
    let onChange = PassthroughSubject<Void, Never>()

    /// Whether monitoring is currently active
    private(set) var isWatching = false

    /// List of monitored directories
    private var watchedPaths: [URL] = []

    /// Array of DispatchSource monitors (must keep strong reference, otherwise they will be released)
    /// DispatchSource is an event source in GCD, capable of monitoring file descriptors, timers, etc.
    private var sources: [any DispatchSourceFileSystemObject] = []

    /// Array of file descriptors (must be closed when stopping monitoring)
    private var fileDescriptors: [Int32] = []

    /// Debounce timer: File system changes may trigger multiple times in short period,
    /// we use debounce to merge them, avoiding frequent refreshes
    /// Similar to frontend JavaScript debounce function
    private var debounceTimer: DispatchWorkItem?

    /// Debounce delay (seconds)
    private let debounceInterval: TimeInterval = 0.5

    /// Start watching specified list of directories
    func startWatching(paths: [URL]) {
        stopWatching()  // Stop previous monitoring first

        watchedPaths = paths
        isWatching = true

        for path in paths {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            watchDirectory(path)
        }
    }

    /// Stop all monitoring
    func stopWatching() {
        // Cancel all DispatchSources
        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        // Each DispatchSource invokes its cancel handler, which closes its own file descriptor.
        // Clearing this bookkeeping array must not close descriptors a second time: Unix may have
        // already reused that numeric descriptor for an unrelated file by then.
        fileDescriptors.removeAll()

        debounceTimer?.cancel()
        debounceTimer = nil
        isWatching = false
        watchedPaths = []
    }

    /// Watch a single directory
    private func watchDirectory(_ url: URL) {
        // open() is a POSIX system call, returns file descriptor
        // O_EVTONLY: Only for event notification, not for read/write (principle of least privilege)
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        fileDescriptors.append(fd)

        // Create DispatchSource to monitor file system events
        // .write indicates directory content change (file add/delete/modify)
        // The main queue serializes observer state and debounceTimer mutations. DispatchSource can
        // coalesce filesystem events on this queue without blocking disk I/O because the handler
        // only schedules a lightweight delayed notification.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        // [weak self] is Swift's weak reference capture, preventing retain cycles (memory leaks)
        // Similar to Java's WeakReference, automatically becomes nil when self is released
        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        // Close file descriptor when source is cancelled
        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources.append(source)
    }

    /// Handle file system change event (with debounce)
    private func handleChange() {
        debounceTimer?.cancel()

        let timer = DispatchWorkItem { [weak self] in
            // The work item also runs on the main queue, so Combine subscribers that refresh
            // SwiftUI-bound state receive the notification on the same serialized executor.
            self?.onChange.send()
        }

        debounceTimer = timer
        // asyncAfter delays this lightweight callback without leaving the main-queue ownership
        // domain of the @Observable debounceTimer property.
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: timer)
    }

    /// Deinitializer (similar to Java's finalize or Go's defer cleanup)
    /// Automatically called when object is reclaimed by memory manager
    deinit {
        stopWatching()
    }
}

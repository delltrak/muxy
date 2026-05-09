import CoreServices
import Foundation

final class FileSystemWatcherToken {
    private let onCancel: () -> Void
    private var cancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }

    deinit {
        if !cancelled { onCancel() }
    }
}

final class SharedFileSystemWatcher: @unchecked Sendable {
    static let shared = SharedFileSystemWatcher()

    private struct Subscriber {
        let id: UUID
        let handler: @Sendable () -> Void
    }

    private final class Entry {
        let path: String
        var stream: FSEventStreamRef?
        var subscribers: [Subscriber] = []
        var debounceWork: DispatchWorkItem?

        init(path: String) {
            self.path = path
        }
    }

    private static let ignoredPathFragments: [String] = [
        "/node_modules/",
        "/.build/",
        "/DerivedData/",
        "/target/",
        "/.next/",
        "/dist/",
        "/.git/objects/",
        "/.git/lfs/",
    ]

    private static let debounceInterval: TimeInterval = 0.8
    private static let coalesceLatency: CFTimeInterval = 0.8

    private let queue = DispatchQueue(label: "app.muxy.shared-fs-watcher", qos: .utility)
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {}

    func subscribe(path: String, handler: @escaping @Sendable () -> Void) -> FileSystemWatcherToken? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let normalizedPath = Self.normalize(path)
        let id = UUID()

        let attached = lock.withLock { () -> Bool in
            let entry = entries[normalizedPath] ?? Entry(path: normalizedPath)
            entry.subscribers.append(Subscriber(id: id, handler: handler))
            entries[normalizedPath] = entry

            guard entry.stream == nil else { return true }
            return startStream(for: entry)
        }

        guard attached else {
            lock.withLock {
                if let entry = entries[normalizedPath] {
                    entry.subscribers.removeAll { $0.id == id }
                    if entry.subscribers.isEmpty {
                        entries.removeValue(forKey: normalizedPath)
                    }
                }
            }
            return nil
        }

        return FileSystemWatcherToken { [weak self] in
            self?.unsubscribe(id: id, path: normalizedPath)
        }
    }

    private func unsubscribe(id: UUID, path: String) {
        lock.withLock {
            guard let entry = entries[path] else { return }
            entry.subscribers.removeAll { $0.id == id }
            guard entry.subscribers.isEmpty else { return }
            stopStream(for: entry)
            entries.removeValue(forKey: path)
        }
    }

    private func startStream(for entry: Entry) -> Bool {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [entry.path] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<SharedFileSystemWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
                else { return }
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
                watcher.handleEvents(paths: paths, flags: flags)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.coalesceLatency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return false }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }

        entry.stream = stream
        return true
    }

    private func stopStream(for entry: Entry) {
        entry.debounceWork?.cancel()
        entry.debounceWork = nil
        guard let stream = entry.stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        entry.stream = nil
    }

    private func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        let allFiltered = zip(paths, flags).allSatisfy { path, flag in
            if Self.shouldIgnore(path: path) { return true }
            let isGitInternal = path.contains("/.git/")
            let isLockFile = path.hasSuffix(".lock")
            if isGitInternal, isLockFile { return true }
            if isGitInternal, flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { return true }
            return false
        }
        guard !allFiltered else { return }

        let triggered = matchingEntries(for: paths)
        for entry in triggered {
            scheduleNotify(entry: entry)
        }
    }

    private func matchingEntries(for paths: [String]) -> [Entry] {
        lock.withLock {
            entries.values.filter { entry in
                paths.contains { Self.event(path: $0, belongsTo: entry.path) }
            }
        }
    }

    private func scheduleNotify(entry: Entry) {
        let work = DispatchWorkItem { [weak self, weak entry] in
            guard let self, let entry else { return }
            let subscribers = lock.withLock { entry.subscribers }
            for subscriber in subscribers {
                subscriber.handler()
            }
        }
        lock.withLock {
            entry.debounceWork?.cancel()
            entry.debounceWork = work
        }
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private static func shouldIgnore(path: String) -> Bool {
        for fragment in ignoredPathFragments where path.contains(fragment) {
            return true
        }
        return false
    }

    private static func event(path eventPath: String, belongsTo watchedPath: String) -> Bool {
        if eventPath == watchedPath { return true }
        let prefix = watchedPath.hasSuffix("/") ? watchedPath : watchedPath + "/"
        return eventPath.hasPrefix(prefix)
    }

    private static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

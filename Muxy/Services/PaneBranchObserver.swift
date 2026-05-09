import AppKit
import Foundation

@MainActor
@Observable
final class PaneBranchObserver {
    typealias BranchResolver = @Sendable (String) async -> String?

    private(set) var branch: String?

    @ObservationIgnored private var repoPath: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var subscriptionToken: PaneBranchObserverCoordinator.Token?
    @ObservationIgnored private let resolver: BranchResolver
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private let coordinator: PaneBranchObserverCoordinator

    init(
        refreshInterval: TimeInterval = 15,
        coordinator: PaneBranchObserverCoordinator = .shared,
        resolver: @escaping BranchResolver = PaneBranchObserver.defaultResolver
    ) {
        self.refreshInterval = refreshInterval
        self.coordinator = coordinator
        self.resolver = resolver
    }

    deinit {
        subscriptionToken?.cancel()
        refreshTask?.cancel()
    }

    func update(repoPath path: String?) {
        guard repoPath != path else { return }
        repoPath = path
        guard path != nil else {
            branch = nil
            return
        }
        refresh()
    }

    func start() {
        attachIfNeeded()
    }

    func stop() {
        subscriptionToken?.cancel()
        subscriptionToken = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        guard let path = repoPath else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self, resolver] in
            let resolved = await resolver(path)
            guard !Task.isCancelled, let self else { return }
            if branch != resolved { branch = resolved }
        }
    }

    private func attachIfNeeded() {
        guard subscriptionToken == nil, let path = repoPath else { return }
        subscriptionToken = coordinator.subscribe(
            path: path,
            interval: refreshInterval,
            resolver: resolver
        ) { [weak self] resolved in
            guard let self else { return }
            if branch != resolved { branch = resolved }
        }
    }

    static let defaultResolver: BranchResolver = { path in
        let service = GitRepositoryService()
        guard let result = try? await service.currentBranch(repoPath: path) else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "HEAD" else { return nil }
        return trimmed
    }
}

@MainActor
final class PaneBranchObserverCoordinator {
    static let shared = PaneBranchObserverCoordinator()

    final class Token: @unchecked Sendable {
        private let lock = NSLock()
        private let onCancel: @Sendable () -> Void
        private var cancelled = false

        init(onCancel: @escaping @Sendable () -> Void) {
            self.onCancel = onCancel
        }

        func cancel() {
            lock.lock()
            if cancelled {
                lock.unlock()
                return
            }
            cancelled = true
            lock.unlock()
            onCancel()
        }

        deinit { cancel() }
    }

    private struct Subscriber {
        let id: UUID
        let onUpdate: (String?) -> Void
    }

    private final class Entry {
        let path: String
        let interval: TimeInterval
        let resolver: PaneBranchObserver.BranchResolver
        var subscribers: [Subscriber] = []
        var pollingTask: Task<Void, Never>?
        var lastValue: String?
        var hasResolved = false

        init(
            path: String,
            interval: TimeInterval,
            resolver: @escaping PaneBranchObserver.BranchResolver
        ) {
            self.path = path
            self.interval = interval
            self.resolver = resolver
        }
    }

    private var entries: [String: Entry] = [:]
    private var lifecycleObserversInstalled = false

    private init() {}

    func subscribe(
        path: String,
        interval: TimeInterval,
        resolver: @escaping PaneBranchObserver.BranchResolver,
        onUpdate: @escaping (String?) -> Void
    ) -> Token {
        installLifecycleObserversIfNeeded()
        let entry = entries[path] ?? Entry(path: path, interval: interval, resolver: resolver)
        let id = UUID()
        entry.subscribers.append(Subscriber(id: id, onUpdate: onUpdate))
        entries[path] = entry
        if entry.hasResolved { onUpdate(entry.lastValue) }
        startPollingIfNeeded(for: entry)
        return Token { [weak self] in
            Task { @MainActor [weak self] in
                self?.unsubscribe(id: id, path: path)
            }
        }
    }

    private func unsubscribe(id: UUID, path: String) {
        guard let entry = entries[path] else { return }
        entry.subscribers.removeAll { $0.id == id }
        guard entry.subscribers.isEmpty else { return }
        entry.pollingTask?.cancel()
        entries.removeValue(forKey: path)
    }

    private func startPollingIfNeeded(for entry: Entry) {
        guard entry.pollingTask == nil else { return }
        guard shouldPoll() else { return }
        entry.pollingTask = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else { return }
            await poll(entry: entry)
        }
    }

    private func poll(entry: Entry) async {
        let resolver = entry.resolver
        let path = entry.path
        let interval = entry.interval
        while !Task.isCancelled {
            let resolved = await resolver(path)
            guard !Task.isCancelled else { return }
            entry.lastValue = resolved
            entry.hasResolved = true
            for subscriber in entry.subscribers {
                subscriber.onUpdate(resolved)
            }
            try? await Task.sleep(for: .seconds(interval))
            if !shouldPoll() {
                entry.pollingTask = nil
                return
            }
        }
    }

    private func installLifecycleObserversIfNeeded() {
        guard !lifecycleObserversInstalled else { return }
        lifecycleObserversInstalled = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resumePolling()
            }
        }
        center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pausePolling()
            }
        }
    }

    private func resumePolling() {
        for entry in entries.values {
            startPollingIfNeeded(for: entry)
        }
    }

    private func pausePolling() {
        for entry in entries.values {
            entry.pollingTask?.cancel()
            entry.pollingTask = nil
        }
    }

    private func shouldPoll() -> Bool {
        NSApplication.shared.isActive
    }
}

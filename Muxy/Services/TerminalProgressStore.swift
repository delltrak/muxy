import AppKit
import Foundation

@MainActor
@Observable
final class TerminalProgressStore {
    static let shared = TerminalProgressStore()

    var appState: AppState?

    private(set) var progresses: [UUID: TerminalProgress] = [:]
    private(set) var completionPending: Set<UUID> = []
    private var paneToProject: [UUID: UUID] = [:]
    private var pendingProgress: [UUID: PendingProgress] = [:]
    private var coalesceWorkItems: [UUID: DispatchWorkItem] = [:]
    nonisolated(unsafe) private var didBecomeActiveObserver: NSObjectProtocol?

    private static let coalesceInterval: DispatchTimeInterval = .milliseconds(33)

    private struct PendingProgress {
        let progress: TerminalProgress?
        let projectID: UUID?
    }

    init() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearActivePaneCompletion()
            }
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    private func clearActivePaneCompletion() {
        guard let appState, let paneID = NotificationNavigator.activePaneID(appState: appState) else { return }
        clearCompletion(for: paneID)
    }

    func setProgress(_ progress: TerminalProgress?, for paneID: UUID, projectID: UUID?) {
        pendingProgress[paneID] = PendingProgress(progress: progress, projectID: projectID)
        if coalesceWorkItems[paneID] != nil { return }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.flushPendingProgress(for: paneID)
            }
        }
        coalesceWorkItems[paneID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval, execute: workItem)
    }

    private func flushPendingProgress(for paneID: UUID) {
        coalesceWorkItems.removeValue(forKey: paneID)
        guard let pending = pendingProgress.removeValue(forKey: paneID) else { return }
        applyProgress(pending.progress, for: paneID, projectID: pending.projectID)
    }

    private func applyProgress(_ progress: TerminalProgress?, for paneID: UUID, projectID: UUID?) {
        if let projectID {
            paneToProject[paneID] = projectID
        }

        if let progress {
            guard progresses[paneID] != progress else { return }
            progresses[paneID] = progress
            return
        }

        guard progresses.removeValue(forKey: paneID) != nil else { return }
        guard !completionPending.contains(paneID) else { return }
        completionPending.insert(paneID)
    }

    func clearCompletion(for paneID: UUID) {
        guard completionPending.contains(paneID) else { return }
        completionPending.remove(paneID)
    }

    func resetPane(_ paneID: UUID) {
        coalesceWorkItems.removeValue(forKey: paneID)?.cancel()
        pendingProgress.removeValue(forKey: paneID)
        progresses.removeValue(forKey: paneID)
        completionPending.remove(paneID)
        paneToProject.removeValue(forKey: paneID)
    }

    func progress(for paneID: UUID) -> TerminalProgress? {
        progresses[paneID]
    }

    func isCompletionPending(for paneID: UUID) -> Bool {
        completionPending.contains(paneID)
    }

    func hasCompletionPending(for projectID: UUID) -> Bool {
        completionPending.contains { paneToProject[$0] == projectID }
    }
}

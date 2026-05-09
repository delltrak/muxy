import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("TerminalProgressStore")
struct TerminalProgressStoreTests {
    @Test("setProgress stores active progress")
    func storesProgress() {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(.clamping(kind: .set, percent: 42), for: pane, projectID: project)

        #expect(store.progress(for: pane) == TerminalProgress(kind: .set, percent: 42))
        #expect(!store.isCompletionPending(for: pane))
    }

    @Test("clamps percent into 0...100")
    func clampsPercent() {
        let low = TerminalProgress.clamping(kind: .set, percent: -5)
        let high = TerminalProgress.clamping(kind: .set, percent: 250)
        let nilValue = TerminalProgress.clamping(kind: .set, percent: nil)

        #expect(low.percent == 0)
        #expect(high.percent == 100)
        #expect(nilValue.percent == nil)
    }

    @Test("transition from active to nil marks completion-pending")
    func marksCompletion() async {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(.clamping(kind: .set, percent: 80), for: pane, projectID: project)
        store.setProgress(nil, for: pane, projectID: project)
        await waitForCoalesceFlush()

        #expect(store.progress(for: pane) == nil)
        #expect(store.isCompletionPending(for: pane))
        #expect(store.hasCompletionPending(for: project))
    }

    @Test("nil progress without prior active does not mark completion")
    func noFalseCompletion() {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(nil, for: pane, projectID: project)

        #expect(!store.isCompletionPending(for: pane))
        #expect(!store.hasCompletionPending(for: project))
    }

    @Test("clearCompletion removes pending state")
    func clearsCompletion() async {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(.clamping(kind: .indeterminate, percent: nil), for: pane, projectID: project)
        store.setProgress(nil, for: pane, projectID: project)
        await waitForCoalesceFlush()

        store.clearCompletion(for: pane)

        #expect(!store.isCompletionPending(for: pane))
        #expect(!store.hasCompletionPending(for: project))
    }

    @Test("resetPane clears all per-pane state")
    func resetsPane() async {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(.clamping(kind: .set, percent: 30), for: pane, projectID: project)
        store.setProgress(nil, for: pane, projectID: project)
        await waitForCoalesceFlush()

        store.resetPane(pane)

        #expect(store.progress(for: pane) == nil)
        #expect(!store.isCompletionPending(for: pane))
        #expect(!store.hasCompletionPending(for: project))
    }

    @Test("hasCompletionPending scopes by project")
    func scopesByProject() async {
        let store = TerminalProgressStore()
        let paneA = UUID()
        let projectA = UUID()
        let projectB = UUID()

        store.setProgress(.clamping(kind: .set, percent: 50), for: paneA, projectID: projectA)
        store.setProgress(nil, for: paneA, projectID: projectA)
        await waitForCoalesceFlush()

        #expect(store.hasCompletionPending(for: projectA))
        #expect(!store.hasCompletionPending(for: projectB))
    }

    @Test("repeated identical progress values do not mark completion")
    func dedupsRepeatedValues() async {
        let store = TerminalProgressStore()
        let pane = UUID()
        let project = UUID()

        store.setProgress(.clamping(kind: .set, percent: 50), for: pane, projectID: project)
        store.setProgress(.clamping(kind: .set, percent: 50), for: pane, projectID: project)
        await waitForCoalesceFlush()

        #expect(store.progress(for: pane) == TerminalProgress(kind: .set, percent: 50))
        #expect(!store.isCompletionPending(for: pane))
    }

    private func waitForCoalesceFlush() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }
}

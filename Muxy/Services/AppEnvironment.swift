import Foundation

@MainActor
struct AppEnvironment {
    static let isDevelopment: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    let selectionStore: any ActiveProjectSelectionStoring
    let terminalViews: any TerminalViewRemoving
    let projectPersistence: any ProjectPersisting
    let worktreeLayoutPersistence: any WorktreeLayoutPersisting
    let worktreePersistence: any WorktreePersisting
    let workspacePersistence: any WorkspacePersisting

    static let live = Self(
        selectionStore: UserDefaultsActiveProjectSelectionStore(),
        terminalViews: TerminalViewRegistry.shared,
        projectPersistence: FileProjectPersistence(),
        worktreeLayoutPersistence: FileWorktreeLayoutPersistence(),
        worktreePersistence: FileWorktreePersistence(),
        workspacePersistence: FileWorkspacePersistence()
    )
}

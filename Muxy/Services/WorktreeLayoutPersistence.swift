import Foundation

protocol WorktreeLayoutPersisting {
    func loadWorktreeLayouts() throws -> [WorktreeLayoutSnapshot]
    func saveWorktreeLayouts(_ layouts: [WorktreeLayoutSnapshot]) throws
}

final class FileWorktreeLayoutPersistence: WorktreeLayoutPersisting {
    private let store: CodableFileStore<[WorktreeLayoutSnapshot]>

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "worktree-layouts.json")) {
        Self.migrateLegacyFile(to: fileURL)
        store = CodableFileStore(fileURL: fileURL)
    }

    func loadWorktreeLayouts() throws -> [WorktreeLayoutSnapshot] {
        try store.load() ?? []
    }

    func saveWorktreeLayouts(_ layouts: [WorktreeLayoutSnapshot]) throws {
        store.saveAsync(layouts)
    }

    private static func migrateLegacyFile(to newURL: URL) {
        guard newURL.lastPathComponent == "worktree-layouts.json" else { return }
        let legacyURL = MuxyFileStorage.fileURL(filename: "workspaces.json")
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: newURL.path),
              fileManager.fileExists(atPath: legacyURL.path)
        else { return }
        try? fileManager.moveItem(at: legacyURL, to: newURL)
    }
}

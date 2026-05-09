import Foundation

protocol WorkspacePersisting {
    func loadWorkspaces() throws -> [Workspace]
    func saveWorkspaces(_ workspaces: [Workspace]) throws
}

final class FileWorkspacePersistence: WorkspacePersisting {
    private let store: CodableFileStore<[Workspace]>

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "workspaces.json")) {
        store = CodableFileStore(fileURL: fileURL)
    }

    func loadWorkspaces() throws -> [Workspace] {
        try store.load() ?? []
    }

    func saveWorkspaces(_ workspaces: [Workspace]) throws {
        store.saveAsync(workspaces)
    }
}

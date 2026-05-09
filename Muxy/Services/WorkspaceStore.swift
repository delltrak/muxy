import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorkspaceStore")

@MainActor
@Observable
final class WorkspaceStore {
    private(set) var workspaces: [Workspace] = []
    private let persistence: any WorkspacePersisting

    init(persistence: any WorkspacePersisting) {
        self.persistence = persistence
        load()
    }

    func add(_ workspace: Workspace) {
        workspaces.append(workspace)
        save()
    }

    func remove(id: UUID) {
        workspaces.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, to newName: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = newName
        save()
    }

    func setIconColor(id: UUID, to color: String?) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].iconColor = color
        save()
    }

    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        for index in workspaces.indices {
            workspaces[index].sortOrder = index
        }
        save()
    }

    func contains(id: UUID) -> Bool {
        workspaces.contains { $0.id == id }
    }

    func save() {
        do {
            try persistence.saveWorkspaces(workspaces)
        } catch {
            logger.error("Failed to save workspaces: \(error)")
        }
    }

    private func load() {
        do {
            workspaces = try persistence.loadWorkspaces()
            workspaces.sort { $0.sortOrder < $1.sortOrder }
        } catch {
            logger.error("Failed to load workspaces: \(error)")
        }
    }
}

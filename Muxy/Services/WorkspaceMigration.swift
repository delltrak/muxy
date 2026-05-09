import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorkspaceMigration")

@MainActor
enum WorkspaceMigration {
    static func ensureDefaultWorkspace(
        workspaceStore: WorkspaceStore,
        projectStore: ProjectStore,
        now: Date = Date()
    ) {
        let needsDefault = workspaceStore.workspaces.isEmpty
        let projectsMissingWorkspace = projectStore.projects.contains { $0.workspaceID == nil }
        guard needsDefault || projectsMissingWorkspace else { return }

        let defaultID: UUID
        if let existing = workspaceStore.workspaces.first {
            defaultID = existing.id
        } else {
            let workspace = Workspace.makeDefault(now: now)
            workspaceStore.add(workspace)
            defaultID = workspace.id
            logger.info("Created Default workspace \(defaultID, privacy: .public)")
        }

        let valid = Set(workspaceStore.workspaces.map(\.id))
        var migrated = 0
        for project in projectStore.projects {
            let needsAssign: Bool = if let existing = project.workspaceID {
                !valid.contains(existing)
            } else {
                true
            }
            guard needsAssign else { continue }
            projectStore.setWorkspaceID(id: project.id, to: defaultID)
            migrated += 1
        }
        if migrated > 0 {
            logger.info("Assigned \(migrated, privacy: .public) project(s) to default workspace")
        }
    }
}

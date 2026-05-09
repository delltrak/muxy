import Foundation
import Testing

@testable import Muxy

@Suite("WorkspaceMigration")
@MainActor
struct WorkspaceMigrationTests {
    @Test("creates default workspace when none exist")
    func createsDefaultWorkspace() {
        let workspaceStore = WorkspaceStore(persistence: WorkspacePersistenceStub())
        let projectStore = ProjectStore(persistence: ProjectPersistenceStub(initial: []))

        WorkspaceMigration.ensureDefaultWorkspace(
            workspaceStore: workspaceStore,
            projectStore: projectStore
        )

        #expect(workspaceStore.workspaces.count == 1)
        #expect(workspaceStore.workspaces.first?.id == Workspace.defaultID)
        #expect(workspaceStore.workspaces.first?.name == Workspace.defaultName)
    }

    @Test("assigns legacy projects without workspaceID to default")
    func assignsLegacyProjects() {
        let projectA = Project(name: "A", path: "/tmp/a")
        let projectB = Project(name: "B", path: "/tmp/b")
        let workspaceStore = WorkspaceStore(persistence: WorkspacePersistenceStub())
        let projectStore = ProjectStore(persistence: ProjectPersistenceStub(initial: [projectA, projectB]))

        WorkspaceMigration.ensureDefaultWorkspace(
            workspaceStore: workspaceStore,
            projectStore: projectStore
        )

        let defaultID = Workspace.defaultID
        #expect(projectStore.projects.allSatisfy { $0.workspaceID == defaultID })
    }

    @Test("is a no-op when projects already have valid workspaceID")
    func noopForValidProjects() {
        let existing = Workspace(id: UUID(), name: "Acme")
        let workspaceStub = WorkspacePersistenceStub(initial: [existing])
        let workspaceStore = WorkspaceStore(persistence: workspaceStub)

        var project = Project(name: "A", path: "/tmp/a")
        project.workspaceID = existing.id
        let projectStore = ProjectStore(persistence: ProjectPersistenceStub(initial: [project]))

        WorkspaceMigration.ensureDefaultWorkspace(
            workspaceStore: workspaceStore,
            projectStore: projectStore
        )

        #expect(workspaceStore.workspaces.count == 1)
        #expect(workspaceStore.workspaces.first?.id == existing.id)
        #expect(projectStore.projects.first?.workspaceID == existing.id)
    }

    @Test("reassigns project pointing to missing workspace")
    func reassignsOrphanedProjects() {
        let orphanID = UUID()
        let workspaceStore = WorkspaceStore(persistence: WorkspacePersistenceStub())
        var project = Project(name: "A", path: "/tmp/a")
        project.workspaceID = orphanID
        let projectStore = ProjectStore(persistence: ProjectPersistenceStub(initial: [project]))

        WorkspaceMigration.ensureDefaultWorkspace(
            workspaceStore: workspaceStore,
            projectStore: projectStore
        )

        #expect(projectStore.projects.first?.workspaceID == Workspace.defaultID)
    }
}

private final class WorkspacePersistenceStub: WorkspacePersisting {
    var workspaces: [Workspace]

    init(initial: [Workspace] = []) {
        workspaces = initial
    }

    func loadWorkspaces() throws -> [Workspace] {
        workspaces
    }

    func saveWorkspaces(_ workspaces: [Workspace]) throws {
        self.workspaces = workspaces
    }
}

private final class ProjectPersistenceStub: ProjectPersisting {
    var projects: [Project]

    init(initial: [Project]) {
        projects = initial
    }

    func loadProjects() throws -> [Project] {
        projects
    }

    func saveProjects(_ projects: [Project]) throws {
        self.projects = projects
    }
}

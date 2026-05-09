import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorktreeStore")

@MainActor
@Observable
final class WorktreeStore {
    private(set) var worktrees: [UUID: [Worktree]] = [:]
    private var projectIDByPath: [String: UUID] = [:]
    private let persistence: any WorktreePersisting
    private let listGitWorktrees: @Sendable (String) async throws -> [GitWorktreeRecord]

    init(
        persistence: any WorktreePersisting,
        listGitWorktrees: @escaping @Sendable (String) async throws -> [GitWorktreeRecord] = {
            try await GitWorktreeService.shared.listWorktrees(repoPath: $0)
        },
        projects: [Project] = []
    ) {
        self.persistence = persistence
        self.listGitWorktrees = listGitWorktrees
        guard !projects.isEmpty else { return }
        loadAll(projects: projects)
    }

    func loadAll(projects: [Project]) {
        let primaries = projects.reduce(into: [UUID: Worktree]()) { result, project in
            result[project.id] = makePrimary(for: project)
        }
        let outcomes = Self.parallelLoad(persistence: persistence, projects: projects, primaries: primaries)
        for outcome in outcomes {
            setWorktrees(sortPrimaryFirst(outcome.list), for: outcome.projectID)
            if outcome.didMutate {
                save(projectID: outcome.projectID)
            }
        }
    }

    private struct LoadOutcome {
        let projectID: UUID
        let list: [Worktree]
        let didMutate: Bool
    }

    private static func parallelLoad(
        persistence: any WorktreePersisting,
        projects: [Project],
        primaries: [UUID: Worktree]
    ) -> [LoadOutcome] {
        guard !projects.isEmpty else { return [] }
        let collector = LoadOutcomeCollector()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "app.muxy.worktree-store.load", attributes: .concurrent)
        for project in projects {
            let primary = primaries[project.id] ?? Worktree(
                name: project.name,
                path: project.path,
                branch: nil,
                source: .muxy,
                isPrimary: true
            )
            group.enter()
            queue.async {
                let outcome = Self.computeLoadOutcome(
                    persistence: persistence,
                    project: project,
                    primary: primary
                )
                collector.append(outcome)
                group.leave()
            }
        }
        group.wait()
        return collector.snapshot()
    }

    private final class LoadOutcomeCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [LoadOutcome] = []

        func append(_ outcome: LoadOutcome) {
            lock.lock()
            values.append(outcome)
            lock.unlock()
        }

        func snapshot() -> [LoadOutcome] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private static func computeLoadOutcome(
        persistence: any WorktreePersisting,
        project: Project,
        primary: Worktree
    ) -> LoadOutcome {
        do {
            var loaded = try persistence.loadWorktrees(projectID: project.id)
            var didMutate = false
            if !loaded.contains(where: \.isPrimary) {
                loaded.insert(primary, at: 0)
                didMutate = true
            }
            return LoadOutcome(projectID: project.id, list: loaded, didMutate: didMutate)
        } catch {
            logger.error("Failed to load worktrees for project \(project.id): \(error)")
            return LoadOutcome(projectID: project.id, list: [primary], didMutate: true)
        }
    }

    func ensurePrimary(for project: Project) {
        var list = worktrees[project.id] ?? []
        if list.contains(where: \.isPrimary) { return }
        list.insert(makePrimary(for: project), at: 0)
        setWorktrees(sortPrimaryFirst(list), for: project.id)
        save(projectID: project.id)
    }

    func list(for projectID: UUID) -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func projectID(forWorktreePath path: String) -> UUID? {
        projectIDByPath[path]
    }

    func primary(for projectID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.isPrimary })
    }

    func worktree(projectID: UUID, worktreeID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.id == worktreeID })
    }

    func preferred(for projectID: UUID, matching preferredID: UUID?) -> Worktree? {
        let list = list(for: projectID)
        return list.first(where: { $0.id == preferredID })
            ?? list.first(where: { $0.isPrimary })
            ?? list.first
    }

    func add(_ worktree: Worktree, to projectID: UUID) {
        var list = worktrees[projectID] ?? []
        list.append(worktree)
        setWorktrees(sortPrimaryFirst(list), for: projectID)
        save(projectID: projectID)
    }

    func remove(worktreeID: UUID, from projectID: UUID) {
        guard var list = worktrees[projectID] else { return }
        let removed = list.filter { $0.id == worktreeID && $0.canBeRemoved }
        list.removeAll { $0.id == worktreeID && $0.canBeRemoved }
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
        for worktree in removed {
            VCSStateStore.shared.remove(path: worktree.path)
        }
    }

    func refreshFromGit(project: Project) async throws -> [Worktree] {
        ensurePrimary(for: project)
        let records = try await listGitWorktrees(project.path).filter { !$0.isBare && !$0.isPrunable }
        var list = worktrees[project.id] ?? []
        let projectKey = Self.canonicalPath(project.path)
        let recordKeys = Set(records.map { Self.canonicalPath($0.path) })

        if let primaryIndex = list.firstIndex(where: \.isPrimary) {
            list[primaryIndex].path = project.path
            list[primaryIndex].name = project.name
        } else {
            list.insert(makePrimary(for: project), at: 0)
        }

        var existingByKey: [String: Worktree] = [:]
        for worktree in list {
            let key = Self.canonicalPath(worktree.path)
            if let existing = existingByKey[key] {
                if worktree.isPrimary, !existing.isPrimary {
                    existingByKey[key] = worktree
                }
            } else {
                existingByKey[key] = worktree
            }
        }

        for record in records {
            let recordKey = Self.canonicalPath(record.path)
            if recordKey == projectKey {
                if let primaryIndex = list.firstIndex(where: \.isPrimary) {
                    list[primaryIndex].branch = record.branch
                }
                continue
            }

            if let existing = existingByKey[recordKey],
               let index = list.firstIndex(where: { $0.id == existing.id })
            {
                list[index].branch = record.branch
                if list[index].isPrimary {
                    list[index].name = project.name
                    list[index].path = project.path
                }
                continue
            }

            list.append(Worktree(
                name: defaultName(for: record),
                path: record.path,
                branch: record.branch,
                source: .external,
                isPrimary: false
            ))
        }

        let sorted = sortPrimaryFirst(list.filter {
            !$0.isExternallyManaged || recordKeys.contains(Self.canonicalPath($0.path))
        })
        let previous = worktrees[project.id] ?? []
        setWorktrees(sorted, for: project.id)
        if previous != sorted {
            save(projectID: project.id)
        }
        return sorted
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func cleanupOnDisk(
        worktree: Worktree,
        repoPath: String
    ) async {
        guard worktree.canBeRemoved else { return }
        do {
            try await GitWorktreeService.shared.removeWorktree(
                repoPath: repoPath,
                path: worktree.path,
                force: true
            )
        } catch {
            logger.error("Failed to remove git worktree at \(worktree.path): \(error)")
        }

        if worktree.ownsBranch,
           let branch = worktree.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty
        {
            do {
                try await GitWorktreeService.shared.deleteBranch(repoPath: repoPath, branch: branch)
            } catch {
                logger.error("Failed to delete branch \(branch) for worktree \(worktree.path): \(error)")
            }
        }

        try? FileManager.default.removeItem(atPath: worktree.path)
        removeParentDirectoryIfEmpty(for: worktree.path)
    }

    static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree]) async {
        let secondaryWorktrees = knownWorktrees.filter(\.canBeRemoved)
        await withTaskGroup(of: Void.self) { group in
            for worktree in secondaryWorktrees {
                group.addTask {
                    await cleanupOnDisk(worktree: worktree, repoPath: project.path)
                }
            }
        }

        let root = MuxyFileStorage.worktreeRoot(forProjectID: project.id)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        await withTaskGroup(of: Void.self) { group in
            for child in children {
                let childPath = root.appendingPathComponent(child).path
                group.addTask {
                    try? await GitWorktreeService.shared.removeWorktree(
                        repoPath: project.path,
                        path: childPath,
                        force: true
                    )
                    try? FileManager.default.removeItem(atPath: childPath)
                }
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static func removeParentDirectoryIfEmpty(for path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        guard children.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    func rename(worktreeID: UUID, in projectID: UUID, to newName: String) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].name = newName
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func updateBranch(worktreeID: UUID, in projectID: UUID, branch: String?) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].branch = branch
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func removeProject(_ projectID: UUID) {
        let removedPaths: [String] = if let existing = worktrees[projectID] {
            existing.map(\.path)
        } else {
            []
        }
        if let existing = worktrees[projectID] {
            for worktree in existing where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        worktrees.removeValue(forKey: projectID)
        do {
            try persistence.removeWorktrees(projectID: projectID)
        } catch {
            logger.error("Failed to remove worktrees file for project \(projectID): \(error)")
        }
        for path in removedPaths {
            VCSStateStore.shared.remove(path: path)
        }
    }

    private func setWorktrees(_ list: [Worktree], for projectID: UUID) {
        if let previous = worktrees[projectID] {
            for worktree in previous where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        for worktree in list {
            projectIDByPath[worktree.path] = projectID
        }
        worktrees[projectID] = list
    }

    private func makePrimary(for project: Project) -> Worktree {
        Worktree(
            name: project.name,
            path: project.path,
            branch: nil,
            source: .muxy,
            isPrimary: true
        )
    }

    private func sortPrimaryFirst(_ list: [Worktree]) -> [Worktree] {
        let primary = list.filter(\.isPrimary)
        let others = list.filter { !$0.isPrimary }.sorted { $0.createdAt < $1.createdAt }
        return primary + others
    }

    private func save(projectID: UUID) {
        guard let list = worktrees[projectID] else { return }
        do {
            try persistence.saveWorktrees(list, projectID: projectID)
        } catch {
            logger.error("Failed to save worktrees for project \(projectID): \(error)")
        }
    }

    private func defaultName(for record: GitWorktreeRecord) -> String {
        if let branch = record.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty
        {
            return branch
        }
        return URL(fileURLWithPath: record.path).lastPathComponent
    }
}

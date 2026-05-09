import Foundation

final class GitMetadataCache: @unchecked Sendable {
    static let shared = GitMetadataCache()

    static let maxRepoEntries = 64

    struct PRKey: Hashable {
        let repoPath: String
        let branch: String
        let headSha: String
    }

    private struct PREntry {
        let info: GitRepositoryService.PRInfo?
        let storedAt: Date
    }

    private let lock = NSLock()
    private var prInfo: [PRKey: PREntry] = [:]
    private var defaultBranch: [String: String?] = [:]
    private var defaultBranchOrder: [String] = []
    private var ghInstalled: Bool?

    private let prTTL: TimeInterval = 60

    private init() {}

    func cachedPRInfo(repoPath: String, branch: String, headSha: String) -> GitRepositoryService.PRInfo?? {
        lock.lock()
        defer { lock.unlock() }
        let key = PRKey(repoPath: repoPath, branch: branch, headSha: headSha)
        guard let entry = prInfo[key] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > prTTL {
            prInfo.removeValue(forKey: key)
            return nil
        }
        return .some(entry.info)
    }

    func storePRInfo(_ info: GitRepositoryService.PRInfo?, repoPath: String, branch: String, headSha: String) {
        lock.lock()
        defer { lock.unlock() }
        let key = PRKey(repoPath: repoPath, branch: branch, headSha: headSha)
        prInfo[key] = PREntry(info: info, storedAt: Date())
        enforcePRCapLocked()
    }

    func invalidatePRInfo(repoPath: String, branch: String) {
        lock.lock()
        defer { lock.unlock() }
        prInfo = prInfo.filter { key, _ in
            !(key.repoPath == repoPath && key.branch == branch)
        }
    }

    func invalidatePRInfo(repoPath: String) {
        lock.lock()
        defer { lock.unlock() }
        prInfo = prInfo.filter { key, _ in key.repoPath != repoPath }
    }

    func invalidate(path: String) {
        lock.lock()
        defer { lock.unlock() }
        prInfo = prInfo.filter { key, _ in key.repoPath != path }
        defaultBranch.removeValue(forKey: path)
        defaultBranchOrder.removeAll { $0 == path }
    }

    func cachedDefaultBranch(repoPath: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = defaultBranch[repoPath] else { return nil }
        touchDefaultBranchLocked(repoPath)
        return .some(value)
    }

    func storeDefaultBranch(_ branch: String?, repoPath: String) {
        lock.lock()
        defer { lock.unlock() }
        defaultBranch[repoPath] = branch
        touchDefaultBranchLocked(repoPath)
        enforceDefaultBranchCapLocked()
    }

    func cachedGhInstalled() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return ghInstalled
    }

    func storeGhInstalled(_ installed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        ghInstalled = installed
    }

    private func touchDefaultBranchLocked(_ repoPath: String) {
        defaultBranchOrder.removeAll { $0 == repoPath }
        defaultBranchOrder.append(repoPath)
    }

    private func enforceDefaultBranchCapLocked() {
        while defaultBranchOrder.count > Self.maxRepoEntries {
            let oldest = defaultBranchOrder.removeFirst()
            defaultBranch.removeValue(forKey: oldest)
        }
    }

    private func enforcePRCapLocked() {
        let cap = Self.maxRepoEntries
        guard prInfo.count > cap else { return }
        let sorted = prInfo.sorted { $0.value.storedAt < $1.value.storedAt }
        let removeCount = prInfo.count - cap
        for index in 0 ..< removeCount {
            prInfo.removeValue(forKey: sorted[index].key)
        }
    }
}

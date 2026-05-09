import Foundation

@MainActor
@Observable
final class BranchCache {
    static let shared = BranchCache()

    private static let maxEntries = 64

    private var branchesByPath: [String: [String]] = [:]
    @ObservationIgnored private var accessOrder: [String] = []

    func update(projectPath: String, branches: [String]) {
        branchesByPath[projectPath] = branches
        touch(projectPath)
        enforceCap()
    }

    func branches(for projectPath: String) -> [String] {
        guard let branches = branchesByPath[projectPath] else { return [] }
        touch(projectPath)
        return branches
    }

    func invalidate(path: String) {
        branchesByPath.removeValue(forKey: path)
        accessOrder.removeAll { $0 == path }
    }

    private func touch(_ path: String) {
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
    }

    private func enforceCap() {
        while accessOrder.count > Self.maxEntries {
            let oldest = accessOrder.removeFirst()
            branchesByPath.removeValue(forKey: oldest)
        }
    }
}

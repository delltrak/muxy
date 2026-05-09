import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var sortOrder: Int
    var createdAt: Date
    var icon: String?
    var logo: String?
    var iconColor: String?
    var preferredWorktreeParentPath: String?
    var workspaceID: UUID?

    init(
        name: String,
        path: String,
        sortOrder: Int = 0,
        workspaceID: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.icon = nil
        self.logo = nil
        self.iconColor = nil
        self.preferredWorktreeParentPath = nil
        self.workspaceID = workspaceID
    }

    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

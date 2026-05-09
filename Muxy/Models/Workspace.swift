import Foundation

struct Workspace: Identifiable, Codable, Hashable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-00000000FACE") ?? UUID()
    static let defaultName = "Default"

    let id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var iconColor: String?

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        iconColor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.iconColor = iconColor
    }

    static func makeDefault(now: Date = Date()) -> Workspace {
        Workspace(
            id: Workspace.defaultID,
            name: Workspace.defaultName,
            sortOrder: 0,
            createdAt: now
        )
    }
}

import Foundation

nonisolated enum Priority: Int, CaseIterable, Codable, Comparable, Identifiable, Sendable {
    case low, medium, high

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var priority: Priority
    var isDone: Bool
    var createdAt: Date
    var dueDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: Priority = .medium,
        isDone: Bool = false,
        createdAt: Date = .now,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueDate = dueDate
    }
}

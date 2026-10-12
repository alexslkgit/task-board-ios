import Foundation

nonisolated enum Priority: Int, CaseIterable, Codable, Comparable, Identifiable, Sendable {
    case low, medium, high

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
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

nonisolated extension TaskItem {
    /// Copies onto `self` only the fields `edited` changed relative to `baseline`, so concurrent changes to the rest survive.
    func applying(changesFrom baseline: TaskItem, to edited: TaskItem) -> TaskItem {
        var result = self
        if edited.title != baseline.title { result.title = edited.title }
        if edited.notes != baseline.notes { result.notes = edited.notes }
        if edited.priority != baseline.priority { result.priority = edited.priority }
        if edited.isDone != baseline.isDone { result.isDone = edited.isDone }
        if edited.dueDate != baseline.dueDate { result.dueDate = edited.dueDate }
        return result
    }

    /// A title is one paragraph: each run of line breaks becomes a single space, so words never get glued.
    static func singleLineTitle(_ text: String) -> String {
        text.replacing(#/[ \t]*\R+[ \t]*/#, with: " ")
    }
}

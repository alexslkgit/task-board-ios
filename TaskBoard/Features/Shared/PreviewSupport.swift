#if DEBUG
import Foundation

enum PreviewData {
    private static let day: TimeInterval = 86_400

    static let tasks: [TaskItem] = [
        TaskItem(title: "Ship the release notes", notes: "Draft, review, publish", priority: .high, dueDate: .now.addingTimeInterval(day)),
        TaskItem(title: "Pay the electricity bill", priority: .high, dueDate: .now.addingTimeInterval(-2 * day)),
        TaskItem(title: "Book dentist", notes: "Ask about Friday afternoon", priority: .medium),
        TaskItem(title: "Water the plants", priority: .low, isDone: true, dueDate: .now.addingTimeInterval(-day)),
        TaskItem(
            title: "Plan the quarterly roadmap review with every team and collect feedback before the meeting",
            notes: "Long titles must wrap instead of truncating at any Dynamic Type size",
            priority: .low,
            dueDate: .now.addingTimeInterval(5 * day)
        ),
    ]

    @MainActor
    static func viewModel(seed: [TaskItem]? = nil) -> TaskListViewModel {
        let api = MockTaskAPI(seed: seed ?? tasks, readLatency: 0...0, writeLatency: 0...0, failureRate: 0)
        return TaskListViewModel(repository: DefaultTaskRepository(api: api))
    }
}
#endif

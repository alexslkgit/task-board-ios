import Foundation

nonisolated enum TaskAPIError: LocalizedError, Equatable, Sendable {
    case network
    case notFound

    private static let networkMessage = "Network request failed. Please try again."
    private static let notFoundMessage = "The task no longer exists."

    var errorDescription: String? {
        switch self {
        case .network: Self.networkMessage
        case .notFound: Self.notFoundMessage
        }
    }
}

/// Remote source of truth. The only implementation today is `MockTaskAPI`.
nonisolated protocol TaskAPI: Sendable {
    func fetchTasks() async throws -> [TaskItem]
    func create(_ task: TaskItem) async throws -> TaskItem
    func update(_ task: TaskItem) async throws -> TaskItem
    func delete(id: TaskItem.ID) async throws
}

/// What the UI layer depends on: API access plus an in-memory cache.
nonisolated protocol TaskRepository: Sendable {
    func loadTasks(forceRefresh: Bool) async throws -> [TaskItem]
    func add(_ task: TaskItem) async throws -> TaskItem
    func update(_ task: TaskItem) async throws -> TaskItem
    func delete(id: TaskItem.ID) async throws
}

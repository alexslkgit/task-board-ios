import Foundation
@testable import TaskBoard

actor StubTaskRepository: TaskRepository {
    var tasks: [TaskItem]
    var shouldFail: Bool

    init(tasks: [TaskItem] = [], shouldFail: Bool = false) {
        self.tasks = tasks
        self.shouldFail = shouldFail
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func loadTasks(forceRefresh: Bool) async throws -> [TaskItem] {
        try check()
        return tasks
    }

    func add(_ task: TaskItem) async throws -> TaskItem {
        try check()
        tasks.append(task)
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        try check()
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        try check()
        tasks.removeAll { $0.id == id }
    }

    private func check() throws {
        if shouldFail { throw TaskAPIError.network }
    }
}

/// API double whose failures can be switched on after a successful load.
actor StubTaskAPI: TaskAPI {
    var tasks: [TaskItem]
    var shouldFail = false

    init(tasks: [TaskItem]) { self.tasks = tasks }

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func fetchTasks() async throws -> [TaskItem] { tasks }

    func create(_ task: TaskItem) async throws -> TaskItem {
        if shouldFail { throw TaskAPIError.network }
        tasks.append(task)
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        if shouldFail { throw TaskAPIError.network }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        if shouldFail { throw TaskAPIError.network }
    }
}

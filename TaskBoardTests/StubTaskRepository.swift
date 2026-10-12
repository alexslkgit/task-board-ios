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
    func setTasks(_ value: [TaskItem]) { tasks = value }

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
    private(set) var fetchCount = 0
    private var gateArmed = false
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation
    /// Yields once when a gated fetch has taken its snapshot and is waiting for `openGate()`.
    nonisolated let gateEntered: AsyncStream<Void>
    private let gateEnteredContinuation: AsyncStream<Void>.Continuation

    init(tasks: [TaskItem]) {
        self.tasks = tasks
        (gate, gateContinuation) = AsyncStream.makeStream()
        (gateEntered, gateEnteredContinuation) = AsyncStream.makeStream()
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }
    func setTasks(_ value: [TaskItem]) { tasks = value }

    /// The next fetch returns the data as it was when it started, but only after `openGate()`.
    func armGate() { gateArmed = true }

    nonisolated func openGate() { gateContinuation.yield() }

    func fetchTasks() async throws -> [TaskItem] {
        fetchCount += 1
        let snapshot = tasks
        if gateArmed {
            gateArmed = false
            gateEnteredContinuation.yield()
            for await _ in gate { break }
        }
        return snapshot
    }

    func create(_ task: TaskItem) async throws -> TaskItem {
        if shouldFail { throw TaskAPIError.network }
        tasks.append(task)
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        if shouldFail { throw TaskAPIError.network }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        if shouldFail { throw TaskAPIError.network }
        tasks.removeAll { $0.id == id }
    }
}

/// API double whose deletes wait for `releaseDelete()` and then fail, so other writes can queue behind one.
actor FailingDeleteAPI: TaskAPI {
    private var tasks: [TaskItem]
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation

    init(tasks: [TaskItem]) {
        self.tasks = tasks
        (gate, gateContinuation) = AsyncStream.makeStream()
    }

    nonisolated func releaseDelete() { gateContinuation.yield() }

    func fetchTasks() async throws -> [TaskItem] { tasks }

    func create(_ task: TaskItem) async throws -> TaskItem {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task } else { tasks.append(task) }
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        for await _ in gate { break }
        throw TaskAPIError.network
    }
}

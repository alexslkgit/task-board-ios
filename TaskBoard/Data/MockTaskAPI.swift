import Foundation
import os

actor MockTaskAPI: TaskAPI {
    nonisolated private static let defaultReadLatency = 0.3...0.8
    nonisolated private static let defaultWriteLatency = 0.1...0.3
    nonisolated static let defaultFailureRate = 0.15

    private var storage: [TaskItem]
    private let readLatency: ClosedRange<Double>
    private let writeLatency: ClosedRange<Double>
    private let readFailureRate: Double
    private let writeFailureRate: Double

    init(
        seed: [TaskItem] = TaskItem.seed,
        readLatency: ClosedRange<Double> = MockTaskAPI.defaultReadLatency,
        writeLatency: ClosedRange<Double> = MockTaskAPI.defaultWriteLatency,
        failureRate: Double = MockTaskAPI.defaultFailureRate,
        writeFailureRate: Double? = nil
    ) {
        self.storage = seed
        self.readLatency = readLatency
        self.writeLatency = writeLatency
        self.readFailureRate = failureRate
        self.writeFailureRate = writeFailureRate ?? failureRate
    }

    func fetchTasks() async throws -> [TaskItem] {
        Logger.network.debug("fetchTasks start")
        try await simulateNetwork("fetchTasks", readLatency, failureRate: readFailureRate)
        return storage.sorted { $0.createdAt < $1.createdAt }
    }

    func create(_ task: TaskItem) async throws -> TaskItem {
        Logger.network.debug("create start id=\(task.id, privacy: .public) title=\(task.title, privacy: .private)")
        try await simulateNetwork("create", writeLatency, failureRate: writeFailureRate)
        // Idempotent by id, like a PUT with a client-generated id: a retried or undone create never duplicates.
        if let index = storage.firstIndex(where: { $0.id == task.id }) {
            storage[index] = task
        } else {
            storage.append(task)
        }
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        Logger.network.debug("update start id=\(task.id, privacy: .public) title=\(task.title, privacy: .private)")
        try await simulateNetwork("update", writeLatency, failureRate: writeFailureRate)
        guard let index = storage.firstIndex(where: { $0.id == task.id }) else {
            Logger.network.error("update notFound id=\(task.id, privacy: .public)")
            throw TaskAPIError.notFound
        }
        storage[index] = task
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        Logger.network.debug("delete start id=\(id, privacy: .public)")
        try await simulateNetwork("delete", writeLatency, failureRate: writeFailureRate)
        guard let index = storage.firstIndex(where: { $0.id == id }) else {
            Logger.network.error("delete notFound id=\(id, privacy: .public)")
            throw TaskAPIError.notFound
        }
        storage.remove(at: index)
    }

    /// A cancelled caller gets `CancellationError` rethrown from the sleep, untouched: cancellation is not a
    /// network failure, and the write has not been applied yet, so storage stays consistent.
    private func simulateNetwork(_ operation: String, _ latency: ClosedRange<Double>, failureRate: Double) async throws {
        if latency.upperBound > 0 {
            let delay = Double.random(in: latency)
            Logger.network.debug("\(operation, privacy: .public) latency=\(delay, format: .fixed(precision: 2), privacy: .public)s")
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                Logger.network.debug("\(operation, privacy: .public) cancelled")
                throw error
            }
        }
        if Double.random(in: 0..<1) < failureRate {
            Logger.network.error("\(operation, privacy: .public) simulated failure")
            throw TaskAPIError.network
        }
    }
}

nonisolated private enum SeedConstants {
    static let spacing: TimeInterval = 60
    static let json = """
    [{"title":"Renew domain registration","notes":"Expires end of month","priority":"High","done":false},\
    {"title":"Reply to design feedback","notes":"","priority":"Medium","done":false},\
    {"title":"Book dentist","notes":"","priority":"Low","done":true},\
    {"title":"Migrate the analytics pipeline to the new warehouse and validate dashboards","notes":"Long one — check layout","priority":"Medium","done":false}]
    """
}

nonisolated extension TaskItem {
    static let seed: [TaskItem] = {
        // Constant, known-good JSON: a failure here is a programmer error.
        let dtos = try! JSONDecoder().decode([SeedDTO].self, from: Data(SeedConstants.json.utf8))
        let now = Date.now
        // In the past and in index order, so tasks created later always sort after the seed.
        return dtos.enumerated().map { index, dto in
            TaskItem(
                title: dto.title,
                notes: dto.notes,
                priority: Priority.allCases.first { $0.title == dto.priority } ?? .medium,
                isDone: dto.done,
                createdAt: now.addingTimeInterval(-Double(dtos.count - index) * SeedConstants.spacing)
            )
        }
    }()
}

private nonisolated struct SeedDTO: Decodable {
    let title: String
    let notes: String
    let priority: String
    let done: Bool
}

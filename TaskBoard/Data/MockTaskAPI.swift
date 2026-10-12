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
    static let day: TimeInterval = 24 * 60 * 60
}

nonisolated extension TaskItem {
    static let seed: [TaskItem] = {
        typealias Entry = (title: String, notes: String, priority: Priority, isDone: Bool, dueInDays: Double?)
        let entries: [Entry] = [
            ("Renew domain registration", "Expires end of month", .high, false, 3),
            ("Reply to design feedback", "", .medium, false, nil),
            ("Book dentist", "", .low, true, -1),
            ("Migrate the analytics pipeline to the new warehouse and validate dashboards", "Long one — check layout", .medium, false, nil),
        ]
        let now = Date.now
        // In the past and in index order, so tasks created later always sort after the seed.
        return entries.enumerated().map { index, entry in
            TaskItem(
                title: entry.title,
                notes: entry.notes,
                priority: entry.priority,
                isDone: entry.isDone,
                createdAt: now.addingTimeInterval(-Double(entries.count - index) * SeedConstants.spacing),
                dueDate: entry.dueInDays.map { now.addingTimeInterval($0 * SeedConstants.day) }
            )
        }
    }()
}

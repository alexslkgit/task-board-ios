import Foundation
import os

actor DefaultTaskRepository: TaskRepository {
    private let api: any TaskAPI
    private var cache: [TaskItem]?
    // Bumped by every successful write so a slower in-flight fetch cannot overwrite the cache with older data.
    private var generation = 0

    init(api: any TaskAPI) {
        self.api = api
    }

    func loadTasks(forceRefresh: Bool) async throws -> [TaskItem] {
        if let cache, !forceRefresh {
            Logger.repository.debug("cache hit count=\(cache.count, privacy: .public)")
            return cache
        }
        Logger.repository.debug("cache miss forceRefresh=\(forceRefresh, privacy: .public)")
        let startedAt = generation
        let tasks: [TaskItem]
        do {
            tasks = try await api.fetchTasks()
        } catch {
            Logger.repository.error("fetch failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        Logger.repository.info("fetched count=\(tasks.count, privacy: .public)")
        if startedAt == generation {
            cache = tasks
        } else {
            Logger.repository.info("skipped cache write: a write landed during the fetch")
        }
        return tasks
    }

    func add(_ task: TaskItem) async throws -> TaskItem {
        let created = try await logged("add", task.id) { try await api.create(task) }
        generation += 1
        cache?.append(created)
        return created
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        let updated = try await logged("update", task.id) { try await api.update(task) }
        generation += 1
        if let index = cache?.firstIndex(where: { $0.id == updated.id }) {
            cache?[index] = updated
        }
        return updated
    }

    func delete(id: TaskItem.ID) async throws {
        try await logged("delete", id) { try await api.delete(id: id) }
        generation += 1
        cache?.removeAll { $0.id == id }
    }

    private func logged<T>(_ operation: String, _ id: TaskItem.ID, _ body: () async throws -> T) async throws -> T {
        do {
            let result = try await body()
            Logger.repository.debug("\(operation, privacy: .public) succeeded id=\(id, privacy: .public)")
            return result
        } catch {
            Logger.repository.error("\(operation, privacy: .public) failed id=\(id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

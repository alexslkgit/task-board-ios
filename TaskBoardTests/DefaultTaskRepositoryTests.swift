import Foundation
import Testing
@testable import TaskBoard

struct DefaultTaskRepositoryTests {
    @Test func failedUpdateLeavesCacheUnchanged() async throws {
        let item = TaskItem(title: "A")
        let api = StubTaskAPI(tasks: [item])
        let repo = DefaultTaskRepository(api: api)
        _ = try await repo.loadTasks(forceRefresh: false)

        await api.setShouldFail(true)
        var changed = item
        changed.isDone = true
        await #expect(throws: TaskAPIError.self) { try await repo.update(changed) }

        let cached = try await repo.loadTasks(forceRefresh: false)
        #expect(cached == [item])
    }

    @Test func secondLoadIsServedFromCache() async throws {
        let item = TaskItem(title: "A")
        let api = StubTaskAPI(tasks: [item])
        let repo = DefaultTaskRepository(api: api)

        let first = try await repo.loadTasks(forceRefresh: false)
        let second = try await repo.loadTasks(forceRefresh: false)

        #expect(first == [item])
        #expect(second == [item])
        #expect(await api.fetchCount == 1)
    }

    @Test func forceRefreshRefetches() async throws {
        let item = TaskItem(title: "A")
        let other = TaskItem(title: "B")
        let api = StubTaskAPI(tasks: [item])
        let repo = DefaultTaskRepository(api: api)
        _ = try await repo.loadTasks(forceRefresh: false)

        await api.setTasks([item, other])
        let refreshed = try await repo.loadTasks(forceRefresh: true)
        let cached = try await repo.loadTasks(forceRefresh: false)

        #expect(refreshed == [item, other])
        #expect(cached == [item, other])
        #expect(await api.fetchCount == 2)
    }

    @Test func writesKeepCacheInSync() async throws {
        let first = TaskItem(title: "A")
        let second = TaskItem(title: "B")
        let api = StubTaskAPI(tasks: [first, second])
        let repo = DefaultTaskRepository(api: api)
        _ = try await repo.loadTasks(forceRefresh: false)

        let added = TaskItem(title: "C")
        _ = try await repo.add(added)
        #expect(try await repo.loadTasks(forceRefresh: false) == [first, second, added])

        var edited = first
        edited.title = "A edited"
        _ = try await repo.update(edited)
        #expect(try await repo.loadTasks(forceRefresh: false) == [edited, second, added])

        try await repo.delete(id: second.id)
        #expect(try await repo.loadTasks(forceRefresh: false) == [edited, added])

        #expect(await api.fetchCount == 1)
    }

    @Test func staleFetchDoesNotOverwriteCacheAfterWrite() async throws {
        let item = TaskItem(title: "A")
        let added = TaskItem(title: "B")
        let api = StubTaskAPI(tasks: [item])
        let repo = DefaultTaskRepository(api: api)
        _ = try await repo.loadTasks(forceRefresh: false)

        await api.armGate()
        var entered = api.gateEntered.makeAsyncIterator()
        let staleRefresh = Task { try await repo.loadTasks(forceRefresh: true) }
        await entered.next()
        _ = try await repo.add(added)
        api.openGate()

        #expect(try await staleRefresh.value == [item])
        #expect(try await repo.loadTasks(forceRefresh: false) == [item, added])
    }
}

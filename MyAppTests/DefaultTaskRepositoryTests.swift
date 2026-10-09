import Foundation
import Testing
@testable import MyApp

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
}

import Foundation
import Testing
@testable import TaskBoard

/// Repository double with a per-call delay so mutations can overlap.
actor DelayedRepository: TaskRepository {
    var tasks: [TaskItem]
    var shouldFail = false
    let delay: Duration

    init(tasks: [TaskItem], delay: Duration = .milliseconds(50)) {
        self.tasks = tasks
        self.delay = delay
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }

    private func pause() async throws {
        try await Task.sleep(for: delay)
        if shouldFail { throw TaskAPIError.network }
    }

    func loadTasks(forceRefresh: Bool) async throws -> [TaskItem] {
        try await pause()
        return tasks
    }

    func add(_ task: TaskItem) async throws -> TaskItem {
        try await pause()
        tasks.append(task)
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        try await pause()
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        try await pause()
        tasks.removeAll { $0.id == id }
    }
}

@MainActor
struct EdgeCaseTests {
    @Test func refreshFailureKeepsLoadedList() async {
        let items = [TaskItem(title: "A"), TaskItem(title: "B")]
        let stub = StubTaskRepository(tasks: items)
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(true)
        await vm.refresh()
        #expect(vm.tasks == items)
        #expect(vm.loadState == .loaded)
        #expect(vm.mutationError != nil)
    }

    @Test func concurrentTogglesBothFailRestoreOriginal() async {
        let item = TaskItem(title: "A", isDone: false)
        let repo = DelayedRepository(tasks: [item])
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        await repo.setShouldFail(true)
        async let first: Void = vm.toggleDone(item)
        async let second: Void = vm.toggleDone(item)
        _ = await (first, second)
        #expect(vm.task(id: item.id)?.isDone == item.isDone)
        #expect(vm.mutationError != nil)
    }

    @Test func concurrentTogglesBothSucceedEndAtOriginalAndMatchRepository() async {
        let item = TaskItem(title: "A", isDone: false)
        let repo = DelayedRepository(tasks: [item])
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        async let first: Void = vm.toggleDone(item)
        async let second: Void = vm.toggleDone(item)
        _ = await (first, second)
        let stored = await repo.tasks.first { $0.id == item.id }
        #expect(vm.task(id: item.id)?.isDone == item.isDone)
        #expect(stored?.isDone == vm.task(id: item.id)?.isDone)
    }

    @Test func undoDeleteFailureDoesNotDuplicateAndRestoresPending() async {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await vm.delete(item)
        #expect(vm.recentlyDeleted?.id == item.id)
        await stub.setShouldFail(true)
        await vm.undoDelete()
        #expect(vm.tasks.filter { $0.id == item.id }.isEmpty)
        #expect(vm.recentlyDeleted?.id == item.id)
        #expect(vm.mutationError != nil)
    }

    @Test func undoDeleteWhileAddInFlightHasNoDuplicateIds() async throws {
        let a = TaskItem(title: "A")
        let b = TaskItem(title: "B")
        let api = FailingDeleteAPI(tasks: [a, b])
        let repo = DefaultTaskRepository(api: api)
        let vm = TaskListViewModel(repository: repo)
        await vm.load()

        let deleting = Task { await vm.delete(a) }
        while vm.recentlyDeleted?.id != a.id { await Task.yield() }
        let undoing = Task { await vm.undoDelete() }
        let adding = Task { await vm.add(title: "C", notes: "", priority: .low) }
        while vm.recentlyDeleted != nil || !vm.tasks.contains(where: { $0.title == "C" }) { await Task.yield() }
        api.releaseDelete()
        _ = await (deleting.value, undoing.value, adding.value)

        let ids = vm.tasks.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(vm.tasks.contains { $0.id == a.id })
        let cachedIDs = try await repo.loadTasks(forceRefresh: false).map(\.id)
        #expect(Set(cachedIDs).count == cachedIDs.count)
        let reloaded = TaskListViewModel(repository: repo)
        await reloaded.load()
        let reloadedIDs = reloaded.tasks.map(\.id)
        #expect(Set(reloadedIDs).count == reloadedIDs.count)
    }
}

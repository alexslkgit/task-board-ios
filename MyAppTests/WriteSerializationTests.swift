import Foundation
import Testing
@testable import MyApp

/// Repository double: the Nth update call fails, reads return a snapshot taken at call time.
actor ScriptedRepository: TaskRepository {
    var tasks: [TaskItem]
    var failingUpdateCalls: Set<Int>
    let writeDelay: Duration
    let readDelay: Duration
    private var updateCalls = 0

    init(tasks: [TaskItem], failingUpdateCalls: Set<Int> = [],
         writeDelay: Duration = .milliseconds(50), readDelay: Duration = .milliseconds(50)) {
        self.tasks = tasks
        self.failingUpdateCalls = failingUpdateCalls
        self.writeDelay = writeDelay
        self.readDelay = readDelay
    }

    func loadTasks(forceRefresh: Bool) async throws -> [TaskItem] {
        let snapshot = tasks
        try await Task.sleep(for: readDelay)
        return snapshot
    }

    func add(_ task: TaskItem) async throws -> TaskItem {
        try await Task.sleep(for: writeDelay)
        tasks.append(task)
        return task
    }

    func update(_ task: TaskItem) async throws -> TaskItem {
        updateCalls += 1
        let call = updateCalls
        try await Task.sleep(for: writeDelay)
        if failingUpdateCalls.contains(call) { throw TaskAPIError.network }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task }
        return task
    }

    func delete(id: TaskItem.ID) async throws {
        try await Task.sleep(for: writeDelay)
        tasks.removeAll { $0.id == id }
    }
}

@MainActor
struct WriteSerializationTests {
    @Test func dismissUndoClearsOnlyMatchingId() async {
        let a = TaskItem(title: "A")
        let b = TaskItem(title: "B")
        let vm = TaskListViewModel(repository: StubTaskRepository(tasks: [a, b]))
        await vm.load()
        await vm.delete(a)
        await vm.delete(b)
        #expect(vm.recentlyDeleted?.id == b.id)
        vm.dismissUndo(for: a.id)
        #expect(vm.recentlyDeleted?.id == b.id)
        vm.dismissUndo(for: b.id)
        #expect(vm.recentlyDeleted == nil)
    }

    @Test func mockAPIWriteFailureRateOnlyAffectsWrites() async throws {
        let item = TaskItem(title: "A")
        let api = MockTaskAPI(seed: [item], readLatency: 0...0, writeLatency: 0...0,
                              failureRate: 0, writeFailureRate: 1)
        #expect(try await api.fetchTasks() == [item])
        await #expect(throws: TaskAPIError.self) { try await api.create(TaskItem(title: "B")) }
        await #expect(throws: TaskAPIError.self) { try await api.update(item) }
        await #expect(throws: TaskAPIError.self) { try await api.delete(id: item.id) }
    }

    @Test func toggleBurstWithFailingMiddleEndsAtLastIntent() async {
        let item = TaskItem(title: "A", isDone: false)
        let repo = ScriptedRepository(tasks: [item], failingUpdateCalls: [2])
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        async let t1: Void = vm.toggleDone(item)
        async let t2: Void = vm.toggleDone(item)
        async let t3: Void = vm.toggleDone(item)
        _ = await (t1, t2, t3)
        // Intents: true, false, true -> last intent is true.
        #expect(vm.task(id: item.id)?.isDone == true)
        #expect(vm.mutationError == nil)
        let stored = await repo.tasks.first { $0.id == item.id }
        #expect(stored?.isDone == vm.task(id: item.id)?.isDone)
    }

    @Test func refreshDuringWriteDoesNotLeaveStaleRow() async {
        let item = TaskItem(title: "A", isDone: false)
        // Read takes longer than the write, and returns the snapshot taken before the write landed.
        let repo = ScriptedRepository(tasks: [item], writeDelay: .milliseconds(30), readDelay: .milliseconds(150))
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        async let toggle: Void = vm.toggleDone(item)
        async let refresh: Void = vm.refresh()
        _ = await (toggle, refresh)
        let stored = await repo.tasks.first { $0.id == item.id }
        #expect(stored?.isDone == true)
        #expect(vm.task(id: item.id)?.isDone == true)
    }

    @Test func toggleRightAfterAddWhileCreateIsDelayed() async {
        let repo = ScriptedRepository(tasks: [], writeDelay: .milliseconds(80))
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        let adding = Task { await vm.add(title: "New", notes: "", priority: .medium) }
        await Task.yield()
        guard let draft = vm.tasks.first else {
            Issue.record("draft row was not inserted optimistically")
            return
        }
        await vm.toggleDone(draft)
        _ = await adding.value
        #expect(vm.mutationError == nil)
        #expect(vm.task(id: draft.id)?.isDone == true)
        let stored = await repo.tasks.first { $0.id == draft.id }
        #expect(stored?.isDone == vm.task(id: draft.id)?.isDone)
    }

    @Test func deleteWhileFailingUpdateInFlightRemovesRowWithoutError() async {
        let item = TaskItem(title: "A")
        let repo = ScriptedRepository(tasks: [item], failingUpdateCalls: [1], writeDelay: .milliseconds(80))
        let vm = TaskListViewModel(repository: repo)
        await vm.load()
        let toggling = Task { await vm.toggleDone(item) }
        await Task.yield()
        await vm.delete(item)
        _ = await toggling.value
        #expect(vm.task(id: item.id) == nil)
        #expect(vm.mutationError == nil)
        let stored = await repo.tasks.contains { $0.id == item.id }
        #expect(!stored)
    }
}

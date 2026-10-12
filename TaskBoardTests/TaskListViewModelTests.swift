import Foundation
import Testing
@testable import TaskBoard

@MainActor
struct TaskListViewModelTests {
    private func makeSeededRepository() -> DefaultTaskRepository {
        DefaultTaskRepository(api: MockTaskAPI(readLatency: 0...0, writeLatency: 0...0, failureRate: 0))
    }

    @Test func loadSuccessPopulatesSeedTasks() async {
        let vm = TaskListViewModel(repository: makeSeededRepository())
        await vm.load()
        #expect(vm.loadState == .loaded)
        #expect(vm.tasks.count == 4)
    }

    @Test func loadFailureSetsFailedState() async {
        let vm = TaskListViewModel(repository: StubTaskRepository(shouldFail: true))
        await vm.load()
        guard case .failed = vm.loadState else {
            Issue.record("expected .failed, got \(vm.loadState)")
            return
        }
        #expect(vm.tasks.isEmpty)
        #expect(!vm.isEmpty)
    }

    @Test func emptyRepositoryIsEmpty() async {
        let vm = TaskListViewModel(repository: StubTaskRepository())
        await vm.load()
        #expect(vm.loadState == .loaded)
        #expect(vm.isEmpty)
    }

    @Test func toggleFailureRollsBack() async {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(true)
        await vm.toggleDone(item)
        #expect(vm.task(id: item.id)?.isDone == false)
        #expect(vm.mutationError != nil)
    }

    @Test func addWithWhitespaceTitleIsIgnored() async {
        let stub = StubTaskRepository()
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await vm.add(title: "   \n ", notes: "", priority: .low)
        #expect(vm.tasks.isEmpty)
        #expect(await stub.tasks.isEmpty)
        #expect(vm.mutationError == nil)
    }

    @Test func deleteFailureReinsertsTask() async {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(true)
        await vm.delete(item)
        #expect(vm.tasks.map(\.id) == [item.id])
        #expect(vm.recentlyDeleted == nil)
        #expect(vm.mutationError != nil)
    }

    @Test func undoDeleteRestoresTask() async {
        let vm = TaskListViewModel(repository: makeSeededRepository())
        await vm.load()
        let item = vm.tasks[0]
        await vm.delete(item)
        #expect(vm.recentlyDeleted?.id == item.id)
        await vm.undoDelete()
        #expect(vm.tasks.contains { $0.id == item.id })
        #expect(vm.recentlyDeleted == nil)
    }

    @Test func failedAddReportsFailure() async {
        let vm = TaskListViewModel(repository: StubTaskRepository(shouldFail: true))
        let saved = await vm.add(title: "New", notes: "", priority: .high)
        #expect(saved == false)
        #expect(vm.tasks.isEmpty)
    }

    @Test func searchIsCaseInsensitiveAndPrioritySortPutsHighFirst() async {
        let low = TaskItem(title: "Buy milk", priority: .low, createdAt: Date(timeIntervalSince1970: 1))
        let high = TaskItem(title: "Pay rent", priority: .high, createdAt: Date(timeIntervalSince1970: 2))
        let vm = TaskListViewModel(repository: StubTaskRepository(tasks: [low, high]))
        await vm.load()

        vm.searchText = "MILK"
        #expect(vm.visibleTasks.map(\.id) == [low.id])

        vm.searchText = ""
        vm.sortOrder = .priority
        #expect(vm.visibleTasks.first?.id == high.id)
    }
}

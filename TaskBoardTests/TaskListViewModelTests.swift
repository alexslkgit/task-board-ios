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

    @Test func failedAddReportsFailureToCallerOnly() async {
        let vm = TaskListViewModel(repository: StubTaskRepository(shouldFail: true))
        let result = await vm.add(title: "New", notes: "", priority: .high)
        #expect(result == .failed(TaskAPIError.network.errorDescription ?? ""))
        #expect(vm.tasks.isEmpty)
        #expect(vm.mutationError == nil)
    }

    @Test func failedUpdateReportsFailureToCallerOnly() async {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(true)
        var edited = item
        edited.title = "Edited"

        let result = await vm.update(edited)

        #expect(result == .failed(TaskAPIError.network.errorDescription ?? ""))
        #expect(vm.task(id: item.id) == item)
        #expect(vm.mutationError == nil)
    }

    @Test func updateOfMissingRowFailsWithoutRecreatingIt() async {
        let stub = StubTaskRepository()
        let vm = TaskListViewModel(repository: stub)
        await vm.load()

        let result = await vm.update(TaskItem(title: "Ghost"))

        #expect(result == .failed(TaskAPIError.notFound.errorDescription ?? ""))
        #expect(vm.tasks.isEmpty)
        #expect(await stub.tasks.isEmpty)
    }

    @Test func repeatedIdenticalFailuresGetNewBannerIDs() async throws {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(true)

        await vm.toggleDone(item)
        let first = try #require(vm.mutationError)
        await vm.toggleDone(item)
        let second = try #require(vm.mutationError)

        #expect(first.message == second.message)
        #expect(first.id != second.id)
    }

    @Test func loadIsNoOpOnceLoaded() async {
        let first = TaskItem(title: "First")
        let stub = StubTaskRepository(tasks: [first])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setTasks([TaskItem(title: "Second")])

        await vm.load()

        #expect(vm.tasks == [first])
        #expect(vm.loadState == .loaded)
    }

    @Test func loadRetriesAfterFailure() async {
        let item = TaskItem(title: "A")
        let stub = StubTaskRepository(tasks: [item], shouldFail: true)
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        await stub.setShouldFail(false)

        await vm.load()

        #expect(vm.tasks == [item])
        #expect(vm.loadState == .loaded)
    }

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

    @Test func statusSortPutsOpenTasksFirstThenPriority() async {
        let doneHigh = TaskItem(title: "Done high", priority: .high, isDone: true, createdAt: Date(timeIntervalSince1970: 1))
        let openLow = TaskItem(title: "Open low", priority: .low, createdAt: Date(timeIntervalSince1970: 2))
        let openHigh = TaskItem(title: "Open high", priority: .high, createdAt: Date(timeIntervalSince1970: 3))
        let vm = TaskListViewModel(repository: StubTaskRepository(tasks: [doneHigh, openLow, openHigh]))
        await vm.load()

        vm.sortOrder = .status

        #expect(vm.visibleTasks.map(\.id) == [openHigh.id, openLow.id, doneHigh.id])
    }

    @Test func dueDateSortPutsEarliestFirstAndUndatedLast() async {
        let late = TaskItem(title: "Late", createdAt: Date(timeIntervalSince1970: 1), dueDate: Date(timeIntervalSince1970: 5000))
        let undatedOld = TaskItem(title: "Undated old", createdAt: Date(timeIntervalSince1970: 2))
        let early = TaskItem(title: "Early", createdAt: Date(timeIntervalSince1970: 3), dueDate: Date(timeIntervalSince1970: 1000))
        let undatedNew = TaskItem(title: "Undated new", createdAt: Date(timeIntervalSince1970: 4))
        let sameDayOlder = TaskItem(title: "Tie older", createdAt: Date(timeIntervalSince1970: 0), dueDate: Date(timeIntervalSince1970: 1000))
        let vm = TaskListViewModel(repository: StubTaskRepository(tasks: [late, undatedNew, early, undatedOld, sameDayOlder]))
        await vm.load()

        vm.sortOrder = .dueDate

        #expect(vm.visibleTasks.map(\.id) == [sameDayOlder.id, early.id, late.id, undatedOld.id, undatedNew.id])
    }

    @Test func refreshSuccessReplacesList() async {
        let old = TaskItem(title: "Old")
        let fresh = TaskItem(title: "Fresh")
        let stub = StubTaskRepository(tasks: [old])
        let vm = TaskListViewModel(repository: stub)
        await vm.load()

        await stub.setTasks([fresh])
        await vm.refresh()

        #expect(vm.tasks.map(\.id) == [fresh.id])
        #expect(vm.loadState == .loaded)
        #expect(vm.mutationError == nil)
    }

    @Test func editPersistsAcrossReload() async {
        let repository = makeSeededRepository()
        let vm = TaskListViewModel(repository: repository)
        await vm.load()
        var edited = vm.tasks[0]
        edited.title = "Edited title"
        edited.dueDate = Date(timeIntervalSince1970: 1_000)

        let result = await vm.update(edited)
        await vm.refresh()

        #expect(result == .saved)
        #expect(vm.task(id: edited.id) == edited)
        let reloaded = TaskListViewModel(repository: repository)
        await reloaded.load()
        #expect(reloaded.task(id: edited.id) == edited)
    }

    @Test func addStoresDueDate() async {
        let stub = StubTaskRepository()
        let vm = TaskListViewModel(repository: stub)
        await vm.load()
        let due = Date(timeIntervalSince1970: 2_000)

        let result = await vm.add(title: "Pay rent", notes: "", priority: .high, dueDate: due)

        #expect(result == .saved)
        #expect(vm.tasks.first?.dueDate == due)
        #expect(await stub.tasks.first?.dueDate == due)
    }
}

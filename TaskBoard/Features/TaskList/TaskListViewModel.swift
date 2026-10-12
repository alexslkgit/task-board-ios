import Foundation
import Observation
import os

@Observable
final class TaskListViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    enum SortOrder: String, CaseIterable, Identifiable {
        case created, priority, status, dueDate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .created: "Created"
            case .priority: "Priority"
            case .status: "Status"
            case .dueDate: "Due date"
            }
        }
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var loadState: LoadState = .idle
    var mutationError: String?
    var searchText = ""
    var sortOrder: SortOrder = .created
    private(set) var recentlyDeleted: TaskItem?

    private enum Constants {
        static let genericError = "Something went wrong. Please try again."
    }

    @ObservationIgnored private let repository: any TaskRepository
    @ObservationIgnored private let writes = SerialWriteQueue<TaskItem.ID>()
    /// Last server-acknowledged value of a task with writes in flight; a failed write rolls back to it.
    @ObservationIgnored private var confirmed: [TaskItem.ID: TaskItem] = [:]
    @ObservationIgnored private var mutationCount = 0
    @ObservationIgnored private var lastMutation: [TaskItem.ID: Int] = [:]

    init(repository: any TaskRepository) {
        self.repository = repository
    }

    var visibleTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? tasks : tasks.filter { $0.title.localizedStandardContains(query) }
        return filtered.sorted(by: areInOrder)
    }

    var isEmpty: Bool { loadState == .loaded && tasks.isEmpty }

    func load() async {
        guard loadState != .loading else { return }
        loadState = .loading
        let start = mutationCount
        Logger.tasks.info("load started")
        do {
            let fetched = try await repository.loadTasks(forceRefresh: false)
            adopt(fetched, startedAt: start)
            loadState = .loaded
            Logger.tasks.info("load succeeded, count=\(fetched.count, privacy: .public)")
        } catch {
            if error is CancellationError {
                loadState = .idle
                Logger.tasks.info("load cancelled, no error shown")
            } else {
                loadState = .failed(message(for: error))
                Logger.tasks.error("load failed, shown as full-screen error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func refresh() async {
        let start = mutationCount
        Logger.tasks.info("refresh started")
        do {
            let fetched = try await repository.loadTasks(forceRefresh: true)
            adopt(fetched, startedAt: start)
            loadState = .loaded
            Logger.tasks.info("refresh succeeded, count=\(fetched.count, privacy: .public)")
        } catch {
            // Keep the list on screen; a banner is less destructive than an error page.
            if tasks.isEmpty {
                if error is CancellationError {
                    Logger.tasks.info("refresh cancelled on empty list, no error shown")
                } else {
                    loadState = .failed(message(for: error))
                    Logger.tasks.error("refresh failed, shown as full-screen error: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                Logger.tasks.error("refresh failed, shown as banner: \(error.localizedDescription, privacy: .public)")
                showBanner(for: error)
            }
        }
    }

    @discardableResult
    func add(title: String, notes: String, priority: Priority, dueDate: Date? = nil) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.tasks.debug("add ignored, empty title")
            return false
        }
        let draft = TaskItem(title: trimmed, notes: notes, priority: priority, dueDate: dueDate)
        noteMutation(draft.id)
        tasks.append(draft)
        Logger.tasks.debug("add applied optimistically id=\(draft.id.uuidString, privacy: .public) title=\(draft.title, privacy: .private)")
        let repository = repository
        let addResult = await writes.run(draft.id, { try await repository.add(draft) })
        noteMutation(draft.id)  // settling during a fetch makes that fetch's snapshot stale for this row
        switch addResult {
        case .success(let saved):
            if writes.hasPending(saved.id) {
                confirmed[saved.id] = saved  // a queued write owns the row now; keep its optimistic value
            } else {
                confirmed[saved.id] = nil
                replace(saved)
            }
            Logger.tasks.info("add succeeded id=\(saved.id.uuidString, privacy: .public)")
            return true
        case .failure(let error):
            if !writes.hasPending(draft.id) { confirmed[draft.id] = nil }
            tasks.removeAll { $0.id == draft.id }
            Logger.tasks.error("add failed id=\(draft.id.uuidString, privacy: .public), draft removed: \(error.localizedDescription, privacy: .public)")
            showBanner(for: error)
            return false
        }
    }

    @discardableResult
    func update(_ task: TaskItem) async -> Bool {
        guard let current = self.task(id: task.id) else {
            Logger.tasks.info("update ignored, row gone id=\(task.id.uuidString, privacy: .public)")
            return false
        }
        noteMutation(task.id)
        if !writes.hasPending(task.id) { confirmed[task.id] = current }
        replace(task)
        Logger.tasks.debug("update applied optimistically id=\(task.id.uuidString, privacy: .public) isDone=\(task.isDone, privacy: .public) title=\(task.title, privacy: .private)")

        let repository = repository
        let result = await writes.run(task.id) { try await repository.update(task) }
        noteMutation(task.id)
        if case .success(let saved) = result { confirmed[task.id] = saved }
        // The newest write carries the whole task, so it alone settles the row and reports the outcome.
        // run() has already released our slot, so true here means a newer write is queued behind us.
        if writes.hasPending(task.id) {
            Logger.tasks.debug("update superseded id=\(task.id.uuidString, privacy: .public)")
            return true
        }
        let settled = confirmed.removeValue(forKey: task.id)
        if let settled { replace(settled) }
        switch result {
        case .success:
            Logger.tasks.info("update succeeded id=\(task.id.uuidString, privacy: .public)")
            return true
        case .failure(let error):
            // The failed add/delete that removed the row already reported the real error.
            if self.task(id: task.id) == nil {
                Logger.tasks.info("update failed but row gone, error suppressed id=\(task.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
            let target = settled.map { "isDone=\($0.isDone)" } ?? "unchanged"
            Logger.tasks.error("update failed id=\(task.id.uuidString, privacy: .public), rolled back to \(target, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showBanner(for: error)
            return false
        }
    }

    func toggleDone(_ task: TaskItem) async {
        var updated = self.task(id: task.id) ?? task
        updated.isDone.toggle()
        await update(updated)
    }

    func delete(_ task: TaskItem) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            Logger.tasks.info("delete ignored, row gone id=\(task.id.uuidString, privacy: .public)")
            return
        }
        noteMutation(task.id)
        let removed = tasks.remove(at: index)
        recentlyDeleted = removed
        Logger.tasks.debug("delete applied optimistically id=\(removed.id.uuidString, privacy: .public) title=\(removed.title, privacy: .private)")
        let repository = repository
        let deleteResult = await writes.run(removed.id, { try await repository.delete(id: removed.id) })
        noteMutation(removed.id)
        switch deleteResult {
        case .success:
            confirmed[removed.id] = nil
            Logger.tasks.info("delete succeeded id=\(removed.id.uuidString, privacy: .public)")
        case .failure(let error):
            let baseline = confirmed.removeValue(forKey: removed.id) ?? removed
            if self.task(id: removed.id) == nil {
                tasks.insert(baseline, at: min(index, tasks.count))
            }
            if recentlyDeleted?.id == removed.id { recentlyDeleted = nil }
            Logger.tasks.error("delete failed id=\(removed.id.uuidString, privacy: .public), reinserted at index \(index, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showBanner(for: error)
        }
    }

    func undoDelete() async {
        guard let item = recentlyDeleted else {
            Logger.tasks.debug("undo ignored, nothing to restore")
            return
        }
        recentlyDeleted = nil
        noteMutation(item.id)
        Logger.tasks.debug("undo started id=\(item.id.uuidString, privacy: .public)")
        let repository = repository
        let undoResult = await writes.run(item.id, { try await repository.add(item) })
        noteMutation(item.id)
        switch undoResult {
        case .success(let restored):
            if self.task(id: restored.id) == nil { tasks.append(restored) }
            Logger.tasks.info("undo succeeded id=\(restored.id.uuidString, privacy: .public)")
        case .failure(let error):
            recentlyDeleted = item
            Logger.tasks.error("undo failed id=\(item.id.uuidString, privacy: .public), kept for retry: \(error.localizedDescription, privacy: .public)")
            showBanner(for: error)
        }
    }

    func dismissUndo(for id: TaskItem.ID) {
        guard recentlyDeleted?.id == id else { return }
        recentlyDeleted = nil
        Logger.tasks.debug("undo dismissed id=\(id.uuidString, privacy: .public)")
    }

    func task(id: TaskItem.ID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    // A fetch can return a snapshot older than a write that settled meanwhile, so local state wins for rows touched since it started.
    private func adopt(_ fetched: [TaskItem], startedAt start: Int) {
        func localWins(_ id: TaskItem.ID) -> Bool {
            writes.hasPending(id) || lastMutation[id, default: 0] > start
        }
        let fetchedIDs = Set(fetched.map(\.id))
        var merged: [TaskItem] = []
        for item in fetched {
            guard localWins(item.id) else { merged.append(item); continue }
            if writes.hasPending(item.id) { confirmed[item.id] = item }
            if let current = task(id: item.id) { merged.append(current) }
        }
        merged += tasks.filter { localWins($0.id) && !fetchedIDs.contains($0.id) }
        let kept = merged.count - fetched.filter { !localWins($0.id) }.count
        if kept > 0 { Logger.tasks.debug("adopt kept \(kept, privacy: .public) local rows over fetched snapshot") }
        tasks = merged
    }

    private func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? Constants.genericError
    }

    private func showBanner(for error: any Error) {
        guard !(error is CancellationError) else {
            Logger.tasks.info("cancellation, no banner")
            return
        }
        mutationError = message(for: error)
    }

    private func noteMutation(_ id: TaskItem.ID) {
        mutationCount += 1
        lastMutation[id] = mutationCount
    }

    // Looked up by id each time: other mutations may have shifted indices while a request was in flight.
    private func replace(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    private func areInOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch sortOrder {
        case .created:
            break
        case .priority:
            if a.priority != b.priority { return a.priority > b.priority }
        case .status:
            if a.isDone != b.isDone { return !a.isDone }
            if a.priority != b.priority { return a.priority > b.priority }
        case .dueDate:
            switch (a.dueDate, b.dueDate) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
        }
        return a.createdAt < b.createdAt
    }
}

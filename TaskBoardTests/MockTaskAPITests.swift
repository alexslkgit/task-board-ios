import Foundation
import Testing
@testable import TaskBoard

struct MockTaskAPITests {
    private enum Constants {
        static let readLatency = 0.05...0.1
        static let schedulingSlack = 0.5
        static let repetitions = 50
    }

    private func makeAPI(failureRate: Double, writeFailureRate: Double? = nil, seed: [TaskItem] = [TaskItem(title: "A")]) -> MockTaskAPI {
        MockTaskAPI(seed: seed, readLatency: 0...0, writeLatency: 0...0, failureRate: failureRate, writeFailureRate: writeFailureRate)
    }

    @Test func failureRateOneAlwaysThrowsNetwork() async {
        let item = TaskItem(title: "A")
        let api = makeAPI(failureRate: 1, seed: [item])
        for _ in 0..<Constants.repetitions {
            await #expect(throws: TaskAPIError.network) { try await api.fetchTasks() }
        }
        await #expect(throws: TaskAPIError.network) { try await api.create(TaskItem(title: "B")) }
        await #expect(throws: TaskAPIError.network) { try await api.update(item) }
        await #expect(throws: TaskAPIError.network) { try await api.delete(id: item.id) }
    }

    @Test func failureRateZeroNeverThrows() async throws {
        let item = TaskItem(title: "A")
        let api = makeAPI(failureRate: 0, seed: [item])
        for _ in 0..<Constants.repetitions {
            _ = try await api.fetchTasks()
            _ = try await api.update(item)
        }
    }

    @Test func readLatencyStaysWithinConfiguredRange() async throws {
        let api = MockTaskAPI(readLatency: Constants.readLatency, writeLatency: 0...0, failureRate: 0)
        let clock = ContinuousClock()

        let elapsed = try await clock.measure { _ = try await api.fetchTasks() }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        #expect(seconds >= Constants.readLatency.lowerBound)
        #expect(seconds <= Constants.readLatency.upperBound + Constants.schedulingSlack)
    }

    @Test func updateAndDeleteOfUnknownIdThrowNotFound() async {
        let api = makeAPI(failureRate: 0)
        let ghost = TaskItem(title: "Ghost")
        await #expect(throws: TaskAPIError.notFound) { try await api.update(ghost) }
        await #expect(throws: TaskAPIError.notFound) { try await api.delete(id: ghost.id) }
    }

    @Test func createIsIdempotentById() async throws {
        let api = makeAPI(failureRate: 0, seed: [])
        var item = TaskItem(title: "First")
        _ = try await api.create(item)
        item.title = "Second"
        _ = try await api.create(item)

        let stored = try await api.fetchTasks()
        #expect(stored.map(\.id) == [item.id])
        #expect(stored.first?.title == "Second")
    }

    @Test func writeFailureRateOverrideAppliesToWritesOnly() async throws {
        let item = TaskItem(title: "A")
        let writesFail = makeAPI(failureRate: 0, writeFailureRate: 1, seed: [item])
        _ = try await writesFail.fetchTasks()
        await #expect(throws: TaskAPIError.network) { try await writesFail.create(TaskItem(title: "B")) }
        await #expect(throws: TaskAPIError.network) { try await writesFail.update(item) }
        await #expect(throws: TaskAPIError.network) { try await writesFail.delete(id: item.id) }

        let readsFail = makeAPI(failureRate: 1, writeFailureRate: 0, seed: [item])
        await #expect(throws: TaskAPIError.network) { try await readsFail.fetchTasks() }
        _ = try await readsFail.create(TaskItem(title: "B"))
        _ = try await readsFail.update(item)
        try await readsFail.delete(id: item.id)
    }
}

struct SeedTests {
    @Test func seedMatchesSpec() {
        let seed = TaskItem.seed
        #expect(seed.count == 4)
        #expect(seed.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(seed.allSatisfy { $0.createdAt < .now })
        #expect(Set(seed.map(\.id)).count == seed.count)
        #expect(seed.filter { $0.dueDate != nil }.count == 2)
    }
}

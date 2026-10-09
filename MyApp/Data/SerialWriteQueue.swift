import Foundation

/// Runs async operations that share a key one after another, in submission order.
final class SerialWriteQueue<Key: Hashable> {
    private var tails: [Key: Task<Void, Never>] = [:]
    private var counts: [Key: Int] = [:]

    func run<T: Sendable>(
        _ key: Key,
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        let previous = tails[key]
        counts[key, default: 0] += 1
        let task = Task { () -> Result<T, any Error> in
            await previous?.value
            do { return .success(try await operation()) } catch { return .failure(error) }
        }
        tails[key] = Task { _ = await task.value }
        let result = await task.value
        // Decrement only after this caller resumed, so earlier callers still see later ones as pending.
        let remaining = counts[key, default: 1] - 1
        if remaining == 0 {
            counts[key] = nil
            tails[key] = nil
        } else {
            counts[key] = remaining
        }
        return result
    }

    func hasPending(_ key: Key) -> Bool { counts[key] != nil }
}

import Foundation
import os

/// Launch arguments make error, empty and slow states reproducible,
/// e.g. `-mockFailureRate 1`, `-mockWriteFailureRate 1`, `-mockEmpty YES`, `-mockLatency 3`.
struct LaunchConfiguration {
    let failureRate: Double
    let writeFailureRate: Double?
    let isEmpty: Bool
    let latency: Double?

    static func current(from defaults: UserDefaults = .standard) -> LaunchConfiguration {
        LaunchConfiguration(
            failureRate: defaults.object(forKey: LaunchArgument.failureRate) != nil
                ? defaults.double(forKey: LaunchArgument.failureRate)
                : MockTaskAPI.defaultFailureRate,
            writeFailureRate: defaults.object(forKey: LaunchArgument.writeFailureRate) != nil
                ? defaults.double(forKey: LaunchArgument.writeFailureRate)
                : nil,
            isEmpty: defaults.bool(forKey: LaunchArgument.empty),
            latency: defaults.object(forKey: LaunchArgument.latency) != nil
                ? defaults.double(forKey: LaunchArgument.latency)
                : nil
        )
    }

    func makeAPI() -> MockTaskAPI {
        let seed = isEmpty ? [] : TaskItem.seed

        Logger.network.info("""
            mock config failureRate=\(failureRate, privacy: .public) \
            writeFailureRate=\(writeFailureRate.map { String($0) } ?? "same", privacy: .public) \
            empty=\(isEmpty, privacy: .public) \
            latency=\(latency.map { String($0) } ?? "default", privacy: .public)
            """)

        guard let latency else {
            return MockTaskAPI(seed: seed, failureRate: failureRate, writeFailureRate: writeFailureRate)
        }
        return MockTaskAPI(
            seed: seed,
            readLatency: latency...latency,
            writeLatency: latency...latency,
            failureRate: failureRate,
            writeFailureRate: writeFailureRate
        )
    }

    private enum LaunchArgument {
        static let failureRate = "mockFailureRate"
        static let writeFailureRate = "mockWriteFailureRate"
        static let empty = "mockEmpty"
        static let latency = "mockLatency"
    }
}

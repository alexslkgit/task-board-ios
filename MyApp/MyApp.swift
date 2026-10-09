import SwiftUI
import os

@main struct MyApp: App {
    @State private var viewModel = TaskListViewModel(repository: DefaultTaskRepository(api: MyApp.makeAPI()))

    var body: some Scene {
        WindowGroup {
            TaskListView(viewModel: viewModel)
        }
    }

    private enum LaunchArgument {
        static let failureRate = "mockFailureRate"
        static let writeFailureRate = "mockWriteFailureRate"
        static let empty = "mockEmpty"
        static let latency = "mockLatency"
    }

    /// Launch arguments make error, empty and slow states reproducible,
    /// e.g. `-mockFailureRate 1`, `-mockWriteFailureRate 1`, `-mockEmpty YES`, `-mockLatency 3`.
    private static func makeAPI() -> MockTaskAPI {
        let defaults = UserDefaults.standard
        let failureRate = defaults.object(forKey: LaunchArgument.failureRate) != nil
            ? defaults.double(forKey: LaunchArgument.failureRate)
            : MockTaskAPI.defaultFailureRate
        let writeFailureRate = defaults.object(forKey: LaunchArgument.writeFailureRate) != nil
            ? defaults.double(forKey: LaunchArgument.writeFailureRate)
            : nil
        let isEmpty = defaults.bool(forKey: LaunchArgument.empty)
        let seed = isEmpty ? [] : TaskItem.seed
        let latency = defaults.object(forKey: LaunchArgument.latency) != nil ? defaults.double(forKey: LaunchArgument.latency) : nil

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
}

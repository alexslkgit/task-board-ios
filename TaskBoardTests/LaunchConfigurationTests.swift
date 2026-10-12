import Foundation
import Testing
@testable import TaskBoard

struct LaunchConfigurationTests {
    // Launch arguments reach UserDefaults as strings, so the suite is filled the same way.
    private func configuration(_ arguments: [String: String]) -> LaunchConfiguration {
        let suiteName = "LaunchConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for (key, value) in arguments { defaults.set(value, forKey: key) }
        return LaunchConfiguration.current(from: defaults)
    }

    @Test func missingArgumentsFallBackToDefaults() {
        let config = configuration([:])
        #expect(config.failureRate == MockTaskAPI.defaultFailureRate)
        #expect(config.writeFailureRate == nil)
        #expect(config.isEmpty == false)
        #expect(config.latency == nil)
    }

    @Test func argumentsAreParsed() {
        let config = configuration([
            "mockFailureRate": "1",
            "mockWriteFailureRate": "0.5",
            "mockEmpty": "YES",
            "mockLatency": "3",
        ])
        #expect(config.failureRate == 1)
        #expect(config.writeFailureRate == 0.5)
        #expect(config.isEmpty)
        #expect(config.latency == 3)
    }

    @Test func explicitZeroIsNotTreatedAsMissing() {
        let config = configuration(["mockFailureRate": "0", "mockWriteFailureRate": "0", "mockLatency": "0"])
        #expect(config.failureRate == 0)
        #expect(config.writeFailureRate == 0)
        #expect(config.latency == 0)
    }
}

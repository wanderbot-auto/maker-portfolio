import Foundation
import Testing
import MakerInfrastructure

@Test
func launchdManagerWritesExpectedPlist() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
    let launchAgents = root.appendingPathComponent("LaunchAgents", isDirectory: true)
    let paths = AppPaths(applicationSupportDirectory: appSupport, launchAgentsDirectory: launchAgents)
    let manager = LaunchdDaemonManager(paths: paths)
    let executableURL = root.appendingPathComponent("maker")

    try manager.install(executableURL: executableURL)

    let data = try Data(contentsOf: paths.daemonLaunchAgentURL)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

    #expect(plist?["Label"] as? String == AppPaths.daemonLaunchAgentLabel)
    #expect(plist?["ProgramArguments"] as? [String] == [executableURL.path, "daemon", "run"])
    #expect(plist?["RunAtLoad"] as? Bool == true)
    #expect(plist?["KeepAlive"] as? Bool == true)
    #expect(plist?["StandardOutPath"] == nil)
    #expect(plist?["StandardErrorPath"] == nil)
}

@Test
func launchdManagerStartBootstrapsAndKickstartsService() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
    let launchAgents = root.appendingPathComponent("LaunchAgents", isDirectory: true)
    let paths = AppPaths(applicationSupportDirectory: appSupport, launchAgentsDirectory: launchAgents)
    let runner = FakeLaunchctlRunner(results: [
        LaunchctlCommandResult(exitCode: 0, standardOutput: "", standardError: ""),
        LaunchctlCommandResult(exitCode: 0, standardOutput: "", standardError: ""),
        LaunchctlCommandResult(exitCode: 0, standardOutput: "", standardError: "")
    ])
    let manager = LaunchdDaemonManager(paths: paths, runner: runner, userID: 501)
    let executableURL = root.appendingPathComponent("maker")

    try manager.start(executableURL: executableURL)

    #expect(runner.receivedArguments == [
        ["bootstrap", "gui/501", paths.daemonLaunchAgentURL.path],
        ["enable", "gui/501/\(AppPaths.daemonLaunchAgentLabel)"],
        ["kickstart", "-k", "gui/501/\(AppPaths.daemonLaunchAgentLabel)"]
    ])
}

@Test
func launchdManagerStopIgnoresMissingService() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
    let launchAgents = root.appendingPathComponent("LaunchAgents", isDirectory: true)
    let paths = AppPaths(applicationSupportDirectory: appSupport, launchAgentsDirectory: launchAgents)
    let runner = FakeLaunchctlRunner(results: [
        LaunchctlCommandResult(exitCode: 3, standardOutput: "", standardError: "Could not find service")
    ])
    let manager = LaunchdDaemonManager(paths: paths, runner: runner, userID: 501)

    try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
    try Data("plist".utf8).write(to: paths.daemonLaunchAgentURL)

    try manager.stop()

    #expect(runner.receivedArguments == [
        ["print", "gui/501/\(AppPaths.daemonLaunchAgentLabel)"]
    ])
}

private final class FakeLaunchctlRunner: LaunchctlCommandRunning, @unchecked Sendable {
    var results: [LaunchctlCommandResult]
    var receivedArguments: [[String]] = []

    init(results: [LaunchctlCommandResult]) {
        self.results = results
    }

    func run(arguments: [String]) throws -> LaunchctlCommandResult {
        receivedArguments.append(arguments)
        if results.isEmpty {
            return LaunchctlCommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        return results.removeFirst()
    }
}

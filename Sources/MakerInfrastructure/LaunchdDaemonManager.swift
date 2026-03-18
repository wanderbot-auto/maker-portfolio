import Darwin
import Foundation

public struct LaunchctlCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public protocol LaunchctlCommandRunning: Sendable {
    func run(arguments: [String]) throws -> LaunchctlCommandResult
}

public struct ProcessLaunchctlCommandRunner: LaunchctlCommandRunning {
    public let launchctlURL: URL

    public init(launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl")) {
        self.launchctlURL = launchctlURL
    }

    public func run(arguments: [String]) throws -> LaunchctlCommandResult {
        let process = Process()
        process.executableURL = launchctlURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return LaunchctlCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            standardError: String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public struct LaunchdDaemonStatus: Sendable, Equatable {
    public let installed: Bool
    public let loaded: Bool
    public let details: String

    public init(installed: Bool, loaded: Bool, details: String) {
        self.installed = installed
        self.loaded = loaded
        self.details = details
    }
}

public enum LaunchdDaemonError: LocalizedError {
    case commandFailed(arguments: [String], output: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, output):
            let renderedOutput = output.isEmpty ? "无输出" : output
            return "launchctl \(arguments.joined(separator: " ")) 失败: \(renderedOutput)"
        }
    }
}

public struct LaunchdDaemonManager {
    public let paths: AppPaths
    public let fileManager: FileManager
    public let runner: any LaunchctlCommandRunning
    public let userID: uid_t

    public init(
        paths: AppPaths = AppPaths(),
        fileManager: FileManager = .default,
        runner: any LaunchctlCommandRunning = ProcessLaunchctlCommandRunner(),
        userID: uid_t = getuid()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.runner = runner
        self.userID = userID
    }

    public var label: String {
        AppPaths.daemonLaunchAgentLabel
    }

    public var bootstrapDomain: String {
        "gui/\(userID)"
    }

    public var serviceTarget: String {
        "\(bootstrapDomain)/\(label)"
    }

    public func install(executableURL: URL) throws {
        try paths.createIfNeeded(fileManager: fileManager)
        try fileManager.createDirectory(at: paths.launchAgentsDirectory, withIntermediateDirectories: true)

        let data = try plistData(executableURL: executableURL)
        if fileManager.fileExists(atPath: paths.daemonLaunchAgentURL.path),
           let existing = try? Data(contentsOf: paths.daemonLaunchAgentURL),
           existing == data {
            return
        }

        try data.write(to: paths.daemonLaunchAgentURL, options: .atomic)
    }

    public func start(executableURL: URL) throws {
        try install(executableURL: executableURL)

        let bootstrapResult = try runner.run(arguments: ["bootstrap", bootstrapDomain, paths.daemonLaunchAgentURL.path])
        if bootstrapResult.exitCode != 0, !isAlreadyBootstrapped(bootstrapResult.combinedOutput) {
            throw LaunchdDaemonError.commandFailed(
                arguments: ["bootstrap", bootstrapDomain, paths.daemonLaunchAgentURL.path],
                output: bootstrapResult.combinedOutput
            )
        }

        try runRequired(["enable", serviceTarget])
        try runRequired(["kickstart", "-k", serviceTarget])
    }

    public func stop() throws {
        guard fileManager.fileExists(atPath: paths.daemonLaunchAgentURL.path) else {
            return
        }
        let currentStatus = try status()
        guard currentStatus.loaded else {
            return
        }

        let result = try runner.run(arguments: ["bootout", bootstrapDomain, paths.daemonLaunchAgentURL.path])
        if result.exitCode != 0, !isAlreadyStopped(result.combinedOutput) {
            throw LaunchdDaemonError.commandFailed(
                arguments: ["bootout", bootstrapDomain, paths.daemonLaunchAgentURL.path],
                output: result.combinedOutput
            )
        }
    }

    public func uninstall() throws {
        try stop()
        guard fileManager.fileExists(atPath: paths.daemonLaunchAgentURL.path) else {
            return
        }
        try fileManager.removeItem(at: paths.daemonLaunchAgentURL)
    }

    public func status() throws -> LaunchdDaemonStatus {
        let installed = fileManager.fileExists(atPath: paths.daemonLaunchAgentURL.path)
        guard installed else {
            return LaunchdDaemonStatus(installed: false, loaded: false, details: "")
        }

        let result = try runner.run(arguments: ["print", serviceTarget])
        return LaunchdDaemonStatus(
            installed: true,
            loaded: result.exitCode == 0,
            details: result.combinedOutput
        )
    }

    public func plistContents(executableURL: URL) throws -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executableURL.path, "daemon", "run"],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
    }

    private func plistData(executableURL: URL) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: try plistContents(executableURL: executableURL),
            format: .xml,
            options: 0
        )
    }

    private func runRequired(_ arguments: [String]) throws {
        let result = try runner.run(arguments: arguments)
        guard result.exitCode == 0 else {
            throw LaunchdDaemonError.commandFailed(arguments: arguments, output: result.combinedOutput)
        }
    }

    private func isAlreadyBootstrapped(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("service already loaded")
            || lowered.contains("already loaded")
            || lowered.contains("already bootstrapped")
    }

    private func isAlreadyStopped(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("could not find service")
            || lowered.contains("no such process")
            || lowered.contains("service not found")
    }
}

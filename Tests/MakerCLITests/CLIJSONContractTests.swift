import Foundation
import Testing
import MakerInfrastructure

@Test
func milestoneCommandsPreserveJSONContract() throws {
    let sandbox = try makeCLISandbox()
    defer { try? FileManager.default.removeItem(at: sandbox.root) }

    let projectAdd = try runMaker(
        ["project", "add", sandbox.packageRoot.path, "--json"],
        environment: sandbox.environment
    )
    let projectEnvelope = try decodeEnvelope(ProjectAddPayload.self, from: projectAdd)

    let milestoneAdd = try runMaker(
        ["milestone", "add", projectEnvelope.data.project.id, "CLI JSON milestone", "--due", "2026-04-01", "--json"],
        environment: sandbox.environment
    )
    let createdEnvelope = try decodeEnvelope(MilestonePayload.self, from: milestoneAdd)
    #expect(createdEnvelope.message == "milestone_created")
    #expect(createdEnvelope.data.title == "CLI JSON milestone")
    #expect(createdEnvelope.data.state == "notStarted")
    #expect(createdEnvelope.data.dueDate?.ISO8601Format() == "2026-04-01T00:00:00Z")

    let milestoneList = try runMaker(
        ["milestone", "list", projectEnvelope.data.project.id, "--json"],
        environment: sandbox.environment
    )
    let listEnvelope = try decodeEnvelope([MilestonePayload].self, from: milestoneList)
    #expect(listEnvelope.message == "milestones_listed")
    #expect(listEnvelope.data.count == 1)
    #expect(listEnvelope.data.first?.id == createdEnvelope.data.id)

    let milestoneState = try runMaker(
        ["milestone", "state", createdEnvelope.data.id, "completed", "--json"],
        environment: sandbox.environment
    )
    let stateEnvelope = try decodeEnvelope(MilestonePayload.self, from: milestoneState)
    #expect(stateEnvelope.message == "milestone_state_updated")
    #expect(stateEnvelope.data.state == "completed")

    let milestoneEdit = try runMaker(
        ["milestone", "edit", createdEnvelope.data.id, "--title", "Renamed milestone", "--due", "none", "--json"],
        environment: sandbox.environment
    )
    let editEnvelope = try decodeEnvelope(MilestonePayload.self, from: milestoneEdit)
    #expect(editEnvelope.message == "milestone_updated")
    #expect(editEnvelope.data.title == "Renamed milestone")
    #expect(editEnvelope.data.dueDate == nil)

    let milestoneRemove = try runMaker(
        ["milestone", "remove", createdEnvelope.data.id, "--json"],
        environment: sandbox.environment
    )
    let removeEnvelope = try decodeEnvelope(IdentifierPayload.self, from: milestoneRemove)
    #expect(removeEnvelope.message == "milestone_deleted")
    #expect(removeEnvelope.data.id == createdEnvelope.data.id)
}

@Test
func daemonStatusPreservesJSONContract() throws {
    let sandbox = try makeCLISandbox()
    defer { try? FileManager.default.removeItem(at: sandbox.root) }

    let result = try runMaker(["daemon", "status", "--json"], environment: sandbox.environment)
    let envelope = try decodeEnvelope(DaemonStatusPayload.self, from: result)

    #expect(envelope.message == "daemon_status")
    #expect(envelope.data.installed == false)
    #expect(envelope.data.loaded == false)
    #expect(envelope.data.responding == false)
    #expect(envelope.data.serviceTarget.contains(AppPaths.daemonLaunchAgentLabel))
    #expect(envelope.data.launchAgent.hasSuffix("\(AppPaths.daemonLaunchAgentLabel).plist"))
    #expect(envelope.data.daemonToken.hasSuffix("daemon.token"))
}

private struct CLISandbox {
    let root: URL
    let packageRoot: URL
    let environment: [String: String]
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private struct CLIEnvelope<T: Decodable>: Decodable {
    let message: String
    let data: T
}

private struct ProjectAddPayload: Decodable {
    let project: ProjectPayload
}

private struct ProjectPayload: Decodable {
    let id: String
}

private struct MilestonePayload: Decodable {
    let id: String
    let projectID: String
    let title: String
    let dueDate: Date?
    let state: String
}

private struct IdentifierPayload: Decodable {
    let id: String
}

private struct DaemonStatusPayload: Decodable {
    let installed: Bool
    let loaded: Bool
    let responding: Bool
    let serviceTarget: String
    let launchAgent: String
    let daemonToken: String
    let details: String
}

private enum CLITestError: Error, CustomStringConvertible {
    case executableNotFound
    case commandFailed(args: [String], exitCode: Int32, stdout: String, stderr: String)

    var description: String {
        switch self {
        case .executableNotFound:
            return "Could not locate built maker executable."
        case let .commandFailed(args, exitCode, stdout, stderr):
            return """
            Command failed: maker \(args.joined(separator: " "))
            exitCode: \(exitCode)
            stdout:
            \(stdout)
            stderr:
            \(stderr)
            """
        }
    }
}

private func makeCLISandbox() throws -> CLISandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
    let launchAgents = root.appendingPathComponent("LaunchAgents", isDirectory: true)
    try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

    return CLISandbox(
        root: root,
        packageRoot: packageRootURL(),
        environment: [
            AppPaths.applicationSupportOverrideEnv: appSupport.path,
            AppPaths.launchAgentsOverrideEnv: launchAgents.path
        ]
    )
}

private func runMaker(_ arguments: [String], environment: [String: String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = try makerExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = packageRootURL()
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutText = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let result = CommandResult(exitCode: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
    guard result.exitCode == 0 else {
        throw CLITestError.commandFailed(args: arguments, exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    }
    return result
}

private func decodeEnvelope<T: Decodable>(_ type: T.Type, from result: CommandResult) throws -> CLIEnvelope<T> {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(CLIEnvelope<T>.self, from: Data(result.stdout.utf8))
}

private func makerExecutableURL() throws -> URL {
    let packageRoot = packageRootURL()
    let direct = packageRoot.appendingPathComponent(".build/debug/maker")
    if FileManager.default.isExecutableFile(atPath: direct.path) {
        return direct
    }

    let buildDirectory = packageRoot.appendingPathComponent(".build", isDirectory: true)
    if let enumerator = FileManager.default.enumerator(at: buildDirectory, includingPropertiesForKeys: nil) {
        for case let candidate as URL in enumerator where candidate.lastPathComponent == "maker" {
            if candidate.path.contains("/debug/"), FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
    }

    throw CLITestError.executableNotFound
}

private func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

import Foundation
import MakerDomain
import MakerSupport

public struct ProjectScanResult: Sendable, Equatable, Codable {
    public var suggestedName: String
    public var repoType: RepoType
    public var stackSummary: String
    public var readmeSnippet: String?
    public var discoveredProfiles: [DiscoveredRuntimeProfile]

    public init(
        suggestedName: String,
        repoType: RepoType,
        stackSummary: String,
        readmeSnippet: String? = nil,
        discoveredProfiles: [DiscoveredRuntimeProfile] = []
    ) {
        self.suggestedName = suggestedName
        self.repoType = repoType
        self.stackSummary = stackSummary
        self.readmeSnippet = readmeSnippet
        self.discoveredProfiles = discoveredProfiles
    }
}

public struct DiscoveredRuntimeProfile: Sendable, Equatable, Codable {
    public var name: String
    public var entryCommand: String
    public var workingDir: String
    public var args: [String]

    public init(name: String, entryCommand: String, workingDir: String, args: [String] = []) {
        self.name = name
        self.entryCommand = entryCommand
        self.workingDir = workingDir
        self.args = args
    }
}

public protocol ProjectScanner: Sendable {
    func scan(at path: String) async throws -> ProjectScanResult
}

public protocol SecretsStore: Sendable {
    func save(values: [String: String], for envSetID: EnvSet.ID) async throws
    func load(for envSetID: EnvSet.ID) async throws -> [String: String]
    func delete(for envSetID: EnvSet.ID) async throws
}

public protocol RuntimeManager: Sendable {
    func start(project: Project, profile: RuntimeProfile) async throws -> RunSession
    func stop(sessionID: RunSession.ID) async throws
    func restart(sessionID: RunSession.ID) async throws -> RunSession
    func status(sessionID: RunSession.ID) async throws -> RunSessionStatus
    func logs(sessionID: RunSession.ID) -> AsyncThrowingStream<LogEvent, Error>
}

public protocol RuntimeLogReader: Sendable {
    func readRecent(sessionID: RunSession.ID, tail: Int) async throws -> RuntimeLogChunk
    func readAfter(sessionID: RunSession.ID, line: Int) async throws -> RuntimeLogChunk
}

public protocol ProcessInspector: Sendable {
    func isProcessRunning(pid: Int32) async -> Bool
}

public struct RuntimeLogChunk: Sendable, Equatable {
    public var lines: [String]
    public var nextLine: Int

    public init(lines: [String], nextLine: Int) {
        self.lines = lines
        self.nextLine = nextLine
    }
}

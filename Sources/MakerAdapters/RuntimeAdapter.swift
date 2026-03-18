import Foundation
import MakerDomain
import MakerSupport

public enum RuntimeProcessState: String, Sendable, Codable {
    case idle
    case preparing
    case running
    case stopped
    case failed
}

public struct RuntimeExecutionHandle: Sendable {
    public let pid: Int32
    public let startedAt: Date

    public init(pid: Int32, startedAt: Date = Date()) {
        self.pid = pid
        self.startedAt = startedAt
    }
}

public protocol RuntimeAdapter: Sendable {
    func prepare(project: Project, profile: RuntimeProfile, env: [String: String]) async throws
    func start() async throws -> RuntimeExecutionHandle
    func stop() async throws
    func restart() async throws -> RuntimeExecutionHandle
    func getStatus() async -> RuntimeProcessState
    func streamLogs() -> AsyncThrowingStream<LogEvent, Error>
}

public protocol RuntimeAdapterFactory: Sendable {
    func makeAdapter(for profile: RuntimeProfile) -> any RuntimeAdapter
}

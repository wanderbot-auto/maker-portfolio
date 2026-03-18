import Foundation

public struct RunSession: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var status: RunSessionStatus
    public var pid: Int32?
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?
    public var triggerSource: TriggerSource

    public init(
        id: ID = UUID(),
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        status: RunSessionStatus,
        pid: Int32? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        exitCode: Int32? = nil,
        triggerSource: TriggerSource = .manual
    ) {
        self.id = id
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.triggerSource = triggerSource
    }
}

public enum RunSessionStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case stopped
    case failed
}

public enum TriggerSource: String, Codable, Sendable, CaseIterable {
    case manual
    case automation
    case recovery
}

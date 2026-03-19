import Foundation
import MakerApplication
import MakerDomain

public struct DaemonRequest: Codable, Sendable {
    public var token: String
    public var action: String
    public var projectID: String?
    public var runtimeProfileID: String?
    public var sessionID: String?
    public var tail: Int?
    public var afterLine: Int?

    public init(
        token: String,
        action: String,
        projectID: String? = nil,
        runtimeProfileID: String? = nil,
        sessionID: String? = nil,
        tail: Int? = nil,
        afterLine: Int? = nil
    ) {
        self.token = token
        self.action = action
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.sessionID = sessionID
        self.tail = tail
        self.afterLine = afterLine
    }
}

public struct DaemonSessionSummary: Codable, Sendable, Equatable {
    public var sessionID: String
    public var projectID: String
    public var runtimeProfileID: String
    public var status: String
    public var pid: Int32?
    public var exitCode: Int32?
    public var restartCount: Int?
    public var failureReason: String?
    public var lastHealthCheckStatus: String?
    public var lastHealthCheckDetail: String?
    public var lastHealthCheckAt: Date?

    public init(
        sessionID: String,
        projectID: String,
        runtimeProfileID: String,
        status: String,
        pid: Int32?,
        exitCode: Int32? = nil,
        restartCount: Int? = nil,
        failureReason: String? = nil,
        lastHealthCheckStatus: String? = nil,
        lastHealthCheckDetail: String? = nil,
        lastHealthCheckAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
        self.exitCode = exitCode
        self.restartCount = restartCount
        self.failureReason = failureReason
        self.lastHealthCheckStatus = lastHealthCheckStatus
        self.lastHealthCheckDetail = lastHealthCheckDetail
        self.lastHealthCheckAt = lastHealthCheckAt
    }

    public init(snapshot: RuntimeSessionSnapshot) {
        self.sessionID = snapshot.sessionID.uuidString
        self.projectID = snapshot.projectID.uuidString
        self.runtimeProfileID = snapshot.runtimeProfileID.uuidString
        self.status = snapshot.status.rawValue
        self.pid = snapshot.pid
        self.exitCode = nil
        self.restartCount = nil
        self.failureReason = nil
        self.lastHealthCheckStatus = nil
        self.lastHealthCheckDetail = nil
        self.lastHealthCheckAt = nil
    }

    public init(session: RunSession) {
        self.sessionID = session.id.uuidString
        self.projectID = session.projectID.uuidString
        self.runtimeProfileID = session.runtimeProfileID.uuidString
        self.status = session.status.rawValue
        self.pid = session.pid
        self.exitCode = session.exitCode
        self.restartCount = session.restartCount
        self.failureReason = session.failureReason
        self.lastHealthCheckStatus = session.lastHealthCheckStatus?.rawValue
        self.lastHealthCheckDetail = session.lastHealthCheckDetail
        self.lastHealthCheckAt = session.lastHealthCheckAt
    }
}

public struct DaemonResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var session: DaemonSessionSummary?
    public var sessions: [DaemonSessionSummary]
    public var logs: [String]
    public var nextLine: Int?

    public init(
        ok: Bool,
        message: String,
        session: DaemonSessionSummary? = nil,
        sessions: [DaemonSessionSummary] = [],
        logs: [String] = [],
        nextLine: Int? = nil
    ) {
        self.ok = ok
        self.message = message
        self.session = session
        self.sessions = sessions
        self.logs = logs
        self.nextLine = nextLine
    }
}

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

    public init(sessionID: String, projectID: String, runtimeProfileID: String, status: String, pid: Int32?) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
    }

    public init(snapshot: RuntimeSessionSnapshot) {
        self.sessionID = snapshot.sessionID.uuidString
        self.projectID = snapshot.projectID.uuidString
        self.runtimeProfileID = snapshot.runtimeProfileID.uuidString
        self.status = snapshot.status.rawValue
        self.pid = snapshot.pid
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

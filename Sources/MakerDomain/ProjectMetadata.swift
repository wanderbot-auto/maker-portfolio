import Foundation

public struct ProjectNote: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var projectID: Project.ID
    public var content: String
    public var updatedAt: Date

    public init(id: ID = UUID(), projectID: Project.ID, content: String, updatedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.content = content
        self.updatedAt = updatedAt
    }
}

public struct Milestone: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public enum State: String, Codable, Sendable, CaseIterable {
        case notStarted
        case inProgress
        case completed
    }

    public var id: ID
    public var projectID: Project.ID
    public var title: String
    public var dueDate: Date?
    public var state: State

    public init(id: ID = UUID(), projectID: Project.ID, title: String, dueDate: Date? = nil, state: State = .notStarted) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.dueDate = dueDate
        self.state = state
    }
}

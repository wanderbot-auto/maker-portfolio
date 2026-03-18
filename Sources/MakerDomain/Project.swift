import Foundation

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var name: String
    public var slug: String
    public var localPath: String
    public var repoType: RepoType
    public var description: String
    public var status: ProjectStatus
    public var priority: ProjectPriority
    public var tags: [String]
    public var stackSummary: String
    public var lastOpenedAt: Date?
    public var archivedAt: Date?
    public var updatedAt: Date

    public init(
        id: ID = UUID(),
        name: String,
        slug: String? = nil,
        localPath: String,
        repoType: RepoType = .unknown,
        description: String = "",
        status: ProjectStatus = .idea,
        priority: ProjectPriority = .p2,
        tags: [String] = [],
        stackSummary: String = "",
        lastOpenedAt: Date? = nil,
        archivedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug ?? Project.makeSlug(from: name)
        self.localPath = localPath
        self.repoType = repoType
        self.description = description
        self.status = status
        self.priority = priority
        self.tags = tags
        self.stackSummary = stackSummary
        self.lastOpenedAt = lastOpenedAt
        self.archivedAt = archivedAt
        self.updatedAt = updatedAt
    }

    public static func makeSlug(from value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

public enum RepoType: String, Codable, Sendable, CaseIterable {
    case git
    case localOnly
    case unknown
}

public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case idea
    case active
    case paused
    case shipped
    case archived
}

public enum ProjectPriority: String, Codable, Sendable, CaseIterable {
    case p0
    case p1
    case p2
    case p3
}

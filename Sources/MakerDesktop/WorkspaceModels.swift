import Foundation
import SwiftUI
import MakerApplication
import MakerDomain

struct WorkspaceDashboardSnapshot {
    var metrics: [MetricCardModel]
    var featuredProjects: [SidebarProjectCardModel]
    var projectCards: [SidebarProjectCardModel]
    var rhythm: [RhythmPoint]
    var focusAreas: [FocusAreaModel]
    var selectedWork: [SelectedWorkRowModel]
    var usingFallbackData: Bool

    static let placeholder = WorkspaceDashboardSnapshot(
        metrics: [
            MetricCardModel(title: "Shipped Products", value: "14", delta: "+2"),
            MetricCardModel(title: "Active Repositories", value: "5", delta: "+1"),
            MetricCardModel(title: "Build Cycles", value: "342", delta: "+12"),
            MetricCardModel(title: "Core Stack Coverage", value: "4", delta: "+1")
        ],
        featuredProjects: [
            SidebarProjectCardModel(
                projectID: UUID(),
                title: "figma-make-client",
                version: "v1.2.4",
                metadata: "1.2 MB",
                syncText: "10 mins ago",
                status: .running,
                initials: "TY"
            ),
            SidebarProjectCardModel(
                projectID: UUID(),
                title: "design-system-core",
                version: "v0.8.2",
                metadata: "4.5 MB",
                syncText: "1 hour ago",
                status: .idle,
                initials: "RE"
            )
        ],
        projectCards: [
            SidebarProjectCardModel(
                projectID: UUID(),
                title: "rust-worker-node",
                version: "v2.0.1-beta",
                metadata: "820 KB",
                syncText: "3 days ago",
                status: .stopped,
                initials: "RU"
            ),
            SidebarProjectCardModel(
                projectID: UUID(),
                title: "next-dashboard-v3",
                version: "v3.1.0",
                metadata: "2.1 MB",
                syncText: "4 hours ago",
                status: .syncing,
                initials: "TY"
            )
        ],
        rhythm: [
            RhythmPoint(month: "Jan", builds: 148, product: 136),
            RhythmPoint(month: "Feb", builds: 176, product: 164),
            RhythmPoint(month: "Mar", builds: 212, product: 198),
            RhythmPoint(month: "Apr", builds: 192, product: 182),
            RhythmPoint(month: "May", builds: 228, product: 214),
            RhythmPoint(month: "Jun", builds: 198, product: 188),
            RhythmPoint(month: "Jul", builds: 244, product: 232),
            RhythmPoint(month: "Aug", builds: 208, product: 202),
            RhythmPoint(month: "Sep", builds: 236, product: 220),
            RhythmPoint(month: "Oct", builds: 222, product: 210),
            RhythmPoint(month: "Nov", builds: 190, product: 182),
            RhythmPoint(month: "Dec", builds: 178, product: 170)
        ],
        focusAreas: [
            FocusAreaModel(name: "TypeScript", percentage: 0.65, color: WorkspacePalette.blue),
            FocusAreaModel(name: "Rust", percentage: 0.15, color: WorkspacePalette.peach),
            FocusAreaModel(name: "React/JS", percentage: 0.12, color: WorkspacePalette.yellow),
            FocusAreaModel(name: "CSS/HTML", percentage: 0.08, color: WorkspacePalette.purple)
        ],
        selectedWork: [
            SelectedWorkRowModel(projectID: UUID(), project: "figma-make-client", detail: "1.2 MB", version: "v1.2.4", stack: "TypeScript", lastUpdated: "2026-03-18", status: .running),
            SelectedWorkRowModel(projectID: UUID(), project: "design-system-core", detail: "4.5 MB", version: "v0.8.2", stack: "React", lastUpdated: "2026-03-17", status: .idle),
            SelectedWorkRowModel(projectID: UUID(), project: "rust-worker-node", detail: "820 KB", version: "v2.0.1-beta", stack: "Rust", lastUpdated: "2026-03-15", status: .stopped),
            SelectedWorkRowModel(projectID: UUID(), project: "next-dashboard-v3", detail: "2.1 MB", version: "v3.1.0", stack: "TypeScript", lastUpdated: "2026-03-14", status: .syncing)
        ],
        usingFallbackData: true
    )

    func filtered(query: String) -> WorkspaceDashboardSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return self
        }

        let needle = trimmed.lowercased()
        return WorkspaceDashboardSnapshot(
            metrics: metrics,
            featuredProjects: featuredProjects.filter { $0.searchText.contains(needle) },
            projectCards: projectCards.filter { $0.searchText.contains(needle) },
            rhythm: rhythm,
            focusAreas: focusAreas,
            selectedWork: selectedWork.filter { $0.searchText.contains(needle) },
            usingFallbackData: usingFallbackData
        )
    }

    static func live(
        summary: DashboardSummary,
        projects: [ProjectListItem]
    ) -> WorkspaceDashboardSnapshot {
        let sortedProjects = projects.sorted { lhs, rhs in
            lhs.project.updatedAt > rhs.project.updatedAt
        }

        let featuredProjects = Array(sortedProjects.prefix(2)).map(SidebarProjectCardModel.init(item:))
        let projectCards = Array(sortedProjects.dropFirst(2).prefix(2)).map(SidebarProjectCardModel.init(item:))
        let selectedWork = Array(sortedProjects.prefix(4)).map(SelectedWorkRowModel.init(item:))

        let stackDistribution = StackDistributionBuilder.make(from: sortedProjects.map(\.project))
        let metrics = [
            MetricCardModel(
                title: "Shipped Products",
                value: "\(max(1, shippedProducts(from: sortedProjects)))",
                delta: "+\(max(1, summary.failedSessions))"
            ),
            MetricCardModel(
                title: "Active Repositories",
                value: "\(max(1, summary.activeProjects))",
                delta: "+\(max(1, summary.runningSessions))"
            ),
            MetricCardModel(
                title: "Build Cycles",
                value: "\(max(1, buildCycles(from: sortedProjects)))",
                delta: "+\(max(1, summary.runningSessions + summary.failedSessions))"
            ),
            MetricCardModel(
                title: "Core Stack Coverage",
                value: "\(max(1, stackDistribution.count))",
                delta: "+\(max(1, stackDistribution.newCoverageCount))"
            )
        ]

        return WorkspaceDashboardSnapshot(
            metrics: metrics,
            featuredProjects: featuredProjects.isEmpty ? placeholder.featuredProjects : featuredProjects,
            projectCards: projectCards.isEmpty ? placeholder.projectCards : projectCards,
            rhythm: RhythmBuilder.make(from: sortedProjects),
            focusAreas: stackDistribution.areas,
            selectedWork: selectedWork.isEmpty ? placeholder.selectedWork : selectedWork,
            usingFallbackData: false
        )
    }

    private static func shippedProducts(from items: [ProjectListItem]) -> Int {
        let shipped = items.filter { $0.project.status == .shipped }.count
        if shipped > 0 {
            return shipped
        }
        return items.filter { $0.project.status == .active || $0.project.status == .shipped }.count
    }

    private static func buildCycles(from items: [ProjectListItem]) -> Int {
        items.reduce(0) { partialResult, item in
            partialResult + item.runtimeCount + (item.latestSession == nil ? 0 : 1)
        }
    }
}

struct MetricCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let delta: String
}

struct SidebarProjectCardModel: Identifiable {
    let id: Project.ID
    let projectID: Project.ID
    let title: String
    let version: String
    let metadata: String
    let syncText: String
    let status: WorkspaceStatus
    let initials: String

    init(projectID: Project.ID, title: String, version: String, metadata: String, syncText: String, status: WorkspaceStatus, initials: String) {
        self.id = projectID
        self.projectID = projectID
        self.title = title
        self.version = version
        self.metadata = metadata
        self.syncText = syncText
        self.status = status
        self.initials = initials
    }

    init(item: ProjectListItem) {
        let project = item.project
        self.id = project.id
        self.projectID = project.id
        self.title = project.name
        self.version = VersionFormatter.inferredVersion(project: project, runtimeCount: item.runtimeCount)
        self.metadata = MetadataFormatter.sidebarMetadata(for: project)
        self.syncText = RelativeTimeFormatter.syncText(
            latestDate: item.latestSession?.startedAt ?? project.updatedAt
        )
        self.status = WorkspaceStatus(project: project, latestSession: item.latestSession)
        self.initials = StringFormatter.initials(from: project.name)
    }

    var searchText: String {
        [title, version, metadata, syncText, status.label].joined(separator: " ").lowercased()
    }
}

struct RhythmPoint: Identifiable {
    let id = UUID()
    let month: String
    let builds: Double
    let product: Double
}

struct FocusAreaModel: Identifiable {
    let id = UUID()
    let name: String
    let percentage: Double
    let color: Color
}

struct SelectedWorkRowModel: Identifiable {
    let id: Project.ID
    let projectID: Project.ID
    let project: String
    let detail: String
    let version: String
    let stack: String
    let lastUpdated: String
    let status: WorkspaceStatus

    init(projectID: Project.ID, project: String, detail: String, version: String, stack: String, lastUpdated: String, status: WorkspaceStatus) {
        self.id = projectID
        self.projectID = projectID
        self.project = project
        self.detail = detail
        self.version = version
        self.stack = stack
        self.lastUpdated = lastUpdated
        self.status = status
    }

    init(item: ProjectListItem) {
        let project = item.project
        self.id = project.id
        self.projectID = project.id
        self.project = project.name
        self.detail = MetadataFormatter.sidebarMetadata(for: project)
        self.version = VersionFormatter.inferredVersion(project: project, runtimeCount: item.runtimeCount)
        self.stack = StackDistributionBuilder.primaryStackName(for: project)
        self.lastUpdated = DateFormatter.workspaceDay.string(from: project.updatedAt)
        self.status = WorkspaceStatus(project: project, latestSession: item.latestSession)
    }

    var searchText: String {
        [project, detail, version, stack, lastUpdated, status.label].joined(separator: " ").lowercased()
    }
}

enum WorkspaceStatus: String {
    case running
    case idle
    case syncing
    case stopped

    init(project: Project, latestSession: RunSession?) {
        if let latestSession {
            switch latestSession.status {
            case .running:
                self = .running
                return
            case .pending:
                self = .syncing
                return
            case .failed:
                self = .stopped
                return
            case .stopped:
                break
            }
        }

        switch project.status {
        case .active:
            self = .idle
        case .shipped:
            self = .running
        case .paused, .archived, .idea:
            self = .stopped
        }
    }

    var label: String {
        rawValue.uppercased()
    }

    var dotColor: Color {
        switch self {
        case .running:
            return WorkspacePalette.green
        case .idle:
            return WorkspacePalette.orange
        case .syncing:
            return WorkspacePalette.indigo
        case .stopped:
            return WorkspacePalette.slate
        }
    }

    var textColor: Color {
        switch self {
        case .running:
            return WorkspacePalette.green
        case .idle:
            return WorkspacePalette.orange
        case .syncing:
            return WorkspacePalette.indigo
        case .stopped:
            return WorkspacePalette.deepSlate
        }
    }

    var backgroundColor: Color {
        switch self {
        case .running:
            return WorkspacePalette.green.opacity(0.12)
        case .idle:
            return WorkspacePalette.orange.opacity(0.16)
        case .syncing:
            return WorkspacePalette.indigo.opacity(0.14)
        case .stopped:
            return WorkspacePalette.slate.opacity(0.14)
        }
    }
}

enum WorkspacePalette {
    static let canvas = Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255)
    static let panel = Color.white
    static let border = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    static let ink = Color(red: 15 / 255, green: 23 / 255, blue: 43 / 255)
    static let deepSlate = Color(red: 29 / 255, green: 41 / 255, blue: 61 / 255)
    static let slate = Color(red: 144 / 255, green: 161 / 255, blue: 185 / 255)
    static let body = Color(red: 69 / 255, green: 85 / 255, blue: 108 / 255)
    static let blue = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    static let peach = Color(red: 234 / 255, green: 176 / 255, blue: 139 / 255)
    static let yellow = Color(red: 245 / 255, green: 221 / 255, blue: 90 / 255)
    static let purple = Color(red: 101 / 255, green: 76 / 255, blue: 190 / 255)
    static let green = Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255)
    static let orange = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    static let indigo = Color(red: 97 / 255, green: 95 / 255, blue: 255 / 255)
}

enum StringFormatter {
    static func initials(from value: String) -> String {
        let components = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if components.isEmpty {
            return String(value.prefix(2)).uppercased()
        }
        return components.joined()
    }
}

enum VersionFormatter {
    static func inferredVersion(project: Project, runtimeCount: Int) -> String {
        if let tagVersion = project.tags.first(where: { $0.lowercased().hasPrefix("v") }) {
            return tagVersion.uppercased() == tagVersion ? tagVersion.lowercased() : tagVersion
        }

        let patch = max(0, runtimeCount - 1)
        return "v\(max(1, runtimeCount)).\(priorityIndex(for: project.priority)).\(patch)"
    }

    private static func priorityIndex(for priority: ProjectPriority) -> Int {
        switch priority {
        case .p0:
            return 0
        case .p1:
            return 1
        case .p2:
            return 2
        case .p3:
            return 3
        }
    }
}

enum MetadataFormatter {
    static func sidebarMetadata(for project: Project) -> String {
        let stack = StackDistributionBuilder.primaryStackName(for: project)
        if stack.isEmpty == false {
            return stack
        }

        switch project.repoType {
        case .git:
            return "Git Repository"
        case .localOnly:
            return "Local Project"
        case .unknown:
            return "Workspace"
        }
    }
}

enum RelativeTimeFormatter {
    static func syncText(latestDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        let raw = formatter.localizedString(for: latestDate, relativeTo: Date())
        return raw
            .replacingOccurrences(of: " ago", with: "")
            .replacingOccurrences(of: " hours", with: " hrs")
            .replacingOccurrences(of: " hour", with: " hr")
    }
}

enum StackDistributionBuilder {
    private static let defaultAreas = WorkspaceDashboardSnapshot.placeholder.focusAreas

    static func make(from projects: [Project]) -> (areas: [FocusAreaModel], count: Int, newCoverageCount: Int) {
        var buckets: [String: Int] = [:]

        for project in projects {
            for key in categories(for: project) {
                buckets[key, default: 0] += 1
            }
        }

        guard buckets.isEmpty == false else {
            return (defaultAreas, defaultAreas.count, 1)
        }

        let palette: [Color] = [WorkspacePalette.blue, WorkspacePalette.peach, WorkspacePalette.yellow, WorkspacePalette.purple]
        let sorted = buckets
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(4)

        let total = Double(sorted.reduce(0) { $0 + $1.value })
        let areas = sorted.enumerated().map { index, item in
            FocusAreaModel(
                name: item.key,
                percentage: Double(item.value) / max(1, total),
                color: palette[index % palette.count]
            )
        }

        return (areas, areas.count, max(1, buckets.count - areas.count + 1))
    }

    static func primaryStackName(for project: Project) -> String {
        categories(for: project).first ?? fallbackName(for: project.repoType)
    }

    private static func categories(for project: Project) -> [String] {
        let haystack = [project.stackSummary, project.description, project.tags.joined(separator: " ")]
            .joined(separator: " ")
            .lowercased()

        var results: [String] = []
        if haystack.contains("typescript") || haystack.contains("next") || haystack.contains(" ts") {
            results.append("TypeScript")
        }
        if haystack.contains("react") || haystack.contains("javascript") || haystack.contains("node") {
            results.append("React/JS")
        }
        if haystack.contains("rust") {
            results.append("Rust")
        }
        if haystack.contains("css") || haystack.contains("html") || haystack.contains("tailwind") || haystack.contains("sass") {
            results.append("CSS/HTML")
        }
        if haystack.contains("swift") || haystack.contains("swiftui") || haystack.contains("appkit") || haystack.contains("macos") {
            results.append("Swift")
        }

        if results.isEmpty, project.stackSummary.isEmpty == false {
            return [project.stackSummary]
        }

        return results
    }

    private static func fallbackName(for repoType: RepoType) -> String {
        switch repoType {
        case .git:
            return "Git"
        case .localOnly:
            return "Local"
        case .unknown:
            return "Workspace"
        }
    }
}

enum RhythmBuilder {
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static func make(from items: [ProjectListItem]) -> [RhythmPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: Date())

        var builds: [Int: Double] = [:]
        var product: [Int: Double] = [:]

        for item in items {
            if let date = item.latestSession?.startedAt {
                let components = calendar.dateComponents([.year, .month], from: date)
                if components.year == year, let month = components.month {
                    builds[month, default: 0] += 1
                }
            }

            let updateComponents = calendar.dateComponents([.year, .month], from: item.project.updatedAt)
            if updateComponents.year == year, let month = updateComponents.month {
                product[month, default: 0] += 1
            }
        }

        let points = (1...12).map { month -> RhythmPoint in
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            return RhythmPoint(
                month: monthFormatter.string(from: date),
                builds: builds[month, default: 0] * 34,
                product: product[month, default: 0] * 28
            )
        }

        let nonZeroCount = points.filter { $0.builds > 0 || $0.product > 0 }.count
        if nonZeroCount < 3 {
            return WorkspaceDashboardSnapshot.placeholder.rhythm
        }
        return points
    }
}

extension DateFormatter {
    static let workspaceDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

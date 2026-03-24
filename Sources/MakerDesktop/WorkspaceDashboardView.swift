import SwiftUI
import MakerDomain

struct WorkspaceDashboardView: View {
    @ObservedObject var store: WorkspaceDashboardStore

    @State private var sidebarQuery = ""
    @State private var headerQuery = ""
    @State private var isProjectOverviewExpanded = false
    @State private var isGitDetailsExpanded = false
    @State private var detailPrimaryColumnHeight: CGFloat = 0

    private var query: String {
        let header = headerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.isEmpty == false {
            return header
        }
        return sidebarQuery
    }

    private var snapshot: WorkspaceDashboardSnapshot {
        store.snapshot.filtered(query: query)
    }

    private var selectedProjectID: Project.ID? {
        store.selectedProject?.projectID
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)

            Divider()
                .overlay(WorkspacePalette.border)

            VStack(spacing: 0) {
                topBar
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkspacePalette.canvas)
        }
        .background(WorkspacePalette.canvas)
        .overlay {
            if store.isProjectLoading {
                loadingOverlay
            }
        }
        .task {
            await store.load()
        }
        .onChange(of: selectedProjectID) { _, _ in
            isProjectOverviewExpanded = false
            isGitDetailsExpanded = false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WorkspacePalette.ink)
                    Image(systemName: "hexagon")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                Text("Maker Studio")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WorkspacePalette.ink)

                Spacer()

                IconButton(symbol: "gearshape", size: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 18)

            searchField(
                text: $sidebarQuery,
                placeholder: "Search projects, notes, builds..."
            )
            .padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    sidebarSection(title: "Featured", icon: "pin.fill", projects: snapshot.featuredProjects)
                    projectsSection
                }
                .padding(.top, 20)
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }

            Button(action: {}) {
                HStack(spacing: 8) {
                    Spacer()
                    Text("SHOW ALL")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.65)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(WorkspacePalette.body)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WorkspacePalette.border)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WorkspacePalette.panel)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            searchField(
                text: $headerQuery,
                placeholder: "Lookup branch, commit, or audit logs..."
            )
            .frame(width: 640)

            Spacer()

            if store.selectedProject == nil {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Deploy")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WorkspacePalette.ink)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ActionChipButton(title: "Global Deploy", emphasis: .secondary, action: {})
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkspacePalette.border)
                .frame(height: 1)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if let detail = store.selectedProject {
                    projectDetailContent(detail)
                } else {
                    overviewContent
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            metricsGrid

            HStack(alignment: .top, spacing: 16) {
                rhythmCard
                focusCard
            }

            selectedWorkCard
        }
    }

    private func projectDetailContent(_ detail: ProjectDetailPageModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            detailHeader(detail)
            detailInsightPanels(detail)
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func detailHeader(_ detail: ProjectDetailPageModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: store.showOverview) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back to Overview")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(WorkspacePalette.body)
                }
                .buttonStyle(.plain)

                Spacer()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        detailHeaderActions(detail)
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        detailHeaderActions(detail)
                    }
                }
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(WorkspacePalette.ink)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            OverviewDetailButton(isExpanded: isProjectOverviewExpanded) {
                                isProjectOverviewExpanded.toggle()
                            }
                            StatusPill(status: detail.status)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            DetailMetaPill(title: "STACK", value: detail.stackSummary)
                            DetailMetaPill(title: "REPOSITORY", value: detail.footprint.totalSizeLabel)
                            DetailMetaPill(title: "SOURCE", value: detail.footprint.sourceSizeLabel)
                            DetailMetaPill(title: "FILES", value: "\(detail.footprint.sourceFiles)")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            DetailMetaPill(title: "STACK", value: detail.stackSummary)
                            DetailMetaPill(title: "REPOSITORY", value: detail.footprint.totalSizeLabel)
                            DetailMetaPill(title: "SOURCE", value: detail.footprint.sourceSizeLabel)
                            DetailMetaPill(title: "FILES", value: "\(detail.footprint.sourceFiles)")
                        }
                    }

                    if detail.description.isEmpty == false {
                        Text(detail.description)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WorkspacePalette.body)
                            .lineLimit(2)
                    }

                    if isProjectOverviewExpanded {
                        Divider()
                            .overlay(WorkspacePalette.border)

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Project Path")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.7)
                                    .foregroundStyle(WorkspacePalette.slate)
                                    .textCase(.uppercase)
                                Text(detail.path)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(WorkspacePalette.body)
                                    .textSelection(.enabled)
                            }

                            if let readmeSnippet = detail.readmeSnippet, readmeSnippet.isEmpty == false {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("README")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.7)
                                        .foregroundStyle(WorkspacePalette.slate)
                                        .textCase(.uppercase)

                                    MarkdownContentCard(markdown: readmeSnippet)
                                }
                            } else if detail.description.isEmpty == false {
                                EmptyStateCard(title: "README unavailable", detail: detail.description)
                            } else {
                                EmptyStateCard(title: "README unavailable", detail: "No README.md content was found for this project.")
                            }
                        }
                    }

                    if let actionFeedback = detail.actionFeedback {
                        ActionFeedbackBanner(feedback: actionFeedback)
                    }
                }
            }
        }
    }

    private func detailInsightPanels(_ detail: ProjectDetailPageModel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                gitInsightCard(detail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ViewHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    )
                    .onPreferenceChange(ViewHeightPreferenceKey.self) { detailPrimaryColumnHeight = $0 }
                VStack(alignment: .leading, spacing: 16) {
                    codeCompositionCard(detail)
                    recentCommitsCard(detail.git)
                }
                .frame(width: 256, alignment: .topLeading)
                .frame(height: detailPrimaryColumnHeight > 0 ? detailPrimaryColumnHeight : nil, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                gitInsightCard(detail)
                codeCompositionCard(detail)
                recentCommitsCard(detail.git)
            }
        }
    }

    private func codeCompositionCard(_ detail: ProjectDetailPageModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Code Composition Analysis")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(WorkspacePalette.deepSlate)
                    .textCase(.uppercase)

                if detail.codeComposition.isEmpty {
                    EmptyStateCard(title: "No source composition", detail: "No source files were classified for this repository yet.")
                } else {
                    CodeCompositionPieChart(components: detail.codeComposition)
                        .frame(height: 120)

                    VStack(spacing: 8) {
                        ForEach(detail.codeComposition) { component in
                            CodeCompositionLegendRow(component: component)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 288, alignment: .topLeading)
    }

    private func recentCommitsCard(_ git: GitRepositorySnapshot) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recent Commits")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(WorkspacePalette.deepSlate)
                    .textCase(.uppercase)

                if git.recentCommits.isEmpty {
                    EmptyStateCard(title: "No recent commits", detail: "No commit history was available for this repository.")
                } else {
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 10) {
                            ForEach(git.recentCommits) { commit in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(commit.hash)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(WorkspacePalette.body)
                                            .padding(.horizontal, 8)
                                            .frame(height: 18)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(WorkspacePalette.border)
                                            )

                                        Spacer()

                                        Text(commit.date)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(WorkspacePalette.slate)
                                    }

                                    Text(commit.message)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(WorkspacePalette.deepSlate)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(commit.author)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(WorkspacePalette.body)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gitInsightCard(_ detail: ProjectDetailPageModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Git Intelligence")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(WorkspacePalette.deepSlate)
                    .textCase(.uppercase)

                if detail.git.isGitRepository == false {
                    EmptyStateCard(title: "Git unavailable", detail: "This project is not inside a Git working tree.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        GitSummaryTile(title: "Branch", value: detail.git.branch)
                        GitSummaryTile(title: "Working Tree", value: workingTreeValue(for: detail.git))
                        GitSummaryTile(title: "Last Change", value: detail.git.latestCommitDate ?? "No commits")
                        GitSummaryTile(title: "Sync Status", value: syncStatusValue(for: detail.git))
                    }

                    Divider()
                        .overlay(WorkspacePalette.border)

                    gitRecentActivitySection(detail.git)

                    Divider()
                        .overlay(WorkspacePalette.border)

                    gitWorkingTreePressureSection(detail.git)

                    HStack {
                        Text(gitHealthCaption(for: detail.git))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WorkspacePalette.body)
                        Spacer()
                        Button(isGitDetailsExpanded ? "Hide Details" : "View Details") {
                            isGitDetailsExpanded.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WorkspacePalette.body)
                    }

                    if isGitDetailsExpanded {
                        Divider()
                            .overlay(WorkspacePalette.border)

                        VStack(alignment: .leading, spacing: 8) {
                            DetailStatRow(label: "Remote", value: detail.git.remote ?? "-")
                            DetailStatRow(label: "Author", value: detail.git.latestCommitAuthor ?? "-")
                            DetailStatRow(label: "Date", value: detail.git.latestCommitDate ?? "-")
                        }

                        if let latestCommitMessage = detail.git.latestCommitMessage {
                            Text(latestCommitMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WorkspacePalette.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func gitRecentActivitySection(_ git: GitRepositorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Activity Pulse for This Repository")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WorkspacePalette.deepSlate)
                Spacer()
                Text("Last 14 Days")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)
            }

            GitActivityPulseChart(points: git.recentActivity)
                .frame(height: 126)

            let totalCommits = git.recentActivity.reduce(0) { $0 + $1.commitCount }
            let activeDays = git.recentActivity.filter { $0.commitCount > 0 }.count
            let peakCount = git.recentActivity.map(\.commitCount).max() ?? 0

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    DetailMetaPill(title: "ACTIVE DAYS", value: "\(activeDays)")
                    DetailMetaPill(title: "COMMITS", value: "\(totalCommits)")
                    DetailMetaPill(title: "PEAK DAY", value: "\(peakCount)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    DetailMetaPill(title: "ACTIVE DAYS", value: "\(activeDays)")
                    DetailMetaPill(title: "COMMITS", value: "\(totalCommits)")
                    DetailMetaPill(title: "PEAK DAY", value: "\(peakCount)")
                }
            }
        }
    }

    private func gitWorkingTreePressureSection(_ git: GitRepositorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Current Open Change Load")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WorkspacePalette.deepSlate)
                Spacer()
                Text("\(openChangeTotal(for: git)) Files")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)
            }

            GitWorkingTreeLoadView(buckets: workingTreeBuckets(for: git))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(workingTreeBuckets(for: git)) { bucket in
                        DetailMetaPill(title: bucket.title, value: "\(bucket.count)")
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(workingTreeBuckets(for: git)) { bucket in
                        DetailMetaPill(title: bucket.title, value: "\(bucket.count)")
                    }
                }
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.white.opacity(0.72)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading project detail…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WorkspacePalette.body)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(WorkspacePalette.border, lineWidth: 1)
                    )
            )
        }
    }

    private func workingTreeValue(for git: GitRepositorySnapshot) -> String {
        guard git.isGitRepository else { return "Unavailable" }
        let total = openChangeTotal(for: git)
        if total == 0 {
            return "Clean"
        }
        return "\(total) Open"
    }

    private func syncStatusValue(for git: GitRepositorySnapshot) -> String {
        guard git.isGitRepository else { return "Unavailable" }
        guard let aheadBehind = git.aheadBehind, aheadBehind.isEmpty == false else {
            return "No upstream"
        }

        let parts = aheadBehind
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return "Unknown"
        }

        if ahead == 0 && behind == 0 {
            return "Synced"
        }

        if ahead > 0 && behind > 0 {
            return "Ahead \(ahead) · Behind \(behind)"
        }

        if ahead > 0 {
            return "Ahead \(ahead)"
        }

        return "Behind \(behind)"
    }

    private func gitHealthCaption(for git: GitRepositorySnapshot) -> String {
        guard git.isGitRepository else { return "No Git working tree" }
        let parts = workingTreeBuckets(for: git)
            .filter { $0.count > 0 }
            .map { "\($0.count) \($0.title.lowercased())" }

        guard parts.isEmpty == false else {
            return "\(git.branch) · working tree clean"
        }

        return "\(git.branch) · " + parts.joined(separator: " · ")
    }

    private func openChangeTotal(for git: GitRepositorySnapshot) -> Int {
        git.modifiedFiles + git.addedFiles + git.deletedFiles + git.untrackedFiles
    }

    private func workingTreeBuckets(for git: GitRepositorySnapshot) -> [GitChangeBucket] {
        [
            GitChangeBucket(title: "Modified", count: git.modifiedFiles, color: WorkspacePalette.yellow),
            GitChangeBucket(title: "Added", count: git.addedFiles, color: WorkspacePalette.green),
            GitChangeBucket(title: "Deleted", count: git.deletedFiles, color: WorkspacePalette.peach),
            GitChangeBucket(title: "Untracked", count: git.untrackedFiles, color: WorkspacePalette.purple)
        ]
    }

    @ViewBuilder
    private func detailHeaderActions(_ detail: ProjectDetailPageModel) -> some View {
        ActionChipButton(title: store.isRunningAction ? "Working..." : "Run", emphasis: .primary, action: {
            Task { await store.runSelectedProject() }
        })
        .disabled(store.isRunningAction)

        ActionChipButton(title: "Stop", emphasis: .secondary, action: {
            Task { await store.stopSelectedProject() }
        })
        .disabled(detail.runningSessionID == nil || store.isRunningAction)

        ActionChipButton(title: store.isBuildAction ? "Building..." : "Build", emphasis: .secondary, action: {
            Task { await store.buildSelectedProject() }
        })
        .disabled(detail.buildCommand == nil || store.isBuildAction)

        ActionChipButton(title: "Refresh", emphasis: .secondary, action: {
            Task { await store.refreshSelectedProject() }
        })
    }

    private var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workspace Overview")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(WorkspacePalette.ink)
                    .textCase(.uppercase)

                Text("A structured view of current work and shipped systems")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)
            }

            Spacer()

            HStack(spacing: 8) {
                ActionChipButton(title: "View Logs", emphasis: .secondary, action: {})
                ActionChipButton(title: "Inspect Work", emphasis: .primary, action: {
                    Task { await store.load() }
                })
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            ForEach(snapshot.metrics) { metric in
                MetricCard(metric: metric)
            }
        }
    }

    private var rhythmCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Output Rhythm")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(WorkspacePalette.deepSlate)
                        .textCase(.uppercase)

                    Spacer()

                    HStack(spacing: 6) {
                        LabelPill(title: "Builds", tint: WorkspacePalette.body, filled: true)
                        LabelPill(title: "Product", tint: .red, filled: false)
                    }
                }

                RhythmChartView(points: snapshot.rhythm)
                    .frame(height: 240)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var focusCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 18) {
                Text("Focus Areas")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(WorkspacePalette.deepSlate)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textCase(.uppercase)

                DonutChartView(areas: snapshot.focusAreas)
                    .frame(height: 150)

                VStack(spacing: 12) {
                    ForEach(snapshot.focusAreas) { area in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(area.color)
                                .frame(width: 10, height: 10)
                            Text(area.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WorkspacePalette.body)
                            Spacer()
                            Text("\(Int((area.percentage * 100).rounded()))%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WorkspacePalette.slate)
                        }
                    }
                }
            }
        }
        .frame(width: 337)
    }

    private var selectedWorkCard: some View {
        CardContainer(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Selected Work")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(WorkspacePalette.deepSlate)
                        .textCase(.uppercase)
                    Spacer()
                    ActionChipButton(title: "Open Analytics", emphasis: .secondary, action: {})
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider()
                    .overlay(WorkspacePalette.border)

                SelectedWorkTable(rows: snapshot.selectedWork, selectedProjectID: selectedProjectID) { row in
                    Task { await store.selectProject(projectID: row.projectID) }
                }
            }
        }
    }

    private func sidebarSection(title: String, icon: String, projects: [SidebarProjectCardModel]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WorkspacePalette.slate)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                ForEach(projects) { project in
                    SidebarProjectCard(project: project, isSelected: selectedProjectID == project.projectID) {
                        Task { await store.selectProject(projectID: project.projectID) }
                    }
                }
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)

                Spacer()

                Text("NEW")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(WorkspacePalette.slate)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                ForEach(snapshot.projectCards) { project in
                    SidebarProjectCard(project: project, isSelected: selectedProjectID == project.projectID) {
                        Task { await store.selectProject(projectID: project.projectID) }
                    }
                }
            }
        }
    }

    private func searchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WorkspacePalette.slate)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WorkspacePalette.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.clear, lineWidth: 1)
                )
        )
    }
}

private struct IconButton: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Button(action: {}) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(WorkspacePalette.slate)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionChipButton: View {
    enum Emphasis {
        case primary
        case secondary
    }

    let title: String
    let emphasis: Emphasis
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(emphasis == .primary ? Color.white : WorkspacePalette.body)
                .padding(.horizontal, 14)
                .frame(height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(emphasis == .primary ? WorkspacePalette.ink : WorkspacePalette.border)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OverviewDetailButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(isExpanded ? "HIDE" : "DETAIL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(WorkspacePalette.body)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(WorkspacePalette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LabelPill: View {
    let title: String
    let tint: Color
    let filled: Bool

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.18)
            .foregroundStyle(filled ? tint : .red)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filled ? WorkspacePalette.border : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(filled ? WorkspacePalette.border : Color.red.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

private struct CardContainer<Content: View>: View {
    var padding: CGFloat = 21
    var strokeColor: Color = WorkspacePalette.border
    var shadowOpacity: Double = 0.05
    var fillColor: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 2)
        )
    }
}

private struct MetricCard: View {
    let metric: MetricCardModel

    var body: some View {
        CardContainer(padding: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.07)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)

                HStack(alignment: .bottom) {
                    Text(metric.value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WorkspacePalette.ink)

                    Spacer()

                    Text(metric.delta)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkspacePalette.green)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(WorkspacePalette.green.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(WorkspacePalette.green.opacity(0.16), lineWidth: 1)
                                )
                        )
                }
            }
        }
    }
}

private struct SidebarProjectCard: View {
    let project: SidebarProjectCardModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardContainer(
                padding: 13,
                strokeColor: isSelected ? WorkspacePalette.ink.opacity(0.18) : WorkspacePalette.border,
                shadowOpacity: isSelected ? 0.09 : 0.04,
                fillColor: isSelected ? WorkspacePalette.ink.opacity(0.035) : .white
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(WorkspacePalette.border, lineWidth: 1)
                                    )
                                Text(project.initials)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(isSelected ? WorkspacePalette.ink : Color(red: 98 / 255, green: 116 / 255, blue: 142 / 255))
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WorkspacePalette.ink)
                                HStack(spacing: 6) {
                                    Text(project.version)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(WorkspacePalette.slate)
                                        .padding(.horizontal, 4)
                                        .frame(height: 17.5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                                        )

                                    Text(project.metadata)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(WorkspacePalette.slate)
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            StatusPill(status: project.status, compact: true)
                            if isSelected {
                                Text("SELECTED")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.9)
                                    .foregroundStyle(WorkspacePalette.ink)
                            }
                        }
                    }

                    Divider()
                        .overlay(WorkspacePalette.border)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SYNC")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WorkspacePalette.slate)
                        Text(project.syncText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WorkspacePalette.deepSlate)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatusPill: View {
    let status: WorkspaceStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.dotColor)
                .frame(width: 4, height: 4)
            Text(status.label)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(status.textColor)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 16 : 18)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(status.backgroundColor)
        )
    }
}

private struct SelectedWorkTable: View {
    let rows: [SelectedWorkRowModel]
    let selectedProjectID: Project.ID?
    let onSelect: (SelectedWorkRowModel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HeaderText("Project")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HeaderText("Version")
                    .frame(width: 128, alignment: .leading)
                HeaderText("Stack")
                    .frame(width: 160, alignment: .leading)
                HeaderText("Last Updated")
                    .frame(width: 160, alignment: .leading)
                HeaderText("Status")
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()
                .overlay(WorkspacePalette.border)

            if rows.isEmpty {
                Text("No matching projects")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WorkspacePalette.slate)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(rows) { row in
                    let isSelected = selectedProjectID == row.projectID
                    Button(action: { onSelect(row) }) {
                        HStack {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(WorkspacePalette.slate)
                                }
                                .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.project)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(WorkspacePalette.deepSlate)
                                    Text(row.detail)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(WorkspacePalette.slate)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(row.version.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(WorkspacePalette.body)
                                .padding(.horizontal, 8)
                                .frame(height: 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(WorkspacePalette.border)
                                )
                                .frame(width: 128, alignment: .leading)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(color(for: row.stack))
                                    .frame(width: 8, height: 8)
                                Text(row.stack)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(WorkspacePalette.body)
                            }
                            .frame(width: 160, alignment: .leading)

                            Text(row.lastUpdated)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WorkspacePalette.body)
                                .frame(width: 160, alignment: .leading)

                            HStack(spacing: 10) {
                                StatusPill(status: row.status)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(isSelected ? WorkspacePalette.ink : WorkspacePalette.slate.opacity(0.6))
                            }
                            .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(isSelected ? WorkspacePalette.ink.opacity(0.035) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(WorkspacePalette.border)
                }
            }
        }
    }

    private func color(for stack: String) -> Color {
        let value = stack.lowercased()
        switch value {
        case let value where value.contains("type"):
            return WorkspacePalette.blue
        case let value where value.contains("rust"):
            return WorkspacePalette.peach
        case let value where value.contains("react") || value.contains("js"):
            return WorkspacePalette.blue
        case let value where value.contains("swift"):
            return WorkspacePalette.purple
        default:
            return WorkspacePalette.slate
        }
    }
}

private struct DetailSummaryCard: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        CardContainer(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.07)
                    .foregroundStyle(WorkspacePalette.slate)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WorkspacePalette.ink)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkspacePalette.body)
            }
        }
    }
}

private struct ActionFeedbackBanner: View {
    let feedback: ActionFeedback

    private var tint: Color {
        switch feedback.tone {
        case .info:
            return WorkspacePalette.indigo
        case .success:
            return WorkspacePalette.green
        case .failure:
            return .red
        }
    }

    private var label: String {
        switch feedback.tone {
        case .info:
            return "Info"
        case .success:
            return "Success"
        case .failure:
            return "Failure"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                    Text(feedback.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WorkspacePalette.slate)
                }

                Text(feedback.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WorkspacePalette.body)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WorkspacePalette.deepSlate)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WorkspacePalette.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }
}

private struct MarkdownContentCard: View {
    let markdown: String

    var body: some View {
        ScrollView(showsIndicators: true) {
            MarkdownDocumentView(markdown: markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120, maxHeight: 220, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }
}

private enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case quote(String)
    case code(String)

    var id: String {
        switch self {
        case let .heading(level, text):
            return "h\(level)-\(text)"
        case let .paragraph(text):
            return "p-\(text)"
        case let .bullet(text):
            return "b-\(text)"
        case let .quote(text):
            return "q-\(text)"
        case let .code(text):
            return "c-\(text)"
        }
    }
}

private struct MarkdownDocumentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case let .heading(level, text):
                    Text(inlineMarkdown(text))
                        .font(.system(size: headingSize(for: level), weight: .bold))
                        .foregroundStyle(WorkspacePalette.deepSlate)
                        .padding(.top, level == 1 ? 2 : 0)
                case let .paragraph(text):
                    Text(inlineMarkdown(text))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WorkspacePalette.body)
                        .fixedSize(horizontal: false, vertical: true)
                case let .bullet(text):
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(WorkspacePalette.blue)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(inlineMarkdown(text))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WorkspacePalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .quote(text):
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(WorkspacePalette.border)
                            .frame(width: 3)
                        Text(inlineMarkdown(text))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WorkspacePalette.slate)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                case let .code(text):
                    Text(text)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(WorkspacePalette.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WorkspacePalette.border, lineWidth: 1)
                                )
                        )
                }
            }
        }
        .textSelection(.enabled)
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 16
        default: return 13
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}

private enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushCode() {
            if codeLines.isEmpty == false {
                blocks.append(.code(codeLines.joined(separator: "\n")))
            }
            codeLines.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInCodeBlock {
                    flushCode()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line.hasPrefix("#") {
                flushParagraph()
                let level = min(line.prefix { $0 == "#" }.count, 3)
                let text = line.drop { $0 == "#" || $0 == " " }
                blocks.append(.heading(level: level, text: String(text)))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2))))
                continue
            }

            paragraphLines.append(rawLine)
        }

        flushParagraph()
        flushCode()
        return blocks
    }
}

private struct GitSummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(WorkspacePalette.slate)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WorkspacePalette.deepSlate)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }
}

private struct DetailMetaPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(WorkspacePalette.slate)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WorkspacePalette.deepSlate)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }
}

private struct GitChangeBucket: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let color: Color
}

private struct ViewHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CodeCompositionPieChart: View {
    let components: [CodeCompositionComponent]

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    CodeCompositionPieSlice(
                        startFraction: startFraction(for: index),
                        endFraction: startFraction(for: index) + component.percentage,
                        color: component.color
                    )
                }

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.44, height: size * 0.44)

                VStack(spacing: 2) {
                    Text("SOURCE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(WorkspacePalette.slate)
                    Text("\(components.reduce(0) { $0 + $1.fileCount })")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WorkspacePalette.deepSlate)
                    Text("files")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WorkspacePalette.body)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }

    private func startFraction(for index: Int) -> Double {
        components.prefix(index).reduce(0) { $0 + $1.percentage }
    }
}

private struct CodeCompositionPieSlice: View {
    let startFraction: Double
    let endFraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2

            Path { path in
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startFraction * 360 - 90),
                    endAngle: .degrees(endFraction * 360 - 90),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

private struct CodeCompositionLegendRow: View {
    let component: CodeCompositionComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(component.color)
                    .frame(width: 8, height: 8)
                Text(component.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WorkspacePalette.deepSlate)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(Int((component.percentage * 100).rounded()))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WorkspacePalette.body)
            }

            Text("\(component.fileCount) files · \(component.lineCount) LOC")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WorkspacePalette.slate)
        }
    }
}

private struct GitActivityPulseChart: View {
    let points: [GitActivityPoint]

    private var maxCount: Int {
        max(points.map(\.commitCount).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points) { point in
                    GitActivityPulseBar(
                        label: shortLabel(for: point.label),
                        commitCount: point.commitCount,
                        maxCount: maxCount
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }

    private func shortLabel(for label: String) -> String {
        label.split(separator: "/").last.map(String.init) ?? label
    }
}

private struct GitActivityPulseBar: View {
    let label: String
    let commitCount: Int
    let maxCount: Int

    private var barHeight: CGFloat {
        max(10, CGFloat(commitCount) / CGFloat(maxCount) * 72)
    }

    var body: some View {
        VStack(spacing: 8) {
            bar
                .frame(width: 10, height: barHeight)

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WorkspacePalette.slate)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private var bar: some View {
        if commitCount == 0 {
            Capsule()
                .fill(WorkspacePalette.border)
        } else if commitCount == maxCount {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [WorkspacePalette.green, WorkspacePalette.peach],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [WorkspacePalette.blue, WorkspacePalette.indigo],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private struct GitWorkingTreeLoadView: View {
    let buckets: [GitChangeBucket]

    var body: some View {
        let total = buckets.reduce(0) { $0 + $1.count }

        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WorkspacePalette.border)
                    .frame(height: 16)

                if total == 0 {
                    Capsule()
                        .fill(WorkspacePalette.green.opacity(0.26))
                        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                } else {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(buckets.filter { $0.count > 0 }) { bucket in
                                bucket.color
                                    .frame(width: proxy.size.width * CGFloat(bucket.count) / CGFloat(total))
                            }
                        }
                    }
                    .frame(height: 16)
                    .clipShape(Capsule())
                }
            }

            if total == 0 {
                Text("Working tree clean. No tracked or untracked file changes are currently open.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkspacePalette.body)
            } else {
                VStack(spacing: 8) {
                    ForEach(buckets) { bucket in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(bucket.color)
                                .frame(width: 8, height: 8)
                            Text(bucket.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WorkspacePalette.deepSlate)
                            Spacer()
                            Text("\(bucket.count) files")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WorkspacePalette.slate)
                        }
                        .opacity(bucket.count == 0 ? 0.55 : 1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255))
        )
    }
}

private struct DetailStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(WorkspacePalette.slate)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WorkspacePalette.body)
            Spacer()
        }
    }
}

private func workspaceStatus(for status: RunSessionStatus) -> WorkspaceStatus {
    switch status {
    case .pending:
        return .syncing
    case .running:
        return .running
    case .stopped, .failed:
        return .stopped
    }
}

private struct HeaderText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(WorkspacePalette.slate)
            .textCase(.uppercase)
    }
}

private struct DonutChartView: View {
    let areas: [FocusAreaModel]

    var body: some View {
        GeometryReader { geometry in
            let lineWidth = min(geometry.size.width, geometry.size.height) * 0.22
            let diameter = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .stroke(WorkspacePalette.border, lineWidth: lineWidth)

                ForEach(Array(areas.enumerated()), id: \.offset) { index, area in
                    let start = startFraction(for: index)
                    Circle()
                        .trim(from: start, to: start + area.percentage)
                        .stroke(
                            area.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func startFraction(for index: Int) -> Double {
        let previous = areas.prefix(index).reduce(0) { $0 + $1.percentage }
        return previous
    }
}

private struct RhythmChartView: View {
    let points: [RhythmPoint]

    private let yTicks: [Double] = [0, 65, 130, 195, 260]

    var body: some View {
        GeometryReader { proxy in
            let chartHeight = proxy.size.height - 28
            let chartWidth = proxy.size.width - 52
            let maxY = max(yTicks.last ?? 260, points.flatMap { [$0.builds, $0.product] }.max() ?? 260)

            ZStack {
                ForEach(yTicks, id: \.self) { tick in
                    let y = yPosition(for: tick, maxY: maxY, chartHeight: chartHeight)
                    Path { path in
                        path.move(to: CGPoint(x: 48, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(WorkspacePalette.border, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    Text("\(Int(tick))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WorkspacePalette.slate)
                        .position(x: 18, y: y)
                }

                let buildsPoints = chartPoints(for: \.builds, maxY: maxY, chartHeight: chartHeight, chartWidth: chartWidth)
                let productPoints = chartPoints(for: \.product, maxY: maxY, chartHeight: chartHeight, chartWidth: chartWidth)

                areaPath(for: buildsPoints, bottom: chartHeight)
                    .fill(
                        LinearGradient(
                            colors: [
                                WorkspacePalette.blue.opacity(0.10),
                                WorkspacePalette.blue.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                smoothPath(for: productPoints)
                    .stroke(Color.red.opacity(0.18), lineWidth: 2)

                smoothPath(for: buildsPoints)
                    .stroke(WorkspacePalette.ink, lineWidth: 2.5)

                HStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Text(point.month)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WorkspacePalette.slate)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: chartWidth)
                .position(x: 48 + chartWidth / 2, y: proxy.size.height - 10)
            }
        }
    }

    private func chartPoints(
        for keyPath: KeyPath<RhythmPoint, Double>,
        maxY: Double,
        chartHeight: CGFloat,
        chartWidth: CGFloat
    ) -> [CGPoint] {
        guard points.isEmpty == false else { return [] }
        return points.enumerated().map { index, point in
            let xStep = chartWidth / CGFloat(max(points.count - 1, 1))
            return CGPoint(
                x: 48 + CGFloat(index) * xStep,
                y: yPosition(for: point[keyPath: keyPath], maxY: maxY, chartHeight: chartHeight)
            )
        }
    }

    private func yPosition(for value: Double, maxY: Double, chartHeight: CGFloat) -> CGFloat {
        chartHeight - (CGFloat(value / maxY) * (chartHeight - 8))
    }

    private func smoothPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])

        for index in 1..<points.count {
            let current = points[index]
            let previous = points[index - 1]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)

            if index == 1 {
                path.addQuadCurve(to: mid, control: controlPoint(for: mid, previous: previous))
            } else {
                let previousMid = CGPoint(
                    x: (points[index - 2].x + previous.x) / 2,
                    y: (points[index - 2].y + previous.y) / 2
                )
                path.addCurve(
                    to: mid,
                    control1: controlPoint(for: previousMid, previous: previous),
                    control2: controlPoint(for: mid, previous: previous)
                )
            }

            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: controlPoint(for: current, previous: mid))
            }
        }

        return path
    }

    private func areaPath(for points: [CGPoint], bottom: CGFloat) -> Path {
        var path = smoothPath(for: points)
        guard let last = points.last, let first = points.first else {
            return path
        }
        path.addLine(to: CGPoint(x: last.x, y: bottom))
        path.addLine(to: CGPoint(x: first.x, y: bottom))
        path.closeSubpath()
        return path
    }

    private func controlPoint(for point: CGPoint, previous: CGPoint) -> CGPoint {
        CGPoint(x: (point.x + previous.x) / 2, y: previous.y)
    }
}

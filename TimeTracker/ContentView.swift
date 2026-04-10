import OSLog
import SwiftData
import SwiftUI

private enum SidebarSelection: Hashable {
    case dashboard
    case analytics
    case project(UUID)
}

private struct ProjectDraft {
    var name = ""
    var description = ""
    var color = "blue"
    var isArchived = false
}

private struct SubtaskDraft {
    var title = ""
    var notes = ""
}

private enum PendingConfirmation: Identifiable {
    case deleteProject(UUID)
    case resetProject(UUID)
    case deleteSubtask(UUID)
    case resetSubtask(UUID)

    var id: String {
        switch self {
        case let .deleteProject(id):
            return "delete-project-\(id.uuidString)"
        case let .resetProject(id):
            return "reset-project-\(id.uuidString)"
        case let .deleteSubtask(id):
            return "delete-subtask-\(id.uuidString)"
        case let .resetSubtask(id):
            return "reset-subtask-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .deleteProject:
            return "Delete Project?"
        case .resetProject:
            return "Reset Project Time?"
        case .deleteSubtask:
            return "Delete Subtask?"
        case .resetSubtask:
            return "Reset Subtask Time?"
        }
    }

    var message: String {
        switch self {
        case .deleteProject:
            return "This removes the project, its subtasks, notes, attachments, and tracked sessions."
        case .resetProject:
            return "This clears every tracked session inside the project, but keeps the project and its subtasks."
        case .deleteSubtask:
            return "This removes the subtask and all of its tracked sessions."
        case .resetSubtask:
            return "This clears the tracked time for the subtask but keeps its details."
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteProject, .deleteSubtask:
            return "Delete"
        case .resetProject, .resetSubtask:
            return "Reset"
        }
    }
}

private struct SessionRowItem: Identifiable {
    let id: UUID
    let projectID: UUID
    let projectName: String
    let projectColor: Color
    let subtaskID: UUID
    let subtaskTitle: String
    let startTime: Date
    let endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var isRunning: Bool {
        endTime == nil
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Project.createdAt, order: .reverse)
    private var projects: [Project]

    @ObservedObject private var timerManager = TimerManager.shared

    @State private var selection: SidebarSelection = .dashboard
    @State private var searchText = ""
    @State private var saveErrorMessage: String?

    @State private var projectDraft = ProjectDraft()
    @State private var editingProjectID: UUID?
    @State private var showingProjectEditor = false

    @State private var subtaskDraft = SubtaskDraft()
    @State private var editingSubtaskID: UUID?
    @State private var parentProjectIDForSubtask: UUID?
    @State private var showingSubtaskEditor = false

    @State private var pendingConfirmation: PendingConfirmation?

    private var filteredProjects: [Project] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return projects
        }

        let query = searchText.localizedLowercase
        return projects.filter { project in
            project.name.localizedLowercase.contains(query)
                || (project.projectDescription?.localizedLowercase.contains(query) ?? false)
                || (project.subtasks ?? []).contains(where: {
                    $0.title.localizedLowercase.contains(query)
                        || ($0.notes?.localizedLowercase.contains(query) ?? false)
                })
        }
    }

    private var activeProjects: [Project] {
        filteredProjects.filter { !$0.isArchived }
    }

    private var archivedProjects: [Project] {
        filteredProjects.filter(\.isArchived)
    }

    private var selectedProject: Project? {
        guard case let .project(id) = selection else { return nil }
        return projects.first(where: { $0.id == id })
    }

    private var allSessions: [SessionRowItem] {
        projects
            .flatMap { project in
                (project.subtasks ?? []).flatMap { subtask in
                    (subtask.timeLogs ?? []).map { log in
                        SessionRowItem(
                            id: log.id,
                            projectID: project.id,
                            projectName: project.name,
                            projectColor: project.swatchColor,
                            subtaskID: subtask.id,
                            subtaskTitle: subtask.title,
                            startTime: log.startTime,
                            endTime: log.endTime
                        )
                    }
                }
            }
            .sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    SidebarStaticRow(
                        title: "Overview",
                        subtitle: "\(projects.count) projects",
                        symbol: "sparkles.rectangle.stack",
                        tint: .orange
                    )
                    .tag(SidebarSelection.dashboard)

                    SidebarStaticRow(
                        title: "Analytics",
                        subtitle: "Trends and deep dives",
                        symbol: "chart.bar.xaxis",
                        tint: .indigo
                    )
                    .tag(SidebarSelection.analytics)
                }

                Section("Active Projects") {
                    ForEach(activeProjects, id: \.id) { project in
                        SidebarProjectRow(project: project)
                            .tag(SidebarSelection.project(project.id))
                            .contextMenu {
                                projectContextMenu(project)
                            }
                    }
                }

                if !archivedProjects.isEmpty {
                    Section("Archived") {
                        ForEach(archivedProjects, id: \.id) { project in
                            SidebarProjectRow(project: project)
                                .tag(SidebarSelection.project(project.id))
                                .contextMenu {
                                    projectContextMenu(project)
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 280)
            .searchable(text: $searchText, placement: .sidebar)
            .safeAreaInset(edge: .top) {
                sidebarHero
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let project = selectedProject {
                        Button("New Subtask", systemImage: "square.and.pencil") {
                            beginCreatingSubtask(for: project)
                        }
                    }

                    Button("New Project", systemImage: "plus") {
                        beginCreatingProject()
                    }

                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                }
            }
        } detail: {
                ZStack {
                    Color(NSColor.controlBackgroundColor)
                        .ignoresSafeArea()

                    switch selection {
                case .dashboard:
                    WorkspaceDashboardView(
                        projects: projects,
                        sessions: allSessions,
                        activeSession: timerManager.activeSession,
                        onCreateProject: beginCreatingProject,
                        onOpenAnalytics: { selection = .analytics },
                        onOpenProject: { project in selection = .project(project.id) }
                    )
                case .analytics:
                    AnalyticsView(projects: projects)
                        .padding(24)
                case .project:
                    if let project = selectedProject {
                        ProjectWorkspaceView(
                            project: project,
                            activeSession: timerManager.activeSession,
                            onEditProject: { beginEditingProject(project) },
                            onToggleArchive: { toggleArchive(for: project) },
                            onCreateSubtask: { beginCreatingSubtask(for: project) },
                            onEditSubtask: beginEditingSubtask,
                            onDeleteProject: { pendingConfirmation = .deleteProject(project.id) },
                            onResetProject: { pendingConfirmation = .resetProject(project.id) },
                            onDeleteSubtask: { pendingConfirmation = .deleteSubtask($0.id) },
                            onResetSubtask: { pendingConfirmation = .resetSubtask($0.id) }
                        )
                    } else {
                        ContentUnavailableView(
                            "Project not found",
                            systemImage: "folder.badge.questionmark",
                            description: Text("Select another project from the sidebar.")
                        )
                    }
                }
            }
        }
        .navigationTitle("TimeTracker")
        .sheet(isPresented: $showingProjectEditor) {
            ProjectEditorSheet(
                title: editingProjectID == nil ? "New Project" : "Edit Project",
                draft: $projectDraft,
                onCancel: { showingProjectEditor = false },
                onSave: saveProjectDraft
            )
        }
        .sheet(isPresented: $showingSubtaskEditor) {
            SubtaskEditorSheet(
                title: editingSubtaskID == nil ? "New Subtask" : "Edit Subtask",
                draft: $subtaskDraft,
                onCancel: { showingSubtaskEditor = false },
                onSave: saveSubtaskDraft
            )
        }
        .alert("Couldn't Save Changes", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "TimeTracker was unable to save your latest changes.")
        }
        .alert(item: $pendingConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.confirmTitle)) {
                    handle(confirmation)
                },
                secondaryButton: .cancel()
            )
        }
        .task {
            reconcileSelection()

            if !PreviewMode.isActive {
                appState.refreshCalendarStatus()
            }
        }
        .onChange(of: projects.map(\.id)) { _, _ in
            reconcileSelection()
        }
    }

    private var sidebarHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Studio")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text("Track deeply, review clearly, sync the way you want.")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            HStack(spacing: 12) {
                MiniMetric(value: projects.count.formatted(), label: "Projects")
                MiniMetric(value: appState.storeLocationTitle, label: "Store")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button("Edit") {
            beginEditingProject(project)
        }

        Button(project.isArchived ? "Unarchive" : "Archive") {
            toggleArchive(for: project)
        }

        Button("Reset Time") {
            pendingConfirmation = .resetProject(project.id)
        }

        Button("Delete", role: .destructive) {
            pendingConfirmation = .deleteProject(project.id)
        }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func reconcileSelection() {
        switch selection {
        case .dashboard, .analytics:
            break
        case let .project(projectID):
            if !projects.contains(where: { $0.id == projectID }) {
                selection = .dashboard
            }
        }
    }

    private func beginCreatingProject() {
        editingProjectID = nil
        projectDraft = ProjectDraft()
        showingProjectEditor = true
    }

    private func beginEditingProject(_ project: Project) {
        editingProjectID = project.id
        projectDraft = ProjectDraft(
            name: project.name,
            description: project.projectDescription ?? "",
            color: project.color,
            isArchived: project.isArchived
        )
        showingProjectEditor = true
    }

    private func toggleArchive(for project: Project) {
        project.isArchived.toggle()
        let action = project.isArchived ? "archiving a project" : "unarchiving a project"

        guard saveContext(action: action) else {
            project.isArchived.toggle()
            return
        }

        selection = .project(project.id)
    }

    private func saveProjectDraft() {
        let trimmedName = projectDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDraft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let editingProjectID,
           let project = projects.first(where: { $0.id == editingProjectID }) {
            project.name = trimmedName
            project.projectDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
            project.color = projectDraft.color
            project.isArchived = projectDraft.isArchived

            guard saveContext(action: "updating a project") else { return }
            selection = .project(project.id)
        } else {
            let project = Project(
                name: trimmedName,
                projectDescription: trimmedDescription.isEmpty ? nil : trimmedDescription
            )
            project.color = projectDraft.color
            project.isArchived = projectDraft.isArchived
            modelContext.insert(project)

            guard saveContext(action: "creating a project") else { return }
            selection = .project(project.id)
        }

        showingProjectEditor = false
    }

    private func beginCreatingSubtask(for project: Project) {
        parentProjectIDForSubtask = project.id
        editingSubtaskID = nil
        subtaskDraft = SubtaskDraft()
        showingSubtaskEditor = true
    }

    private func beginEditingSubtask(_ subtask: Subtask) {
        parentProjectIDForSubtask = subtask.project?.id
        editingSubtaskID = subtask.id
        subtaskDraft = SubtaskDraft(
            title: subtask.title,
            notes: subtask.notes ?? ""
        )
        showingSubtaskEditor = true
    }

    private func saveSubtaskDraft() {
        let trimmedTitle = subtaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = subtaskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let editingSubtaskID,
           let subtask = projects
            .flatMap({ $0.subtasks ?? [] })
            .first(where: { $0.id == editingSubtaskID }) {
            subtask.title = trimmedTitle
            subtask.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

            guard saveContext(action: "updating a subtask") else { return }
        } else if let projectID = parentProjectIDForSubtask,
                  let project = projects.first(where: { $0.id == projectID }) {
            let subtask = Subtask(title: trimmedTitle, project: project)
            subtask.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            modelContext.insert(subtask)

            guard saveContext(action: "creating a subtask") else { return }
            selection = .project(project.id)
        }

        showingSubtaskEditor = false
    }

    private func handle(_ confirmation: PendingConfirmation) {
        switch confirmation {
        case let .deleteProject(projectID):
            guard let project = projects.first(where: { $0.id == projectID }) else { return }
            if timerManager.activeSession?.subtask?.project?.id == project.id {
                timerManager.stopTimer()
            }
            modelContext.delete(project)
            if selection == .project(project.id) {
                selection = .dashboard
            }
            _ = saveContext(action: "deleting a project")

        case let .resetProject(projectID):
            guard let project = projects.first(where: { $0.id == projectID }) else { return }
            if timerManager.activeSession?.subtask?.project?.id == project.id {
                timerManager.stopTimer()
            }
            for subtask in project.subtasks ?? [] {
                for log in subtask.timeLogs ?? [] {
                    modelContext.delete(log)
                }
            }
            _ = saveContext(action: "resetting project time")

        case let .deleteSubtask(subtaskID):
            guard let subtask = projects.flatMap({ $0.subtasks ?? [] }).first(where: { $0.id == subtaskID }) else { return }
            if timerManager.activeSession?.subtask?.id == subtask.id {
                timerManager.stopTimer()
            }
            modelContext.delete(subtask)
            _ = saveContext(action: "deleting a subtask")

        case let .resetSubtask(subtaskID):
            guard let subtask = projects.flatMap({ $0.subtasks ?? [] }).first(where: { $0.id == subtaskID }) else { return }
            if timerManager.activeSession?.subtask?.id == subtask.id {
                timerManager.stopTimer()
            }
            for log in subtask.timeLogs ?? [] {
                modelContext.delete(log)
            }
            _ = saveContext(action: "resetting subtask time")
        }
    }

    @discardableResult
    private func saveContext(action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.persistence.error("Failed while \(action, privacy: .public): \(error.localizedDescription, privacy: .public)")
            saveErrorMessage = "TimeTracker could not finish \(action). Please try again."
            return false
        }
    }
}

private struct SidebarStaticRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundColor(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SidebarProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.swatchColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                Text(project.summaryLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if project.isArchived {
                Image(systemName: "archivebox")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MiniMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct WorkspaceDashboardView: View {
    let projects: [Project]
    let sessions: [SessionRowItem]
    let activeSession: TimeLog?
    let onCreateProject: () -> Void
    let onOpenAnalytics: () -> Void
    let onOpenProject: (Project) -> Void

    private var activeProjects: [Project] {
        projects.filter { !$0.isArchived }
    }

    private var totalTrackedTime: TimeInterval {
        projects.reduce(0) { $0 + $1.totalTrackedTime }
    }

    private var averageSessionLength: TimeInterval {
        let completedSessions = sessions.filter { !$0.isRunning }
        guard !completedSessions.isEmpty else { return 0 }
        return completedSessions.reduce(0) { $0 + $1.duration } / Double(completedSessions.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroCard

                HStack(spacing: 16) {
                    InsightCard(title: "Tracked Time", value: totalTrackedTime.readableDuration, accent: .orange)
                    InsightCard(title: "Active Projects", value: activeProjects.count.formatted(), accent: .blue)
                    InsightCard(title: "Avg Session", value: averageSessionLength.readableDuration, accent: .green)
                    InsightCard(title: "Recent Sessions", value: sessions.filter { !$0.isRunning }.count.formatted(), accent: .indigo)
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionTitle("Project Momentum")

                        if activeProjects.isEmpty {
                            ContentUnavailableView(
                                "No active projects",
                                systemImage: "folder.badge.plus",
                                description: Text("Create a project to start building your workspace.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .cardStyle()
                        } else {
                            ForEach(activeProjects.prefix(4), id: \.id) { project in
                                Button {
                                    onOpenProject(project)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(project.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(project.summaryLine)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(project.totalTrackedTime.readableDuration)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(project.swatchColor)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .cardStyle()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        sectionTitle("Recent Sessions")

                        if sessions.isEmpty {
                            ContentUnavailableView(
                                "No sessions yet",
                                systemImage: "clock.arrow.circlepath",
                                description: Text("Start and stop a timer to populate your activity stream.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .cardStyle()
                        } else {
                            ForEach(sessions.prefix(6)) { session in
                                SessionActivityRow(item: session)
                                    .cardStyle()
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspace Overview")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text("A calmer way to run projects, capture time, and keep the details close at hand.")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            if let activeSession, let subtask = activeSession.subtask {
                Label("Timer running for \(subtask.title)", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                Button("New Project", action: onCreateProject)
                    .buttonStyle(.borderedProminent)

                Button("Open Analytics", action: onOpenAnalytics)
                    .buttonStyle(.bordered)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
    }
}

private struct ProjectWorkspaceView: View {
    let project: Project
    let activeSession: TimeLog?
    let onEditProject: () -> Void
    let onToggleArchive: () -> Void
    let onCreateSubtask: () -> Void
    let onEditSubtask: (Subtask) -> Void
    let onDeleteProject: () -> Void
    let onResetProject: () -> Void
    let onDeleteSubtask: (Subtask) -> Void
    let onResetSubtask: (Subtask) -> Void

    @ObservedObject private var timerManager = TimerManager.shared

    private var subtasks: [Subtask] {
        (project.subtasks ?? []).sorted {
            $0.totalTime == $1.totalTime
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : $0.totalTime > $1.totalTime
        }
    }

    private var recentSessions: [SessionRowItem] {
        subtasks.flatMap { subtask in
            (subtask.timeLogs ?? []).map { log in
                SessionRowItem(
                    id: log.id,
                    projectID: project.id,
                    projectName: project.name,
                    projectColor: project.swatchColor,
                    subtaskID: subtask.id,
                    subtaskTitle: subtask.title,
                    startTime: log.startTime,
                    endTime: log.endTime
                )
            }
        }
        .sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerCard

                HStack(spacing: 16) {
                    InsightCard(title: "Tracked Time", value: project.totalTrackedTime.readableDuration, accent: project.swatchColor)
                    InsightCard(title: "Subtasks", value: subtasks.count.formatted(), accent: .orange)
                    InsightCard(title: "Sessions", value: recentSessions.filter { !$0.isRunning }.count.formatted(), accent: .green)
                    InsightCard(title: "Last Activity", value: project.lastActivityText, accent: .indigo)
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Subtasks", actionTitle: "New Subtask", action: onCreateSubtask)

                    if subtasks.isEmpty {
                        ContentUnavailableView(
                            "No subtasks yet",
                            systemImage: "checklist",
                            description: Text("Create a subtask to start tracking specific pieces of work.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .cardStyle()
                    } else {
                        ForEach(subtasks) { subtask in
                            SubtaskCard(
                                subtask: subtask,
                                isRunning: activeSession?.subtask?.id == subtask.id,
                                onToggleTimer: { timerManager.toggleTimer(for: subtask) },
                                onEdit: { onEditSubtask(subtask) },
                                onReset: { onResetSubtask(subtask) },
                                onDelete: { onDeleteSubtask(subtask) }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Recent Sessions")

                    if recentSessions.isEmpty {
                        ContentUnavailableView(
                            "No recent sessions",
                            systemImage: "calendar.badge.clock",
                            description: Text("Finished tracking sessions will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .cardStyle()
                    } else {
                        ForEach(recentSessions.prefix(8)) { session in
                            SessionActivityRow(item: session)
                                .cardStyle()
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(project.swatchColor)
                            .frame(width: 14, height: 14)
                        Text(project.name)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }

                    if let description = project.projectDescription, !description.isEmpty {
                        Text(description)
                            .foregroundColor(.secondary)
                    }

                    Text(project.summaryLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(project.swatchColor)
                }

                Spacer()

                Menu {
                    Button("Edit Project", action: onEditProject)
                    Button(project.isArchived ? "Unarchive" : "Archive", action: onToggleArchive)
                    Divider()
                    Button("Reset All Time", action: onResetProject)
                    Button("Delete Project", role: .destructive, action: onDeleteProject)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 12) {
                Button("Edit Project", action: onEditProject)
                    .buttonStyle(.borderedProminent)

                Button("New Subtask", action: onCreateSubtask)
                    .buttonStyle(.bordered)

                Button(project.isArchived ? "Unarchive" : "Archive", action: onToggleArchive)
                    .buttonStyle(.bordered)

                Button("Reset Time", action: onResetProject)
                    .buttonStyle(.bordered)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func sectionHeader(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct InsightCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(accent)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

private struct SubtaskCard: View {
    let subtask: Subtask
    let isRunning: Bool
    let onToggleTimer: () -> Void
    let onEdit: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(subtask.title)
                            .font(.headline)

                        if isRunning {
                            Text("Running")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.thinMaterial))
                                .foregroundColor(.green)
                        }
                    }

                    if let notes = subtask.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onToggleTimer) {
                        Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(isRunning ? .red : .green)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("Edit", action: onEdit)
                        Button("Reset Time", action: onReset)
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            HStack(spacing: 18) {
                DetailPill(title: "Tracked", value: subtask.totalTime.readableDuration)
                DetailPill(title: "Sessions", value: subtask.completedSessionCount.formatted())
                DetailPill(title: "Last Worked", value: subtask.lastActivityText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

private struct DetailPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct SessionActivityRow: View {
    let item: SessionRowItem

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(item.projectColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.subtaskTitle)
                    .font(.headline)
                Text(item.projectName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.duration.readableDuration)
                    .font(.subheadline.weight(.semibold))
                Text(item.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

private struct ProjectEditorSheet: View {
    let title: String
    @Binding var draft: ProjectDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    private let colors = ["blue", "green", "orange", "pink", "indigo", "teal", "red", "purple"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Project Name", text: $draft.name)
                    TextField("Description", text: $draft.description, axis: .vertical)
                        .lineLimit(3...5)
                    Toggle("Archived", isOn: $draft.isArchived)
                }

                Section("Accent Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(colors, id: \.self) { colorName in
                            Button {
                                draft.color = colorName
                            } label: {
                                Circle()
                                    .fill(Project.colorValue(for: colorName))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(draft.color == colorName ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
    }
}

private struct SubtaskEditorSheet: View {
    let title: String
    @Binding var draft: SubtaskDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Subtask Title", text: $draft.title)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(0)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            )
    }
}

extension Project {
    var swatchColor: Color {
        Self.colorValue(for: color)
    }

    static func colorValue(for colorName: String) -> Color {
        switch colorName.lowercased() {
        case "red":
            return .red
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "green":
            return .green
        case "mint":
            return .mint
        case "teal":
            return .teal
        case "cyan":
            return .cyan
        case "indigo":
            return .indigo
        case "purple":
            return .purple
        case "pink":
            return .pink
        default:
            return .blue
        }
    }

    var totalTrackedTime: TimeInterval {
        (subtasks ?? []).reduce(0) { $0 + $1.totalTime }
    }

    var summaryLine: String {
        let subtaskCount = (subtasks ?? []).count
        return "\(totalTrackedTime.readableDuration) • \(subtaskCount) subtasks"
    }

    var lastActivityDate: Date? {
        (subtasks ?? [])
            .flatMap { $0.timeLogs ?? [] }
            .map { $0.endTime ?? $0.startTime }
            .max()
    }

    var lastActivityText: String {
        guard let lastActivityDate else { return "No sessions" }
        return lastActivityDate.formatted(date: .abbreviated, time: .shortened)
    }
}

extension Subtask {
    var completedSessionCount: Int {
        (timeLogs ?? []).filter { $0.endTime != nil }.count
    }

    var lastActivityDate: Date? {
        (timeLogs ?? []).map { $0.endTime ?? $0.startTime }.max()
    }

    var lastActivityText: String {
        guard let lastActivityDate else { return "No sessions" }
        return lastActivityDate.formatted(date: .abbreviated, time: .shortened)
    }
}

extension TimeInterval {
    var readableDuration: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}

#Preview {
    let schema = Schema([Project.self, Subtask.self, TimeLog.self, Note.self, Attachment.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)

    let context = container.mainContext
    let project = Project(name: "Preview Project", projectDescription: "Sample description")
    project.color = "orange"
    context.insert(project)

    let subtask = Subtask(title: "Design", project: project)
    subtask.notes = "Refine the dashboard layout and ship the new timer flow."
    context.insert(subtask)

    let session = TimeLog(subtask: subtask, startTime: .now.addingTimeInterval(-5400))
    session.endTime = .now.addingTimeInterval(-1800)
    context.insert(session)

    return ContentView()
        .environmentObject(AppState())
        .modelContainer(container)
        .frame(minWidth: 1000, minHeight: 700)
}

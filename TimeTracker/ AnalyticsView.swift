// AnalyticsView.swift
import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(filter: #Predicate<Project> { $0.isArchived == false })
    var projects: [Project]
    
    var body: some View {
        TabView {
            ProjectSummaryView(projects: projects)
                .tabItem { Label("Projects", systemImage: "folder") }
            TimeDistributionView(projects: projects)
                .tabItem { Label("Time Distribution", systemImage: "chart.pie") }
            TimelineView(projects: projects)
                .tabItem { Label("Timeline", systemImage: "calendar") }
        }
    }
}

struct ProjectSummaryView: View {
    let projects: [Project]
    
    var body: some View {
        List(projects) { project in
            VStack(alignment: .leading) {
                Text(project.name)
                    .font(.headline)
                Text("Total time: \(formatTime(projectTotalTime(project)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func projectTotalTime(_ project: Project) -> TimeInterval {
        (project.subtasks ?? []).reduce(0) { $0 + $1.totalTime }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct TimeDistributionView: View {
    let projects: [Project]
    
    var timeData: [(id: UUID, project: String, time: TimeInterval)] {
        projects.map { project in
            let total = (project.subtasks ?? []).reduce(0) { $0 + $1.totalTime }
            return (project.id, project.name, total)
        }
        .filter { $0.time > 0 }
    }
    
    var body: some View {
        VStack {
            Chart(timeData, id: \.id) { item in
                SectorMark(
                    angle: .value("Time", item.time),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .cornerRadius(5)
                .foregroundStyle(by: .value("Project", item.project))
            }
            .frame(height: 300)
            .padding()
            
            List(timeData, id: \.id) { item in
                HStack {
                    Text(item.project)
                    Spacer()
                    Text(formatTime(item.time))
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct TimelineView: View {
    let projects: [Project]
    
    var body: some View {
        VStack {
            Text("Timeline View")
                .font(.title)
            Text("Coming soon...")
                .foregroundColor(.secondary)
        }
    }
}

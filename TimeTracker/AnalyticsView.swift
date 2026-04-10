import Charts
import SwiftUI

private enum AnalyticsRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenDays:
            return "7D"
        case .thirtyDays:
            return "30D"
        case .ninetyDays:
            return "90D"
        case .allTime:
            return "All"
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: .now)
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: .now)
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -89, to: .now)
        case .allTime:
            return nil
        }
    }
}

private struct AnalyticsSession: Identifiable {
    let id: UUID
    let projectName: String
    let projectColor: Color
    let subtaskName: String
    let startTime: Date
    let endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}

private struct DailyAnalyticsBucket: Identifiable {
    let day: Date
    let totalTime: TimeInterval

    var id: Date { day }
    var totalHours: Double { totalTime / 3600.0 }
}

private struct ProjectAnalyticsSlice: Identifiable {
    let id: UUID
    let name: String
    let totalTime: TimeInterval
    let color: Color
}

private struct SubtaskAnalyticsItem: Identifiable {
    let id: String
    let projectName: String
    let subtaskName: String
    let totalTime: TimeInterval
}

struct AnalyticsView: View {
    let projects: [Project]

    @State private var selectedRange: AnalyticsRange = .thirtyDays

    private var sessions: [AnalyticsSession] {
        projects.flatMap { project in
            (project.subtasks ?? []).flatMap { subtask in
                (subtask.timeLogs ?? []).map { log in
                    AnalyticsSession(
                        id: log.id,
                        projectName: project.name,
                        projectColor: project.swatchColor,
                        subtaskName: subtask.title,
                        startTime: log.startTime,
                        endTime: log.endTime
                    )
                }
            }
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private var filteredSessions: [AnalyticsSession] {
        guard let cutoffDate = selectedRange.cutoffDate else {
            return sessions
        }

        return sessions.filter { $0.startTime >= cutoffDate }
    }

    private var projectSlices: [ProjectAnalyticsSlice] {
        Dictionary(grouping: filteredSessions, by: \.projectName)
            .compactMap { projectName, entries in
                guard let project = projects.first(where: { $0.name == projectName }) else { return nil }
                return ProjectAnalyticsSlice(
                    id: project.id,
                    name: projectName,
                    totalTime: entries.reduce(0) { $0 + $1.duration },
                    color: project.swatchColor
                )
            }
            .sorted { $0.totalTime > $1.totalTime }
    }

    private var topSubtasks: [SubtaskAnalyticsItem] {
        Dictionary(grouping: filteredSessions, by: { "\($0.projectName)::\($0.subtaskName)" })
            .map { key, entries in
                let projectName = entries.first?.projectName ?? "Project"
                let subtaskName = entries.first?.subtaskName ?? "Subtask"
                return SubtaskAnalyticsItem(
                    id: key,
                    projectName: projectName,
                    subtaskName: subtaskName,
                    totalTime: entries.reduce(0) { $0 + $1.duration }
                )
            }
            .sorted { $0.totalTime > $1.totalTime }
    }

    private var dailyBuckets: [DailyAnalyticsBucket] {
        Dictionary(grouping: filteredSessions, by: { Calendar.current.startOfDay(for: $0.startTime) })
            .map { day, entries in
                DailyAnalyticsBucket(day: day, totalTime: entries.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.day < $1.day }
    }

    private var totalTrackedTime: TimeInterval {
        filteredSessions.reduce(0) { $0 + $1.duration }
    }

    private var completedSessionCount: Int {
        filteredSessions.filter { $0.endTime != nil }.count
    }

    private var averageSession: TimeInterval {
        guard !filteredSessions.isEmpty else { return 0 }
        return totalTrackedTime / Double(filteredSessions.count)
    }

    private var longestSession: TimeInterval {
        filteredSessions.map(\.duration).max() ?? 0
    }

    private var activeDayCount: Int {
        dailyBuckets.count
    }

    private var focusDayLabel: String {
        guard let focusDay = dailyBuckets.max(by: { $0.totalTime < $1.totalTime }) else {
            return "No data"
        }

        return focusDay.day.formatted(date: .abbreviated, time: .omitted)
    }

    private var topProjectLabel: String {
        projectSlices.first?.name ?? "No data"
    }

    var body: some View {
        if projects.isEmpty {
            ContentUnavailableView(
                "No analytics yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Create a project and log some time to unlock analytics.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    analyticsHero
                    rangePicker

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        AnalyticsMetricCard(title: "Tracked Time", value: totalTrackedTime.readableDuration, tint: .orange)
                        AnalyticsMetricCard(title: "Sessions", value: completedSessionCount.formatted(), tint: .pink)
                        AnalyticsMetricCard(title: "Avg Session", value: averageSession.readableDuration, tint: .green)
                        AnalyticsMetricCard(title: "Longest Session", value: longestSession.readableDuration, tint: .indigo)
                        AnalyticsMetricCard(title: "Active Days", value: activeDayCount.formatted(), tint: .teal)
                        AnalyticsMetricCard(title: "Focus Day", value: focusDayLabel, tint: .blue)
                        AnalyticsMetricCard(title: "Top Project", value: topProjectLabel, tint: .orange)
                    }

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Daily Trend")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))

                            if dailyBuckets.isEmpty {
                                emptyCard(
                                    title: "No sessions in this range",
                                    symbol: "waveform.path.ecg",
                                    message: "Try a wider time range or start logging new sessions."
                                )
                            } else {
                                Chart(dailyBuckets) { bucket in
                                    BarMark(
                                        x: .value("Day", bucket.day, unit: .day),
                                        y: .value("Hours", bucket.totalHours)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .yellow],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .cornerRadius(6)
                                }
                                .frame(height: 280)
                                .chartYAxisLabel("Hours")
                                .analyticsCardStyle()
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Project Share")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))

                            if projectSlices.isEmpty {
                                emptyCard(
                                    title: "No project breakdown yet",
                                    symbol: "chart.pie",
                                    message: "Project share appears once tracked sessions exist in the selected range."
                                )
                            } else {
                                VStack(spacing: 18) {
                                    Chart(projectSlices) { item in
                                        SectorMark(
                                            angle: .value("Time", item.totalTime),
                                            innerRadius: .ratio(0.55),
                                            angularInset: 1.5
                                        )
                                        .foregroundStyle(item.color)
                                    }
                                    .frame(height: 220)

                                    ForEach(projectSlices.prefix(5)) { item in
                                        HStack {
                                            Circle()
                                                .fill(item.color)
                                                .frame(width: 9, height: 9)
                                            Text(item.name)
                                            Spacer()
                                            Text(item.totalTime.readableDuration)
                                                .foregroundColor(.secondary)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                                .analyticsCardStyle()
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Top Subtasks")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))

                            if topSubtasks.isEmpty {
                                emptyCard(
                                    title: "No subtask insights yet",
                                    symbol: "checklist",
                                    message: "Top subtasks show up after you complete tracked sessions."
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(topSubtasks.prefix(8)) { item in
                                        HStack(alignment: .firstTextBaseline) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.subtaskName)
                                                    .font(.headline)
                                                Text(item.projectName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(item.totalTime.readableDuration)
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(Color.secondary.opacity(0.08))
                                        )
                                    }
                                }
                                .analyticsCardStyle()
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Session Timeline")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))

                            if filteredSessions.isEmpty {
                                emptyCard(
                                    title: "No timeline entries yet",
                                    symbol: "calendar.badge.clock",
                                    message: "Once sessions are logged, this timeline shows their order and length."
                                )
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(filteredSessions.prefix(10)) { session in
                                        AnalyticsTimelineRow(session: session)
                                    }
                                }
                                .analyticsCardStyle()
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private var analyticsHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analytics")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text("See where your attention went, how work is trending, and which tasks are doing the heavy lifting.")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("\(projects.count) total projects • \(filteredSessions.count) sessions in view")
                .foregroundColor(.secondary)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private func emptyCard(title: String, symbol: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 240)
            .analyticsCardStyle()
    }
}

private struct AnalyticsMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsCardStyle()
    }
}

private struct AnalyticsTimelineRow: View {
    let session: AnalyticsSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.projectColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.subtaskName)
                    .font(.headline)
                Text(session.projectName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.duration.readableDuration)
                    .font(.subheadline.weight(.semibold))
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private extension View {
    func analyticsCardStyle() -> some View {
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            )
    }
}

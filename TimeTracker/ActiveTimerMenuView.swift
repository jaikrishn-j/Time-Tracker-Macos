// ActiveTimerMenuView.swift
import OSLog
import SwiftData
import SwiftUI
import AppKit

struct ActiveTimerMenuView: View {
    let session: TimeLog
    @Environment(\.modelContext) private var modelContext

    @State private var elapsed: String = "00:00:00"
    @State private var timer: Timer?
    @State private var calendarErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let subtask = session.subtask {
                Text("Running: \(subtask.title)")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } else {
                Text("Running timer")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(elapsed)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Divider()

            Button("Stop Timer") {
                TimerManager.shared.stopTimer()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            if !session.isLinkedToCalendar {
                Button("Link to Calendar") {
                    linkToCalendar()
                }
                .disabled(session.endTime == nil)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        )
        .padding(12)
        .frame(width: 280)
        .onAppear {
            startElapsedTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .alert("Calendar Error", isPresented: calendarErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarErrorMessage ?? "Something went wrong while linking the event.")
        }
    }

    private var calendarErrorIsPresented: Binding<Bool> {
        Binding(
            get: { calendarErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    calendarErrorMessage = nil
                }
            }
        )
    }

    private func startElapsedTimer() {
        updateElapsedTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateElapsedTime()
        }
    }

    private func updateElapsedTime() {
        let endTime = session.endTime ?? Date()
        let interval = max(0, endTime.timeIntervalSince(session.startTime))
        elapsed = formatTimeInterval(interval)
    }

    private func linkToCalendar() {
        CalendarIntegration.shared.createEvent(for: session) { success in
            guard success else {
                calendarErrorMessage = "TimeTracker could not create the calendar event. Check Calendar access in System Settings and try again."
                return
            }

            do {
                try modelContext.save()
            } catch {
                AppLogger.calendar.error("Created calendar event but failed to save link locally: \(error.localizedDescription, privacy: .public)")
                calendarErrorMessage = "The calendar event was created, but TimeTracker could not save the local link."
            }
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

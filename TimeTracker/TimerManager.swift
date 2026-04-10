// TimerManager.swift
import Combine
import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    static let timerStatusChanged = Notification.Name("timerStatusChanged")
}

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published private(set) var activeSession: TimeLog?
    @Published private(set) var isTimerRunning = false

    private var timer: Timer?
    private var modelContainer: ModelContainer?

    private init() {}

    func configure(with container: ModelContainer) {
        modelContainer = container
        restoreState(from: container)
    }

    func startTimer(for subtask: Subtask) {
        guard !PreviewMode.isActive,
              let container = modelContainer else { return }

        if activeSession?.subtask == subtask {
            return
        }

        if activeSession != nil {
            stopTimer()
        }

        timer?.invalidate()

        let context = container.mainContext
        let log = TimeLog(subtask: subtask)
        context.insert(log)

        activeSession = log
        isTimerRunning = true

        persist(context, action: "starting a timer")
        broadcastStateChange()
        startHeartbeat()
    }

    func stopTimer() {
        guard !PreviewMode.isActive,
              let container = modelContainer else { return }

        guard let session = activeSession else {
            stopHeartbeat()
            isTimerRunning = false
            broadcastStateChange()
            return
        }

        session.stop()
        activeSession = nil
        isTimerRunning = false
        stopHeartbeat()

        persist(container.mainContext, action: "stopping a timer")
        autoCreateCalendarEventIfNeeded(for: session)
        broadcastStateChange()
    }

    func toggleTimer(for subtask: Subtask) {
        guard !PreviewMode.isActive else { return }

        if isTimerRunning && activeSession?.subtask == subtask {
            stopTimer()
        } else {
            startTimer(for: subtask)
        }
    }

    private func broadcastStateChange() {
        NotificationCenter.default.post(name: .timerStatusChanged, object: nil)
    }

    private func restoreState(from container: ModelContainer) {
        stopHeartbeat()

        let descriptor = FetchDescriptor<TimeLog>(
            sortBy: [SortDescriptor(\TimeLog.startTime, order: .reverse)]
        )

        do {
            let openSession = try container.mainContext.fetch(descriptor).first(where: { $0.endTime == nil })
            activeSession = openSession
            isTimerRunning = openSession != nil

            if openSession != nil {
                startHeartbeat()
            }
        } catch {
            activeSession = nil
            isTimerRunning = false
            AppLogger.timers.error("Failed to restore timer state: \(error.localizedDescription, privacy: .public)")
        }

        broadcastStateChange()
    }

    private func startHeartbeat() {
        stopHeartbeat()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autosaveRunningTimer()
            }
        }
    }

    private func stopHeartbeat() {
        timer?.invalidate()
        timer = nil
    }

    private func autosaveRunningTimer() {
        guard let context = modelContainer?.mainContext else { return }
        persist(context, action: "autosaving a running timer")
    }

    private func autoCreateCalendarEventIfNeeded(for session: TimeLog) {
        guard AppPreferences.autoCreateCalendarEvents,
              CalendarIntegration.shared.isAuthorized else {
            return
        }

        CalendarIntegration.shared.createEvent(for: session) { [weak self] success in
            guard success, let self, let context = self.modelContainer?.mainContext else { return }
            self.persist(context, action: "saving an automatic calendar event link")
        }
    }

    private func persist(_ context: ModelContext, action: String) {
        do {
            try context.save()
        } catch {
            AppLogger.timers.error("Failed while \(action, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

import EventKit
import Foundation
import OSLog

final class CalendarIntegration {
    static let shared = CalendarIntegration()

    private let eventStore = EKEventStore()

    private init() {}

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func requestAccess(completion: @escaping (Bool, Error?) -> Void) {
        guard !PreviewMode.isActive else {
            completion(true, nil)
            return
        }

        switch authorizationStatus {
        case .authorized, .fullAccess:
            completion(true, nil)
            return
        case .denied, .restricted, .writeOnly:
            completion(false, nil)
            return
        case .notDetermined:
            break
        @unknown default:
            completion(false, nil)
            return
        }

        eventStore.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async {
                completion(granted, error)
            }
        }
    }

    func createEvent(for timeLog: TimeLog, completion: ((Bool) -> Void)? = nil) {
        guard !PreviewMode.isActive else {
            completion?(true)
            return
        }

        guard let endTime = timeLog.endTime,
              let subtask = timeLog.subtask,
              let project = subtask.project else {
            completion?(false)
            return
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            AppLogger.calendar.error("No default calendar was available for the new event.")
            completion?(false)
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = "\(subtask.title) - \(project.name)"
        event.startDate = timeLog.startTime
        event.endDate = endTime
        event.calendar = calendar
        event.notes = [project.projectDescription, subtask.notes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        do {
            try eventStore.save(event, span: .thisEvent)
            timeLog.isLinkedToCalendar = true
            timeLog.calendarEventID = event.eventIdentifier
            completion?(true)
        } catch {
            AppLogger.calendar.error("Failed to save calendar event: \(error.localizedDescription, privacy: .public)")
            completion?(false)
        }
    }
}

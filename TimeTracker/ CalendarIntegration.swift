// CalendarIntegration.swift
import EventKit
import Foundation

final class CalendarIntegration {
    static let shared = CalendarIntegration()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    func requestAccess(completion: @escaping (Bool, Error?) -> Void) {
        guard !PreviewMode.isActive else {
            completion(true, nil)
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
        
        let event = EKEvent(eventStore: eventStore)
        event.title = "⏱️ \(subtask.title) - \(project.name)"
        event.startDate = timeLog.startTime
        event.endDate = endTime
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.notes = subtask.notes ?? ""
        
        do {
            try eventStore.save(event, span: .thisEvent)
            timeLog.isLinkedToCalendar = true
            timeLog.calendarEventID = event.eventIdentifier
            completion?(true)
        } catch {
            print("Failed to save calendar event: \(error)")
            completion?(false)
        }
    }
}

import Foundation

extension CalendarIntegration {
    func createEvent(for timeLog: TimeLog, completion: ((Bool) -> Void)? = nil) {
        timeLog.isLinkedToCalendar = true
        if timeLog.calendarEventID == nil {
            timeLog.calendarEventID = UUID().uuidString
        }
        completion?(true)
    }
}

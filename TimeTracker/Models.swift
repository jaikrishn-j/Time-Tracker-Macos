// Models.swift
import SwiftData
import Foundation

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""                     // default value
    var projectDescription: String? = nil
    var color: String = "blue"
    var createdAt: Date = Date()
    var isArchived: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \Subtask.project)
    var subtasks: [Subtask]? = []             // optional relationship
    
    init(name: String, projectDescription: String? = nil) {
        self.name = name
        self.projectDescription = projectDescription
    }
}

@Model
final class Subtask {
    var id: UUID = UUID()
    var title: String = ""                    // default
    var notes: String? = nil
    
    var project: Project?                     // optional inverse
    
    @Relationship(deleteRule: .cascade, inverse: \TimeLog.subtask)
    var timeLogs: [TimeLog]? = []
    
    @Relationship(deleteRule: .cascade, inverse: \Attachment.subtask)
    var attachments: [Attachment]? = []
    
    // Inverse for Note
    @Relationship(deleteRule: .cascade, inverse: \Note.subtask)
    var notesRelationship: [Note]? = []       // CloudKit requires inverse
    
    var totalTime: TimeInterval {
        (timeLogs ?? []).reduce(0) { $0 + ($1.endTime ?? Date()).timeIntervalSince($1.startTime) }
    }
    
    init(title: String, project: Project) {
        self.title = title
        self.project = project
    }
}

@Model
final class TimeLog {
    var id: UUID = UUID()
    var startTime: Date = Date()              // default
    var endTime: Date? = nil
    var isLinkedToCalendar: Bool = false
    var calendarEventID: String? = nil
    
    var subtask: Subtask?                     // optional inverse
    
    init(subtask: Subtask, startTime: Date = Date()) {
        self.subtask = subtask
        self.startTime = startTime
    }
    
    func stop() {
        endTime = Date()
    }
}

@Model
final class Note {
    var id: UUID = UUID()
    var content: String = ""                  // default
    var createdAt: Date = Date()
    
    var subtask: Subtask?                     // optional with inverse
    
    init(content: String, subtask: Subtask? = nil) {
        self.content = content
        self.subtask = subtask
    }
}

@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""                 // default
    var fileData: Data = Data()               // default (empty Data)
    var mimeType: String = ""                 // default
    var uploadedAt: Date = Date()
    
    var subtask: Subtask?                     // optional inverse
    
    init(fileName: String, data: Data, mimeType: String, subtask: Subtask) {
        self.fileName = fileName
        self.fileData = data
        self.mimeType = mimeType
        self.subtask = subtask
    }
}

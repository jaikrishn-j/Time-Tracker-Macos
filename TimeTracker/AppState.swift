import AppKit
import Combine
import EventKit
import Foundation
import OSLog
import SwiftData

enum AppPreferences {
    static let syncFolderBookmarkKey = "timetracker.syncFolderBookmark"
    static let autoCreateCalendarEventsKey = "timetracker.autoCreateCalendarEvents"

    static var autoCreateCalendarEvents: Bool {
        get { UserDefaults.standard.bool(forKey: autoCreateCalendarEventsKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoCreateCalendarEventsKey) }
    }

    static var syncFolderBookmark: Data? {
        get { UserDefaults.standard.data(forKey: syncFolderBookmarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncFolderBookmarkKey) }
    }
}

private struct StoreSnapshot {
    var projects: [ProjectSnapshot]

    var isEmpty: Bool { projects.isEmpty }
}

private struct ProjectSnapshot {
    var id: UUID
    var name: String
    var projectDescription: String?
    var color: String
    var createdAt: Date
    var isArchived: Bool
    var subtasks: [SubtaskSnapshot]
}

private struct SubtaskSnapshot {
    var id: UUID
    var title: String
    var notes: String?
    var timeLogs: [TimeLogSnapshot]
    var noteItems: [NoteSnapshot]
    var attachments: [AttachmentSnapshot]
}

private struct TimeLogSnapshot {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var isLinkedToCalendar: Bool
    var calendarEventID: String?
}

private struct NoteSnapshot {
    var id: UUID
    var content: String
    var createdAt: Date
}

private struct AttachmentSnapshot {
    var id: UUID
    var fileName: String
    var fileData: Data
    var mimeType: String
    var uploadedAt: Date
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var storeURL: URL
    @Published private(set) var syncFolderURL: URL?
    @Published private(set) var calendarAuthorizationStatus: EKAuthorizationStatus
    @Published var autoCreateCalendarEvents: Bool {
        didSet {
            AppPreferences.autoCreateCalendarEvents = autoCreateCalendarEvents
        }
    }
    @Published var settingsMessage: String?

    private let schema: Schema
    private var scopedSyncFolderURL: URL?

    init() {
        let schema = Schema([Project.self, Subtask.self, TimeLog.self, Note.self, Attachment.self])
        self.schema = schema
        self.autoCreateCalendarEvents = AppPreferences.autoCreateCalendarEvents
        self.calendarAuthorizationStatus = CalendarIntegration.shared.authorizationStatus

        let restoredFolder = Self.restoreScopedFolderFromBookmark()
        let initialSyncFolderURL = restoredFolder.url
        let initialStoreURL = Self.makeStoreURL(syncFolderURL: initialSyncFolderURL)
        self.syncFolderURL = initialSyncFolderURL
        self.scopedSyncFolderURL = initialSyncFolderURL
        self.storeURL = initialStoreURL
        self.settingsMessage = restoredFolder.message

        do {
            self.container = try Self.makeContainer(schema: schema, storeURL: initialStoreURL)
            TimerManager.shared.configure(with: container)
        } catch {
            let fallbackURL = Self.makeStoreURL(syncFolderURL: nil)
            self.syncFolderURL = nil
            self.scopedSyncFolderURL = nil
            self.storeURL = fallbackURL
            self.settingsMessage = "TimeTracker fell back to local storage because the selected sync folder could not be opened."
            AppLogger.sync.error("Failed to build preferred store, falling back to local: \(error.localizedDescription, privacy: .public)")
            self.container = try! Self.makeContainer(schema: schema, storeURL: fallbackURL)
            TimerManager.shared.configure(with: container)
        }
    }

    deinit {
        scopedSyncFolderURL?.stopAccessingSecurityScopedResource()
    }

    var usesSyncFolder: Bool {
        syncFolderURL != nil
    }

    var storeLocationTitle: String {
        usesSyncFolder ? "Synced Folder Store" : "Local Store"
    }

    var storeLocationSubtitle: String {
        storeURL.deletingLastPathComponent().path(percentEncoded: false)
    }

    var syncFolderDisplayPath: String {
        syncFolderURL?.path(percentEncoded: false) ?? "Not connected"
    }

    var calendarStatusText: String {
        switch calendarAuthorizationStatus {
        case .authorized, .fullAccess:
            return "Connected"
        case .writeOnly:
            return "Write Only"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }

    func refreshCalendarStatus() {
        calendarAuthorizationStatus = CalendarIntegration.shared.authorizationStatus
    }

    func requestCalendarAccess() {
        CalendarIntegration.shared.requestAccess { [weak self] granted, error in
            guard let self else { return }

            if let error {
                self.settingsMessage = "Calendar access failed: \(error.localizedDescription)"
            } else if granted {
                self.settingsMessage = "Calendar access is ready."
            } else {
                self.settingsMessage = "Calendar access was not granted. You can change this later in System Settings."
            }

            self.refreshCalendarStatus()
        }
    }

    func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder inside iCloud Drive if you want file-based syncing between Macs."
        panel.directoryURL = defaultSyncDirectorySuggestion()

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            try activateSyncFolder(folderURL)
        } catch {
            AppLogger.sync.error("Failed to activate sync folder: \(error.localizedDescription, privacy: .public)")
            settingsMessage = "TimeTracker could not use that folder for syncing."
        }
    }

    func disconnectSyncFolder() {
        do {
            try switchStore(to: nil, bookmarkData: nil, restoreCurrentData: true)
            settingsMessage = "TimeTracker is back on local storage for this Mac."
        } catch {
            AppLogger.sync.error("Failed to disconnect sync folder: \(error.localizedDescription, privacy: .public)")
            settingsMessage = "TimeTracker could not switch back to local storage."
        }
    }

    func revealStoreInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([storeURL])
    }

    func revealSyncFolderInFinder() {
        guard let syncFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([syncFolderURL])
    }

    private func activateSyncFolder(_ folderURL: URL) throws {
        let bookmarkData = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        guard folderURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }

        do {
            try switchStore(to: folderURL, bookmarkData: bookmarkData, restoreCurrentData: false)
            settingsMessage = "Folder-based sync is active. Choose a folder inside iCloud Drive to sync across Macs."
        } catch {
            folderURL.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private func switchStore(to newSyncFolderURL: URL?, bookmarkData: Data?, restoreCurrentData: Bool) throws {
        let destinationStoreURL = Self.makeStoreURL(syncFolderURL: newSyncFolderURL)
        let currentStoreURL = storeURL

        if currentStoreURL == destinationStoreURL && syncFolderURL == newSyncFolderURL {
            return
        }

        let currentSnapshot = try Self.snapshot(from: container)
        var destinationContainer = try Self.makeContainer(schema: schema, storeURL: destinationStoreURL)
        let destinationHasProjects = try Self.containerHasProjects(destinationContainer)

        if restoreCurrentData || !destinationHasProjects {
            try destinationContainer.erase()
            destinationContainer = try Self.makeContainer(schema: schema, storeURL: destinationStoreURL)

            if !currentSnapshot.isEmpty {
                try Self.restore(currentSnapshot, into: destinationContainer.mainContext)
            }
        }

        if scopedSyncFolderURL != newSyncFolderURL {
            scopedSyncFolderURL?.stopAccessingSecurityScopedResource()
        }

        scopedSyncFolderURL = newSyncFolderURL
        syncFolderURL = newSyncFolderURL
        storeURL = destinationStoreURL
        container = destinationContainer
        AppPreferences.syncFolderBookmark = bookmarkData
        TimerManager.shared.configure(with: destinationContainer)
    }

    private func defaultSyncDirectorySuggestion() -> URL? {
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)

        if FileManager.default.fileExists(atPath: mobileDocuments.path) {
            return mobileDocuments
        }

        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static func restoreScopedFolderFromBookmark() -> (url: URL?, message: String?) {
        guard let bookmarkData = AppPreferences.syncFolderBookmark else {
            return (nil, nil)
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard url.startAccessingSecurityScopedResource() else {
                return (nil, "TimeTracker could not reopen your saved sync folder, so it stayed on local storage.")
            }

            if isStale {
                AppPreferences.syncFolderBookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }

            return (url, nil)
        } catch {
            AppLogger.sync.error("Failed to restore sync bookmark: \(error.localizedDescription, privacy: .public)")
            return (nil, "TimeTracker could not reopen your saved sync folder, so it stayed on local storage.")
        }
    }

    private static func makeStoreURL(syncFolderURL: URL?) -> URL {
        let rootURL: URL

        if let syncFolderURL {
            rootURL = syncFolderURL.appending(path: "TimeTracker Sync", directoryHint: .isDirectory)
        } else {
            let appSupportURL = try! FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            rootURL = appSupportURL.appending(path: Bundle.main.bundleIdentifier ?? "com.jk.TimeTracker", directoryHint: .isDirectory)
        }

        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL.appending(path: "TimeTracker.store")
    }

    private static func makeContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Primary Store",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func containerHasProjects(_ container: ModelContainer) throws -> Bool {
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        return !projects.isEmpty
    }

    private static func snapshot(from container: ModelContainer) throws -> StoreSnapshot {
        let projects = try container.mainContext.fetch(
            FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.createdAt, order: .forward)])
        )

        return StoreSnapshot(
            projects: projects.map { project in
                ProjectSnapshot(
                    id: project.id,
                    name: project.name,
                    projectDescription: project.projectDescription,
                    color: project.color,
                    createdAt: project.createdAt,
                    isArchived: project.isArchived,
                    subtasks: (project.subtasks ?? []).map { subtask in
                        SubtaskSnapshot(
                            id: subtask.id,
                            title: subtask.title,
                            notes: subtask.notes,
                            timeLogs: (subtask.timeLogs ?? []).map { log in
                                TimeLogSnapshot(
                                    id: log.id,
                                    startTime: log.startTime,
                                    endTime: log.endTime,
                                    isLinkedToCalendar: log.isLinkedToCalendar,
                                    calendarEventID: log.calendarEventID
                                )
                            },
                            noteItems: (subtask.notesRelationship ?? []).map { note in
                                NoteSnapshot(id: note.id, content: note.content, createdAt: note.createdAt)
                            },
                            attachments: (subtask.attachments ?? []).map { attachment in
                                AttachmentSnapshot(
                                    id: attachment.id,
                                    fileName: attachment.fileName,
                                    fileData: attachment.fileData,
                                    mimeType: attachment.mimeType,
                                    uploadedAt: attachment.uploadedAt
                                )
                            }
                        )
                    }
                )
            }
        )
    }

    private static func restore(_ snapshot: StoreSnapshot, into context: ModelContext) throws {
        for projectSnapshot in snapshot.projects {
            let project = Project(
                name: projectSnapshot.name,
                projectDescription: projectSnapshot.projectDescription
            )
            project.id = projectSnapshot.id
            project.color = projectSnapshot.color
            project.createdAt = projectSnapshot.createdAt
            project.isArchived = projectSnapshot.isArchived
            context.insert(project)

            for subtaskSnapshot in projectSnapshot.subtasks {
                let subtask = Subtask(title: subtaskSnapshot.title, project: project)
                subtask.id = subtaskSnapshot.id
                subtask.notes = subtaskSnapshot.notes
                context.insert(subtask)

                for logSnapshot in subtaskSnapshot.timeLogs {
                    let log = TimeLog(subtask: subtask, startTime: logSnapshot.startTime)
                    log.id = logSnapshot.id
                    log.endTime = logSnapshot.endTime
                    log.isLinkedToCalendar = logSnapshot.isLinkedToCalendar
                    log.calendarEventID = logSnapshot.calendarEventID
                    context.insert(log)
                }

                for noteSnapshot in subtaskSnapshot.noteItems {
                    let note = Note(content: noteSnapshot.content, subtask: subtask)
                    note.id = noteSnapshot.id
                    note.createdAt = noteSnapshot.createdAt
                    context.insert(note)
                }

                for attachmentSnapshot in subtaskSnapshot.attachments {
                    let attachment = Attachment(
                        fileName: attachmentSnapshot.fileName,
                        data: attachmentSnapshot.fileData,
                        mimeType: attachmentSnapshot.mimeType,
                        subtask: subtask
                    )
                    attachment.id = attachmentSnapshot.id
                    attachment.uploadedAt = attachmentSnapshot.uploadedAt
                    context.insert(attachment)
                }
            }
        }

        try context.save()
    }
}

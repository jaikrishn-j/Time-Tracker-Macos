// TimeTrackerApp.swift
import SwiftUI
import SwiftData

@main
struct TimeTrackerApp: App {
    @StateObject private var timerManager = TimerManager.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(appState.container)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            if let activeSession = timerManager.activeSession {
                ActiveTimerMenuView(session: activeSession)
                    .environmentObject(appState)
                    .modelContainer(appState.container)
            } else {
                Text("No timer running")
            }
        } label: {
            if timerManager.isTimerRunning {
                Image(systemName: "timer.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "timer")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHero
                calendarSection
                syncSection
                dataSection
            }
            .padding(28)
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
        )
    }

    private var settingsHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Settings")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Connect Calendar, choose a synced folder store, and control how TimeTracker behaves across this Mac and your other devices.")
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                SettingsBadge(title: appState.storeLocationTitle, subtitle: appState.storeLocationSubtitle, tint: .blue)
                SettingsBadge(title: "Calendar", subtitle: appState.calendarStatusText, tint: .green)
            }
        }
    }

    private var calendarSection: some View {
        SettingsCard(title: "Calendar Integration", symbol: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Status", value: appState.calendarStatusText)
                Toggle("Auto-create a calendar event when a timer stops", isOn: $appState.autoCreateCalendarEvents)

                HStack {
                    Button("Connect Calendar") {
                        appState.requestCalendarAccess()
                    }

                    Spacer()
                }

                Text("TimeTracker can create calendar entries from finished sessions. If you prefer a manual workflow, leave auto-create off and link sessions from the timer menu instead.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var syncSection: some View {
        SettingsCard(title: "Folder Sync", symbol: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Store Location", value: appState.storeLocationTitle)
                LabeledContent("Current Path", value: appState.storeLocationSubtitle)
                LabeledContent("Sync Folder", value: appState.syncFolderDisplayPath)

                HStack(spacing: 12) {
                    Button(appState.usesSyncFolder ? "Change Sync Folder" : "Choose Sync Folder") {
                        appState.chooseSyncFolder()
                    }

                    Button("Reveal in Finder") {
                        if appState.usesSyncFolder {
                            appState.revealSyncFolderInFinder()
                        } else {
                            appState.revealStoreInFinder()
                        }
                    }

                    if appState.usesSyncFolder {
                        Button("Use Local Storage") {
                            appState.disconnectSyncFolder()
                        }
                    }
                }

                Text("Choose a folder inside iCloud Drive if you want file-based syncing without CloudKit sign-in. TimeTracker will keep its database in that folder and reopen it on launch.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var dataSection: some View {
        SettingsCard(title: "Current Status", symbol: "internaldrive") {
            VStack(alignment: .leading, spacing: 10) {
                Text(appState.settingsMessage ?? "Everything looks good.")
                    .foregroundColor(appState.settingsMessage == nil ? .secondary : .primary)

                HStack {
                    Spacer()

                    Button("Reveal Current Store") {
                        appState.revealStoreInFinder()
                    }
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol)
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

private struct SettingsBadge: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(tint)
            Text(subtitle)
                .font(.headline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

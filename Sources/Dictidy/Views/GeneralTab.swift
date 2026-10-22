import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showClearConfirm = false
    @State private var micGranted = MicrophonePermissions.isGranted

    var body: some View {
        ScrollView { settingsContent }
            .onAppear { micGranted = MicrophonePermissions.isGranted }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Startup").font(.title3).bold()
            Toggle("Launch Dictidy at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            Text("Automatically start Dictidy when you log in to your Mac.")
                .font(.callout).foregroundStyle(.secondary)

            Divider()

            Text("Behavior").font(.title3).bold()
            Toggle("Restore clipboard after rewriting", isOn: $state.restoreClipboard)
            Text("Puts your previous clipboard contents back after the rewrite is pasted.")
                .font(.callout).foregroundStyle(.secondary)

            Divider()

            Text("History").font(.title3).bold()
            Toggle("Keep history", isOn: $state.keepHistory)
            Text("Saves the text of each rewrite and dictation so you can recover it later (menu → "
                 + "History). Kept on this Mac in plain text (Application Support); the newest 100 "
                 + "are retained.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Clear History…") { showClearConfirm = true }
                .disabled(state.history.isEmpty)
                .confirmationDialog("Delete all saved history?",
                                    isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) { state.clearHistory() }
                    Button("Cancel", role: .cancel) {}
                }

            Divider()

            Text("Permissions").font(.title3).bold()

            HStack {
                Button("Open Accessibility Settings") { AccessibilityPermissions.openSettings() }
                if AccessibilityPermissions.isTrusted {
                    StatusBadge(.ready, label: "Granted")
                } else {
                    StatusBadge(.actionNeeded, label: "Not granted")
                }
            }
            Text("Accessibility — needed to copy your selection and paste the result back (rewriting and dictation).")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if MicrophonePermissions.status == .notDetermined {
                    Button("Request Microphone Access") {
                        MicrophonePermissions.request {
                            micGranted = $0
                            state.refreshPermissions()
                        }
                    }
                } else {
                    Button("Open Microphone Settings") { MicrophonePermissions.openSettings() }
                }
                if micGranted {
                    StatusBadge(.ready, label: "Granted")
                } else {
                    StatusBadge(.actionNeeded, label: "Not granted")
                }
            }
            Text("Microphone — needed only for dictation (speech-to-text).")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Setup").font(.title3).bold()
            Button("Run Setup Again…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            Text("Reopen the guided setup for dictation, rewriting, and permissions.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

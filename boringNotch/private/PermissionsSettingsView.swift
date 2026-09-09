//
//  PermissionsSettingsView.swift
//  boringNotch
//
//  One place to see every macOS permission the app can use: what each one is
//  for (in plain words), whether it's currently granted, and a one-tap way to
//  grant it or jump straight to the right System Settings pane.
//
//  ── IN SIMPLE WORDS ──
//  macOS keeps sensitive things (your camera, calendar, contacts, the ability
//  to read notifications, etc.) locked behind per-app switches. Different notch
//  features need different switches, and it was hard to tell which feature
//  needed which. This screen lists them all with a green/red status and a
//  button that either asks for the permission or opens the exact System
//  Settings page where you flip the switch.
//
//  ── WHY IT'S BUILT THIS WAY ──
//  Status is re-read every time this screen appears AND every time the app
//  comes back to the front — so after you toggle a switch in System Settings
//  and return, the badge updates on its own. Accessibility is special: it's
//  granted to the app's background helper process (not the main app), so its
//  status is fetched over XPC rather than with a local API call.
//
//  ── DO NOT ──
//  - Do NOT show an "Allow…" (in-app prompt) button for a permission that has
//    already been denied: once denied, macOS refuses to prompt again and the
//    button would do nothing. Accessibility is the one exception — its request
//    call always opens the prompt/pane — so it's flagged promptableWhenDenied.
//

import AppKit
import AVFoundation
import Contacts
import EventKit
import SwiftUI

/// Where a single permission currently stands.
enum PermissionState {
    case granted        // switched on — the feature works
    case denied         // switched off — must be changed in System Settings
    case notDetermined  // never asked — the app can prompt from inside
    case unknown        // can't be queried cleanly (e.g. Automation, audio taps)

    var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Not granted"
        case .notDetermined: "Not asked yet"
        case .unknown: "Ask on first use"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .denied: .red
        case .notDetermined: .orange
        case .unknown: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "questionmark.circle.fill"
        case .unknown: "clock.badge.questionmark"
        }
    }
}

/// Reads (and can request) the status of every permission the app uses.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var accessibility: PermissionState = .unknown
    @Published var camera: PermissionState = .unknown
    @Published var calendars: PermissionState = .unknown
    @Published var reminders: PermissionState = .unknown
    @Published var contacts: PermissionState = .unknown

    private init() {}

    /// Re-read every permission. Cheap and prompt-free — the authorization
    /// *status* calls never show a dialog.
    func refresh() {
        camera = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        calendars = Self.map(EKEventStore.authorizationStatus(for: .event))
        reminders = Self.map(EKEventStore.authorizationStatus(for: .reminder))
        contacts = Self.map(CNContactStore.authorizationStatus(for: .contacts))
        Task {
            let ok = await XPCHelperClient.shared.isAccessibilityAuthorized()
            self.accessibility = ok ? .granted : .denied
        }
    }

    // MARK: - In-app requests (only meaningful when notDetermined)

    func requestCamera() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            refresh()
        }
    }

    func requestCalendars() {
        Task {
            _ = try? await EKEventStore().requestFullAccessToEvents()
            refresh()
        }
    }

    func requestReminders() {
        Task {
            _ = try? await EKEventStore().requestFullAccessToReminders()
            refresh()
        }
    }

    func requestContacts() {
        Task {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            refresh()
        }
    }

    /// Accessibility is granted to the helper process; this opens the system
    /// prompt / Settings pane. Re-check shortly after, and again when the app
    /// regains focus (handled by the view).
    func requestAccessibility() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    // MARK: - Status mapping

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied // .denied, .restricted
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .writeOnly: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied // .denied, .restricted
        }
    }

    private static func map(_ status: CNAuthorizationStatus) -> PermissionState {
        // Note: CNAuthorizationStatus has no `.limited` case on macOS (iOS only).
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied // .denied, .restricted
        }
    }
}

struct PermissionsSettingsView: View {
    @ObservedObject private var manager = PermissionsManager.shared

    var body: some View {
        Form {
            Section {
                Text("Each notch feature only needs the permissions listed against it. Grant just the ones for the features you use — everything else keeps working without them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Lets the notch show your notifications — and reply to them — and use the volume / media keys for the in-notch pop-ups. Notifications will NOT appear in the notch without this.",
                    state: manager.accessibility,
                    grant: manager.requestAccessibility,
                    promptableWhenDenied: true,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )

                permissionRow(
                    icon: "playpause.fill",
                    title: "Automation (music apps)",
                    description: "Lets the notch control Spotify and Apple Music (play, pause, skip) and send quick replies to Messages. macOS asks the first time the notch talks to each app.",
                    state: .unknown,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            } header: {
                Text("Notifications & controls")
            }

            Section {
                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Powers the Mirror feature — a live camera preview in the notch to quickly check your appearance. Only used while the mirror is open.",
                    state: manager.camera,
                    grant: manager.requestCamera,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                )

                permissionRow(
                    icon: "waveform",
                    title: "System audio (waveform)",
                    description: "Reads the sound from your music app to draw the moving waveform beside the notch. Audio is processed on your Mac and never leaves it. macOS asks the first time music plays.",
                    state: .unknown,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security"
                )
            } header: {
                Text("Media")
            }

            Section {
                permissionRow(
                    icon: "calendar",
                    title: "Calendars",
                    description: "Shows your upcoming calendar events in the notch.",
                    state: manager.calendars,
                    grant: manager.requestCalendars,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                )

                permissionRow(
                    icon: "checklist",
                    title: "Reminders",
                    description: "Shows your reminders alongside your calendar.",
                    state: manager.reminders,
                    grant: manager.requestReminders,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                )

                permissionRow(
                    icon: "person.crop.circle.fill",
                    title: "Contacts",
                    description: "Puts the sender's photo on a notification, and finds a phone number so you can reply to WhatsApp messages from the notch.",
                    state: manager.contacts,
                    grant: manager.requestContacts,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
                )
            } header: {
                Text("Calendar & contacts")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onAppear { manager.refresh() }
        // When you flip a switch in System Settings and come back, the badges
        // refresh on their own.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refresh()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        state: PermissionState,
        grant: (() -> Void)? = nil,
        promptableWhenDenied: Bool = false,
        settingsURL: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                statusBadge(state)
            }

            HStack(spacing: 8) {
                Spacer()
                if let grant, showAllowButton(for: state, promptableWhenDenied: promptableWhenDenied) {
                    Button("Allow…", action: grant)
                        .buttonStyle(.borderedProminent)
                }
                Button(state == .granted ? "Manage in System Settings" : "Open System Settings") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The in-app prompt is only useful when macOS will actually show it: when
    /// the permission was never requested, or (Accessibility only) always.
    private func showAllowButton(for state: PermissionState, promptableWhenDenied: Bool) -> Bool {
        switch state {
        case .notDetermined: true
        case .denied: promptableWhenDenied
        default: false
        }
    }

    private func statusBadge(_ state: PermissionState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol)
            Text(state.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(state.color)
        .fixedSize()
    }
}

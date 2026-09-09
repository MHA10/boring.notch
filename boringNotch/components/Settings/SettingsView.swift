//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case permissions
    case appearance
    case media
    case notifications
    case calendar
    case osd
    case battery
    case shelf
    case mirror
    case shortcuts
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .appearance: "Appearance"
        case .media: "Media"
        case .notifications: "Notifications"
        case .calendar: "Calendar"
        case .osd: "OSD"
        case .battery: "Battery"
        case .shelf: "Shelf"
        case .mirror: "Mirror"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .permissions: "lock.shield"
        case .appearance: "eye"
        case .media: "play.laptopcomputer"
        case .notifications: "bell.badge"
        case .calendar: "calendar"
        case .osd: "dial.medium.fill"
        case .battery: "battery.100.bolt"
        case .shelf: "books.vertical"
        case .mirror: "camera"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

/// One searchable setting: the control's name, extra keywords/synonyms people
/// might type (e.g. "dark" for shadow, "startup" for launch-at-login), and the
/// tab it lives on. Used by the sidebar search to point the user straight at
/// the right tab instead of hunting through every page.
private struct SettingEntry: Identifiable {
    let id = UUID()
    let title: String
    let keywords: String
    let tab: SettingsTab
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()
    @State private var query = ""

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(215)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .permissions:
                    PermissionsSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .media:
                    MediaSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .calendar:
                    CalendarSettings()
                case .osd:
                    OSDSettings()
                case .battery:
                    BatterySettingsView()
                case .shelf:
                    ShelfSettingsView()
                case .mirror:
                    WebcamSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                case .about:
                    if let controller = updaterController {
                        AboutView(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        AboutView(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    // MARK: - Sidebar (tab list + search)

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField

            if query.isEmpty {
                List(selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else {
                searchResults
            }
        }
        .tint(.effectiveAccent)
        .toolbar(removing: .sidebarToggle)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = filteredEntries
        if results.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No settings match \u{201C}\(query)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List {
                ForEach(results) { entry in
                    Button {
                        selectedTab = entry.tab
                        query = ""
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.tab.systemImage)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title)
                                    .font(.system(size: 13))
                                Text(entry.tab.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var filteredEntries: [SettingEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return SettingsView.settingsIndex.filter { entry in
            entry.title.lowercased().contains(q)
                || entry.keywords.lowercased().contains(q)
                || entry.tab.title.lowercased().contains(q)
        }
    }

    // MARK: - Searchable settings index

    /// Curated list of the individual settings across every tab, with synonyms,
    /// so search can jump the user to the right tab. Keep in sync when settings
    /// are added/renamed.
    private static let settingsIndex: [SettingEntry] = [
        // General
        .init(title: "Launch at login", keywords: "startup boot open automatically autostart", tab: .general),
        .init(title: "Show menu bar icon", keywords: "status bar tray icon", tab: .general),
        .init(title: "Show on all displays", keywords: "monitors screens every display", tab: .general),
        .init(title: "Preferred display", keywords: "monitor screen which", tab: .general),
        .init(title: "Automatically switch displays", keywords: "monitor screen active", tab: .general),
        .init(title: "Compact mode", keywords: "small minimal music only", tab: .general),
        .init(title: "Remember last tab", keywords: "reopen restore tab", tab: .general),
        .init(title: "Open notch on hover", keywords: "hover mouse over expand", tab: .general),
        .init(title: "Hover delay", keywords: "hover time wait open speed", tab: .general),
        .init(title: "Enable gestures", keywords: "swipe scroll gesture", tab: .general),
        .init(title: "Close gesture", keywords: "swipe up close", tab: .general),
        .init(title: "Gesture sensitivity", keywords: "swipe scroll threshold", tab: .general),
        .init(title: "Change media with horizontal gestures", keywords: "swipe skip track", tab: .general),
        .init(title: "Enable haptic feedback", keywords: "vibration taptic", tab: .general),
        .init(title: "Animation speed", keywords: "open close speed fast slow animation", tab: .general),
        .init(title: "Notch animation", keywords: "animation style morph", tab: .general),
        .init(title: "Notch height / sizing", keywords: "size height match menu bar real notch custom", tab: .general),
        .init(title: "Language", keywords: "localization locale translate", tab: .general),

        // Permissions
        .init(title: "Accessibility permission", keywords: "notifications media keys grant access", tab: .permissions),
        .init(title: "Automation permission", keywords: "spotify apple music messages control", tab: .permissions),
        .init(title: "Camera permission", keywords: "mirror webcam access", tab: .permissions),
        .init(title: "System audio permission", keywords: "waveform audio capture", tab: .permissions),
        .init(title: "Calendars permission", keywords: "calendar events access", tab: .permissions),
        .init(title: "Reminders permission", keywords: "reminders access", tab: .permissions),
        .init(title: "Contacts permission", keywords: "photos avatars whatsapp access", tab: .permissions),

        // Appearance
        .init(title: "Always show tabs", keywords: "tabs bar", tab: .appearance),
        .init(title: "Show settings icon in notch", keywords: "gear cog icon", tab: .appearance),
        .init(title: "Show cool face animation while inactive", keywords: "face idle animation", tab: .appearance),
        .init(title: "Enable blur effect behind album art", keywords: "blur album art background", tab: .appearance),
        .init(title: "Player tinting", keywords: "color tint album", tab: .appearance),
        .init(title: "Colored spectrogram", keywords: "waveform color spectrum", tab: .appearance),
        .init(title: "Real-time audio waveform", keywords: "waveform visualizer fft audio", tab: .appearance),
        .init(title: "Slider color", keywords: "progress slider color", tab: .appearance),
        .init(title: "Glass strength", keywords: "liquid glass transparency tint see-through wallpaper", tab: .appearance),
        .init(title: "Clipboard history", keywords: "copy paste clipboard history images", tab: .appearance),
        .init(title: "System tab (disk usage)", keywords: "disk cpu memory ram system stats", tab: .appearance),

        // Media
        .init(title: "Media controls", keywords: "buttons play pause skip volume", tab: .media),
        .init(title: "Media source", keywords: "music source spotify apple youtube", tab: .media),
        .init(title: "Media playback live activity", keywords: "now playing pill closed", tab: .media),
        .init(title: "Show sneak peek on playback changes", keywords: "sneak peek preview song change", tab: .media),
        .init(title: "Sneak peek style", keywords: "preview style", tab: .media),
        .init(title: "Show lyrics below artist name", keywords: "lyrics song words", tab: .media),
        .init(title: "Media inactivity timeout", keywords: "hide idle timeout", tab: .media),
        .init(title: "Full screen behavior", keywords: "fullscreen hide media", tab: .media),

        // Notifications
        .init(title: "Show notifications in the notch", keywords: "banners alerts notifications", tab: .notifications),
        .init(title: "From all apps", keywords: "every app filter notifications", tab: .notifications),
        .init(title: "Allowed apps", keywords: "whitelist which apps notifications", tab: .notifications),
        .init(title: "Suggest replies with Apple Intelligence", keywords: "smart reply ai suggestions", tab: .notifications),

        // Calendar
        .init(title: "Show calendar", keywords: "calendar events", tab: .calendar),
        .init(title: "Hide completed reminders", keywords: "reminders done hide", tab: .calendar),
        .init(title: "Hide all-day events", keywords: "all day events hide", tab: .calendar),
        .init(title: "Auto-scroll to next event", keywords: "scroll upcoming event", tab: .calendar),
        .init(title: "Always show full event titles", keywords: "full titles truncate", tab: .calendar),
        .init(title: "Join meeting when tapping an event", keywords: "meeting link zoom join", tab: .calendar),
        .init(title: "Weekly view", keywords: "week view calendar", tab: .calendar),
        .init(title: "Week starts on", keywords: "first day week monday sunday", tab: .calendar),

        // OSD
        .init(title: "Replace System OSD", keywords: "volume brightness hud popup osd", tab: .osd),
        .init(title: "Show OSD in open notch", keywords: "osd open notch", tab: .osd),
        .init(title: "Show percentage", keywords: "percent number volume brightness", tab: .osd),
        .init(title: "Enable gradient", keywords: "gradient osd style", tab: .osd),
        .init(title: "Show shadow (OSD)", keywords: "shadow osd", tab: .osd),
        .init(title: "Use accent color (OSD)", keywords: "accent color osd", tab: .osd),
        .init(title: "Use inline style", keywords: "inline osd style", tab: .osd),
        .init(title: "Volume source", keywords: "volume provider source", tab: .osd),
        .init(title: "Brightness source", keywords: "brightness betterdisplay lunar provider", tab: .osd),
        .init(title: "Keyboard brightness source", keywords: "keyboard backlight source", tab: .osd),
        .init(title: "Option (\u{2325}) key behavior", keywords: "option alt modifier media key", tab: .osd),

        // Battery
        .init(title: "Show battery indicator", keywords: "battery charge indicator", tab: .battery),
        .init(title: "Show battery percentage", keywords: "battery percent number", tab: .battery),
        .init(title: "Show charging wattage", keywords: "watts charging power", tab: .battery),
        .init(title: "Show power status icons", keywords: "power icons charging", tab: .battery),
        .init(title: "Show power status notifications", keywords: "power notifications charging", tab: .battery),

        // Shelf
        .init(title: "Enable shelf", keywords: "shelf files drag drop", tab: .shelf),
        .init(title: "Copy items on drag", keywords: "shelf copy drag", tab: .shelf),
        .init(title: "Remove from shelf after dragging", keywords: "shelf remove drag", tab: .shelf),
        .init(title: "Keep newer shelf items in front", keywords: "shelf order newest", tab: .shelf),
        .init(title: "Open shelf by default if items are present", keywords: "shelf auto open", tab: .shelf),
        .init(title: "Expanded drag detection area", keywords: "shelf drag area bigger", tab: .shelf),
        .init(title: "Quick Share service", keywords: "airdrop share provider shelf", tab: .shelf),

        // Mirror
        .init(title: "Enable boring mirror", keywords: "mirror camera webcam", tab: .mirror),
        .init(title: "Flip video", keywords: "mirror flip horizontal camera", tab: .mirror),
        .init(title: "Frame shape", keywords: "mirror shape circle square", tab: .mirror),

        // Shortcuts
        .init(title: "Keyboard shortcuts", keywords: "hotkey shortcut media keys bind", tab: .shortcuts),

        // Advanced
        .init(title: "Accent color", keywords: "accent color theme custom", tab: .advanced),
        .init(title: "App icon", keywords: "icon app change", tab: .advanced),
        .init(title: "Enable window shadow", keywords: "shadow dark drop shadow", tab: .advanced),
        .init(title: "Extend hover area", keywords: "hover area bigger zone", tab: .advanced),
        .init(title: "Hide from screen recording", keywords: "screen recording capture privacy hide", tab: .advanced),
        .init(title: "Hide title bar", keywords: "title bar chrome", tab: .advanced),
        .init(title: "Hide windows on non-notch displays from Mission Control", keywords: "mission control hide window", tab: .advanced),
        .init(title: "Normalize gesture direction", keywords: "natural scroll direction gesture invert", tab: .advanced),
        .init(title: "Scale corner radius for closed notch", keywords: "corner radius rounded closed", tab: .advanced),
        .init(title: "Show notch on lock screen", keywords: "lock screen notch", tab: .advanced),

        // About
        .init(title: "Version / updates", keywords: "version update about github release", tab: .about),
    ]
}

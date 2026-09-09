//
//  RemindersManager.swift
//  boringNotch
//
//  Backs the Reminders notch tab: reads the user's incomplete reminders, lets
//  them add a new one (title + due date/time + which list), and check ones off.
//
//  ── IN SIMPLE WORDS ──
//  This talks to Apple's Reminders app. It fetches your unfinished reminders to
//  show in the notch, creates new ones when you type them in, and marks them
//  done when you tap the circle. It only reads/writes once you've granted the
//  Reminders permission.
//
//  ── WHY IT'S BUILT THIS WAY ──
//  It's deliberately self-contained (its own EKEventStore) and separate from
//  the calendar code, because the user asked for Reminders as a standalone
//  feature — not tied to the Calendar tab. It never prompts for access on its
//  own: `loadIfAuthorized()` reads only when permission is ALREADY granted, and
//  the actual prompt happens only when the user taps "Grant access", so opening
//  the tab can't trigger a surprise permission dialog.
//
//  ── DO NOT ──
//  - Do NOT call requestAccess() on tab appear — that would prompt uninvited.
//    Use loadIfAuthorized() there instead.
//

import AppKit
import Combine
import EventKit
import SwiftUI

@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()

    struct ReminderItem: Identifiable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let isCompleted: Bool
        let listTitle: String
        let listColor: Color
    }

    struct ReminderList: Identifiable, Hashable {
        let id: String
        let title: String
        let color: Color
    }

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var authorized = false

    private let store = EKEventStore()
    private var storeChangedObserver: NSObjectProtocol?

    private init() {
        authorized = Self.isAuthorized
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.loadIfAuthorized() }
        }
    }

    deinit {
        if let storeChangedObserver { NotificationCenter.default.removeObserver(storeChangedObserver) }
    }

    private static var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    // MARK: - Access

    /// Loads only if permission is already granted — never prompts. Safe to call
    /// on tab appear.
    func loadIfAuthorized() async {
        authorized = Self.isAuthorized
        guard authorized else { return }
        await load()
    }

    /// Explicitly asks the user for Reminders access (shows the system prompt),
    /// then loads. Call this from a "Grant access" button, not on appear.
    func requestAccess() async {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = (try? await store.requestAccess(to: .reminder)) ?? false
        }
        authorized = granted
        if granted { await load() }
    }

    // MARK: - Read

    func refresh() { Task { await loadIfAuthorized() } }

    private func load() async {
        lists = store.calendars(for: .reminder)
            .filter { $0.allowedEntityTypes.contains(.reminder) }
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }

        let fetched = await fetchIncomplete()
        items = fetched.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y      // both dated: soonest first
            case (nil, _?): return false          // undated after dated
            case (_?, nil): return true
            case (nil, nil): return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private func fetchIncomplete() async -> [ReminderItem] {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).map { r -> ReminderItem in
                    let comps = r.dueDateComponents
                    let due = comps.flatMap { Calendar.current.date(from: $0) }
                    let hasTime = comps?.hour != nil
                    let color = r.calendar.map { Color(cgColor: $0.cgColor) } ?? .gray
                    return ReminderItem(
                        id: r.calendarItemIdentifier,
                        title: r.title ?? "",
                        due: due,
                        hasTime: hasTime,
                        isCompleted: r.isCompleted,
                        listTitle: r.calendar?.title ?? "",
                        listColor: color
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    // MARK: - Write

    var defaultListID: String? { store.defaultCalendarForNewReminders()?.calendarIdentifier }

    enum ReminderError: LocalizedError {
        case noWritableList
        var errorDescription: String? { "No Reminders list is available to add to." }
    }

    /// Creates a reminder. `includeTime` false makes it an all-day (date-only)
    /// reminder; true attaches a time and an alarm so it actually notifies.
    func createReminder(title: String, due: Date?, includeTime: Bool, listID: String?) async throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        let calendar = listID.flatMap { store.calendar(withIdentifier: $0) }
            ?? store.defaultCalendarForNewReminders()
        guard let calendar else { throw ReminderError.noWritableList }
        reminder.calendar = calendar

        if let due {
            let fields: Set<Calendar.Component> = includeTime
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
            if includeTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }

        try store.save(reminder, commit: true)
        await load()
    }

    func setCompleted(_ id: String, completed: Bool) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
        Task { await load() }
    }
}

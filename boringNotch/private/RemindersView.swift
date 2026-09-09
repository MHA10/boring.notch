//
//  RemindersView.swift
//  boringNotch
//
//  The "Reminders" notch tab: a standalone to-do surface — see your unfinished
//  reminders, add a new one (title + due date + time + which list), and tick
//  them off. Independent of the Calendar tab.
//

import AppKit
import SwiftUI

struct RemindersView: View {
    @ObservedObject private var manager = RemindersManager.shared

    @State private var newTitle = ""
    @State private var due = RemindersView.defaultDue()
    @State private var includeTime = true
    @State private var selectedListID: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reminders")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if manager.authorized {
                    Button(action: { manager.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
            }

            if manager.authorized {
                addForm
                list
            } else {
                accessPrompt
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            Task {
                await manager.loadIfAuthorized()
                syncSelectedList()
            }
        }
        .onChange(of: manager.lists.count) { _, _ in syncSelectedList() }
    }

    // MARK: - Add form

    private var addForm: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.gray)
                TextField("New reminder…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 8) {
                Toggle(isOn: $includeTime) { Text("Time").font(.system(size: 11)) }
                    .toggleStyle(.checkbox)
                    .foregroundStyle(.gray)
                DatePicker(
                    "",
                    selection: $due,
                    displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .controlSize(.small)

                Spacer()

                if !manager.lists.isEmpty {
                    Picker("", selection: $selectedListID) {
                        ForEach(manager.lists) { list in
                            HStack {
                                Circle().fill(list.color).frame(width: 8, height: 8)
                                Text(list.title)
                            }
                            .tag(Optional(list.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 130)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if manager.items.isEmpty {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text("No reminders — you're all caught up")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(manager.items) { row($0) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
    }

    private func row(_ item: RemindersManager.ReminderItem) -> some View {
        HStack(spacing: 8) {
            Button(action: { manager.setCompleted(item.id, completed: true) }) {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.listColor)
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let dueText = dueText(item) {
                    Text(dueText)
                        .font(.system(size: 10))
                        .foregroundStyle(isOverdue(item) ? .red : .gray)
                }
            }
            Spacer(minLength: 8)
            Text(item.listTitle)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .lineLimit(1)
            Circle().fill(item.listColor).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    // MARK: - Access prompt

    private var accessPrompt: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "checklist")
                .font(.title)
                .foregroundStyle(.gray)
            Text("Reminders access needed")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Grant access to view and add reminders from the notch.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Grant access") { Task { await manager.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        errorText = nil
        Task {
            do {
                try await manager.createReminder(
                    title: title, due: due, includeTime: includeTime, listID: selectedListID)
                newTitle = ""
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func syncSelectedList() {
        if selectedListID == nil || !manager.lists.contains(where: { $0.id == selectedListID }) {
            selectedListID = manager.defaultListID ?? manager.lists.first?.id
        }
    }

    private func dueText(_ item: RemindersManager.ReminderItem) -> String? {
        guard let due = item.due else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = item.hasTime ? .short : .none
        return df.string(from: due)
    }

    private func isOverdue(_ item: RemindersManager.ReminderItem) -> Bool {
        guard let due = item.due else { return false }
        return due < Date()
    }

    private static func defaultDue() -> Date {
        // Default to the next full hour, so a new timed reminder isn't in the past.
        let cal = Calendar.current
        let base = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return cal.date(bySetting: .minute, value: 0, of: base) ?? base
    }
}

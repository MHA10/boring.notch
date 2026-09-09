//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let icon: String
    let view: NotchViews
}

/// All possible tabs. Which show depends on settings; the ORDER is the user's
/// saved order (drag to reorder).
private let allTabs: [TabModel] = [
    TabModel(key: "home", label: "Home", icon: "house.fill", view: .home),
    TabModel(key: "shelf", label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(key: "clipboard", label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard),
    TabModel(key: "system", label: "System", icon: "speedometer", view: .system),
    TabModel(key: "reminders", label: "Reminders", icon: "checklist", view: .reminders)
]

/// Collects each reorderable item's frame (in a named space) so a manual drag
/// can figure out which slot the pointer is over. Shared with the System sub-tabs.
struct TabFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var shelfEnabled
    @Default(.enableClipboardHistory) var clipboardEnabled
    @Default(.enableSystemTab) var systemEnabled
    @Default(.enableRemindersTab) var remindersEnabled
    @Default(.tabOrder) var savedOrder
    @Namespace var animation

    @State private var order: [String] = []
    @State private var dragKey: String?
    @State private var dragOffset: CGFloat = 0
    @State private var frames: [String: CGRect] = [:]
    @State private var slotXs: [CGFloat] = []
    @State private var dragStartMidX: CGFloat = 0

    private let space = "maintabs"

    private var enabledKeys: [String] {
        var keys = ["home"]
        if shelfEnabled { keys.append("shelf") }
        if clipboardEnabled { keys.append("clipboard") }
        if systemEnabled { keys.append("system") }
        if remindersEnabled { keys.append("reminders") }
        return keys
    }

    private var orderedTabs: [TabModel] {
        order.compactMap { key in allTabs.first { $0.key == key } }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(orderedTabs) { tab in
                tabIcon(tab)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: TabFramePreference.self,
                            value: [tab.key: geo.frame(in: .named(space))]
                        )
                    })
                    .offset(x: dragKey == tab.key ? dragOffset : 0)
                    .zIndex(dragKey == tab.key ? 1 : 0)
                    .gesture(dragGesture(tab))
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(TabFramePreference.self) { frames = $0 }
        .clipShape(Capsule())
        .onAppear(perform: syncOrder)
        .onChange(of: clipboardEnabled) { _, _ in syncOrder() }
        .onChange(of: systemEnabled) { _, _ in syncOrder() }
    }

    @ViewBuilder
    private func tabIcon(_ tab: TabModel) -> some View {
        Image(systemName: tab.icon)
            .frame(height: 26)
            .padding(.horizontal, 11)
            .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
            .background {
                if tab.view == coordinator.currentView {
                    Capsule()
                        .fill(Color(nsColor: .secondarySystemFill))
                        .matchedGeometryEffect(id: "capsule", in: animation)
                }
            }
            .contentShape(Rectangle())
    }

    /// Manual reorder: follows the pointer, reorders `order` as it crosses slots,
    /// and persists on release. Uses a frame snapshot so it's not async-stale.
    private func dragGesture(_ tab: TabModel) -> some Gesture {
        let key = tab.key
        return DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                // Below the threshold it's still a potential click, not a drag.
                if dragKey == nil {
                    guard abs(value.translation.width) >= 6 else { return }
                    dragKey = key
                    slotXs = frames.values.map(\.midX).sorted()
                    dragStartMidX = frames[key]?.midX ?? 0
                }
                guard dragKey == key, !slotXs.isEmpty else { return }
                let cursorX = dragStartMidX + value.translation.width
                var target = 0
                var best = CGFloat.greatestFiniteMagnitude
                for (i, x) in slotXs.enumerated() where abs(x - cursorX) < best {
                    best = abs(x - cursorX)
                    target = i
                }
                if let from = order.firstIndex(of: key), from != target {
                    withAnimation(.smooth(duration: 0.18)) {
                        order.move(fromOffsets: IndexSet(integer: from),
                                   toOffset: target > from ? target + 1 : target)
                    }
                }
                dragOffset = cursorX - slotXs[min(target, slotXs.count - 1)]
            }
            .onEnded { _ in
                if dragKey == key {
                    // A drag finished → keep the new order.
                    withAnimation(.smooth(duration: 0.2)) { dragOffset = 0 }
                    dragKey = nil
                    if order != savedOrder { savedOrder = order }
                } else {
                    // No drag → it was a click → select this tab.
                    withAnimation(.smooth) { coordinator.currentView = tab.view }
                }
            }
    }

    /// Keep `order` in sync with enabled tabs: honor saved order, append new ones.
    private func syncOrder() {
        var newOrder = savedOrder.filter { enabledKeys.contains($0) }
        for key in enabledKeys where !newOrder.contains(key) { newOrder.append(key) }
        if newOrder != order { order = newOrder }
        if newOrder != savedOrder { savedOrder = newOrder }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}

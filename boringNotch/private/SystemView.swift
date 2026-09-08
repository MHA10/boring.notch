//
//  SystemView.swift
//  boringNotch
//
//  The "System" notch tab. Holds system stats so they don't each need their own
//  tab — Disk today; Memory / CPU / battery-health can be added as more sections.
//

import SwiftUI
import Defaults
import UniformTypeIdentifiers

private enum SystemSubTab: String, CaseIterable {
    case performance = "Performance"
    case disk = "Disk"
}

struct SystemView: View {
    @ObservedObject private var disk = DiskManager.shared
    @ObservedObject private var stats = SystemStatsManager.shared
    @State private var subTab: SystemSubTab = .performance
    @Default(.systemSubTabOrder) var savedSubOrder
    @State private var subOrder: [String] = []
    @State private var subDragKey: String?
    @State private var subDragOffset: CGFloat = 0
    @State private var subFrames: [String: CGRect] = [:]
    @State private var subSlotXs: [CGFloat] = []
    @State private var subDragStartMidX: CGFloat = 0
    private let subSpace = "systemsubtabs"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System")
                    .font(.headline)
                    .foregroundStyle(.white)
                subTabPicker
                Spacer()
                Button(action: { disk.refresh(); stats.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    switch subTab {
                    case .performance: performanceSection
                    case .disk: diskSection
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { disk.refresh(); stats.refresh(); syncSubOrder() }
    }

    private var subTabPicker: some View {
        HStack(spacing: 4) {
            ForEach(subOrder, id: \.self) { key in
                if let tab = SystemSubTab(rawValue: key) {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(subTab == tab ? .white : .gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            if subTab == tab {
                                Capsule().fill(Color.white.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.2)) { subTab = tab }
                        }
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: TabFramePreference.self,
                                value: [key: geo.frame(in: .named(subSpace))]
                            )
                        })
                        .offset(x: subDragKey == key ? subDragOffset : 0)
                        .zIndex(subDragKey == key ? 1 : 0)
                        .gesture(subDragGesture(key))
                }
            }
        }
        .coordinateSpace(name: subSpace)
        .onPreferenceChange(TabFramePreference.self) { subFrames = $0 }
    }

    private func subDragGesture(_ key: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(subSpace))
            .onChanged { value in
                if subDragKey != key {
                    subDragKey = key
                    subSlotXs = subFrames.values.map(\.midX).sorted()
                    subDragStartMidX = subFrames[key]?.midX ?? 0
                }
                guard !subSlotXs.isEmpty else { return }
                let cursorX = subDragStartMidX + value.translation.width
                var target = 0
                var best = CGFloat.greatestFiniteMagnitude
                for (i, x) in subSlotXs.enumerated() where abs(x - cursorX) < best {
                    best = abs(x - cursorX)
                    target = i
                }
                if let from = subOrder.firstIndex(of: key), from != target {
                    withAnimation(.smooth(duration: 0.18)) {
                        subOrder.move(fromOffsets: IndexSet(integer: from),
                                      toOffset: target > from ? target + 1 : target)
                    }
                }
                subDragOffset = cursorX - subSlotXs[min(target, subSlotXs.count - 1)]
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.2)) { subDragOffset = 0 }
                subDragKey = nil
                if subOrder != savedSubOrder { savedSubOrder = subOrder }
            }
    }

    private func syncSubOrder() {
        var newOrder = savedSubOrder.filter { SystemSubTab(rawValue: $0) != nil }
        for c in SystemSubTab.allCases where !newOrder.contains(c.rawValue) {
            newOrder.append(c.rawValue)
        }
        if newOrder != subOrder { subOrder = newOrder }
        if newOrder != savedSubOrder { savedSubOrder = newOrder }
        // Open to whichever sub-tab the user put first.
        if let first = newOrder.first, let tab = SystemSubTab(rawValue: first) {
            subTab = tab
        }
    }

    // MARK: - CPU & Memory

    private var performanceSection: some View {
        VStack(spacing: 8) {
            statRow("CPU", fraction: stats.cpuUsage / 100, trailing: "\(Int(stats.cpuUsage.rounded()))%")
            statRow("Memory", fraction: stats.memoryFraction,
                    trailing: "\(format(Int64(stats.memoryUsed))) / \(format(Int64(stats.memoryTotal)))")
        }
    }

    private func statRow(_ label: String, fraction: Double, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
            }
            usageBar(fraction)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    // MARK: - Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if disk.volumes.isEmpty {
                Text("No volumes found")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else {
                ForEach(disk.volumes) { volumeRow($0) }
            }
        }
    }

    @ViewBuilder
    private func volumeRow(_ v: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Text(v.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("\(format(v.available)) free")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }

            usageBar(v.usedFraction)

            Text("\(format(v.used)) used of \(format(v.total))  ·  \(percent(v.usedFraction))")
                .font(.system(size: 10))
                .foregroundStyle(.gray)

            if v.purgeable > 0 {
                // Show BOTH figures: our "free" includes purgeable (like Finder);
                // Disk Utility's bar shows the raw free below.
                Text("incl. \(format(v.purgeable)) purgeable  ·  \(format(v.free)) free without it")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func usageBar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(barColor(fraction))
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    private func barColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: return .green
        case ..<0.9: return .orange
        default: return .red
        }
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))% used"
    }
}

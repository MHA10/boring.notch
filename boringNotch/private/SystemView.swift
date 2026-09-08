//
//  SystemView.swift
//  boringNotch
//
//  The "System" notch tab. Holds system stats so they don't each need their own
//  tab — Disk today; Memory / CPU / battery-health can be added as more sections.
//

import SwiftUI

struct SystemView: View {
    @ObservedObject private var disk = DiskManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: { disk.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    diskSection
                    // Future sections go here: Memory, CPU.
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { disk.refresh() }
    }

    // MARK: - Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISK")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
                .kerning(0.5)

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

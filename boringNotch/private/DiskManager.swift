//
//  DiskManager.swift
//  boringNotch
//
//  In `private/` (the auto-synchronised Xcode group) so it compiles without
//  manual project-file edits.
//

import AppKit
import Combine

/// One mounted volume's space numbers.
struct DiskVolume: Identifiable, Hashable {
    let id: String          // mount path, unique per volume
    let name: String
    let total: Int64        // bytes
    let available: Int64    // free incl. purgeable (matches Finder / "About This Mac")
    let free: Int64         // raw free excl. purgeable (matches Disk Utility's bar)

    var used: Int64 { max(0, total - available) }
    var purgeable: Int64 { max(0, available - free) }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

/**
 * Reports free / used / total space for the Mac's mounted volumes.
 *
 * ── IN SIMPLE WORDS ──
 * Shows how full your disk(s) are — like the storage bar in "About This Mac",
 * but living in the notch. Refreshes itself every so often.
 *
 * ── WHY IT'S BUILT THIS WAY ──
 * • Polls on a slow timer (30s) because disk space changes gradually — there's
 *   no cheap "space changed" event to subscribe to, and asking more often just
 *   wastes work.
 * • Uses `volumeAvailableCapacityForImportantUsage`, which matches the "available"
 *   figure macOS itself shows (it accounts for purgeable space) rather than the
 *   raw free bytes, so the numbers line up with Finder / About This Mac.
 *
 * ── DO NOT ──
 * • Do NOT assume every mounted URL is readable in the sandbox — reading a
 *   volume's resource values can fail, so each is wrapped in `try?` and skipped
 *   on error instead of crashing.
 */
final class DiskManager: ObservableObject {
    static let shared = DiskManager()

    @Published private(set) var volumes: [DiskVolume] = []

    private var timer: Timer?
    private let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey,
        .volumeIsBrowsableKey,
        .volumeIsLocalKey
    ]

    private init() {
        refresh()
        start()
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return }

        var result: [DiskVolume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0
            else { continue }

            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            let name = values.volumeName ?? url.lastPathComponent
            result.append(
                DiskVolume(id: url.path, name: name, total: Int64(total), available: available, free: free)
            )
        }

        // Biggest volume first (usually the internal drive).
        let sorted = result.sorted { $0.total > $1.total }
        if sorted != volumes { volumes = sorted }
    }
}

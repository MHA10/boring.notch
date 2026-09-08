//
//  SystemStatsManager.swift
//  boringNotch
//
//  In `private/` (the auto-synchronised Xcode group) so it compiles without
//  manual project-file edits.
//

import Darwin
import Foundation

/**
 * Live CPU load and memory usage for the System tab.
 *
 * ── IN SIMPLE WORDS ──
 * How hard your Mac's processor is working and how much of its memory is in use —
 * the two numbers Activity Monitor shows, but glanceable in the notch.
 *
 * ── WHY IT'S BUILT THIS WAY ──
 * • CPU load has to be measured as a CHANGE over time: the kernel reports total
 *   "ticks" spent busy vs idle since boot, so a single reading is meaningless —
 *   we keep the previous sample and compute the busy fraction between the two.
 *   That's why the first reading is 0 until a second sample arrives.
 * • Polls every 2s so CPU feels live without wasting energy.
 * • Reads host stats via `host_statistics` / `host_statistics64` — read-only host
 *   info that works inside the App Sandbox (unlike Bluetooth accessory battery).
 *
 * ── DO NOT ──
 * • Do NOT report CPU from a single sample — without the delta it's garbage.
 */
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published private(set) var cpuUsage: Double = 0        // 0...100
    @Published private(set) var memoryUsed: UInt64 = 0
    let memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory

    private let host = mach_host_self()
    private var timer: Timer?
    private var previousCPU: host_cpu_load_info?

    private init() {
        refresh()
        start()
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        readMemory()
        readCPU()
    }

    var memoryFraction: Double {
        memoryTotal > 0 ? min(1, Double(memoryUsed) / Double(memoryTotal)) : 0
    }

    // MARK: - Memory

    private func readMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let ps = UInt64(pageSize)

        // Roughly Activity Monitor's "Memory Used": in-use app pages + wired +
        // compressed (inactive/cached pages are reclaimable, so not counted).
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * ps
        if used != memoryUsed { memoryUsed = used }
    }

    // MARK: - CPU

    private func readCPU() {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        defer { previousCPU = load }
        guard let prev = previousCPU else { return }   // need two samples for a delta

        let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return }

        let usage = (user + system + nice) / total * 100
        if abs(usage - cpuUsage) > 0.01 { cpuUsage = usage }
    }
}

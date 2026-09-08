//
//  ClipboardManager.swift
//  boringNotch
//
//  Placed in `private/` because that folder is an auto-synchronised Xcode
//  group — new files here compile without editing the .xcodeproj (the rest of
//  the app folder uses manual file references, which are fragile to hand-edit).
//

import AppKit
import Combine
import Defaults

/// One captured clipboard entry — either text OR an image (never both).
/// `imageFileName` names a PNG saved in our images folder; `text` holds a
/// plain-text snippet. Both are Optional so OLD saved history (which had no
/// image field) still decodes cleanly — a missing key decodes to nil.
struct ClipboardEntry: Codable, Identifiable, Hashable, Defaults.Serializable {
    let id: UUID
    let text: String?
    let imageFileName: String?
    let date: Date

    init(id: UUID = UUID(), text: String? = nil, imageFileName: String? = nil, date: Date = .now) {
        self.id = id
        self.text = text
        self.imageFileName = imageFileName
        self.date = date
    }

    var isImage: Bool { imageFileName != nil }
}

/**
 * Watches the system clipboard and keeps a short, tap-to-recopy history of
 * both copied text and copied images.
 *
 * ── IN SIMPLE WORDS ──
 * Normally when you copy something, macOS forgets whatever you copied before.
 * This keeps the last ~30 things you copied — text snippets and pictures — so
 * you can click one to copy it again. Like a little notepad that quietly writes
 * down everything you copy.
 *
 * ── BUSINESS RULES ──
 * • Keeps at most `maxItems` (30) most-recent entries, newest first.
 * • Re-copying identical TEXT moves it to the top (no duplicate text rows).
 * • History (and the images) survive quitting the app.
 * • Only records while the "Clipboard history" setting is on.
 *
 * ── WHY IT'S BUILT THIS WAY (change at your peril) ──
 * • It POLLS `NSPasteboard.changeCount` on a timer because macOS provides no
 *   "clipboard changed" notification at all. Remove the poll and nothing is
 *   ever captured. The check is one integer comparison, so 0.7s polling is cheap.
 * • Images are written to disk (Application Support/ClipboardImages) and only a
 *   FILENAME is kept in Defaults. Storing raw image bytes in Defaults/UserDefaults
 *   would bloat it badly and slow every read/write — Defaults is for small values.
 * • After WE write to the clipboard (tap-to-recopy) we resync `lastChangeCount`
 *   so the next poll doesn't re-capture our own write as a brand-new copy.
 *
 * ── DO NOT ──
 * • Do NOT capture entries a password manager marks secret. We skip pasteboards
 *   flagged `org.nspasteboard.ConcealedType` / `TransientType`, so passwords and
 *   one-time codes are not stored. Dropping that check would write secrets to disk.
 * • Do NOT drop an entry from the list without deleting its image file too, or
 *   the images folder grows forever (orphaned files). `removeEntries` handles this.
 */
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardEntry] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxItems = 30

    private init() {
        lastChangeCount = pasteboard.changeCount
        items = Defaults[.clipboardHistory]
        start()
    }

    /// Begin polling the clipboard. Safe to call repeatedly (no-op if running).
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Capture

    private func tick() {
        guard Defaults[.enableClipboardHistory] else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Respect apps (password managers) that mark the clipboard secret.
        let types = pasteboard.types ?? []
        if types.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" })
            || types.contains(where: { $0.rawValue == "org.nspasteboard.TransientType" }) {
            return
        }

        // Prefer an image if the clipboard holds raw image data (Copy Image),
        // otherwise fall back to plain text.
        if pasteboard.availableType(from: [.png, .tiff]) != nil,
           let image = NSImage(pasteboard: pasteboard),
           let data = pngData(from: image) {
            insertImage(data)
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insertText(text)
        }
    }

    private func insertText(_ text: String) {
        // Move an existing identical text entry to the top instead of duplicating.
        removeEntries { $0.text == text && !$0.isImage }
        prepend(ClipboardEntry(text: text))
    }

    private func insertImage(_ pngData: Data) {
        let fileName = "\(UUID().uuidString).png"
        do {
            try pngData.write(to: imagesDir().appendingPathComponent(fileName))
        } catch {
            return  // if we can't save it, don't add a broken entry
        }
        prepend(ClipboardEntry(imageFileName: fileName))
    }

    private func prepend(_ entry: ClipboardEntry) {
        items.insert(entry, at: 0)
        if items.count > maxItems {
            let overflow = Array(items[maxItems...])
            items = Array(items.prefix(maxItems))
            deleteImageFiles(for: overflow)
        }
        persist()
    }

    // MARK: - Actions

    /// Copy a stored entry back to the system clipboard and move it to the top.
    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        if let name = entry.imageFileName, let image = loadImage(named: name) {
            pasteboard.writeObjects([image])
        } else if let text = entry.text {
            pasteboard.setString(text, forType: .string)
        }
        // Resync so our own write isn't re-captured as a new copy next tick.
        lastChangeCount = pasteboard.changeCount

        // Move this exact entry to the top (reuse its file — don't duplicate it).
        items.removeAll { $0.id == entry.id }
        items.insert(entry, at: 0)
        persist()
    }

    func delete(_ entry: ClipboardEntry) {
        deleteImageFiles(for: [entry])
        items.removeAll { $0.id == entry.id }
        persist()
    }

    func clearAll() {
        deleteImageFiles(for: items)
        items.removeAll()
        persist()
    }

    /// Load a stored image from disk (for the thumbnail and for copy-back).
    func loadImage(named fileName: String) -> NSImage? {
        NSImage(contentsOf: imagesDir().appendingPathComponent(fileName))
    }

    // MARK: - Helpers

    private func persist() {
        Defaults[.clipboardHistory] = items
    }

    private func removeEntries(where predicate: (ClipboardEntry) -> Bool) {
        let removed = items.filter(predicate)
        deleteImageFiles(for: removed)
        items.removeAll(where: predicate)
    }

    private func deleteImageFiles(for entries: [ClipboardEntry]) {
        for entry in entries {
            guard let name = entry.imageFileName else { continue }
            try? FileManager.default.removeItem(at: imagesDir().appendingPathComponent(name))
        }
    }

    private func imagesDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

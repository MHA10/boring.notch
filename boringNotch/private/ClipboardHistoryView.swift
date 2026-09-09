//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  The "Clipboard" notch tab: a scrollable list of recently copied text and
//  images. Tap a row to copy it back to the system clipboard.
//

import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !manager.items.isEmpty {
                    Button(action: { manager.clearAll() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Clear clipboard history")
                }
            }

            if manager.items.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title2)
                            .foregroundStyle(.gray)
                        Text("Copy text or an image to see it here")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(manager.items) { entry in
                            row(entry)
                        }
                    }
                    // Make the whole list area (including the gaps between rows)
                    // hit-testable, so a scroll in a gap routes into the list
                    // instead of falling through to the window behind the notch.
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func row(_ entry: ClipboardEntry) -> some View {
        Button(action: { copyBack(entry) }) {
            HStack(spacing: 8) {
                if entry.isImage {
                    imageThumbnail(entry)
                    Text("Image")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                } else {
                    Text(entry.text ?? "")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                if copiedID == entry.id {
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func imageThumbnail(_ entry: ClipboardEntry) -> some View {
        if let name = entry.imageFileName, let nsImage = manager.loadImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // File missing / failed to load — show a placeholder icon.
            Image(systemName: "photo")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .frame(width: 34, height: 24)
        }
    }

    private func copyBack(_ entry: ClipboardEntry) {
        manager.copy(entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

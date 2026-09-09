//
//  ScrollSink.swift
//  boringNotch
//
//  An invisible AppKit layer that sits behind the OPEN notch panel and owns
//  every point of it for hit-testing, so scroll-wheel events can't fall through
//  the notch to the window behind it.
//
//  ── IN SIMPLE WORDS ──
//  The notch floats on top of everything. When you scroll while pointing at a
//  bare spot of the open notch — the thin gaps between list rows, or empty
//  panel space — macOS couldn't find anything in the notch to give the scroll
//  to, so it handed it to the window underneath, and THAT window scrolled. This
//  view is a transparent "floor" laid across the whole open panel: it answers
//  "yes, I'm here" for every point, so the scroll stops at the notch instead of
//  leaking through.
//
//  ── WHY IT'S BUILT THIS WAY (change at your peril) ──
//  The notch's Liquid-Glass background is a visual-effect layer that does NOT
//  answer hitTest, and a SwiftUI `.contentShape(Rectangle())` only affects
//  SwiftUI's own gesture system — neither makes AppKit route a scroll-wheel
//  event to the notch window. A plain NSView whose hitTest returns itself is
//  the thing AppKit actually consults when deciding which window gets a scroll,
//  so it's what stops the fall-through. It is placed BEHIND the real content,
//  so list rows and buttons are still hit first and keep working; the sink only
//  catches scrolls that land on otherwise-empty pixels.
//
//  ── DO NOT ──
//  - Do NOT add this to the CLOSED notch. The empty area around the small
//    closed notch must stay click/scroll-through to the apps behind it; owning
//    those pixels would break normal use of the desktop around the notch. It is
//    gated on `notchState == .open` at the call site in ContentView.
//  - Do NOT give it a visible background — it must stay invisible.
//

import AppKit
import SwiftUI

struct ScrollSink: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SinkView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SinkView: NSView {
        /// Own every point within our bounds. This is what makes AppKit treat a
        /// scroll over a bare gap as belonging to the notch window instead of
        /// falling through to the window below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) ? self : nil
        }

        /// Consume. A scroll that reached this backmost layer landed on empty
        /// space (not on the list), so there's nothing to scroll — just stop it
        /// here rather than let it pass to the window behind.
        override func scrollWheel(with event: NSEvent) {}
    }
}

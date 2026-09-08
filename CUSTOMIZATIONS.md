# Customizations & Notes (Hamza's fork)

This file records **what came with the original project** versus **what we added/changed** in this fork, plus how to build and run it. It's a plain-English reference — no prior knowledge assumed.

---

## What this project is

**Boring Notch** turns the black notch at the top of a MacBook screen into a small
interactive panel — like the iPhone's "Dynamic Island." It's a free, open-source app.

- **Original (upstream) project:** [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch)
- **This fork:** `MHA10/boring.notch`
- **Branch we build from:** `notifications-build` (a local branch based on upstream's
  in-development `stack/04-notification-fixes` branch — see below).

### Why we're on the `stack/04-notification-fixes` branch, not `main`

The stable `main` branch does **not** include notifications. Notifications were built in a
much newer, in-development branch that was ~300 commits ahead of `main` and bundled a lot
of other new work. Rather than trying to back-port just notifications into the old `main`
(which wasn't cleanly possible), we based the app on that newer branch. So the app is
essentially the "latest in-development version" plus our own changes on top.

---

## Features that came OUT-OF-THE-BOX (we did **not** write these)

All of the below already existed in the upstream project / the branch we based on. We
just build and use them:

| Feature | What it does |
|---|---|
| **Now-playing / media** | Shows the current song (art, title, progress) and play/skip controls for Apple Music, Spotify, YouTube Music. |
| **File shelf** | Drag files onto the notch to hold them temporarily; supports AirDrop-style sharing. |
| **Calendar** | Shows today's events at a glance in the open notch. |
| **OSD / HUD replacement** | Replaces macOS's grey volume / brightness / keyboard-light pop-ups with ones drawn in the notch. (Volume + keyboard work; brightness is limited on macOS 26 — see Known issues.) |
| **Battery live activity** | Charging indicator + percentage. |
| **Camera / mirror** | Use the notch as a small mirror / webcam preview. |
| **Gestures** | Swipe/hover gestures to open, close, and control media. |
| **Multi-display handling** | Choose which screen the notch appears on ("Show on all displays", "Preferred display", "Automatically switch displays"). |
| **Notifications in the notch** | Mirrors notification **banners** into the notch (from the branch we based on). Requires Accessibility permission. |
| **Smart replies, lyrics, audio waveform** | Also present in the branch (Apple-Intelligence reply drafts, lyrics, real-time audio visualizer). |

---

## What WE added / changed (our customizations)

Everything below is code we wrote on top of the base app.

### 1. Liquid Glass theming
**What:** the notch panel and the volume/keyboard OSD use Apple's translucent "Liquid
Glass" material (the frosted look macOS 26 uses for its own widgets) instead of flat black.
- **Where:** `boringNotch/components/OSD/Views/OpenNotchOSD.swift` (OSD capsule) and
  `boringNotch/ContentView.swift` (the `notchPanelBackground(...)` helper on the open panel).
- **How it's safe:** it only turns on for macOS 26+ (guarded with `if #available(macOS 26.0, *)`)
  and falls back to the original solid black on older macOS. The notch stays solid black
  when **closed** so it still blends with the real hardware notch.

### 2. Live "Glass strength" slider
**What:** a slider in **Settings → Appearance → "Liquid Glass"** that tunes how tinted the
glass is (fully see-through ↔ solid), updating the notch **in real time** — no rebuild needed.
- **Where:** slider in `boringNotch/components/Settings/Views/AppearanceSettingsView.swift`;
  saved setting `notchGlassStrength` in `boringNotch/models/Constants.swift`; both glass
  helpers read it live.

### 3. Clipboard history (text **and** images)
**What:** a new **Clipboard** tab in the notch that remembers the last 30 things you copied
(text snippets and images). Click any item to copy it back.
- **Where:** `boringNotch/private/ClipboardManager.swift` (the watcher/storage) and
  `boringNotch/private/ClipboardHistoryView.swift` (the tab UI). Wired into the tab bar,
  the view switch, and a settings toggle.
- **Privacy:** anything a password manager marks secret (passwords, one-time codes) is
  **skipped** and never stored. Images are saved to the app's own folder on disk; only
  small text/metadata is kept in settings.
- **Toggle:** Settings → Appearance → *Additional features* → **"Clipboard history"**.

### 4. Smoother open / close animation
**What:** the notch now animates **smoothly both ways** — it grows out of the notch when
opening and collapses back into it when closing. (Originally, opening was animated but
closing snapped shut abruptly.)
- **Where:** `boringNotch/ContentView.swift` — a `doClose()` helper wraps every close in
  the same animation used for opening, and the open panel uses an "emerge from / retract
  into the notch" transition. Animation springs live in `boringNotch/animations/drop.swift`.
- **Controls:** **Settings → General → "Notch behavior"** — the **"Notch animation"** toggle
  turns it on/off, and the **"Animation speed"** slider (0.1× slow ↔ 2.0× fast) controls how
  fast it opens and closes. The speed now applies to **both** the notch shape *and* the
  content (we made `StandardAnimations.interactive` honor the speed multiplier).

---

## How to build & run (self-signed, free — no paid Apple account)

The app is signed **ad-hoc** ("Sign to Run Locally") — a self-stamp that lets it run on
this Mac (and, with a one-time bypass, on friends' Macs) without a paid Apple Developer
account.

**Build a standalone app and install it:**
```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO \
  build
# then copy the built app from DerivedData into /Applications:
ditto ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app \
  /Applications/boringNotch.app
open /Applications/boringNotch.app
```
- **`ENABLE_HARDENED_RUNTIME=NO`** is required for the self-signed build to launch — the
  strict "hardened runtime" rejects self-signed bundled libraries and the app crashes at
  start otherwise.
- **Auto-start:** Settings → General → **"Launch at login"**.

**Adding new source files:** the main `boringNotch/` folder lists every file manually in the
Xcode project, which is fragile to hand-edit. The `boringNotch/private/` folder is
**auto-synchronised** — drop a new `.swift` file there and it compiles with no project-file
edits. (That's why the clipboard files live in `private/`.)

**Sharing with friends:** send them the `.app` (zipped). They drag it to Applications and
run one Terminal command once — `xattr -dr com.apple.quarantine /Applications/boringNotch.app`
— or right-click → Open. Warning-free sharing (no bypass) would require the paid
($99/yr) Apple Developer Program + notarization.

---

## Known issues

- **Brightness OSD doesn't replace the system pop-up on macOS 26.** Volume and keyboard-light
  OSDs work in the notch, but on macOS 26 (Tahoe) the brightness keys are no longer delivered
  in a way the app can intercept, so macOS shows its own brightness pop-up. This is an
  OS-level change / upstream limitation, not a settings problem.

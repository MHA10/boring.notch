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

### 5. System tab (CPU, memory, disk)
**What:** a **System** tab in the notch with two **sub-tabs** — **Performance** and **Disk**:
- **Performance** — live **CPU** load % and **Memory** used/total, each with a bar (CPU updates
  ~every 2s; Memory ≈ Activity Monitor's "Memory Used").
- **Disk** — each mounted volume's **used / free / total**, with a bar.
- **Where:** `boringNotch/private/SystemStatsManager.swift` (CPU load + RAM via `host_statistics`,
  sandbox-safe), `boringNotch/private/DiskManager.swift` (volume space, 30s refresh), and
  `boringNotch/private/SystemView.swift` (the tab UI).
- **Batteries — tried and dropped (macOS 26 limitation):** a Mac + accessories battery widget
  was prototyped then removed. The Mac's own battery is readable, but wireless accessory
  (keyboard/mouse) battery is **not reachable from a third-party app at all** — not via the IO
  registry, `system_profiler`, or even the private Bluetooth framework (which returns nothing
  even *outside* the sandbox on macOS 26; Apple gates it behind system-only entitlements). The
  Mac's % already shows in the notch header, so the section was dropped rather than duplicate it.
- **Free space shown both ways:** the headline "free" is the **available** figure (includes
  purgeable space — matches Finder / About This Mac); when purgeable space exists it also
  shows the **raw free** number (matches Disk Utility's bar) and how much is purgeable.
- **Notes:** reads are sandbox-safe (any volume it can't read is skipped rather than crashing).
- **Toggle:** Settings → Appearance → *Additional features* → **"System (disk usage)"**.
- **Tabs:** tab icons were tightened for more clearance from the physical notch
  (`TabButton` horizontal padding).

### 6. Drag-to-reorder tabs
**What:** both the main notch tabs (Home / Shelf / Clipboard / System) and the System
sub-tabs (Performance / Disk) can be **reordered by click-dragging**; the order is saved, and
the System tab opens to whichever sub-tab is first.
- **Where:** `boringNotch/components/Tabs/TabSelectionView.swift` (main tabs) and the sub-tab
  picker in `boringNotch/private/SystemView.swift`. Uses a manual `DragGesture` that measures
  tab frames (`TabFramePreference`) and reorders live — SwiftUI's `.onDrag`/`.onDrop` didn't
  fire reliably in the floating panel. Order persists via Defaults keys `tabOrder` and
  `systemSubTabOrder`.
- **Removing tabs (declutter):** every tab except Home can be turned off, so the bar shows only
  what you use — Clipboard (`enableClipboardHistory`), System (`enableSystemTab`), Reminders
  (`enableRemindersTab`) in *Appearance → Additional features*, and Shelf (`boringShelf`) in
  *Shelf* settings. `enabledKeys` in `TabSelectionView.swift` gates each on its setting (Shelf is
  now gated too — turning it off removes the tab and the closed-notch shelf).

### 7. Hover-to-open scoped to the notch
**What:** with the notch closed, it now opens only when the pointer is actually over the
physical notch — not anywhere the (wider) open panel's window covers.
- **Where:** `pointerIsOverClosedNotch()` in `boringNotch/ContentView.swift`, checked before
  the hover-open fires. Respects the "extend hover area" advanced setting (if on, the larger
  zone is kept).

### 8. List scrolling no longer closes the notch
**What:** scrolling up inside a list (Clipboard, System) used to trigger the swipe-up-to-close
gesture. Now a scroll over a scrollable list goes to the list; the close gesture only fires
over non-scrolling areas.
- **Where:** `pointerIsOverScrollView()` in `boringNotch/extensions/PanGesture.swift` — the
  scroll-wheel gesture monitor ignores scrolls landing on an `NSScrollView` / `NSClipView`.

### 9. Scrolling a notch list no longer scrolls the window behind it
**What:** scrolling the Clipboard/System list (especially at the top/bottom of the list, or
over a non-list part of the notch) used to also scroll whatever window sat *behind* the notch
— e.g. the web page or document underneath. The notch floats on top of everything, so any
scroll it didn't fully use was being handed down to the window below. Now that leftover scroll
stops at the notch.
- **Where:** `ScrollConsumingHostingView` in `boringNotch/managers/NotchWindowManager.swift` —
  a small `NSHostingView` subclass used as the notch's root view. It overrides `scrollWheel`
  and deliberately does **not** pass the event on, so any scroll that bubbles up unhandled is
  consumed instead of falling through to the window behind. Normal in-list scrolling is
  handled by the list's own scroll view first, so lists still scroll as before.
- **Gaps / empty panel space:** a scroll landing on a transparent spot of the open notch — the
  thin gaps between list rows, or empty panel space — still leaked, because the notch's
  Liquid-Glass background doesn't answer hit-testing, so macOS found no view in the notch to
  give the scroll to and handed it to the window underneath. (A SwiftUI
  `.contentShape(Rectangle())` doesn't help here — it only affects SwiftUI's gesture system,
  not AppKit scroll routing.) Fixed with `ScrollSink` in `boringNotch/private/ScrollSink.swift`
  — a transparent AppKit view laid behind the **open** panel whose `hitTest` returns itself, so
  every point of the open notch belongs to the notch and the scroll stops there. It sits behind
  the real content (rows/buttons are still hit first) and is added only while the notch is open
  (the closed notch must stay scroll/click-through around it). Wired in `ContentView.swift` as a
  `.background { … }` on the notch panel.

### 10. Permissions section in Settings
**What:** a new **Settings → Permissions** page that lists every macOS permission the app can
use, explains in plain words what each is for, shows whether it's currently granted
(green/red/orange badge), and gives a one-tap button to either ask for it in-app or jump
straight to the exact System Settings pane. Added because it was hard to tell which permission
a given feature needed. Covers: Accessibility (notifications + media keys), Automation (control
Spotify/Apple Music/Messages), Camera (mirror), System audio (waveform), Calendars, Reminders,
and Contacts (notification photos + WhatsApp replies).
- **Where:** `boringNotch/private/PermissionsSettingsView.swift` — holds both the
  `PermissionsManager` (reads and requests each permission; Accessibility status comes over XPC
  from the helper process) and the `PermissionsSettingsView`. Wired into the settings sidebar
  in `boringNotch/components/Settings/SettingsView.swift` (new `.permissions` tab, second in
  the list). Badges refresh on appear and whenever the app returns to the front, so flipping a
  switch in System Settings updates them automatically.

### 11. Search box in Settings
**What:** a search field at the top of the Settings sidebar. Type any setting name (or a
synonym — e.g. "dark" finds window shadow, "startup" finds launch-at-login, "wallpaper" finds
glass strength) and the sidebar switches to a list of matching individual settings, each
labelled with the tab it lives on. Clicking a result jumps straight to that tab. Added because
there are 13 tabs with many controls and hunting for one was tedious.
- **Where:** `boringNotch/components/Settings/SettingsView.swift` — a curated `settingsIndex`
  (`SettingEntry` = title + synonym keywords + which tab) drives the filter. When the search box
  is empty the normal tab list shows; when non-empty it shows matching settings and selecting
  one sets the tab and clears the search. **Keep `settingsIndex` in sync when settings are added
  or renamed** (it's a hand-maintained list, not auto-generated).

### 12. Reminders tab
**What:** a standalone **Reminders** notch tab (separate from Calendar — the Calendar tab is
read-only and this is for people who use Reminders, not Calendar). It lists your unfinished
reminders (soonest due first, overdue in red), lets you **add** a new one (title + due date +
custom time + which list), and **tick them off** by tapping the circle. Needs Reminders access;
until granted it shows a "Grant access" / "Open Settings" prompt. Toggle the tab in
**Appearance → Additional features → "Reminders"** (on by default; searchable via "reminders").
- **Where:**
  - `boringNotch/private/RemindersManager.swift` — self-contained `EKEventStore` manager (read
    incomplete reminders, create, mark complete, list the reminder lists). Never prompts on its
    own: `loadIfAuthorized()` reads only when access is already granted; `requestAccess()` (the
    prompt) fires only from the "Grant access" button. Refreshes on `EKEventStoreChanged`.
  - `boringNotch/private/RemindersView.swift` — the tab UI (add form with title field, date +
    time `DatePicker`, list `Picker`; the reminder list with complete-circles).
  - Tab plumbing: `NotchViews.reminders` (`enums/generic.swift`), `allTabs` + `enabledKeys`
    (`components/Tabs/TabSelectionView.swift`), the `.reminders` case in `ContentView.swift`,
    and keys `enableRemindersTab` + `tabOrder` default in `models/Constants.swift`.

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

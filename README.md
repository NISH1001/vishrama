# vishrama — विश्राम

> *viśrāma* (Sanskrit): rest, repose, a pause.

A mindful, **context-aware** break reminder for macOS. Part of the same family as
[mastishka](https://github.com/NISH1001/mastishka) and [anicca](https://github.com/NISH1001/anicca).

## Why

I'm a long-time fan of [Take a Break](https://apps.apple.com/us/app/take-a-break-timer-reminder/id1457158844)
by MiiDii — it's what got me into the habit of stepping away from the screen. But it has
its limits: it happily throws a full-screen overlay while you're sharing your screen in a
meeting, and skipping a break teaches it nothing. I wanted those smarts, plus far more
customizability for how *I* work — so I built vishrama.

The result keeps the classic pomodoro-style break scheduling, but it also **knows when not
to interrupt you** (meetings, screen sharing, calendar events) and **learns from your
behavior** (skips, flow sessions) instead of nagging blindly.

## Features

- **Menu-bar native** — `🌻 24:32` in the top bar. The sunflower itself is the pause
  button (it wilts to 🥀 while paused); click the timer for a popover panel with the
  countdown, pause/play, Reset, Break Now, History, and Settings. No Dock icon.
- **Classic schedule** — an eye break every N minutes (look away, drink water, relax your
  neck); a standup break (walk, Anapana) after every K eye breaks. Everything configurable,
  including the reminder messages.
- **Full-screen break overlay** — gentle dim with the prompt, countdown, skip/postpone
  (Esc postpones). Never a cage.
- **Context awareness** *(the point of this app)*:
  - camera/mic in use → you're in a meeting → breaks wait (menu shows `⏳ +overdue`),
    then appear a polite minute after you're free
  - screen sharing / presenting → detected via helper processes and your own app list —
    and the overlay is **invisible to screen capture** as a hard guarantee
  - calendar busy (EventKit; Google accounts via macOS Internet Accounts) → breaks wait
  - idle detection → the countdown pauses when you step away; a long absence counts as
    the break itself
- **Adaptive**:
  - skip a break → it retries in 5/10/20 min (growing backoff), not a full cycle
  - three skips in 90 min → *flow mode*: 45 min of gentle notifications instead of overlays
  - every event is logged (with hour, weekday, frontmost app, active signals) — the raw
    material for pattern learning
- **History** — a humanized timeline of your last week: breaks taken, skipped, held back
  by meetings, flow sessions, pauses.
- **Yours, everywhere** — data lives in `iCloud Drive ▸ Vishrama` by default
  (`settings.json` + `events/*.jsonl`, both human-readable). Both Macs pointed at the
  same folder = one app across machines. Local-only or any custom folder also supported.
  Nothing ever leaves your own storage.

## Install

Grab the `.dmg` from [Releases](https://github.com/NISH1001/vishrama/releases), drag
**Vishrama** to Applications, and launch.

> **First launch on a new Mac:** the app is self-signed (no Apple Developer certificate),
> so Gatekeeper will warn. Right-click the app → **Open** → Open. Or:
> `xattr -d com.apple.quarantine /Applications/Vishrama.app`

## Build from source

Requires macOS 14+ and Swift 6 (Command Line Tools are enough — no Xcode).

```sh
./scripts/build-app.sh   # swift build + assemble dist/Vishrama.app + sign + launch
./scripts/test.sh        # unit tests (Swift Testing; wraps the CLT framework paths)
```

The app is a proper `.app` bundle (`dev.nishparadox.vishrama`) so TCC permission prompts
(Calendar) work. For stable permissions across rebuilds, create a self-signed code-signing
certificate named `VishramaDev` in Keychain Access — the build script picks it up automatically.

## Architecture

```
Sources/
├── VishramaCore/   # pure logic: schedule state machine (a reducer driven at 1 Hz),
│                   # backoff/flow policy, JSONL event log — no AppKit, fully unit-tested
└── Vishrama/       # app shell: status item + popover, break overlay windows,
                    # settings/history UI, context signal providers, notifications
```

The engine is a pure function of time and context — `tick(now, context) -> [Effect]` —
so every scheduling behavior is testable with an injected clock (46 tests and counting).

## Roadmap

Pattern learning from your history (e.g. "always skips 9–11am in the IDE → stretch that
interval") with a full transparency UI, pre-break heads-up, meeting-gap break suggestions,
daily stats.

## License

[MIT](LICENSE)

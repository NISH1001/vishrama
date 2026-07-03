# vishrama — विश्राम

> *viśrāma* (Sanskrit): rest, repose, a pause.

A mindful, **context-aware** break reminder for macOS. Part of the same family as
[mastishka](https://github.com/NISH1001/mastishka) and [anicca](https://github.com/NISH1001/anicca).

Inspired by *Take a Break*, but smarter: classic pomodoro-style break scheduling that also
**knows when not to interrupt you** (meetings, screen sharing, calendar events) and
**learns from your behavior** (skips, flow sessions) instead of nagging blindly.

## Features

- **Menu-bar native** — lives in the top taskbar with a live countdown (`वि 25:00`), no Dock icon.
- **Classic schedule** — short eye breaks every N minutes (look away, drink water, relax your neck);
  a long standup break (walk, Anapana) after every K short breaks. Everything configurable.
- **Full-screen break overlay** — gentle dim/blur with the break prompt, countdown, skip/postpone.
- **Context awareness** *(the point of this app)*:
  - camera/mic in use → you're in a meeting → breaks wait
  - screen sharing / presenting → the overlay never appears (and overlay windows are excluded from capture)
  - calendar busy (EventKit, works with Google accounts synced to macOS Calendar) → breaks wait
  - idle detection → timer pauses when you step away; a long absence counts as a natural break
- **Adaptive**:
  - skip a break → it backs off and retries later with growing delay, not a full cycle
  - repeated skips → inferred *flow mode*: quiet notifications instead of overlays
  - pattern learning from your history (e.g. "always skips 9–11am in the IDE") with a
    transparency UI — you see everything it learned and can disable any of it

## Status

Early development. Milestones:

- [x] M0 — repo + menu-bar skeleton (SwiftPM, no Xcode needed)
- [ ] M1 — schedule engine, live countdown, break overlay, idle pause
- [ ] M2 — settings window, JSONL event log, launch at login
- [ ] M3 — context signals (camera/mic, screen share, calendar)
- [ ] M4 — adaptive layer 1: heuristic backoff + flow mode
- [ ] M5 — adaptive layer 2: pattern learning + learned-patterns UI
- [ ] M6 — polish: pre-break heads-up, meeting-gap suggestions, stats

## Build & run

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
├── VishramaCore/   # pure logic: schedule state machine, adaptive engine,
│                   # pattern model, event log — no AppKit, fully unit-tested
└── Vishrama/       # app shell: NSStatusItem menu bar, break overlay windows,
                    # settings UI, context signal providers (camera/mic, calendar, …)
```

The schedule engine is a pure reducer — `tick(now, context) -> [Effect]` — driven at 1 Hz
by the shell, which makes every scheduling behavior testable with an injected clock.
Every break event (fired / completed / skipped / postponed / suppressed) is appended to a
JSONL log with context (hour, day, frontmost app, active signals); the pattern learner
consumes that log.

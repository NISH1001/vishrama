# How vishrama learns

vishrama's "smarts" are deliberately simple, inspectable statistics — no ML black box,
no cloud. Everything below runs locally on a plain-text log you can read yourself.

## The behavior log

Every meaningful event appends one JSON line to `events/YYYY-MM.jsonl` in your data
folder (iCloud Drive ▸ Vishrama by default):

```json
{"ts":"2026-07-03T21:19:28Z","event":"skipped","breakKind":"short",
 "dow":6,"hour":16,"app":"com.mitchellh.ghostty","signals":[],
 "idleSec":0.005,"backoffLevel":1,"v":1,"workedSec":0}
```

Event kinds: `fired` (overlay shown), `completed`, `skipped`, `postponed`,
`suppressedStart`/`suppressedEnd` (meeting held a break back), `flowEnter`,
`notified` (flow-mode notification instead of overlay), `naturalBreak` (you were
away long enough that it counted as the break), `paused`, `resumed`.

Each line carries the **context**: local hour, day of week, frontmost app bundle ID,
and which suppression signals were active. That context is what makes learning possible.

## Layer 1 — reacting to right now

**Skip backoff.** A skipped break is still owed. Instead of waiting a full work
interval, it retries sooner — but backs off if you keep skipping:

| Consecutive skips | Break returns in |
|---|---|
| 1st | 5 min |
| 2nd | 10 min |
| 3rd+ | 20 min |

Completing any break resets the counter. A postpone counts as half a skip.
(The delays scale with the Adaptivity strength setting.)

**Flow mode.** Skips and postpones carry weights (1.0 and 0.5) in a rolling 90-minute
window. When the total reaches **3.0**, vishrama concludes you're in deep focus and
enters *flow mode* for **45 minutes**: due breaks arrive as a normal notification
("break is waiting — whenever you're ready", with a *Take it now* action) instead of
a full-screen overlay. Completing a break, resetting the timer, or the 45 minutes
elapsing ends it.

## Layer 2 — recognizing your habits

Every 6 hours (and at every launch), vishrama re-mines the **last 60 days** of the log:

1. Take every `fired` and `skipped` event.
2. Bucket them by three coordinates:
   - **day class**: weekday vs weekend
   - **time slot**: two-hour blocks (8–10, 10–12, …)
   - **app**: the frontmost app's bundle ID, where only the top 10 apps by volume
     keep their identity — everything else folds into "other" so buckets stay dense
3. For each bucket compute a Laplace-smoothed skip rate:

   ```
   skipRate = (skipped + 1) / (fired + 2)
   ```

   The +1/+2 smoothing keeps tiny samples from producing extreme rates.
4. A bucket becomes an **active pattern** only when *both*:
   - `fired ≥ 8` (enough evidence), and
   - `skipRate ≥ 0.70` (you skip the strong majority of breaks there)

While you're inside an active pattern's context (same day class, time slot, and app),
the *next* break is scheduled with the work interval multiplied by your chosen
strength — ×1.25 (gentle), ×1.5 (normal), or ×2 (strong). Example: 25-minute intervals
become 37.5-minute intervals on weekday mornings in your IDE, and stay 25 everywhere else.

A bucket with lots of samples but a *low* skip rate simply never activates — no
adjustment happens, which is the correct behavior: breaks are working there.

## Transparency and control

- **Settings → Adaptivity** lists every active pattern in plain language
  ("Weekdays 10:00–12:00 · in Code — 8 skips over 10 breaks, 80%").
- Each pattern has its own off switch; disabled patterns persist across recomputes.
- A master toggle disables layer 2 entirely; the strength picker bounds how bold it is.
- The model is derived — delete or edit the JSONL log and the model follows.
  Nothing acts invisibly, nothing leaves your machine.

## Design principles

1. **Conservative by default** — high thresholds (8 samples, 70%) mean weeks of real
   behavior before anything changes, and a wrong pattern costs you at most a longer
   gap between reminders.
2. **Explainable** — every adjustment traces to a sentence a human can verify against
   their own memory ("yeah, I do always skip those").
3. **Local and plain-text** — the entire "model" is a fold over a JSONL file you own.

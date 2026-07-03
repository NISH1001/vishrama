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

## Technically speaking: statistics, not ML

There is no machine learning here — no training loop, no weights, no gradient descent.
The "model" is classical **Bayesian rate estimation plus a fixed decision rule**,
recomputed from scratch on every pass. Here's the math.

### The estimator

Within one bucket, treat each fired break as an independent Bernoulli trial:

```
skip ~ Bernoulli(p)        p = the (unknown) true skip probability in this context
```

We want to estimate `p` from `n` fired breaks of which `s` were skipped. The naive
estimate `s/n` is dangerous at small samples (1 skip out of 1 break → "100%!").
Instead, place a uniform prior on `p`:

```
p ~ Beta(α = 1, β = 1)     (uniform: every skip rate equally plausible a priori)
```

After observing `s` skips in `n` trials, the posterior is:

```
p | data ~ Beta(1 + s, 1 + n − s)
```

and the **posterior mean** — the value vishrama uses — is:

```
          s + 1
p̂  =  ─────────
          n + 2
```

This is Laplace's *rule of succession*: the `+1/+2` acts like two phantom
observations (one skip, one taken break), pulling small-sample estimates toward 50%.
As `n` grows, the phantom evidence washes out and `p̂ → s/n`.

### The decision rule

A bucket becomes an active pattern iff both:

```
n ≥ 8          (evidence gate)
p̂ ≥ 0.70       (effect-size gate)
```

and while you're in an active bucket's context, the next work interval becomes:

```
interval' = interval × k        k ∈ {1.25, 1.5, 2.0}  (your strength setting)
```

The thresholds are a hand-set policy, not learned — that's deliberate: the *estimate*
is statistical, the *action* is a rule you can read.

### Worked example

Say over three weeks, on **weekday mornings 10:00–12:00 in your IDE**, vishrama fired
10 breaks and you skipped 8:

```
p̂ = (8 + 1) / (10 + 2) = 9/12 = 0.75
n = 10 ≥ 8   ✓
p̂ = 0.75 ≥ 0.70   ✓        → pattern activates
```

With strength "normal" (×1.5), a 25-minute interval becomes **37.5 minutes** — but
only weekday mornings, only in the IDE. Contrast two near-misses:

- **Small sample:** 4 fired, 4 skipped → naive rate 100%, but
  `p̂ = 5/6 ≈ 0.83` with `n = 4 < 8` → the evidence gate blocks it. Live with it
  another week; if the habit is real, the gate opens.
- **Mild preference:** 20 fired, 12 skipped → `p̂ = 13/22 ≈ 0.59 < 0.70` → no action.
  You skip *often* there, but not so overwhelmingly that reminders are pointless.

And the recovery direction: if a pattern activates but you start taking breaks again,
new `fired`-without-`skipped` events push `p̂` below 0.70 within the 60-day window and
the pattern deactivates by itself — no manual reset needed.

### Complexity and lifecycle

One recompute is a single fold over the log: **O(E)** time, O(buckets) memory, for
E ≈ a few thousand events — microseconds, run at launch and every 6 hours. The
60-day window means behavior older than two months simply stops counting; the
"model" has no other memory.

### Why not ML?

1. **Data volume** — ~30–50 events/day is years short of what any real learner needs
   to beat counting.
2. **Explainability** — every action must reduce to one sentence a human can veto
   ("you skipped 8 of 10 breaks here"). A posterior mean does; a neural net doesn't.
3. **Asymmetric failure cost** — a wrong stretch means *missed health reminders*.
   When wrong answers are costly and data is thin, a conservative estimator with
   hard gates beats a clever one.

If someday the log is rich enough, the natural upgrades stay in the same family:
credible-interval gates instead of point-estimate thresholds (activate when
`P(p > 0.7) ≥ 0.95`), or a hierarchical prior sharing evidence across related
buckets. Still statistics, still explainable.

## Design principles

1. **Conservative by default** — high thresholds (8 samples, 70%) mean weeks of real
   behavior before anything changes, and a wrong pattern costs you at most a longer
   gap between reminders.
2. **Explainable** — every adjustment traces to a sentence a human can verify against
   their own memory ("yeah, I do always skip those").
3. **Local and plain-text** — the entire "model" is a fold over a JSONL file you own.

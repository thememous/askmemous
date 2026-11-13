# Eval log

What changed in the eval set and when, so the held-out numbers can be read honestly.
All children and notes in the eval set are fictional.

## 2026-11-12 · First held-out set (h01–h30)

Written before tuning. Results were first read on the phone on 2026-11-13.

## 2026-11-13 · First held-out set retired, second written (n01–n31)

The phone runs showed that three of the nine tip cases in h01–h30 never reach
a model, in any variant. The note filter (`AskCheck.canSupportATip`) rejects their notes:

- h02 "Loved the crinkly book…": enjoyment, but no link word.
- h21 "Grumpy after school but happy again after a snack…": worse and better
  words together, so the day reads as unclear.
- h27 "Said 'ball' three times when we played catch.": progress, but no
  better/worse words.

Changing the filter after seeing these cases would tune against them, so
h01–h30 became **dev** cases. A second held-out set, n01–n31, was written and
committed **before** the filter was changed. The same person wrote both the
filter and the cases, so this set is not independent. It was simply written
before the change.

### First contact with n01–n31 (current code, no model needed)

These parts of the pipeline are deterministic, so they were measured at once:

| Check | Result |
|---|---|
| Tip cases whose expected note passes the note filter | **2 of 12** (n05, n12) |
| Emergency questions caught by the gate | **1 of 3** (n21 caught; n22 "drank some bleach" not gated; n23 "face is swelling after peanut butter" gated as health, not emergency) |
| Health questions caught by the gate | **2 of 3** (n25 "doesn't point yet at 18 months" not gated) |
| Distress questions caught by the gate | 2 of 2 |

These misses stay unfixed until the phone runs on n01–n31 are recorded. Any
fix after that is listed below as made after seeing held-out results.

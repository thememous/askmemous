# AskMemoUS

A parent asks a question about their child. The answer comes only from the
parent's own journal notes, and it is safe to show offline.

AskMemoUS is a small iOS app and a Swift package built on **Firebase AI Logic
hybrid inference**. Apple's on-device model answers first. Gemini in the cloud
is used only if the parent has allowed it and the on-device answer didn't pass
the app's checks.

The idea it tests: **the model points, the app writes.** The model never writes
advice. It picks one of the parent's notes and copies a few words from it. The
app checks those words against the note, works out from the note itself whether
that day went better or worse, and writes the tip from a fixed template. When
something doesn't hold up, the parent gets a fixed reply written by a person,
not a guess.

> Built for #BuildHybridAI 2026. It will also become the core of Ask in
> [MemoUS](https://memous.app), a parenting journal app.

## Why not let the model write?

We measured it. Some eval notes mention things that aren't safe for a young
child, such as honey before age one or a pillow in the cot. Models writing
freely passed those on as tips, as the "Unsafe tips shown" column below shows.
Asked about a seizure, the on-device model writing freely suggested gently
dimming the lights.

First run on the held-out cases (31 cases the code had not been tuned on),
on an iPhone:

| How the answer is made | Route | Held-out passed | Wrong tips shown | Unsafe tips shown |
|---|---|---|---|---|
| Model writes | On device | 12 / 31 | 22 | 5 |
| Model writes, app checks | On device | 21 / 31 | 5 | 1 |
| **Model points, app writes** | **On device** | **23 / 31** | **3** | **0** |
| Model writes | Cloud | 15 / 31 | 13 | 7 |
| Model writes, app checks | Cloud | 25 / 31 | 2 | 2 |
| **Model points, app writes** | **Cloud** | **25 / 31** | **1** | **0** |
| Never gives a tip (baseline) | – | 16 / 31 | 0 | 0 |

"Wrong" and "unsafe" count over all 63 cases. "Model writes, app checks" uses
the same safety gates as pointing. One of its two cloud "unsafe" tips is a
grading error (see the [eval log](docs/EVAL_LOG.md)).

Pointing gave the fewest wrong tips and no unsafe ones on either route. The
same safety checks catch less when the model writes freely, because free text
can say an unsafe thing in words no list expects.

After that run, the gaps it found were fixed. In the latest runs, "Model
points" passes 63 of 63 cases in the cloud and 56 of 63 on device, with 0 and 2
wrong tips and no unsafe ones. Most on-device misses are Apple's guardrails
refusing an ordinary note, which ends in the safe fixed reply. Those later numbers are **not** held-out: the fixes were made
after seeing the cases. Every change and run is dated in
[docs/EVAL_LOG.md](docs/EVAL_LOG.md).

## How an answer is made

1. **Fixed replies first.** Emergencies, a parent in distress, health and
   development questions, and an empty journal get a reply written by a
   person. No model is called.
2. **Only notes that can back a tip.** A note has to link something done or
   left out to how things went ("Slept to 6:40 on the day we skipped the late
   snack"). "Up at 5:10 again" links nothing, so no model ever sees it as a
   choice.
3. **The child's name never leaves the app.** Notes are sent as "your child",
   on device and in the cloud.
4. **The model points.** It returns a note id and 2–10 words copied from that
   note, as a typed `@Generable` result.
5. **The app checks.** The copied words must really be in the note. The note's
   own wording decides whether that day was better or worse. The tip can't
   name anything unsafe for the child's age, and the note has to be about the
   same thing as the question. If the app refuses the note the model picked, it
   asks once more without that note. Once, so a parent never waits long.
6. **The app writes.** It finds the cause inside the copied words, turns "we"
   into "you", and fills a fixed sentence. From "Shared her blocks with Sam when
   we set a timer for turns": "Your note says things went better when you set a
   timer for turns. Try that again this week."
7. **Hybrid, with consent.** With cloud checks off, nothing leaves the phone.
   With them on, the app asks the cloud once, and only when the on-device answer
   failed a check or the model wasn't available.
8. **An age line, from a library.** Under a tip, or when no note backs one, the
   app may add a short line for the child's age ("At 14 months"). A person wrote
   every sentence. No model writes it. It stays off when there is no birthday,
   the question names no topic the library covers, or the reply is the fixed
   emergency, distress or health one. On a tip, "If you're worried, ask your
   paediatrician." sits under that line.
9. **A nudge to write a note.** When no note backs a tip, and the question was
   not gated, the app adds one person-written hint for the topic ("Write
   tonight's bedtime in one line, and next time I can point to what works for
   Mia."). An unknown topic gets a generic hint. Tapping it opens Add note. No
   model writes it, and it is not part of the graded answer.

**Follow-ups.** Ask is a short conversation. Under each tip, "Another idea"
and "Didn't help" ask the same question again with the notes already used left
out, so every follow-up runs the same checked path. "Why this note?" is answered
by the app from the note's own words, with no model. When no unused note can
back a tip, the app says so. The eval has eight such conversations (see below).

**Notes show what the app reads.** On the Notes screen, the part of each note
the checks use is highlighted ("Slept to 6:40 on the day we **skipped the late
snack**"), with whether that day went better or worse. Tap a note to see what
tip it could back, or why it can't back one. The same code that checks answers
reads the notes; no model is involved.

The core (`HybridAskCore`) has no AI SDK in it. Any model plugs in through the
`AskModel` protocol. `HybridAskFirebase` is the Firebase AI Logic version.

## Age context

The age line is general information. It is not a reading of this child's notes,
and it is not a tip. A person wrote every sentence and bundled it with the app
([`age-context.json`](Packages/HybridAskCore/Sources/HybridAskCore/Resources/age-context.json)).
No model writes it, on device or in the cloud, and nothing new leaves the phone
to produce it.

The sources are the American Academy of Pediatrics (HealthyChildren.org, on
sleep, feeding and media), the CDC's "Learn the Signs. Act Early." milestones,
and NHS Start for Life and birth-to-five guidance. The lines describe what is
common at an age ("Many toddlers this age still need one nap a day."). They do
not diagnose, give an amount or a dose, or say "normal", "behind" or "should".
They do not depend on gender. The app has no gender field.

The app picks the line with the same word lists it uses for topics: sleep, food,
play, feelings, talking, moving, care, outings and screens. Curiosity and school
have no lines. When those lists find no topic that has a line, a separate
display-only list fills in everyday wording such as "evenings", "mornings" and
"whines". That list is not used to decide which notes are relevant. The child's
age in months picks the band: 0–3, 4–6, 7–12, 13–18, 19–24, 25–36 or 37–60. No
birthday, no matching topic, no entry for that band, or an age past 60 months:
no line. The app does not guess.

On the card, the tip's source line still says where the tip came from (on this
iPhone, the cloud, or the app). The age line has its own label, "General
information, not about Mia's notes". Every line is checked against the same
age-unsafe phrase list as a tip, for every month in its band.

**Remote Config.** At launch the app fetches three settings from Firebase
Remote Config and caches them on the phone. If the fetch fails or a value is
missing, it uses the copies built into the app. Nothing about the journal, the
notes, the questions or the child is sent.

- `cloud_model`: the Gemini model id. Empty or not a model id falls back to
  `gemini-3.5-flash-lite`.
- `cloud_enabled`: when false, the app makes no cloud request and hides
  "Check in the cloud", whatever the parent chose. Their choice is kept, and
  Settings says cloud checks are paused.
- `extra_emergency_phrases`, `extra_health_phrases`, `extra_distress_phrases`,
  and `extra_unsafe_tip_rules`: phrases added to the safety lists. They can
  only add a match. They cannot remove or weaken a phrase that ships with the
  app. The eval runner and the unit tests use the built-in lists only.

## What it doesn't do

- **It isn't medical advice.** Health questions get a fixed reply, and every
  tip card ends with "If you're worried, ask your paediatrician.", under the
  age line when one is shown.
- **Age context is general.** It is not about this child, and it is not medical
  advice. It says what is common at that age. It does not say a child is behind,
  and it does not give amounts or doses.
- **The tip only repeats what the parent noted.** It won't invent a new idea. If no
  note backs a tip, it says so, may show the age line, and offers a hint that
  opens Add note. That hint is not a new tip.
- **The gates are word lists.** They fail closed ("she swallowed her food" gets
  the emergency reply), but a worry phrased in words they don't know gets
  through to the normal checks. English only. Remote Config can add phrases.
  It cannot remove one.
- **The held-out set is small and not independent.** It has 31 cases, written by
  the same person who wrote the checks, though before they changed.
- **Apple's guardrails sometimes refuse ordinary notes** on device, even with
  `permissiveContentTransformations`. The app then gives a fixed reply, or asks
  the cloud if allowed.

## Repository

```
AskMemoUS/                     SwiftUI app: Ask, Notes, Your questions, Settings, Eval runner
AskMemoUS/Mascot.xcassets/     Memo, the MemoUS mascot (not open-licensed, see MASCOT-LICENSE.md)
AskMemoUS/TabIcons.xcassets/   The tab icons, MemoUS art (not open-licensed, see MASCOT-LICENSE.md)
AskMemoUS/AppIcon.xcassets/    The app icon, MemoUS art (not open-licensed, see MASCOT-LICENSE.md)
Packages/HybridAskCore/        Gates, note filter, prompt, checks, tip text, age context, eval cases and runner
Packages/HybridAskFirebase/    AskModel backed by Firebase AI Logic (on-device + Gemini)
docs/EVAL_LOG.md               Every eval change and run, dated
PRIVACY.md                     What the app stores and what it sends, and when
project.yml                    XcodeGen project (the .xcodeproj is generated, not committed)
```

## Run it

You need:

- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An iPhone with Apple Intelligence on iOS 26 or later, for the on-device model
- A Firebase project with **Firebase AI Logic** set up for the Gemini Developer
  API, and **App Check** turned on for the app

Steps:

1. Add an iOS app to your Firebase project and download its
   `GoogleService-Info.plist` into `AskMemoUS/`. It is gitignored. Never commit
   it.
2. In `project.yml`, set `PRODUCT_BUNDLE_IDENTIFIER` to your app's bundle id.
3. Generate the project with your Apple Team ID and open it (or leave the ID
   out and pick your team under Signing & Capabilities in Xcode):

   ```bash
   ASKMEMOUS_TEAM=YOURTEAMID xcodegen generate && open AskMemoUS.xcodeproj
   ```

4. Run on your iPhone. In **Settings → App Check (debug)**, tap **Get App Check
   token**. The debug token is printed in the Xcode console. Add it in the
   Firebase console under App Check → Manage debug tokens. Keep it private; it
   gives anyone who has it access to your project.
5. The app starts with a fictional child, Mia, and seven sample notes. Ask
   something like "She keeps waking at 5am. What could I try?"

Run the core tests (no device or Firebase needed):

```bash
cd Packages/HybridAskCore && swift test
```

## The eval

The cases are in
[`eval-cases.json`](Packages/HybridAskCore/Sources/HybridAskCore/Resources/eval-cases.json),
as plain JSON so other ports can use them. All children and notes in it are
fictional. Each case gives a child, some notes, a question and the expected
outcome: a tip from a given note, a tip or no tip, or a specific fixed reply.
Some also list words a tip must never contain.

Eight cases (`f01`–`f08`) are short conversations. After the first tip, the
parent taps "Another idea?" or "That didn't help." one to three times. Once the
good notes are used up, what's left is unsafe for the child's age, a worse day,
off-topic, or nothing, and the answer must be a fixed reply, never a weaker
tip. They are counted in their own "Follow-ups" column, so the single-question
numbers above stay comparable.

To run it, open **Settings → Eval runner**. In a Release build the eval runner
and the model picker stay hidden until you tap the version line at the bottom
of Settings seven times. That lasts until you quit the app. Debug builds show
them straight away. Pick a variant and a
route, and which cases (all, held-out only, or follow-ups only), then **Run**. Cloud runs wait 4.5 seconds between calls to stay within
the Gemini free tier. Share the table or the full details from the same screen.

## License

[Apache License 2.0](LICENSE), except the MemoUS art. Memo, the star that
answers in the Ask screen, the app icon and the tab icons belong to MemoUS and are not
open-licensed. See [MASCOT-LICENSE.md](MASCOT-LICENSE.md).

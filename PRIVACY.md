# AskMemoUS privacy policy

Last updated: November 17, 2026

AskMemoUS is a test app for the #BuildHybridAI 2026 challenge, made by MemoUS
Software Development Services, Cebu City, Philippines. This policy covers
AskMemoUS only. The MemoUS app has its own policy at
[memous.app/privacy](https://memous.app/privacy).

## In short

- No account, no sign-in, no ads, no analytics, no tracking.
- Your child's name, notes and questions are stored only on your iPhone.
- Nothing about your child leaves the iPhone unless you turn on **Allow cloud checks**.
  Then, only when the iPhone couldn't answer, the question and some notes are sent to
  Google's Gemini model to get an answer, with your child's name replaced by
  "your child". The app does download its own settings from Firebase Remote Config.
  That sends no notes, questions or names.

## What the app stores, and where

| What | Where | How to delete it |
|---|---|---|
| Your child's name and birthday | On this iPhone | Change it in Settings, or delete the app |
| Your notes | On this iPhone | Delete a note, or delete the app |
| Questions you asked, with the date and your child's age then | On this iPhone | Your questions → Delete all, or delete the app |
| Your settings (cloud checks, model) | On this iPhone | Delete the app |

The app opens with a fictional child and sample notes. You can change or delete
them.

We have no server that stores your data, and we can't see it.

The app downloads settings from Firebase Remote Config (which model to use,
whether cloud checks are paused, and extra safety phrases). That download sends
no notes, questions or names. Firebase uses an installation ID for it.

## When something leaves the iPhone

**On device (the default).** Apple's on-device model reads your question and
notes on the iPhone. Nothing is sent anywhere.

**Cloud checks (only if you allow them).** If **Allow cloud checks** is on (in
Settings, or by tapping **Check in the cloud** on an answer), and the on-device
answer didn't pass the app's checks, the app sends one request to Google's
Gemini model through Firebase AI Logic. The request holds:

- your question,
- the notes that could answer it, and
- your child's age in months, if you entered a birthday.

Your child's name is replaced with "your child" before anything is sent, in your
question and in the notes. Google processes the request to produce an answer and
handles it under the
[Gemini API terms](https://ai.google.dev/gemini-api/terms) and
[Google's privacy policy](https://policies.google.com/privacy). We don't keep a
copy.

Write names of other people in your notes (a sibling, a friend) only if you're
happy for them to be sent with the note when cloud checks are on. Only your
child's name is replaced.

**App Check.** To stop others from using the app's Gemini access, every cloud
request carries a Firebase App Check token. It comes from Apple's App Attest and
proves the request came from a real copy of AskMemoUS. It doesn't hold your
notes, your name or anything about you.

**TestFlight.** If you installed AskMemoUS through TestFlight, Apple shares
crash reports and the feedback you send with us, under
[Apple's TestFlight terms](https://www.apple.com/legal/internet-services/itunes/testflight/).

## Children

AskMemoUS is for parents, not for children to use. It doesn't collect
information from children.

## Not medical advice

AskMemoUS only repeats what you noted. It isn't medical advice. Health
questions get a fixed reply that points you to your paediatrician.

## Changes

If this policy changes, the "Last updated" date above changes too. Every
version is kept in this repository's history.

## Contact

[privacy@memous.app](mailto:privacy@memous.app)

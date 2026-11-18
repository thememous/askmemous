# Demo video

The owner records and narrates this. One continuous take, under 3 minutes.
Mia is the sample child, 14 months, with the seven sample notes. Leave the
birthday alone. Cloud checks start undecided (the Settings toggle looks off).
Do not tap that toggle before the cloud card: tapping it off hides the card.

Shots marked **Apple Intelligence** need the on-device model. The others do not.
A Release build keeps Settings to the simple controls. A Debug build also shows
the model picker and the eval runner; don't linger on those.

| Time | Shot | On screen | Needs Apple Intelligence |
|---|---|---|---|
| 0:00–0:12 | Airplane mode on. Open AskMemoUS. Glance at Settings: Allow cloud checks looks off. Do not tap it. | Control Center, then Settings | No |
| 0:12–0:40 | Ask. Use the suggestion "She keeps waking at 5am. What could I try this week?" | Tip from "skipped the late snack", then a quieter **At 14 months** line and "General information, not about Mia's notes". Source line: "Answered on this iPhone". | **Yes** |
| 0:40–0:55 | Notes. Show the snack note with **skipped the late snack** highlighted, and "Can back a tip". | Notes | No |
| 0:55–1:12 | Back to Ask. Tap **Another idea**. | A second checked answer on the same question. | **Yes** |
| 1:12–1:38 | New question no note is about, such as "Bath time is a fight. What could I try?" | "Your recent notes don't point to something specific to try for this yet…", plus an **At 14 months** line, then the **Check this in the cloud?** card. | **Yes** |
| 1:38–1:48 | Turn airplane mode off so the cloud request can leave the phone. | Control Center | No |
| 1:48–2:10 | Tap **Check in the cloud**. | The answer updates. The source line changes to "Checked on this iPhone, answered in the cloud". | Cloud, not Apple Intelligence |
| 2:10–2:22 | Settings, the simple controls only: name, birthday, Allow cloud checks (now on). | Settings | No |
| 2:22–2:40 | Ask "She has a fever. What should I do?" | Only "That's a question for Mia's doctor or nurse…". No age line. | No |
| 2:40–3:00 | The eval table in the README ("Why not let the model write?"). | The held-out numbers | No |

Narration can stay sparse. The pictures carry it: the tip is from the note, the age line is general and labelled as such, a fever never gets either, and the table is why the model only points.

If the on-device model refuses the bath question instead of answering, the card still appears but the age line does not (that reply is "couldn't get an answer", not "no note backs a tip"). Ask the bath question again, or use another care question such as "How do I help with brushing teeth?"

import Foundation
import Testing
@testable import HybridAskCore

private let noNote = AskOutcome.floor(.noSupportingNote)
private let noMore = AskOutcome.floor(.noOtherNote)

@Test func noteNudgeNamesTheTopicAndFillsInTheChild() {
  let sleep = "She keeps waking at 5am. What could I try this week?"
  #expect(NoteNudge.hint(question: sleep, childName: "Mia", outcome: noNote)
    == "Write tonight's bedtime in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "Evenings are hard lately. Any ideas?", childName: "Mia", outcome: noNote)
    == "Write tonight's bedtime in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "Daycare drop-off is hard", childName: "Mia", outcome: noNote)
    == "Write what helped Mia calm down today in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: sleep, childName: "Sam", outcome: noMore)
    == "Write tonight's bedtime in one line, and next time I can point to what works for Sam.")
  #expect(NoteNudge.hint(question: "How can I get her to eat lunch?", childName: "Mia", outcome: noNote)
    == "Write what Mia ate today in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "Why is she so curious about everything?", childName: "Mia", outcome: noNote)
    == "Write what caught Mia's interest in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "She had a tantrum this afternoon", childName: "Mia", outcome: noNote)
    == "Write what helped Mia calm down today in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "How was school today?", childName: "Mia", outcome: noNote)
    == "Write how the day went in one line, and next time I can point to what works for Mia.")
}

@Test func noteNudgeUsesAGenericHintWhenTheTopicIsUnknown() {
  #expect(NoteNudge.hint(question: "What colour is the sky today?", childName: "Mia", outcome: noNote)
    == "Write what happened in one line, and next time I can point to what works for Mia.")
  #expect(NoteNudge.hint(question: "Lunch was unfinished but she woke at 5am", childName: "Mia", outcome: noNote)
    == "Write tonight's bedtime in one line, and next time I can point to what works for Mia.")
}

@Test func noteNudgeStaysOffTipsGatedQuestionsAndOtherFloors() {
  let sleep = "How is bedtime going?"
  let note = AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
  let tip = AskOutcome.tip(text: "Try leaving it out again this week.", basedOn: note)
  #expect(NoteNudge.hint(question: sleep, childName: "Mia", outcome: tip) == nil)
  for reason in [FloorReason.emptyQuestion, .noNotes, .medicalTopic, .emergency, .parentDistress, .unsafeTip, .modelUnavailable, .cloudNotAllowed] {
    #expect(NoteNudge.hint(question: sleep, childName: "Mia", outcome: .floor(reason)) == nil, "\(reason)")
  }
  #expect(NoteNudge.hint(question: "She has a fever and will not sleep", childName: "Mia", outcome: noNote) == nil)
  let extra = AskSafety.withExtras(AskSafetyExtras(healthPhrases: ["night terror"]))
  #expect(NoteNudge.hint(question: "She had a night terror at bedtime", childName: "Mia", outcome: noNote, safety: extra) == nil)
  #expect(NoteNudge.hint(question: "She had a night terror at bedtime", childName: "Mia", outcome: noNote) != nil)
}

@Test func noteNudgeTemplatesAreOnePerTopicAndPassTheTipSafetyList() {
  #expect(Set(NoteNudge.templates).count == AskTopic.allCases.count + 1)
  #expect(NoteNudge.templates.contains(NoteNudge.generic))
  for template in NoteNudge.templates {
    #expect(template.contains("{name}"))
    #expect(!template.contains("should"))
    let filled = template.replacingOccurrences(of: "{name}", with: "Mia")
    #expect(AskSafetyLists.builtIn.unsafePhrase(inTip: filled, ageMonths: nil) == nil, "\(filled)")
    #expect(AskSafetyLists.builtIn.unsafePhrase(inTip: filled, ageMonths: 0) == nil, "\(filled)")
  }
}

@Test func floorCopyAndTheWorryLineAreUnchanged() {
  #expect(FloorText.worryLine == "If you're worried, ask your paediatrician.")
  #expect(FloorText.text(.noSupportingNote, childName: "Mia")
    == "Your recent notes don't point to something specific to try for this yet. Next time it happens, add a quick note about when and what came before — that's what an answer can build on.")
  #expect(FloorText.text(.noOtherNote, childName: "Mia")
    == "That's every note that could back a tip for this so far. Next time you try something, add a quick note about how it went: the next answer can build on it.")
  #expect(!FloorText.text(.noSupportingNote, childName: "Mia").contains(FloorText.worryLine))
  #expect(!FloorText.text(.noSupportingNote, childName: "Mia").contains("next time I can point"))
}

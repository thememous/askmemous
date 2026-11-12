import Foundation
import Testing
@testable import HybridAskCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86_400) }

private let mia = AskChild(name: "Mia", ageMonths: 14)
private let notes = [
  AskNote(text: "Up at 5:10 again, happy and chatty in the cot.", category: "sleep", createdAt: daysAgo(2)),
  AskNote(text: "Long nap 12–2:30 after the park.", category: "routine", createdAt: daysAgo(4)),
  AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", category: "sleep", createdAt: daysAgo(6)),
]

/// Returns a fixed draft per route and records what it was asked.
private final class FakeModel: AskModel, @unchecked Sendable {
  var draft: AskDraft
  var cloudDraft: AskDraft?
  var shouldThrow = false
  var cloudThrows = false
  var routes: [AskRoute] = []
  var calls: Int { routes.count }
  var lastPrompt = ""
  var lastInstructions = ""

  init(_ draft: AskDraft) { self.draft = draft }

  func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    routes.append(route)
    lastPrompt = prompt
    lastInstructions = instructions
    if shouldThrow { throw URLError(.notConnectedToInternet) }
    if route == .cloudOnly {
      if cloudThrows { throw URLError(.notConnectedToInternet) }
      return (cloudDraft ?? draft, .cloud, "cloud-model")
    }
    return (draft, .onDevice, "test-model")
  }
}

// MARK: - Age bands

@Test func bandsMatchMemoUSCutPoints() {
  #expect(AgeBand(ageMonths: 0) == .infant)
  #expect(AgeBand(ageMonths: 11) == .infant)
  #expect(AgeBand(ageMonths: 12) == .toddler)
  #expect(AgeBand(ageMonths: 35) == .toddler)
  #expect(AgeBand(ageMonths: 36) == .earlySchool)
  #expect(AgeBand(ageMonths: 84) == .schoolAge)
  #expect(AgeBand(ageMonths: -1) == nil)
}

// MARK: - Prompt

@Test func notesAreNumberedNewestFirst() {
  let n = AskPrompt.number(notes.reversed(), now: now)
  #expect(n.ids["n1"]?.text.hasPrefix("Up at 5:10") == true)
  #expect(n.ids["n3"]?.text.hasPrefix("Slept to 6:40") == true)
  #expect(n.lines[0].hasPrefix("n1 [2d ago · sleep]"))
}

@Test func noteLimitAndEmptyNotesSkipped() {
  var many = (0..<10).map { AskNote(text: "note \($0)", createdAt: daysAgo($0)) }
  many.append(AskNote(text: "   ", createdAt: now))
  let n = AskPrompt.number(many, now: now)
  #expect(n.ids.count == AskPrompt.noteLimit)
  #expect(n.ids["n1"]?.text == "note 0")
}

@Test func noBirthdateNeverGuessesAStage() {
  let text = AskPrompt.instructions(for: AskChild(name: "Mia", ageMonths: nil))
  #expect(text.contains("No birthdate is known"))
  #expect(!text.contains("toddler"))
}

@Test func instructionsCarryTheHonestyRules() {
  let text = AskPrompt.instructions(for: mia)
  #expect(text.contains("never to the child"))
  #expect(text.contains("noteId to none"))
  #expect(text.contains("No second tip"))
  #expect(text.contains("toddler"))
}

// MARK: - Checks

@Test func tipKeepsTheRealNote() {
  let numbered = AskPrompt.number(notes, now: now)
  let out = AskCheck.review(
    AskDraft(noteId: "n3", tip: "Try skipping the late snack again this week."),
    notes: numbered.ids, child: mia
  )
  guard case let .tip(text, note) = out else { Issue.record("expected tip"); return }
  #expect(text == "Try skipping the late snack again this week.")
  #expect(note.text.hasPrefix("Slept to 6:40"))
}

@Test func unknownOrNoneNoteIsAFloor() {
  let ids = AskPrompt.number(notes, now: now).ids
  #expect(AskCheck.review(AskDraft(noteId: "n9", tip: "Try x."), notes: ids, child: mia) == .floor(.noSupportingNote))
  #expect(AskCheck.review(AskDraft(noteId: "none", tip: ""), notes: ids, child: mia) == .floor(.noSupportingNote))
  #expect(AskCheck.review(AskDraft(noteId: " N2 ", tip: "Try a park morning."), notes: ids, child: mia)
    != .floor(.noSupportingNote))
}

@Test func greetingToTheChildIsDropped() {
  let ids = AskPrompt.number(notes, now: now).ids
  let out = AskCheck.review(
    AskDraft(noteId: "n3", tip: "Hello, Mia. Try skipping the late snack."), notes: ids, child: mia
  )
  #expect(out == .tip(text: "Try skipping the late snack.", basedOn: ids["n3"]!))
}

@Test func listsAndExtraTipsAreCut() {
  let ids = AskPrompt.number(notes, now: now).ids
  let draft = AskDraft(noteId: "n3", tip: """
  Skip the late snack again. Keep bedtime the same.
  - Practice toddler bowling.
  - Build a cushion obstacle course.
  """)
  guard case let .tip(text, _) = AskCheck.review(draft, notes: ids, child: mia) else {
    Issue.record("expected tip"); return
  }
  #expect(text == "Skip the late snack again. Keep bedtime the same.")
}

@Test func medicalWordsBecomeTheFixedReply() {
  let ids = AskPrompt.number(notes, now: now).ids
  let out = AskCheck.review(AskDraft(noteId: "n1", tip: "Ask about melatonin."), notes: ids, child: mia)
  #expect(out == .floor(.medicalTopic))
  #expect(AskCheck.mentionsMedical("Is she delayed?"))
  #expect(!AskCheck.mentionsMedical("Could I delay the snack?"))
}

// MARK: - Flow

@Test func emptyNotesNeverCallTheModel() async {
  let model = FakeModel(AskDraft(noteId: "n1", tip: "x"))
  let answer = await HybridAsk(model: model).answer(question: "What now?", child: mia, notes: [], now: now)
  #expect(answer.outcome == .floor(.noNotes))
  #expect(answer.source == .app)
  #expect(model.calls == 0)
}

@Test func medicalQuestionNeverCallsTheModel() async {
  let model = FakeModel(AskDraft(noteId: "n1", tip: "x"))
  let answer = await HybridAsk(model: model).answer(
    question: "Does she have ADHD?", child: mia, notes: notes, now: now
  )
  #expect(answer.outcome == .floor(.medicalTopic))
  #expect(model.calls == 0)
}

@Test func modelErrorIsAnHonestFloor() async {
  let model = FakeModel(AskDraft(noteId: "n1", tip: "x"))
  model.shouldThrow = true
  let answer = await HybridAsk(model: model).answer(question: "5am?", child: mia, notes: notes, now: now)
  #expect(answer.outcome == .floor(.modelUnavailable))
}

@Test func happyPathSendsNumberedNotes() async {
  let model = FakeModel(AskDraft(noteId: "n3", tip: "Skip the late snack again."))
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am. What could I try?", child: mia, notes: notes, now: now
  )
  #expect(model.lastPrompt.contains("n3 [6d ago · sleep] Slept to 6:40"))
  #expect(answer.source == .onDevice)
  guard case let .tip(_, note) = answer.outcome else { Issue.record("expected tip"); return }
  #expect(note.text.hasPrefix("Slept to 6:40"))
}

@Test func recordRoundTripsAsJSON() throws {
  let answer = AskAnswer(outcome: .tip(text: "Skip it.", basedOn: notes[2]), source: .cloud, modelVersion: "m")
  let record = AskRecord(askedAt: now, question: "5am?", child: mia, answer: answer)
  let data = try JSONEncoder().encode(record)
  #expect(try JSONDecoder().decode(AskRecord.self, from: data) == record)
}

// MARK: - Relevance + escalation

@Test func topicsAreFoundInPlainWords() {
  #expect(AskTopic.of("She keeps waking at 5am") == [.sleep])
  #expect(AskTopic.of("Why is Ethan so curious?").contains(.curiosity))
  #expect(AskTopic.of(notes[2]).isSuperset(of: [.sleep, .food]))
}

@Test func offTopicNoteIsRejected() {
  #expect(!AskCheck.isRelevant(question: "Why is Ethan so curious?", note: notes[1]))
  #expect(AskCheck.isRelevant(question: "She keeps waking at 5am", note: notes[2]))
  #expect(AskCheck.isRelevant(question: "Any ideas for tomorrow?", note: notes[1]))
}

@Test func offTopicOnDeviceAnswerEscalatesToCloud() async {
  let model = FakeModel(AskDraft(noteId: "n2", tip: "Take a walk to explore."))
  model.cloudDraft = AskDraft(noteId: "none", tip: "")
  let answer = await HybridAsk(model: model).answer(
    question: "Why is Ethan so curious?", child: mia, notes: notes, now: now
  )
  #expect(model.routes == [.hybrid, .cloudOnly])
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(answer.source == .cloud)
  #expect(answer.escalated)
}

@Test func offlineEscalationKeepsTheHonestFloor() async {
  let model = FakeModel(AskDraft(noteId: "n2", tip: "Take a walk to explore."))
  model.cloudThrows = true
  let answer = await HybridAsk(model: model).answer(
    question: "Why is Ethan so curious?", child: mia, notes: notes, now: now
  )
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(answer.source == .onDevice)
  #expect(!answer.escalated)
}

@Test func goodOnDeviceAnswerNeverCallsTheCloud() async {
  let model = FakeModel(AskDraft(noteId: "n3", tip: "Skip the late snack again."))
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, now: now
  )
  #expect(model.routes == [.hybrid])
  #expect(!answer.escalated)
}

@Test func onDeviceOnlyRouteNeverEscalates() async {
  let model = FakeModel(AskDraft(noteId: "none", tip: ""))
  _ = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, route: .onDeviceOnly, now: now
  )
  #expect(model.routes == [.onDeviceOnly])
}

// MARK: - Quote + direction

@Test func quoteMustBeRealWordsFromTheNote() {
  #expect(AskCheck.quoteIsInNote("skipped the late snack", note: notes[2]))
  #expect(AskCheck.quoteIsInNote("Skipped  the LATE snack.", note: notes[2]))
  #expect(!AskCheck.quoteIsInNote("gave her a late snack", note: notes[2]))
  #expect(!AskCheck.quoteIsInNote("snack", note: notes[2]))
}

@Test func reversedAdviceIsRejected() {
  let ids = AskPrompt.number(notes, now: now).ids
  let reversed = AskDraft(noteId: "n3", quote: "skipped the late snack", tip: "Offer the late snack again soon.")
  #expect(AskCheck.review(reversed, notes: ids, child: mia) == .floor(.noSupportingNote))
  let kept = AskDraft(noteId: "n3", quote: "skipped the late snack", tip: "Try skipping the late snack this week.")
  #expect(AskCheck.review(kept, notes: ids, child: mia) == .tip(text: "Try skipping the late snack this week.", basedOn: ids["n3"]!))
  let moved = AskDraft(noteId: "n3", quote: "we skipped the late snack", tip: "Move the snack earlier, before bath.")
  #expect(AskCheck.review(moved, notes: ids, child: mia) != .floor(.noSupportingNote))
}

@Test func madeUpQuoteIsRejected() {
  let ids = AskPrompt.number(notes, now: now).ids
  let draft = AskDraft(noteId: "n2", quote: "loves exploring the garden", tip: "Try a garden walk.")
  #expect(AskCheck.review(draft, notes: ids, child: mia) == .floor(.noSupportingNote))
}

@Test func reversedOnDeviceAnswerEscalates() async {
  let model = FakeModel(AskDraft(noteId: "n3", quote: "skipped the late snack", tip: "Offer the late snack again soon."))
  model.cloudDraft = AskDraft(noteId: "n3", quote: "skipped the late snack", tip: "Try skipping the late snack this week.")
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, now: now
  )
  #expect(answer.escalated)
  #expect(answer.outcome == .tip(text: "Try skipping the late snack this week.", basedOn: notes[2]))
}

// MARK: - Echo

@Test func tipThatRepeatsTheNoteIsRejected() {
  #expect(AskCheck.isEcho(tip: "Take a long nap 12–2:30 after the park soon.", note: notes[1]))
  #expect(!AskCheck.isEcho(tip: "Leave the late snack out again tonight.", note: notes[2]))
  #expect(!AskCheck.isEcho(tip: "Try skipping the late snack this week.", note: notes[2]))
  #expect(!AskCheck.isEcho(tip: "Move the snack earlier, before bath.", note: notes[2]))
  let ids = AskPrompt.number(notes, now: now).ids
  let echo = AskDraft(noteId: "n2", quote: "Long nap 12–2:30 after the park", tip: "Take a long nap 12–2:30 after the park soon.")
  #expect(AskCheck.review(echo, notes: ids, child: mia) == .floor(.noSupportingNote))
}

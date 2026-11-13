import Foundation
import Testing
@testable import HybridAskCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86_400) }

private let mia = AskChild(name: "Mia", ageMonths: 14)
private let notes = [
  AskNote(text: "Up at 5:10 again, happy and chatty in the cot.", category: "sleep", createdAt: daysAgo(2)),
  AskNote(text: "Long nap 12–2:30 today.", category: "routine", createdAt: daysAgo(4)),
  AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", category: "sleep", createdAt: daysAgo(6)),
]

/// Returns a fixed draft per route and records what it was asked.
private final class FakeModel: AskModel, @unchecked Sendable {
  var draft: AskDraft
  var cloudDraft: AskDraft?
  var shouldThrow = false
  var cloudThrows = false
  var onDeviceThrows = false
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
    if onDeviceThrows && route != .cloudOnly { throw URLError(.cannotDecodeContentData) }
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

@Test func notesKeepTheGivenOrder() {
  let n = AskPrompt.number(notes, now: now)
  #expect(n.ids["n1"]?.text.hasPrefix("Up at 5:10") == true)
  #expect(n.ids["n3"]?.text.hasPrefix("Slept to 6:40") == true)
  #expect(n.lines[0].hasPrefix("n1 [2d ago · sleep]"))
  let reversed = AskPrompt.number(notes.reversed(), now: now)
  #expect(reversed.ids["n1"]?.text.hasPrefix("Slept to 6:40") == true)
}

@Test func noteLimitAndEmptyNotesSkipped() {
  var many = (0..<10).map { AskNote(text: "note \($0)", createdAt: daysAgo($0)) }
  many.insert(AskNote(text: "   ", createdAt: now), at: 0)
  let n = AskPrompt.number(many, now: now)
  #expect(n.ids.count == AskPrompt.noteLimit)
  #expect(n.ids["n1"]?.text == "note 0")
}

@Test func instructionsAskOnlyForWordsAndDirection() {
  let text = AskPrompt.instructions(for: mia)
  #expect(text.contains("noteId to none"))
  #expect(text.contains("word for word"))
  #expect(!text.contains("dayWas"), "the app reads the day from the note")
  #expect(text.contains("The app writes the tip"))
}

// MARK: - Retrieval

@Test func retrievalFindsTheOlderSleepNote() throws {
  let c = try #require(try EvalSet.bundled().cases.first { $0.id == "h20-retrieval-older-sleep-note" })
  let built = c.askNotes(now: now)
  let picked = AskRetrieval.select(built.notes, question: c.question)
  #expect(picked.count == AskRetrieval.defaultLimit)
  #expect(picked.contains { built.caseIdFor[$0.id] == "g" })
}

@Test func fewNotesAreAllKept() {
  #expect(AskRetrieval.select(notes, question: "Anything?").count == 3)
}

// MARK: - Finding the object

@Test func objectMustBeTheNotesOwnWords() {
  let text = notes[2].text
  #expect(AskCheck.locate("the late snack", in: text)?.span == "the late snack")
  #expect(AskCheck.locate("the late snack", in: text)?.leftOut == true)
  #expect(AskCheck.locate("skipped the LATE snack.", in: text)?.leftOut == true)
  #expect(AskCheck.locate("the day we skipped the late snack", in: text)?.span == "the late snack")
  #expect(AskCheck.locate("gave her a late snack", in: text) == nil)
  #expect(AskCheck.locate("snack", in: text) == nil)
  #expect(AskCheck.locate("loves exploring the garden", in: notes[1].text) == nil)
}

@Test func smallSlipsInCopyingStillMatch() {
  let note = "Went down at 7 without crying when we kept the room dark and quiet after dinner."
  let found = AskCheck.locate("kept the room dark and quiet after dinner", in: note)
  #expect(found?.span == "kept the room dark and quiet after dinner")
  #expect(found?.leftOut == false)
  // One word off out of eight still counts; the span is the note's own text.
  #expect(AskCheck.locate("kept the room dark and calm after dinner", in: note) != nil)
}

@Test func dayIsReadFromTheNotesWording() {
  #expect(AskCheck.dayFromWording(notes[2].text) == .better)
  #expect(AskCheck.dayFromWording("Fussy all afternoon on the day we skipped the morning nap.") == .worse)
  #expect(AskCheck.dayFromWording("Went down at 7 without crying when we kept the room dark.") == .better)
  #expect(AskCheck.dayFromWording("Long nap 12–2:30 after the park.") == .unclear)
  #expect(AskCheck.dayFromWording("Cried at drop-off but settled quickly.") == .unclear)
}

// MARK: - The app decides the direction

@Test func betterDayWithoutItMeansLeaveItOut() {
  let ids = AskPrompt.number(notes, now: now).ids
  #expect(AskCheck.review(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better), notes: ids, child: mia) == .tip(text: "Try leaving out the late snack again this week. That's what was different on the better day in your note.", basedOn: ids["n3"]!))
}

@Test func betterDayWithItMeansRepeatIt() {
  let note = AskNote(text: "Didn't cry at drop-off when we did a quick goodbye wave at the door.", createdAt: daysAgo(1))
  let out = AskCheck.review(AskDraft(noteId: "n1", object: "a quick goodbye wave at the door", dayWas: .better),
                            notes: ["n1": note], child: mia)
  #expect(out == .tip(text: "Try a quick goodbye wave at the door again this week. It's what was different on the better day in your note.", basedOn: note))
}

@Test func worseDayWithoutItMeansKeepIt() {
  let note = AskNote(text: "Fussy all afternoon on the day we skipped the morning nap.", createdAt: daysAgo(1))
  let out = AskCheck.review(AskDraft(noteId: "n1", object: "the morning nap", dayWas: .worse),
                            notes: ["n1": note], child: mia)
  #expect(out == .tip(text: "Try keeping the morning nap this week. Your note shows the day without it was harder.", basedOn: note))
}

@Test func worseDayWithItHasNothingToRepeat() {
  let note = AskNote(text: "Cried for an hour after the late screen time.", createdAt: daysAgo(1))
  let out = AskCheck.review(AskDraft(noteId: "n1", object: "the late screen time", dayWas: .worse),
                            notes: ["n1": note], child: mia)
  #expect(out == .floor(.noSupportingNote))
}

@Test func modelAndNoteMustAgreeOnTheDay() {
  let ids = AskPrompt.number(notes, now: now).ids
  // The note says better; a model claiming worse would flip the advice.
  #expect(AskCheck.review(AskDraft(noteId: "n3", object: "the late snack", dayWas: .worse), notes: ids, child: mia)
    == .floor(.noSupportingNote))
  // Note silent and links nothing: nothing to go on, even when the model calls it a better day.
  #expect(AskCheck.review(AskDraft(noteId: "n2", object: "Long nap 12–2:30 today", dayWas: .better),
                          notes: ids, child: mia) == .floor(.noSupportingNote))
  // Model unsure, note clear: the note decides.
  #expect(AskCheck.review(AskDraft(noteId: "n3", object: "the late snack", dayWas: .unclear), notes: ids, child: mia)
    != .floor(.noSupportingNote))
}

@Test func unknownOrNoneNoteIsAFloor() {
  let ids = AskPrompt.number(notes, now: now).ids
  #expect(AskCheck.review(AskDraft(noteId: "n9", object: "the late snack", dayWas: .better), notes: ids, child: mia) == .floor(.noSupportingNote))
  #expect(AskCheck.review(AskDraft(noteId: "none", object: "", dayWas: .unclear), notes: ids, child: mia) == .floor(.noSupportingNote))
  #expect(AskCheck.review(AskDraft(noteId: " N3 ", object: "the late snack", dayWas: .better), notes: ids, child: mia)
    != .floor(.noSupportingNote))
}

@Test func tipWithoutADeterminerIsQuoted() {
  #expect(TipText.compose(action: .repeatIt, object: "kept the room dark")
    == "Try this again this week: “kept the room dark”. It's what was different on the better day in your note.")
}

@Test func medicalWordsBecomeTheFixedReply() {
  let note = AskNote(text: "Slept through after the melatonin gummy.", createdAt: daysAgo(1))
  let out = AskCheck.review(AskDraft(noteId: "n1", object: "the melatonin gummy", dayWas: .better),
                            notes: ["n1": note], child: mia)
  #expect(out == .floor(.medicalTopic))
  #expect(AskCheck.mentionsMedical("Is she delayed?"))
  #expect(!AskCheck.mentionsMedical("Could I delay the snack?"))
}

// MARK: - Flow

@Test func emptyNotesNeverCallTheModel() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(question: "What now?", child: mia, notes: [], now: now)
  #expect(answer.outcome == .floor(.noNotes))
  #expect(answer.source == .app)
  #expect(model.calls == 0)
}

@Test func medicalQuestionNeverCallsTheModel() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "Does she have ADHD?", child: mia, notes: notes, now: now
  )
  #expect(answer.outcome == .floor(.medicalTopic))
  #expect(model.calls == 0)
}

@Test func modelErrorIsAnHonestFloor() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  model.shouldThrow = true
  let answer = await HybridAsk(model: model).answer(question: "5am?", child: mia, notes: notes, now: now)
  #expect(answer.outcome == .floor(.modelUnavailable))
}

@Test func onlyNotesThatCanBackATipReachTheModel() async {
  #expect(AskCheck.canSupportATip(notes[2].text))   // better day + "skipped"
  #expect(!AskCheck.canSupportATip(notes[0].text))  // "happy and chatty", nothing linked
  #expect(!AskCheck.canSupportATip(notes[1].text))  // doesn't say how the day went
  let model = FakeModel(AskDraft(noteId: "n1", object: "the late snack", dayWas: .unclear))
  _ = await HybridAsk(model: model).answer(question: "She keeps waking at 5am.", child: mia, notes: notes, now: now)
  #expect(!model.lastPrompt.contains("chatty"))
  #expect(!model.lastPrompt.contains("Long nap"))
  // No usable note: the app answers without asking any model.
  let none = FakeModel(AskDraft(noteId: "n1", object: "x y", dayWas: .unclear))
  let answer = await HybridAsk(model: none).answer(question: "5am?", child: mia, notes: Array(notes.prefix(2)), cloudAllowed: true, now: now)
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(none.calls == 0)
}

@Test func happyPathSendsNumberedNotes() async {
  let model = FakeModel(AskDraft(noteId: "n1", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am. What could I try?", child: mia, notes: notes, now: now
  )
  #expect(model.lastPrompt.contains("n1 [6d ago · sleep] Slept to 6:40"))
  #expect(answer.source == .onDevice)
  #expect(answer.outcome == .tip(text: "Try leaving out the late snack again this week. That's what was different on the better day in your note.", basedOn: notes[2]))
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
  let model = FakeModel(AskDraft(noteId: "n2", object: "after the park", dayWas: .better))
  model.cloudDraft = AskDraft(noteId: "none", object: "", dayWas: .unclear)
  let answer = await HybridAsk(model: model).answer(
    question: "Why is Ethan so curious?", child: mia, notes: notes, cloudAllowed: true, now: now
  )
  #expect(model.routes == [.hybrid, .cloudOnly])
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(answer.source == .cloud)
  #expect(answer.escalated)
}

@Test func offlineEscalationKeepsTheHonestFloor() async {
  let model = FakeModel(AskDraft(noteId: "n2", object: "after the park", dayWas: .better))
  model.cloudThrows = true
  let answer = await HybridAsk(model: model).answer(
    question: "Why is Ethan so curious?", child: mia, notes: notes, cloudAllowed: true, now: now
  )
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(answer.source == .onDevice)
  #expect(!answer.escalated)
}

@Test func goodOnDeviceAnswerNeverCallsTheCloud() async {
  let model = FakeModel(AskDraft(noteId: "n1", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, cloudAllowed: true, now: now
  )
  #expect(model.routes == [.hybrid])
  #expect(!answer.escalated)
}

@Test func onDeviceOnlyRouteNeverEscalates() async {
  let model = FakeModel(AskDraft(noteId: "none", object: "", dayWas: .unclear))
  _ = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, route: .onDeviceOnly, now: now
  )
  #expect(model.routes == [.onDeviceOnly])
}

@Test func wrongDayOnDeviceEscalatesAndCloudFixesIt() async {
  let model = FakeModel(AskDraft(noteId: "n1", object: "the late snack", dayWas: .worse))
  model.cloudDraft = AskDraft(noteId: "n1", object: "the late snack", dayWas: .better)
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, cloudAllowed: true, now: now
  )
  #expect(answer.escalated)
  #expect(answer.outcome == .tip(text: "Try leaving out the late snack again this week. That's what was different on the better day in your note.", basedOn: notes[2]))
}

// MARK: - Cloud consent + the child's name

@Test func withoutConsentNothingLeavesThePhone() async {
  let model = FakeModel(AskDraft(noteId: "n2", object: "after the park", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "Why is Ethan so curious?", child: mia, notes: notes, now: now
  )
  #expect(model.routes == [.onDeviceOnly])
  #expect(answer.outcome == .floor(.noSupportingNote))
  #expect(answer.cloudCouldHelp)
  #expect(!answer.escalated)
}

@Test func goodAnswerWithoutConsentDoesNotOfferTheCloud() async {
  let model = FakeModel(AskDraft(noteId: "n1", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(question: "She keeps waking at 5am.", child: mia, notes: notes, now: now)
  #expect(!answer.cloudCouldHelp)
}

@Test func cloudOnlyNeedsConsent() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, route: .cloudOnly, now: now
  )
  #expect(answer.outcome == .floor(.cloudNotAllowed))
  #expect(model.calls == 0)
}

@Test func onDeviceErrorEscalatesWithConsent() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  model.onDeviceThrows = true
  let answer = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: mia, notes: notes, cloudAllowed: true, now: now
  )
  #expect(model.routes == [.hybrid, .cloudOnly])
  #expect(answer.escalated)
  #expect(answer.source == .cloud)
}

@Test func onDeviceErrorWithoutConsentOffersTheCloud() async {
  let model = FakeModel(AskDraft(noteId: "n3", object: "the late snack", dayWas: .better))
  model.onDeviceThrows = true
  let answer = await HybridAsk(model: model).answer(question: "She keeps waking at 5am.", child: mia, notes: notes, now: now)
  #expect(model.routes == [.onDeviceOnly])
  #expect(answer.outcome == .floor(.modelUnavailable))
  #expect(answer.cloudCouldHelp)
}

@Test func theChildsNameIsNeverSentToAModel() async {
  let named = notes + [AskNote(text: "Mia slept to 7 when we kept Mia's room dark.", category: "sleep", createdAt: daysAgo(1))]
  let model = FakeModel(AskDraft(noteId: "n1", object: "your child's room dark", dayWas: .better))
  let answer = await HybridAsk(model: model).answer(
    question: "Mia keeps waking at 5am. What could I try?", child: mia, notes: named, cloudAllowed: true, now: now
  )
  #expect(!model.lastPrompt.contains("Mia"))
  #expect(!model.lastInstructions.contains("Mia"))
  #expect(model.lastPrompt.contains("your child"))
  // The object copied from the redacted note still checks out; the parent sees their own note.
  guard case let .tip(text, note) = answer.outcome else { Issue.record("expected tip, got \(answer.outcome)"); return }
  #expect(note.text.hasPrefix("Mia slept to 7"))
  #expect(!text.contains("Mia"))
}

@Test func redactionIsWholeWordAndCaseSensitive() {
  #expect(AskPrompt.redact("May may nap. Mayfield. May's cup.", name: "May") == "your child may nap. Mayfield. your child's cup.")
  #expect(AskPrompt.redact("No name here.", name: "") == "No name here.")
}

@Test func sourceComesFromTheReportedVersion() {
  #expect(AnswerSource.from(modelVersion: "apple-foundation-models-system-language-model") == .onDevice)
  #expect(AnswerSource.from(modelVersion: "gemini-3.5-flash-lite") == .cloud)
  #expect(AnswerSource.from(modelVersion: nil) == .cloud)
  #expect(AnswerSource.from(modelVersion: "") == .cloud)
}

// MARK: - The app's sample journal (same fictional notes as SampleJournal in the app)

private final class FixedDraft: AskModel, @unchecked Sendable {
  let d: AskDraft
  init(_ d: AskDraft) { self.d = d }
  func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    (d, .onDevice, AnswerSource.onDeviceModelVersion)
  }
}

@Test func sampleJournalGivesSensibleTips() async throws {
  let mia = AskChild(name: "Mia", ageMonths: 14)
  let now = Date()
  let texts = [
    "Up at 5:10 again, happy and chatty in the cot.",
    "Long nap 12–2:30 after the park.",
    "Slept to 6:40 on the day we skipped the late snack.",
    "Settled in ten minutes with the room dark and the white noise on.",
    "Fussier all evening on the day she missed the afternoon nap.",
    "Finished all her lunch when she sat at the table with us.",
    "Pointed at the dog and said “da” three times.",
  ]
  let notes = texts.enumerated().map { i, t in AskNote(text: t, createdAt: now.addingTimeInterval(-Double(i + 1) * 86_400)) }
  // The park note says nothing better or worse, but links the nap to the park.
  #expect(texts.filter(AskCheck.canSupportATip).count == 5)

  func ask(_ q: String, pick text: String, object: String) async -> AskOutcome {
    let numbered = AskPrompt.number(AskRetrieval.select(notes.filter { AskCheck.canSupportATip($0.text) }, question: q),
                                    now: now, childName: "Mia")
    let id = try! #require(numbered.ids.first { $0.value.text == text }?.key)
    return await HybridAsk(model: FixedDraft(AskDraft(noteId: id, object: object, dayWas: .unclear)))
      .answer(question: q, child: mia, notes: notes, route: .onDeviceOnly, now: now).outcome
  }

  let nap = await ask("Evenings are hard lately. Any ideas?", pick: texts[4], object: "missed the afternoon nap")
  #expect(nap == .tip(text: "Try keeping the afternoon nap this week. Your note shows the day without it was harder.", basedOn: notes[4]))
  let dark = await ask("How can I get her to settle at bedtime?", pick: texts[3], object: "the room dark and the white noise on")
  if case let .tip(text, _) = dark { #expect(text.hasPrefix("Try the room dark and the white noise on again")) } else { Issue.record("\(dark)") }
  let lunch = await ask("How can I get her to eat lunch?", pick: texts[5], object: "sat at the table with us")
  if case let .tip(text, _) = lunch { #expect(text.contains("sat at the table with us")) } else { Issue.record("\(lunch)") }
}

// MARK: - Notes that turn, like, or only say what happened (dev cases h02, h21, h27)

private func reviewOne(_ text: String, object: String, dayWas: DayWas = .unclear, name: String = "Mia") -> AskOutcome {
  let note = AskNote(text: text, createdAt: now)
  return AskCheck.review(AskDraft(noteId: "n1", object: object, dayWas: dayWas), notes: ["n1": note],
                         child: AskChild(name: name, ageMonths: 20))
}

private func tipText(_ outcome: AskOutcome) -> String? {
  if case let .tip(text, _) = outcome { return text }
  return nil
}

@Test func aNoteThatTurnsWithButCountsFromTheTurn() {
  let note = "Grumpy after school but happy again after a snack and 20 minutes outside."
  #expect(AskCheck.canSupportATip(note))
  #expect(AskCheck.decidingPart(note) == "happy again after a snack and 20 minutes outside.")
  #expect(tipText(reviewOne(note, object: "a snack and 20 minutes outside"))
    == "Try a snack and 20 minutes outside again this week. It's what was different on the better day in your note.")
  // The part before the turn is not what helped.
  #expect(reviewOne(note, object: "after school") == .floor(.noSupportingNote))
  // Mixed with no turn: still unclear.
  #expect(!AskCheck.canSupportATip("Cried at drop-off, settled after a cuddle."))
  #expect(!AskCheck.canSupportATip("Settled quickly but woke at 2."))
}

@Test func likingSomethingLinksToIt() {
  let note = "Loved the crinkly book, kept grabbing the pages."
  #expect(AskCheck.canSupportATip(note))
  #expect(tipText(reviewOne(note, object: "the crinkly book"))
    == "Try the crinkly book again this week. It's what was different on the better day in your note.")
}

@Test func aNoteThatOnlySaysWhatHappenedGetsAPlainerTip() {
  let note = "Said 'ball' three times when we played catch."
  #expect(AskCheck.canSupportATip(note))
  #expect(tipText(reviewOne(note, object: "when we played catch"))
    == "Try this again this week: “we played catch”. Your note ties it to what happened that day.")
  #expect(tipText(reviewOne("Long nap 12–2:30 after the park.", object: "after the park"))
    == "Try the park again this week. Your note ties it to what happened that day.")
  // No better or worse in the note: leaving something out isn't backed, and a model calling it worse is refused.
  #expect(reviewOne("Long nap on the day we skipped the snack.", object: "the snack") == .floor(.noSupportingNote))
  #expect(reviewOne(note, object: "we played catch", dayWas: .worse) == .floor(.noSupportingNote))
  // Still nothing linked: no tip.
  #expect(!AskCheck.canSupportATip("Pointed at the dog and said “da” three times."))
}

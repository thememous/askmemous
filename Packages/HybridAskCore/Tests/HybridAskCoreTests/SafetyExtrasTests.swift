import Foundation
import Testing
@testable import HybridAskCore

private func extras(
  emergency: String = "[]",
  distress: String = "[]",
  health: String = "[]",
  tips: String = "[]"
) -> AskSafetyLists {
  AskSafety.withExtras(AskSafetyExtras.parsed(
    emergencyJSON: emergency, distressJSON: distress, healthJSON: health, tipRulesJSON: tips
  ))
}

@Test func extraPhraseAddsAMatch() {
  let bleach = "He drank some bleach from under the sink"
  let antifreeze = "She spilled antifreeze in the garage"
  #expect(AskSafety.gate(question: bleach) == .emergency, "the built-in list already gates n22")
  #expect(AskSafety.gate(question: antifreeze) == nil)

  let lists = extras(emergency: #"["drank some bleach", "antifreeze"]"#)
  #expect(lists.gate(question: bleach) == .emergency)
  #expect(lists.gate(question: antifreeze) == .emergency)
  #expect(lists.gate(question: "The antifreeze smell is strong") == .emergency)
}

@Test func malformedEmptyOrOversizedExtrasChangeNothing() {
  let ordinary = "She keeps waking at 5am. What could I try?"
  let seizure = "He had a seizure this morning"
  #expect(AskSafety.gate(question: ordinary) == nil)
  #expect(AskSafety.gate(question: seizure) == .emergency)

  let oversized = String(repeating: "q", count: 61)
  let payloads = [
    "",
    "{",
    "null",
    "\"antifreeze\"",
    "[]",
    "[\"\", \"   \", 4, false, {\"phrase\": \"antifreeze\"}, \"\(oversized)\"]",
  ]
  for json in payloads {
    let lists = extras(emergency: json, distress: json, health: json, tips: json)
    #expect(lists.gate(question: ordinary) == nil)
    #expect(lists.gate(question: seizure) == .emergency)
    #expect(lists.gate(question: oversized) == nil)
    #expect(lists.unsafePhrase(inTip: "Try the night light again.", ageMonths: 4) == nil)
  }
}

@Test func extraCannotUngateABuiltInPhrase() {
  let seizure = "He had a seizure this morning"
  let lists = extras(emergency: #"["", "not a seizure", "fine"]"#)
  #expect(lists.gate(question: seizure) == .emergency)
  #expect(AskSafety.withExtras(.none).gate(question: seizure) == AskSafety.gate(question: seizure))

  let honey = "A spoon of honey before bed."
  let withExtra = extras(tips: #"[{"phrase":"night light","underMonths":24}]"#)
  #expect(withExtra.unsafePhrase(inTip: honey, ageMonths: 9) != nil)
  #expect(AskSafety.unsafePhrase(inTip: honey, ageMonths: 9) != nil)
}

@Test func extraUnsafeTipRuleRespectsUnderMonths() {
  let tip = "Leave the night light on."
  #expect(AskSafety.unsafePhrase(inTip: tip, ageMonths: 4) == nil)
  let lists = extras(tips: """
  [
    {"phrase":"night light","underMonths":12},
    {"phrase":"","underMonths":12},
    {"phrase":"\(String(repeating: "n", count: 61))","underMonths":12},
    {"phrase":"ok","underMonths":"12"},
    {"phrase":"lamp","underMonths":12.5}
  ]
  """)
  #expect(lists.unsafePhrase(inTip: tip, ageMonths: 11) != nil)
  #expect(lists.unsafePhrase(inTip: tip, ageMonths: 12) == nil)
  #expect(lists.unsafePhrase(inTip: tip, ageMonths: 30) == nil)
  #expect(lists.unsafePhrase(inTip: tip, ageMonths: nil) != nil)
  #expect(lists.unsafePhrase(inTip: "Try the lamp again.", ageMonths: 4) == nil)
}

@Test func extraListsKeepTheFirst200() {
  let phrases = (1...201).map { "\"phrase\($0)\"" }.joined(separator: ",")
  let lists = extras(emergency: "[\(phrases)]")
  #expect(lists.gate(question: "What about phrase200") == .emergency)
  #expect(lists.gate(question: "What about phrase201") == nil)
}

@Test func extraWildcardUsesTheSameMatchAsTheBuiltInLists() {
  let lists = extras(emergency: #"["radiator*"]"#)
  #expect(lists.gate(question: "She licked the radiator paint") == .emergency)
  #expect(AskSafety.gate(question: "She licked the radiator paint") == nil)
}

@Test func shortWildcardExtrasAreIgnored() {
  let lists = extras(emergency: #"["a*", "ab*", "abs*"]"#)
  #expect(lists.gate(question: "She had a snack") == nil)
  #expect(lists.gate(question: "She abandoned the nap") == nil)
  #expect(lists.gate(question: "She was absent at lunch") == .emergency)
}

@Test func cloudModelNameRejectsEmptyAndInvalid() {
  #expect(CloudModelName.resolve("") == CloudModelName.fallback)
  #expect(CloudModelName.resolve("   ") == CloudModelName.fallback)
  #expect(CloudModelName.resolve("gemini 2") == CloudModelName.fallback)
  #expect(CloudModelName.resolve("gemini/flash") == CloudModelName.fallback)
  #expect(CloudModelName.resolve(String(repeating: "a", count: 81)) == CloudModelName.fallback)
  #expect(CloudModelName.resolve("gemini-3.5-flash") == "gemini-3.5-flash")
  #expect(CloudModelName.fallback == "gemini-3.5-flash-lite")
}

@Test func lockedLabIgnoresASavedRoute() {
  #expect(AskRoute.cloudOnly.forParent(labUnlocked: false) == .hybrid)
  #expect(AskRoute.onDeviceOnly.forParent(labUnlocked: false) == .hybrid)
  #expect(AskRoute.hybrid.forParent(labUnlocked: false) == .hybrid)
  #expect(AskRoute.cloudOnly.forParent(labUnlocked: true) == .cloudOnly)
  #expect(AskRoute.onDeviceOnly.forParent(labUnlocked: true) == .onDeviceOnly)
}

@Test func extraGateRunsBeforeTheModel() async {
  let model = ExtrasProbe()
  let lists = extras(emergency: #"["antifreeze"]"#)
  let answer = await HybridAsk(model: model).answer(
    question: "She spilled antifreeze in the garage",
    child: AskChild(name: "Mia", ageMonths: 14),
    notes: [AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", createdAt: Date())],
    safety: lists
  )
  #expect(answer.outcome == .floor(.emergency))
  #expect(answer.source == .app)
  #expect(model.calls == 0)
}

@Test func extraTipRuleRefusesANoteTheBuiltInListsAllow() async {
  let note = AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", createdAt: Date())
  let child = AskChild(name: "Mia", ageMonths: 14)
  let model = ExtrasProbe(draft: AskDraft(noteId: "n1", object: "the late snack", dayWas: .better))
  let allowed = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: child, notes: [note], route: .onDeviceOnly, cloudAllowed: true
  )
  #expect(allowed.outcome.isTip)

  let lists = AskSafety.withExtras(AskSafetyExtras(unsafeTipRules: [
    .init(phrase: "snack", underMonths: 24),
  ]))
  let refused = await HybridAsk(model: model).answer(
    question: "She keeps waking at 5am.", child: child, notes: [note],
    route: .onDeviceOnly, cloudAllowed: true, safety: lists
  )
  #expect(refused.outcome == .floor(.unsafeTip))
}

private extension AskOutcome {
  var isTip: Bool {
    if case .tip = self { true } else { false }
  }
}

private final class ExtrasProbe: AskModel, @unchecked Sendable {
  var draft: AskDraft?
  var calls = 0
  init(draft: AskDraft? = nil) { self.draft = draft }

  func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    calls += 1
    guard let draft else { throw URLError(.cannotFindHost) }
    return (draft, .onDevice, "probe")
  }
}

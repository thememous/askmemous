import Foundation
import Testing
@testable import HybridAskCore

private let mia = AskChild(name: "Mia", ageMonths: 14)
private let noBirthday = AskChild(name: "Mia", ageMonths: nil)
private let floor = AskOutcome.floor(.noSupportingNote)
private let sampleNote = AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
private let tip = AskOutcome.tip(text: "Your note says things went better on the day without the late snack. Try leaving it out again this week.", basedOn: sampleNote)

private func line(_ question: String, _ child: AskChild = mia, _ outcome: AskOutcome = floor,
                  safety: AskSafetyLists = .builtIn) -> AgeContext.Line? {
  AgeContext.line(question: question, child: child, outcome: outcome, safety: safety)
}

@Test func ageContextLibraryCoversTheEverydayTopics() throws {
  let loaded = try AgeContext.loadBundled()
  #expect(loaded.sources.contains { $0.contains("American Academy of Pediatrics") })
  #expect(loaded.sources.contains { $0.contains("CDC") })
  #expect(loaded.sources.contains { $0.contains("NHS") })
  #expect(AgeContext.sources == loaded.sources)
  #expect(AgeContext.coveredTopics.count == 9)
  #expect(!AgeContext.coveredTopics.contains(.curiosity))
  #expect(!AgeContext.coveredTopics.contains(.school))
  #expect(AgeContext.entries[.curiosity] == nil)
  #expect(AgeContext.entries[.school] == nil)
  #expect(AgeContext.entryTexts.count == 63)
  for topic in AgeContext.coveredTopics {
    for band in AgeContext.Band.allCases {
      let text = try #require(AgeContext.entries[topic]?[band])
      #expect((1...240).contains(text.count), "\(topic) \(band.rawValue) is \(text.count) characters")
      let sentences = text.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      #expect((1...2).contains(sentences.count), "\(topic) \(band.rawValue)")
      #expect(!text.contains { $0.isNumber }, "\(topic) \(band.rawValue) gives an amount")
    }
  }
}

@Test func ageContextLibraryAvoidsBannedWording() {
  let banned: Set<String> = [
    "normal", "behind", "should", "shouldn", "dose", "doses",
    "he", "she", "his", "her", "him", "hers", "boy", "girl", "son", "daughter",
    "male", "female", "mum", "mom", "dad", "man", "woman",
  ]
  for text in AgeContext.entryTexts {
    let words = Set(AskCheck.normalized(text).split(separator: " ").map(String.init))
    #expect(words.isDisjoint(with: banned), "\(words.intersection(banned)) in: \(text)")
  }
}

@Test func everyAgeContextLinePassesTheTipSafetyListForItsWholeBand() {
  for topic in AgeContext.coveredTopics {
    for band in AgeContext.Band.allCases {
      let text = AgeContext.entries[topic]![band]!
      for month in band.months {
        let hit = AskSafetyLists.builtIn.unsafePhrase(inTip: text, ageMonths: month)
        #expect(hit == nil, "\(topic) \(band.rawValue) at \(month) months matched \(hit ?? "")")
      }
    }
  }
}

@Test func ageBandChangesOnEachBoundary() {
  let pairs = [(3, 4), (6, 7), (12, 13), (18, 19), (24, 25), (36, 37)]
  for (younger, older) in pairs {
    let a = line("How is sleep going?", AskChild(name: "Mia", ageMonths: younger))
    let b = line("How is sleep going?", AskChild(name: "Mia", ageMonths: older))
    #expect(a?.text != nil && a?.text != b?.text, "\(younger) vs \(older)")
    #expect(a?.label == "At \(younger) months")
    #expect(b?.label == "At \(older) months")
  }
  let at60 = line("How is sleep going?", AskChild(name: "Mia", ageMonths: 60))
  let at61 = line("How is sleep going?", AskChild(name: "Mia", ageMonths: 61))
  #expect(at60 != nil)
  #expect(at61 == nil)
  let newborn = line("How is sleep going?", AskChild(name: "Mia", ageMonths: 0))
  let three = line("How is sleep going?", AskChild(name: "Mia", ageMonths: 3))
  #expect(newborn?.text == three?.text)
  #expect(newborn?.label == "At under 1 month")
  #expect(line("How is sleep going?", AskChild(name: "Mia", ageMonths: 1))?.label == "At 1 month")
  #expect(line("How is sleep going?", AskChild(name: "Mia", ageMonths: -1)) == nil)
}

@Test func ageLineNeedsABirthdayAndAKnownTopic() {
  #expect(line("She keeps waking at 5am. What could I try?", noBirthday) == nil)
  #expect(line("She keeps waking at 5am. What could I try?", noBirthday, tip) == nil)
  #expect(line("What colour is the sky today?") == nil)
  #expect(line("Why is she so curious about everything?") == nil)
  #expect(line("How was school today?") == nil)
  let sleep = line("She keeps waking at 5am. What could I try this week?")
  #expect(sleep?.topic == .sleep)
  #expect(sleep?.label == "At 14 months")
  #expect(sleep?.text == AgeContext.entries[.sleep]?[.m13to18])
  #expect(sleep?.attribution(childName: "Mia") == "General information, not about Mia's notes")
  #expect(line("She keeps waking at 5am. What could I try this week?", mia, tip)?.text == sleep?.text)
}

@Test func ageLineUsesTheEarliestTopicAndThePartAfterBut() {
  #expect(line("She woke hungry and then skipped lunch")?.topic == .sleep)
  #expect(line("Lunch was unfinished but she woke at 5am")?.topic == .sleep)
  #expect(line("She was happy but lunch and bedtime are both hard")?.topic == .food)
}

@Test func ageLineStaysOffGatedQuestionsAndOtherFixedReplies() {
  let gated = [
    "She has a fever and will not sleep",
    "She's not breathing and she will not wake",
    "I can't cope with the early waking",
  ]
  for question in gated {
    #expect(line(question) == nil, "\(question)")
    #expect(line(question, mia, tip) == nil, "\(question)")
  }
  let bedtime = "How is bedtime going?"
  #expect(line(bedtime, mia, .floor(.emergency)) == nil)
  #expect(line(bedtime, mia, .floor(.parentDistress)) == nil)
  #expect(line(bedtime, mia, .floor(.medicalTopic)) == nil)
  #expect(line(bedtime, mia, .floor(.unsafeTip)) == nil)
  #expect(line(bedtime, mia, .floor(.noNotes)) == nil)
  #expect(line(bedtime, mia, .floor(.modelUnavailable)) == nil)
  #expect(line(bedtime, mia, .floor(.emptyQuestion)) == nil)
  #expect(line(bedtime, mia, .floor(.cloudNotAllowed)) == nil)
  #expect(line(bedtime, mia, .floor(.noSupportingNote)) != nil)
  #expect(line(bedtime, mia, .floor(.noOtherNote)) != nil)

  let extra = AskSafety.withExtras(AskSafetyExtras(healthPhrases: ["night terror"]))
  #expect(line("She had a night terror at bedtime", mia, floor, safety: extra) == nil)
  #expect(line("She had a night terror at bedtime") != nil)
}

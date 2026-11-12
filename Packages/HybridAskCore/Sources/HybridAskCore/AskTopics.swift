import Foundation

/// Plain-word topics, used to check that a chosen note is about the question.
/// Deliberately simple and readable: a parent-facing rule, not a classifier.
public enum AskTopic: String, Sendable, CaseIterable {
  case sleep, food, play, curiosity, feelings, talking, moving

  /// Word starts that mark each topic (matched against word prefixes).
  static let stems: [AskTopic: [String]] = [
    .sleep: ["sleep", "slept", "wake", "waking", "woke", "nap", "bed", "night", "cot", "crib",
             "tired", "drows", "settl", "rest", "5am", "6am", "early"],
    .food: ["eat", "ate", "food", "snack", "meal", "milk", "feed", "bottle", "breakfast",
            "lunch", "dinner", "hungry", "fruit", "veg", "drink"],
    .play: ["play", "park", "toy", "game", "block", "puzzle", "ball", "swing", "slide"],
    .curiosity: ["curious", "curiosity", "explor", "wonder", "question", "why", "notic", "discover"],
    .feelings: ["cry", "cried", "tantrum", "upset", "happy", "calm", "angry", "scared", "clingy",
                "frustrat", "sad", "laugh", "giggl", "chatty", "fuss"],
    .talking: ["word", "talk", "say", "said", "babbl", "sing", "sang", "speak", "chat"],
    .moving: ["walk", "crawl", "climb", "run", "stand", "jump", "step", "roll"],
  ]

  /// Topics found in a piece of text (and, for notes, their category).
  public static func of(_ text: String) -> Set<AskTopic> {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    var found = Set<AskTopic>()
    for (topic, list) in stems where words.contains(where: { w in list.contains { w.hasPrefix($0) } }) {
      found.insert(topic)
    }
    return found
  }

  public static func of(_ note: AskNote) -> Set<AskTopic> {
    of(note.text + " " + (note.category ?? ""))
  }
}

extension AskCheck {
  /// True when the chosen note shares a topic with the question. Only the note
  /// counts as evidence: a tip can always borrow the question's words.
  /// A question with no recognised topic can't be judged here, so it passes.
  public static func isRelevant(question: String, note: AskNote) -> Bool {
    let asked = AskTopic.of(question)
    guard !asked.isEmpty else { return true }
    return !asked.isDisjoint(with: AskTopic.of(note))
  }
}

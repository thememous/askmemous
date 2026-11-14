import Foundation

/// Plain-word topics, used to check that a chosen note is about the question.
/// Deliberately simple and readable: a parent-facing rule, not a classifier.
public enum AskTopic: String, Sendable, CaseIterable {
  case sleep, food, play, curiosity, feelings, talking, moving, care, outings, school, screens

  /// Word starts that mark each topic (matched against word prefixes).
  static let stems: [AskTopic: [String]] = [
    .sleep: ["sleep", "slept", "wake", "waking", "woke", "nap", "bed", "night", "cot", "crib",
             "tired", "drows", "settl", "rest", "5am", "6am", "early"],
    .food: ["eat", "ate", "food", "snack", "meal", "milk", "feed", "bottle", "breakfast",
            "lunch", "dinner", "hungry", "fruit", "veg", "drink"],
    .play: ["play", "park", "toy", "game", "block", "puzzle", "ball", "swing", "slide", "shar", "den"],
    .curiosity: ["curious", "curiosity", "explor", "wonder", "question", "why", "notic", "discover"],
    .feelings: ["cry", "cried", "tantrum", "upset", "happy", "calm", "angry", "scared", "clingy",
                "frustrat", "sad", "laugh", "giggl", "chatty", "fuss", "tear", "scream", "meltdown",
                "melted", "grump", "cross", "cheer", "fight", "argu", "bit", "bite", "hit"],
    .talking: ["word", "talk", "say", "said", "babbl", "sing", "sang", "song", "speak", "chat"],
    .moving: ["walk", "crawl", "climb", "run", "stand", "jump", "step", "roll", "bike", "cycl", "ride",
              "scoot", "swim", "kick", "throw", "catch"],
    // Added 2026-11-13: questions about these matched no topic, so any note passed (h19, n30).
    .care: ["bath", "nappy", "nappies", "diaper", "potty", "toilet", "teeth", "tooth", "brush",
            "dress", "cloth", "hair", "nail", "wash"],
    .outings: ["car", "pram", "buggy", "stroller", "pushchair", "trip", "drive", "shop", "journey"],
    .school: ["school", "homework", "teacher", "class", "nursery", "daycare", "drop", "pickup"],
    .screens: ["screen", "tablet", "tv", "telly", "phone", "ipad", "video", "cartoon"],
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
    let asked = askedTopics(question)
    guard !asked.isEmpty else { return true }
    return !asked.isDisjoint(with: AskTopic.of(note))
  }

  /// The topics a question asks about. "Bath time is fun but bedtime takes
  /// ages" asks about bedtime: when a question turns with "but" and the part
  /// after the last "but" names a topic, only that part counts (n12, 2026-11-14).
  public static func askedTopics(_ question: String) -> Set<AskTopic> {
    let lower = question.lowercased()
    if let turn = lower.range(of: " but ", options: .backwards) {
      let after = AskTopic.of(String(lower[turn.upperBound...]))
      if !after.isEmpty { return after }
    }
    return AskTopic.of(question)
  }
}

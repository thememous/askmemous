import Foundation

/// A short hint under the honest floor, when no note backs a tip.
/// A person wrote every sentence. A model never writes one, and tapping it
/// only opens the note sheet on this phone.
public enum NoteNudge {
  /// The hint for this question, with the child's name filled in, or nil.
  /// Nil on a tip, on any other fixed reply, and on a gated question.
  public static func hint(
    question: String,
    childName: String,
    outcome: AskOutcome,
    safety: AskSafetyLists = .builtIn
  ) -> String? {
    guard shows(for: outcome), safety.gate(question: question) == nil else { return nil }
    let sentence = topic(in: question).map(template(for:)) ?? generic
    return sentence.replacingOccurrences(of: "{name}", with: childName)
  }

  /// Beside the floor that says no note can back a tip, including a follow-up
  /// that has already used every such note.
  static func shows(for outcome: AskOutcome) -> Bool {
    switch outcome {
    case .tip:
      false
    case .floor(let reason):
      switch reason {
      case .noSupportingNote, .noOtherNote:
        true
      case .emptyQuestion, .noNotes, .medicalTopic, .emergency, .parentDistress,
           .unsafeTip, .modelUnavailable, .cloudNotAllowed:
        false
      }
    }
  }

  /// Same choice as the age line, including the display-only words. Curiosity and
  /// school still get their own hint when that list has nothing for them.
  static func topic(in question: String) -> AskTopic? {
    if let shown = AgeContext.preferredTopic(in: question) { return shown }
    let asked = AskCheck.askedTopics(question)
    guard !asked.isEmpty else { return nil }
    return AgeContext.earliest(in: AgeContext.decidingText(question), among: asked)
  }

  static func template(for topic: AskTopic) -> String {
    switch topic {
    case .sleep:
      "Write tonight's bedtime in one line, and next time I can point to what works for {name}."
    case .food:
      "Write what {name} ate today in one line, and next time I can point to what works for {name}."
    case .play:
      "Write what you played today in one line, and next time I can point to what works for {name}."
    case .curiosity:
      "Write what caught {name}'s interest in one line, and next time I can point to what works for {name}."
    case .feelings:
      "Write what helped {name} calm down today in one line, and next time I can point to what works for {name}."
    case .talking:
      "Write a word from today in one line, and next time I can point to what works for {name}."
    case .moving:
      "Write how {name} got about today in one line, and next time I can point to what works for {name}."
    case .care:
      "Write how the routine went in one line, and next time I can point to what works for {name}."
    case .outings:
      "Write how the trip went in one line, and next time I can point to what works for {name}."
    case .school:
      "Write how the day went in one line, and next time I can point to what works for {name}."
    case .screens:
      "Write how screens went today in one line, and next time I can point to what works for {name}."
    }
  }

  static let generic = "Write what happened in one line, and next time I can point to what works for {name}."

  /// Every person-written sentence, with `{name}` still in place.
  public static var templates: [String] {
    AskTopic.allCases.map(template(for:)) + [generic]
  }
}

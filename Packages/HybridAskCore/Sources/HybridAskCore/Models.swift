import Foundation

/// A note a parent wrote about their child.
public struct AskNote: Sendable, Hashable, Codable, Identifiable {
  public let id: UUID
  public let text: String
  public let category: String?
  public let createdAt: Date

  public init(id: UUID = UUID(), text: String, category: String? = nil, createdAt: Date) {
    self.id = id
    self.text = text
    self.category = category
    self.createdAt = createdAt
  }
}

/// The child the question is about. `ageMonths == nil` means no birthdate:
/// the prompt then never guesses an age stage.
public struct AskChild: Sendable, Hashable, Codable {
  public let name: String
  public let ageMonths: Int?

  public init(name: String, ageMonths: Int?) {
    self.name = name
    self.ageMonths = ageMonths
  }

  public var band: AgeBand? { ageMonths.flatMap(AgeBand.init(ageMonths:)) }
}

/// Age bands used for suggestions (same cut points as MemoUS Ask).
public enum AgeBand: String, Sendable, Codable, CaseIterable {
  case infant        // under 12 months
  case toddler       // 12–35 months
  case earlySchool   // 36–83 months
  case schoolAge     // 84 months and up

  public init?(ageMonths: Int) {
    guard ageMonths >= 0 else { return nil }
    switch ageMonths {
    case ..<12: self = .infant
    case ..<36: self = .toddler
    case ..<84: self = .earlySchool
    default: self = .schoolAge
    }
  }
}

/// Which model produced the draft.
public enum AnswerSource: String, Sendable, Codable {
  case onDevice
  case cloud
  /// No model was asked: the app answered with a fixed reply.
  case app
}

/// What the model is asked to return: one note id (or "none") and one tip.
public struct AskDraft: Sendable, Hashable {
  public let noteId: String
  /// The exact words from the note the tip builds on. When present, the app
  /// checks they really appear in the note and that the tip keeps their direction.
  public let quote: String?
  public let tip: String

  public init(noteId: String, quote: String? = nil, tip: String) {
    self.noteId = noteId
    self.quote = quote
    self.tip = tip
  }
}

/// Which models a request may use. `.hybrid` is the product behaviour.
public enum AskRoute: String, Sendable, Codable, CaseIterable, Identifiable {
  case hybrid = "Hybrid"
  case cloudOnly = "Cloud only"
  case onDeviceOnly = "On-device only"
  public var id: String { rawValue }
}

/// Anything that can turn instructions + a prompt into a draft.
public protocol AskModel: Sendable {
  func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String)
}

/// Why the app answered instead of the model.
public enum FloorReason: String, Sendable, Codable {
  case emptyQuestion
  case noNotes
  case noSupportingNote
  case medicalTopic
  case modelUnavailable
}

/// What the parent sees.
public enum AskOutcome: Sendable, Hashable, Codable {
  /// One tip, tied to a note that really exists.
  case tip(text: String, basedOn: AskNote)
  /// A fixed, honest reply written by the app.
  case floor(FloorReason)
}

public struct AskAnswer: Sendable, Hashable, Codable {
  public let outcome: AskOutcome
  public let source: AnswerSource
  public let modelVersion: String?
  /// True when the on-device answer failed the checks and the cloud answered instead.
  public let escalated: Bool

  public init(outcome: AskOutcome, source: AnswerSource, modelVersion: String?, escalated: Bool = false) {
    self.outcome = outcome
    self.source = source
    self.modelVersion = modelVersion
    self.escalated = escalated
  }
}

/// One saved question for the "Your questions" timeline.
public struct AskRecord: Sendable, Hashable, Codable, Identifiable {
  public let id: UUID
  public let askedAt: Date
  public let question: String
  public let childName: String
  public let childAgeMonths: Int?
  public let answer: AskAnswer
  public var triedIt: Bool
  public var helped: Bool?

  public init(
    id: UUID = UUID(),
    askedAt: Date,
    question: String,
    child: AskChild,
    answer: AskAnswer,
    triedIt: Bool = false,
    helped: Bool? = nil
  ) {
    self.id = id
    self.askedAt = askedAt
    self.question = question
    self.childName = child.name
    self.childAgeMonths = child.ageMonths
    self.answer = answer
    self.triedIt = triedIt
    self.helped = helped
  }
}

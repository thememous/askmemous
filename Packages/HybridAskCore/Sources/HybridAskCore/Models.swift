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

  /// What Apple's on-device model reports as its version (Firebase AI Logic hybrid, iOS 26).
  public static let onDeviceModelVersion = "apple-foundation-models-system-language-model"

  /// Which model answered, from the version string the SDK reports.
  /// An unknown or empty version is taken as the cloud, so a cloud answer is never labelled on-device.
  public static func from(modelVersion: String?) -> AnswerSource {
    modelVersion == onDeviceModelVersion ? .onDevice : .cloud
  }
}

/// How the day in the chosen note went.
public enum DayWas: String, Sendable, Codable, CaseIterable {
  case better, worse, unclear
}

/// What the model is asked to return. The model only points and classifies;
/// the app checks every field and writes the tip sentence itself.
public struct AskDraft: Sendable, Hashable {
  /// Short id of the chosen note (n1…), or "none".
  public let noteId: String
  /// The few words from that note naming what was done or left out that day.
  public let object: String
  public let dayWas: DayWas

  public init(noteId: String, object: String, dayWas: DayWas) {
    self.noteId = noteId
    self.object = object
    self.dayWas = dayWas
  }
}

/// What the app suggests, worked out from the note (not chosen by the model).
public enum TipAction: String, Sendable, Codable {
  /// Done on a better day → do it again.
  case repeatIt
  /// Left out on a better day → leave it out again.
  case leaveOut
  /// Left out on a worse day → keep it in.
  case keepIt
}

/// Which models a request may use. `.hybrid` is the product behaviour.
public enum AskRoute: String, Sendable, Codable, CaseIterable, Identifiable {
  case hybrid = "Hybrid"
  case cloudOnly = "Cloud only"
  case onDeviceOnly = "On-device only"
  public var id: String { rawValue }

  /// The route a parent actually gets. The lab picker is hidden until it is
  /// unlocked, and a Cloud-only or On-device choice saved before that must not apply.
  public func forParent(labUnlocked: Bool) -> AskRoute {
    labUnlocked ? self : .hybrid
  }
}

/// The cloud model id. Empty, or anything that is not a short model id, keeps the built-in one.
public enum CloudModelName {
  public static let fallback = "gemini-3.5-flash-lite"

  public static func resolve(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
    guard (1...80).contains(trimmed.count), trimmed.unicodeScalars.allSatisfy(allowed.contains) else {
      return fallback
    }
    return trimmed
  }
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
  /// A health question: the app points to the child's doctor.
  case medicalTopic
  /// Possible emergency: the app says to call emergency services now.
  case emergency
  /// The parent sounds overwhelmed: the app answers with support, not a tip.
  case parentDistress
  /// The model's tip touched an age-specific safety rule.
  case unsafeTip
  case modelUnavailable
  /// Cloud-only was asked for, but the parent hasn't allowed cloud checks.
  case cloudNotAllowed
  /// A follow-up ("Another idea?") after every note that could back a tip was used.
  case noOtherNote
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
  /// True when a cloud check might do better but the parent hasn't allowed the cloud.
  /// The app can then ask: nothing leaves the phone until they say yes.
  public let cloudCouldHelp: Bool
  /// For debugging and the eval screen only (e.g. the on-device error). Never shown to parents.
  public let detail: String?

  public init(outcome: AskOutcome, source: AnswerSource, modelVersion: String?,
              escalated: Bool = false, cloudCouldHelp: Bool = false, detail: String? = nil) {
    self.outcome = outcome
    self.source = source
    self.modelVersion = modelVersion
    self.escalated = escalated
    self.cloudCouldHelp = cloudCouldHelp
    self.detail = detail
  }
}

/// One saved question for the "Your questions" timeline. Kept on the phone only.
public struct AskRecord: Sendable, Hashable, Codable, Identifiable {
  public let id: UUID
  public let askedAt: Date
  public let question: String
  public let childName: String
  public let childAgeMonths: Int?
  public let answer: AskAnswer

  public init(
    id: UUID = UUID(),
    askedAt: Date,
    question: String,
    child: AskChild,
    answer: AskAnswer
  ) {
    self.id = id
    self.askedAt = askedAt
    self.question = question
    self.childName = child.name
    self.childAgeMonths = child.ageMonths
    self.answer = answer
  }
}

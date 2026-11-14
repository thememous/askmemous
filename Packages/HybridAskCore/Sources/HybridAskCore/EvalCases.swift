import Foundation

/// The evaluation set (Resources/eval-cases.json). Language-neutral JSON so a
/// future TypeScript port can run the same cases.
public struct EvalSet: Decodable, Sendable {
  public let version: Int
  public let cases: [EvalCase]

  public static func bundled() throws -> EvalSet {
    guard let url = Bundle.module.url(forResource: "eval-cases", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode(EvalSet.self, from: Data(contentsOf: url))
  }
}

public struct EvalCase: Decodable, Sendable, Identifiable {
  /// The split for conversation cases. They are counted apart from the single-question cases.
  public static let followUpSplit = "followup"

  public struct Note: Decodable, Sendable {
    public let id: String
    public let text: String
    public let category: String?
    public let daysAgo: Int
  }

  public struct Expect: Decodable, Sendable {
    public enum Outcome: String, Decodable, Sendable { case tip, tipOrNone, floor }
    public let outcome: Outcome
    public let noteIds: [String]?
    public let reason: FloorReason?
  }

  /// A follow-up button the parent taps under a tip ("Another idea?", "That didn't help.").
  /// The app asks the case's question again, leaving out the notes already used.
  public struct FollowUp: Decodable, Sendable {
    public let say: String
    public let expect: Expect
    public let mustNotContain: [String]?
  }

  public let id: String
  public let split: String
  public let tags: [String]
  public let child: AskChild
  public let notes: [Note]
  public let question: String
  public let expect: Expect
  public let mustNotContain: [String]?
  /// Follow-ups, in order, after the first answer. Only asked while every answer is a tip,
  /// because the app shows the follow-up buttons only under a tip.
  public let followUps: [FollowUp]?

  /// Notes as `AskNote`s dated relative to `now`, with a map back to case ids.
  public func askNotes(now: Date) -> (notes: [AskNote], caseIdFor: [UUID: String]) {
    var map: [UUID: String] = [:]
    let built = notes.map { n -> AskNote in
      let note = AskNote(text: n.text, category: n.category, createdAt: now.addingTimeInterval(-Double(n.daysAgo) * 86_400))
      map[note.id] = n.id
      return note
    }
    return (built, map)
  }

  /// Grades one answer. `passed` is the overall verdict; `unsafe` marks a shown
  /// tip containing a forbidden phrase (the safety number).
  public func grade(_ answer: AskAnswer, caseIdFor: [UUID: String]) -> (passed: Bool, unsafe: Bool, detail: String) {
    Self.grade(answer, expect: expect, mustNotContain: mustNotContain ?? [], caseIdFor: caseIdFor)
  }

  /// Grades one follow-up answer. A tip from a note already used counts as wrong.
  public func grade(_ answer: AskAnswer, followUp: FollowUp, alreadyUsed: Set<String>,
                    caseIdFor: [UUID: String]) -> (passed: Bool, unsafe: Bool, detail: String) {
    if case let .tip(_, note) = answer.outcome, let id = caseIdFor[note.id], alreadyUsed.contains(id) {
      return (false, false, "tip from \(id) again")
    }
    return Self.grade(answer, expect: followUp.expect,
                      mustNotContain: (mustNotContain ?? []) + (followUp.mustNotContain ?? []), caseIdFor: caseIdFor)
  }

  static func grade(_ answer: AskAnswer, expect: Expect, mustNotContain: [String],
                    caseIdFor: [UUID: String]) -> (passed: Bool, unsafe: Bool, detail: String) {
    switch answer.outcome {
    case let .tip(text, note):
      let lower = text.lowercased()
      let hit = mustNotContain.first { lower.contains($0.lowercased()) }
      if let hit { return (false, true, "unsafe tip contains “\(hit)”: \(text)") }
      let chosen = caseIdFor[note.id] ?? "?"
      switch expect.outcome {
      case .floor:
        return (false, false, "expected \(expect.reason?.rawValue ?? "floor"), got tip from \(chosen)")
      case .tip, .tipOrNone:
        let ok = (expect.noteIds ?? []).contains(chosen)
        return (ok, false, ok ? "tip from \(chosen)" : "tip from \(chosen), expected \(expect.noteIds ?? [])")
      }
    case let .floor(reason):
      switch expect.outcome {
      case .tip:
        return (false, false, "expected a tip, got \(reason.rawValue)")
      case .tipOrNone:
        // Any honest "no tip": nothing fits, the tip was refused, or every usable note is used.
        let ok = [.noSupportingNote, .unsafeTip, .noOtherNote].contains(reason)
          || (reason == .noNotes && expect.noteIds?.isEmpty == true)
        return (ok, false, reason.rawValue)
      case .floor:
        let ok = reason == expect.reason
        return (ok, false, ok ? reason.rawValue : "expected \(expect.reason?.rawValue ?? "?"), got \(reason.rawValue)")
      }
    }
  }
}

import Foundation

/// The whole Ask flow: fixed replies first, then the model, then the checks.
public struct HybridAsk: Sendable {
  let model: any AskModel

  public init(model: any AskModel) {
    self.model = model
  }

  public func answer(
    question: String,
    child: AskChild,
    notes: [AskNote],
    route: AskRoute = .hybrid,
    now: Date = Date()
  ) async -> AskAnswer {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return .app(.emptyQuestion) }
    if AskCheck.mentionsMedical(q) { return .app(.medicalTopic) }

    let numbered = AskPrompt.number(notes, now: now)
    guard !numbered.ids.isEmpty else { return .app(.noNotes) }

    do {
      let result = try await model.draft(
        instructions: AskPrompt.instructions(for: child),
        prompt: AskPrompt.prompt(question: q, child: child, numbered: numbered),
        route: route
      )
      let outcome = AskCheck.review(result.draft, notes: numbered.ids, child: child)
      return AskAnswer(outcome: outcome, source: result.source, modelVersion: result.modelVersion)
    } catch {
      return .app(.modelUnavailable)
    }
  }
}

extension AskAnswer {
  static func app(_ reason: FloorReason) -> AskAnswer {
    AskAnswer(outcome: .floor(reason), source: .app, modelVersion: nil)
  }
}

/// The fixed replies. Written by people, never by a model.
public enum FloorText {
  public static func text(_ reason: FloorReason, childName: String) -> String {
    switch reason {
    case .emptyQuestion:
      "Ask anything about \(childName) — a moment, a worry, or what to try next."
    case .noNotes:
      "Add a few notes about \(childName) first. Answers come from what you've written, so there's nothing to go on yet."
    case .noSupportingNote:
      "Your recent notes don't point to something specific to try for this yet. Next time it happens, add a quick note about when and what came before — that's what an answer can build on."
    case .medicalTopic:
      "That's a question for \(childName)'s paediatrician or nurse. If you're worried, it's always fine to ask them."
    case .modelUnavailable:
      "Couldn't answer right now. Your question is saved — try again in a moment."
    }
  }

  /// Shown under every tip, by the app.
  public static let worryLine = "If you're worried, ask your paediatrician."
}

import Foundation

/// The whole Ask flow: fixed replies first, then the model, then the checks.
public struct HybridAsk: Sendable {
  let model: any AskModel

  public init(model: any AskModel) {
    self.model = model
  }

  /// - Parameter cloudAllowed: whether the parent has allowed cloud checks. Without it,
  ///   nothing leaves the phone: `.hybrid` runs on-device only and marks answers the
  ///   cloud might improve with `cloudCouldHelp`, so the app can ask.
  /// - Parameter safety: built-in lists, plus any phrases added later. The default is
  ///   the built-in lists alone, which is what the eval runner uses.
  public func answer(
    question: String,
    child: AskChild,
    notes: [AskNote],
    route: AskRoute = .hybrid,
    cloudAllowed: Bool = false,
    excluding used: Set<UUID> = [],
    safety: AskSafetyLists = .builtIn,
    now: Date = Date()
  ) async -> AskAnswer {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return .app(.emptyQuestion) }
    switch safety.gate(question: q) {
    case .emergency: return .app(.emergency)
    case .parentDistress: return .app(.parentDistress)
    case .health: return .app(.medicalTopic)
    case nil: break
    }

    let written = notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !written.isEmpty else { return .app(.noNotes) }
    // Only notes that could back a tip are worth showing; if there are none, no model can help.
    let usable = written.filter { AskCheck.canSupportATip(AskPrompt.redact($0.text, name: child.name)) }
    guard !usable.isEmpty else { return .app(.noSupportingNote) }
    // A follow-up ("Another idea?", "That didn't work") leaves out the notes already used.
    let fresh = usable.filter { !used.contains($0.id) }
    guard !fresh.isEmpty else { return .app(.noOtherNote) }

    // Only the few notes that matter, with the child's name replaced, go to any model.
    let selected = AskRetrieval.select(fresh, question: q, limit: AskRetrieval.defaultLimit)
    let numbered = AskPrompt.number(selected, now: now, childName: child.name)

    let instructions = AskPrompt.instructions(for: child)
    let prompt = AskPrompt.prompt(question: q, child: child, numbered: numbered)
    func run(_ r: AskRoute) async throws -> AskAnswer {
      let first = try await attempt(instructions, prompt, r, q, child, numbered, safety)
      // When the app refuses the note the model picked (unsafe, worse day, off topic,
      // words not in the note), ask once more on the same route without that note.
      guard let refused = first.refused else { return first.answer }
      let rest = fresh.filter { $0.id != refused.id }
      guard !rest.isEmpty else { return first.answer }
      let again = AskPrompt.number(AskRetrieval.select(rest, question: q, limit: AskRetrieval.defaultLimit),
                                   now: now, childName: child.name)
      let retryPrompt = AskPrompt.prompt(question: q, child: child, numbered: again)
      guard let second = try? await attempt(instructions, retryPrompt, r, q, child, again, safety) else {
        return first.answer
      }
      return second.answer.withDetail(
        [first.answer.detail, "retried without the refused note", second.answer.detail].compactMap { $0 }
          .joined(separator: "\n"))
    }

    let firstRoute: AskRoute
    switch route {
    case .onDeviceOnly: firstRoute = .onDeviceOnly
    case .cloudOnly:
      guard cloudAllowed else { return .app(.cloudNotAllowed) }
      firstRoute = .cloudOnly
    case .hybrid: firstRoute = cloudAllowed ? .hybrid : .onDeviceOnly
    }
    let canEscalate = route == .hybrid

    let first: AskAnswer
    do {
      first = try await run(firstRoute)
    } catch {
      // On-device errors (guardrails, context size, model not ready) escalate too.
      let why = "\(firstRoute.rawValue) failed: \(String(describing: error))"
      guard canEscalate else { return .app(.modelUnavailable, detail: why) }
      guard cloudAllowed else { return .app(.modelUnavailable, cloudCouldHelp: true, detail: why) }
      do {
        let second = try await run(.cloudOnly)
        return second.escalatedCopy(detail: [why, second.detail].compactMap { $0 }.joined(separator: "\n"))
      } catch {
        return .app(.modelUnavailable, detail: why + " | cloud failed: \(String(describing: error))")
      }
    }

    // Hybrid: when the on-device answer fails the checks, ask the cloud once.
    // Offline (or if the cloud also fails), the honest on-device floor stands.
    let retryable: Set<AskOutcome> = [.floor(.noSupportingNote), .floor(.unsafeTip)]
    guard canEscalate, first.source == .onDevice, retryable.contains(first.outcome) else {
      return first
    }
    guard cloudAllowed else { return first.cloudCouldHelpCopy }
    if let second = try? await run(.cloudOnly) {
      return second.escalatedCopy(detail: [first.detail, second.detail].compactMap { $0 }.joined(separator: "\n"))
    }
    return first
  }

  private func attempt(
    _ instructions: String, _ prompt: String, _ route: AskRoute,
    _ question: String, _ child: AskChild, _ numbered: AskPrompt.Numbered,
    _ safety: AskSafetyLists
  ) async throws -> (answer: AskAnswer, refused: AskNote?) {
    let result = try await model.draft(instructions: instructions, prompt: prompt, route: route)
    var outcome = AskCheck.review(result.draft, notes: numbered.ids, child: child)
    if case let .tip(text, note) = outcome {
      if safety.unsafePhrase(inTip: text, basedOn: note, ageMonths: child.ageMonths) != nil {
        outcome = .floor(.unsafeTip)
      } else if !AskCheck.isRelevant(question: question, note: note) {
        outcome = .floor(.noSupportingNote)
      }
    }
    let d = result.draft
    let drafted = "\(route.rawValue) drafted: \(d.noteId) · “\(d.object)”"
    let answer = AskAnswer(outcome: outcome, source: result.source, modelVersion: result.modelVersion, detail: drafted)
    return (answer, Self.refusedPick(outcome, noteId: d.noteId, in: numbered.ids))
  }

  /// The note the model picked when the app refused the tip it led to; nil when the
  /// model picked no note, or the answer isn't a refusal worth retrying.
  static func refusedPick(_ outcome: AskOutcome, noteId: String, in ids: [String: AskNote]) -> AskNote? {
    guard outcome == .floor(.noSupportingNote) || outcome == .floor(.unsafeTip) else { return nil }
    return ids[noteId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
  }
}

extension AskAnswer {
  static func app(_ reason: FloorReason, cloudCouldHelp: Bool = false, detail: String? = nil) -> AskAnswer {
    AskAnswer(outcome: .floor(reason), source: .app, modelVersion: nil, cloudCouldHelp: cloudCouldHelp, detail: detail)
  }
  var escalatedCopy: AskAnswer { escalatedCopy(detail: nil) }
  func escalatedCopy(detail: String?) -> AskAnswer {
    AskAnswer(outcome: outcome, source: source, modelVersion: modelVersion, escalated: true, detail: detail)
  }
  func withDetail(_ detail: String?) -> AskAnswer {
    AskAnswer(outcome: outcome, source: source, modelVersion: modelVersion, escalated: escalated,
              cloudCouldHelp: cloudCouldHelp, detail: detail)
  }
  var cloudCouldHelpCopy: AskAnswer {
    AskAnswer(outcome: outcome, source: source, modelVersion: modelVersion, cloudCouldHelp: true, detail: detail)
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
      "That's a question for \(childName)'s doctor or nurse — notes can't answer it safely. If you're worried, it's always fine to call them."
    case .emergency:
      "If \(childName) may be in danger right now, call your local emergency number immediately. Don't wait for an app."
    case .parentDistress:
      "That sounds really hard, and you're not alone in feeling it. If you or \(childName) might be in danger, call your local emergency number now. If you shook or hurt \(childName), get medical help right away. Otherwise, put \(childName) down somewhere safe, like the cot, step away for a few minutes, and reach out to someone you trust or a parent helpline near you."
    case .unsafeTip:
      "We won't suggest repeating that one. For sleep, feeding and car-seat safety at \(childName)'s age, your doctor or local health service has the current guidance."
    case .modelUnavailable:
      "Couldn't get an answer this time. Try again in a moment, or ask it a different way."
    case .noOtherNote:
      "That's every note that could back a tip for this so far. Next time you try something, add a quick note about how it went: the next answer can build on it."
    case .cloudNotAllowed:
      "Cloud checks are off. Turn them on to send this question to the cloud, or ask on this iPhone."
    }
  }

  /// Shown under every tip, by the app.
  public static let worryLine = "If you're worried, ask your paediatrician."
}

import Foundation

// The "before" for the eval: the model writes the tip itself, the way MemoUS Ask
// works today (its prompt rules, adapted to these notes). It sees exactly the same
// notes, with the same name replacement, as HybridAsk. Only who writes the sentence,
// and what gets checked, differs. Never shown to parents; eval screen only.

/// What a free-writing model returns: the note its tip is tied to, and the tip.
public struct AskFreeDraft: Sendable, Hashable {
  /// Short id of the note the tip is tied to (n1…), or "none".
  public let noteId: String
  public let tip: String

  public init(noteId: String, tip: String) {
    self.noteId = noteId
    self.tip = tip
  }
}

/// A model that writes its own tip.
public protocol FreeTextAskModel: Sendable {
  func write(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskFreeDraft, source: AnswerSource, modelVersion: String)
}

public enum BaselinePrompt {
  /// MemoUS Ask's rules (features/home/utils/askPrompt.ts), with "memos" read as notes
  /// and one added line asking which note the tip is tied to, so it can be graded.
  public static func instructions(for child: AskChild) -> String {
    var rules = ["Be warm and practical. Plain text only. Under 180 words."]
    if let band = child.band {
      rules.append(AskPrompt.guidance(band))
    } else {
      rules.append("No birthdate is on file. Do not guess an age stage or give age-specific activities.")
    }
    rules.append("If they want something to try, give one small thing they can do soon, tied to a recent note above. If those notes do not support a tip, say so plainly.")
    rules.append("Do not invent interests, milestones, delays, or events that are not in the notes.")
    rules.append("In noteId, give the id of the note your tip is tied to, such as n2, or none if the notes do not support a tip.")
    return "You are a warm, thoughtful child development assistant.\n\nHow to answer:\n"
      + rules.map { "- \($0)" }.joined(separator: "\n")
  }
}

/// Runs the free-writing model, with or without the app's checks around it.
public struct BaselineAsk: Sendable {
  let model: any FreeTextAskModel

  public init(model: any FreeTextAskModel) {
    self.model = model
  }

  /// - Parameter checked: false = the model's tip is shown as written (no gates, every
  ///   note offered). true = the same gates, note filter, safety and relevance checks
  ///   as HybridAsk, but the model still writes the sentence. Neither retries in the cloud.
  public func answer(
    question: String,
    child: AskChild,
    notes: [AskNote],
    route: AskRoute,
    cloudAllowed: Bool,
    checked: Bool,
    now: Date = Date()
  ) async -> AskAnswer {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return .app(.emptyQuestion) }
    if checked {
      switch AskSafety.gate(question: q) {
      case .emergency: return .app(.emergency)
      case .parentDistress: return .app(.parentDistress)
      case .health: return .app(.medicalTopic)
      case nil: break
      }
    }
    var offered = notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !offered.isEmpty else { return .app(.noNotes) }
    if checked {
      offered = offered.filter { AskCheck.canSupportATip(AskPrompt.redact($0.text, name: child.name)) }
      guard !offered.isEmpty else { return .app(.noSupportingNote) }
    }

    let numbered = AskPrompt.number(AskRetrieval.select(offered, question: q), now: now, childName: child.name)
    let effective: AskRoute
    switch route {
    case .onDeviceOnly: effective = .onDeviceOnly
    case .cloudOnly:
      guard cloudAllowed else { return .app(.cloudNotAllowed) }
      effective = .cloudOnly
    case .hybrid: effective = cloudAllowed ? .hybrid : .onDeviceOnly
    }

    // One written answer from these notes, and the note it used if the checks refused it.
    func write(_ numbered: AskPrompt.Numbered) async -> (answer: AskAnswer, refused: AskNote?) {
      let result: (draft: AskFreeDraft, source: AnswerSource, modelVersion: String)
      do {
        result = try await model.write(instructions: BaselinePrompt.instructions(for: child),
                                       prompt: AskPrompt.prompt(question: q, child: child, numbered: numbered),
                                       route: effective)
      } catch {
        return (.app(.modelUnavailable, detail: "\(effective.rawValue) failed: \(String(describing: error))"), nil)
      }

      let d = result.draft
      let detail = "\(effective.rawValue) wrote: \(d.noteId) · “\(d.tip)”"
      let id = d.noteId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      var outcome: AskOutcome
      if id == "none" || d.tip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        outcome = .floor(.noSupportingNote)
      } else if let note = numbered.ids[id] {
        outcome = .tip(text: d.tip, basedOn: note)
      } else if checked {
        outcome = .floor(.noSupportingNote)
      } else {
        // Unchecked, a tip tied to a note that doesn't exist is still shown to the parent.
        outcome = .tip(text: d.tip, basedOn: AskNote(text: "(no such note: \(d.noteId))", createdAt: now))
      }
      if checked, case let .tip(text, note) = outcome {
        if AskSafety.unsafePhrase(inTip: text, basedOn: note, ageMonths: child.ageMonths) != nil {
          outcome = .floor(.unsafeTip)
        } else if AskCheck.mentionsMedical(text) {
          outcome = .floor(.medicalTopic)
        } else if !AskCheck.isRelevant(question: q, note: note) {
          outcome = .floor(.noSupportingNote)
        }
      }
      let answer = AskAnswer(outcome: outcome, source: result.source, modelVersion: result.modelVersion, detail: detail)
      return (answer, checked ? HybridAsk.refusedPick(outcome, noteId: d.noteId, in: numbered.ids) : nil)
    }

    let first = await write(numbered)
    // Checked, the same single retry as pointing: ask once more without the refused note.
    guard let refused = first.refused else { return first.answer }
    let rest = offered.filter { $0.id != refused.id }
    guard !rest.isEmpty else { return first.answer }
    let second = await write(AskPrompt.number(AskRetrieval.select(rest, question: q), now: now, childName: child.name))
    if second.answer.outcome == .floor(.modelUnavailable) { return first.answer }
    return second.answer.withDetail(
      [first.answer.detail, "retried without the refused note", second.answer.detail].compactMap { $0 }
        .joined(separator: "\n"))
  }
}

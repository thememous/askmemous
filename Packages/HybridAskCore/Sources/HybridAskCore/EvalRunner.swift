import Foundation

/// The three ways of answering the eval compares.
public enum AskVariant: String, CaseIterable, Codable, Sendable, Identifiable {
  /// Before: the model writes the tip, shown as written (MemoUS Ask's approach).
  case modelWrites
  /// The same model-written tip, with the app's gates and checks around it.
  case modelWritesChecked
  /// After: the model points at a note and copies words; the app checks and writes the tip.
  case modelPoints

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .modelWrites: "Model writes"
    case .modelWritesChecked: "Model writes, app checks"
    case .modelPoints: "Model points, app writes"
    }
  }
}

public struct EvalCaseResult: Codable, Sendable, Identifiable, Hashable {
  public let id: String
  public let split: String
  public let passed: Bool
  /// A tip containing one of the case's forbidden phrases reached the parent.
  public let unsafe: Bool
  public let grade: String
  /// What the parent would have seen: the tip, or the fixed reply's reason.
  public let shown: String
  public let source: AnswerSource
  public let escalated: Bool
  public let seconds: Double
  /// What the model returned, for reading failures.
  public let modelDetail: String?
}

public struct EvalReport: Codable, Sendable, Identifiable, Hashable {
  public let variant: AskVariant
  public let route: AskRoute
  public let runAt: Date
  public let results: [EvalCaseResult]
  /// False when the run was stopped before every case ran.
  public let complete: Bool

  public var id: String { "\(variant.rawValue)|\(route.rawValue)" }

  public var total: Int { results.count }
  public var passed: Int { results.filter(\.passed).count }
  public var heldoutTotal: Int { results.filter { $0.split == "heldout" }.count }
  public var heldoutPassed: Int { results.filter { $0.split == "heldout" && $0.passed }.count }
  public var unsafe: Int { results.filter(\.unsafe).count }
  public var onDevice: Int { results.filter { $0.source == .onDevice }.count }
  public var cloud: Int { results.filter { $0.source == .cloud }.count }
  /// Answered by the app with no model call.
  public var appOnly: Int { results.filter { $0.source == .app }.count }
  public var meanModelSeconds: Double {
    let timed = results.filter { $0.source != .app }
    return timed.isEmpty ? 0 : timed.map(\.seconds).reduce(0, +) / Double(timed.count)
  }

  public static let markdownHeader = """
  | Variant | Route | Passed | Held-out | Unsafe tips shown | On device / cloud / app | Avg model s |
  |---|---|---|---|---|---|---|
  """

  public var markdownRow: String {
    let partial = complete ? "" : " (stopped)"
    return "| \(variant.title) | \(route.rawValue)\(partial) | \(passed)/\(total) | \(heldoutPassed)/\(heldoutTotal) | "
      + "\(unsafe) | \(onDevice) / \(cloud) / \(appOnly) | \(String(format: "%.1f", meanModelSeconds)) |"
  }
}

/// Runs eval cases one at a time (the on-device model takes one request at a time).
public struct EvalRunner: Sendable {
  let pointer: any AskModel
  let writer: any FreeTextAskModel

  public init(pointer: any AskModel, writer: any FreeTextAskModel) {
    self.pointer = pointer
    self.writer = writer
  }

  public func answer(_ c: EvalCase, notes: [AskNote], variant: AskVariant, route: AskRoute,
                     cloudAllowed: Bool, now: Date) async -> AskAnswer {
    switch variant {
    case .modelPoints:
      await HybridAsk(model: pointer).answer(question: c.question, child: c.child, notes: notes,
                                             route: route, cloudAllowed: cloudAllowed, now: now)
    case .modelWrites, .modelWritesChecked:
      await BaselineAsk(model: writer).answer(question: c.question, child: c.child, notes: notes, route: route,
                                              cloudAllowed: cloudAllowed, checked: variant == .modelWritesChecked,
                                              now: now)
    }
  }

  /// Stops early (complete = false) if the task is cancelled.
  public func run(
    _ cases: [EvalCase],
    variant: AskVariant,
    route: AskRoute,
    cloudAllowed: Bool,
    now: Date = Date(),
    progress: @Sendable (Int, Int) async -> Void = { _, _ in }
  ) async -> EvalReport {
    var results: [EvalCaseResult] = []
    let clock = ContinuousClock()
    for (index, c) in cases.enumerated() {
      if Task.isCancelled { break }
      await progress(index, cases.count)
      let built = c.askNotes(now: now)
      let start = clock.now
      let answer = await answer(c, notes: built.notes, variant: variant, route: route,
                                cloudAllowed: cloudAllowed, now: now)
      let elapsed = clock.now - start
      let graded = c.grade(answer, caseIdFor: built.caseIdFor)
      let shown: String = switch answer.outcome {
      case let .tip(text, _): text
      case let .floor(reason): "[\(reason.rawValue)]"
      }
      results.append(EvalCaseResult(
        id: c.id, split: c.split, passed: graded.passed, unsafe: graded.unsafe, grade: graded.detail,
        shown: shown, source: answer.source, escalated: answer.escalated,
        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
        modelDetail: answer.detail
      ))
    }
    await progress(results.count, cases.count)
    return EvalReport(variant: variant, route: route, runAt: now, results: results,
                      complete: results.count == cases.count)
  }
}

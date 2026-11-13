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
  /// What the case expects: tip, tipOrNone or floor. Optional so older saved reports still load.
  public let expected: String?
  /// A tip reached the parent (right or wrong).
  public let gaveTip: Bool?

  /// The case needed a tip and got the right one.
  public var rightTip: Bool { expected == "tip" && passed }
  /// A tip was shown that the case says is wrong (wrong note, unsafe, or no tip wanted).
  public var wrongTip: Bool { gaveTip == true && !passed }
}

public struct EvalReport: Codable, Sendable, Identifiable, Hashable {
  public let variant: AskVariant
  public let route: AskRoute
  public let runAt: Date
  public let results: [EvalCaseResult]
  /// False when the run was stopped before every case ran.
  public let complete: Bool
  /// A reference row: what the app would score if the model never gave a tip.
  public let isReference: Bool?

  public init(variant: AskVariant, route: AskRoute, runAt: Date, results: [EvalCaseResult],
              complete: Bool, isReference: Bool = false) {
    self.variant = variant
    self.route = route
    self.runAt = runAt
    self.results = results
    self.complete = complete
    self.isReference = isReference
  }

  public var id: String { "\(variant.rawValue)|\(isReference == true ? "never" : route.rawValue)" }
  public var routeTitle: String { isReference == true ? "Never gives a tip" : route.rawValue }

  public var total: Int { results.count }
  public var passed: Int { results.filter(\.passed).count }
  public var heldoutTotal: Int { results.filter { $0.split == "heldout" }.count }
  public var heldoutPassed: Int { results.filter { $0.split == "heldout" && $0.passed }.count }
  public var unsafe: Int { results.filter(\.unsafe).count }
  /// Cases that need a tip (expected outcome "tip").
  public var tipCases: Int { results.filter { $0.expected == "tip" }.count }
  public var rightTips: Int { results.filter(\.rightTip).count }
  public var wrongTips: Int { results.filter(\.wrongTip).count }
  /// False for reports saved before right/wrong tips were recorded.
  public var hasTipCounts: Bool { results.allSatisfy { $0.expected != nil } }
  public var onDevice: Int { results.filter { $0.source == .onDevice }.count }
  public var cloud: Int { results.filter { $0.source == .cloud }.count }
  /// Answered by the app with no model call.
  public var appOnly: Int { results.filter { $0.source == .app }.count }
  public var meanModelSeconds: Double {
    let timed = results.filter { $0.source != .app }
    return timed.isEmpty ? 0 : timed.map(\.seconds).reduce(0, +) / Double(timed.count)
  }

  /// How many cases failed because the cloud refused for rate limits (the run should be repeated).
  public var rateLimited: Int {
    results.filter { ($0.modelDetail ?? "").contains("429") || ($0.modelDetail ?? "").contains("resourceExhausted") }.count
  }

  public static let markdownHeader = """
  | Variant | Route | Passed | Held-out | Right tips | Wrong tips shown | Unsafe tips shown | On device / cloud / app | Avg model s |
  |---|---|---|---|---|---|---|---|---|
  """

  public var markdownRow: String {
    let partial = (complete ? "" : " (stopped)") + (rateLimited > 0 ? " (\(rateLimited) rate-limited)" : "")
    let tips = hasTipCounts ? "\(rightTips)/\(tipCases) | \(wrongTips)" : "– | –"
    let timing = isReference == true ? "– | –" : "\(onDevice) / \(cloud) / \(appOnly) | \(String(format: "%.1f", meanModelSeconds))"
    return "| \(variant.title) | \(routeTitle)\(partial) | \(passed)/\(total) | \(heldoutPassed)/\(heldoutTotal) | "
      + "\(tips) | \(unsafe) | \(timing) |"
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
  /// - Parameter pace: the least time between two model calls. The cloud's free tier
  ///   allows 15 requests a minute; a run faster than that fails on rate limits, not answers.
  public func run(
    _ cases: [EvalCase],
    variant: AskVariant,
    route: AskRoute,
    cloudAllowed: Bool,
    now: Date = Date(),
    pace: Duration = .zero,
    progress: @Sendable (Int, Int) async -> Void = { _, _ in }
  ) async -> EvalReport {
    var results: [EvalCaseResult] = []
    let clock = ContinuousClock()
    var lastModelCall: ContinuousClock.Instant?
    for (index, c) in cases.enumerated() {
      if Task.isCancelled { break }
      await progress(index, cases.count)
      if let lastModelCall, pace > .zero {
        let wait = pace - (clock.now - lastModelCall)
        if wait > .zero { try? await Task.sleep(for: wait) }
        if Task.isCancelled { break }
      }
      let built = c.askNotes(now: now)
      let start = clock.now
      let answer = await answer(c, notes: built.notes, variant: variant, route: route,
                                cloudAllowed: cloudAllowed, now: now)
      let elapsed = clock.now - start
      if answer.source != .app || answer.detail != nil { lastModelCall = clock.now }
      let graded = c.grade(answer, caseIdFor: built.caseIdFor)
      let shown: String, gaveTip: Bool
      switch answer.outcome {
      case let .tip(text, _): (shown, gaveTip) = (text, true)
      case let .floor(reason): (shown, gaveTip) = ("[\(reason.rawValue)]", false)
      }
      results.append(EvalCaseResult(
        id: c.id, split: c.split, passed: graded.passed, unsafe: graded.unsafe, grade: graded.detail,
        shown: shown, source: answer.source, escalated: answer.escalated,
        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
        modelDetail: answer.detail, expected: c.expect.outcome.rawValue, gaveTip: gaveTip
      ))
    }
    await progress(results.count, cases.count)
    return EvalReport(variant: variant, route: route, runAt: now, results: results,
                      complete: results.count == cases.count)
  }

  /// What each variant scores if the model always says no note fits. Any real run
  /// should be compared with this: many cases pass by giving no tip at all.
  public static func neverTipsReports(_ cases: [EvalCase], now: Date = Date()) async -> [EvalReport] {
    let runner = EvalRunner(pointer: NeverTips(), writer: NeverTips())
    var reports: [EvalReport] = []
    for variant in AskVariant.allCases {
      let r = await runner.run(cases, variant: variant, route: .onDeviceOnly, cloudAllowed: false, now: now)
      reports.append(EvalReport(variant: variant, route: .onDeviceOnly, runAt: now, results: r.results,
                                complete: r.complete, isReference: true))
    }
    return reports
  }
}

/// A stand-in model that always answers "no note fits". No model is called.
struct NeverTips: AskModel, FreeTextAskModel {
  func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    (AskDraft(noteId: "none", object: "", dayWas: .unclear), .app, "")
  }

  func write(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskFreeDraft, source: AnswerSource, modelVersion: String) {
    (AskFreeDraft(noteId: "none", tip: ""), .app, "")
  }
}

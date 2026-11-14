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

  /// For follow-up cases: some step showed a tip the case says is wrong.
  public let wrongTipShown: Bool?
  /// For follow-up cases: how many answers were asked (the first plus follow-ups).
  public let steps: Int?

  public init(id: String, split: String, passed: Bool, unsafe: Bool, grade: String, shown: String,
              source: AnswerSource, escalated: Bool, seconds: Double, modelDetail: String?,
              expected: String?, gaveTip: Bool?, wrongTipShown: Bool? = nil, steps: Int? = nil) {
    self.id = id
    self.split = split
    self.passed = passed
    self.unsafe = unsafe
    self.grade = grade
    self.shown = shown
    self.source = source
    self.escalated = escalated
    self.seconds = seconds
    self.modelDetail = modelDetail
    self.expected = expected
    self.gaveTip = gaveTip
    self.wrongTipShown = wrongTipShown
    self.steps = steps
  }

  public var isFollowUp: Bool { split == EvalCase.followUpSplit }
  /// The case needed a tip and got the right one.
  public var rightTip: Bool { expected == "tip" && passed }
  /// A tip was shown that the case says is wrong (wrong note, unsafe, or no tip wanted).
  public var wrongTip: Bool { wrongTipShown ?? (gaveTip == true && !passed) }
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

  /// Single-question cases. The main numbers count only these, so they stay
  /// comparable with runs from before follow-ups were added.
  public var single: [EvalCaseResult] { results.filter { !$0.isFollowUp } }
  public var followUps: [EvalCaseResult] { results.filter(\.isFollowUp) }

  public var total: Int { single.count }
  public var passed: Int { single.filter(\.passed).count }
  public var heldoutTotal: Int { single.filter { $0.split == "heldout" }.count }
  public var heldoutPassed: Int { single.filter { $0.split == "heldout" && $0.passed }.count }
  public var unsafe: Int { single.filter(\.unsafe).count }
  /// Cases that need a tip (expected outcome "tip").
  public var tipCases: Int { single.filter { $0.expected == "tip" }.count }
  public var rightTips: Int { single.filter(\.rightTip).count }
  public var wrongTips: Int { single.filter(\.wrongTip).count }
  /// False for reports saved before right/wrong tips were recorded.
  public var hasTipCounts: Bool { results.allSatisfy { $0.expected != nil } }

  /// Follow-up conversations that passed at every step.
  public var followUpPassed: Int { followUps.filter(\.passed).count }
  public var followUpWrong: Int { followUps.filter(\.wrongTip).count }
  public var followUpUnsafe: Int { followUps.filter(\.unsafe).count }
  public var followUpText: String {
    followUps.isEmpty ? "–" : "\(followUpPassed)/\(followUps.count) · \(followUpWrong) wrong · \(followUpUnsafe) unsafe"
  }

  public var onDevice: Int { single.filter { $0.source == .onDevice }.count }
  public var cloud: Int { single.filter { $0.source == .cloud }.count }
  /// Answered by the app with no model call.
  public var appOnly: Int { single.filter { $0.source == .app }.count }
  public var meanModelSeconds: Double {
    let timed = single.filter { $0.source != .app }
    return timed.isEmpty ? 0 : timed.map(\.seconds).reduce(0, +) / Double(timed.count)
  }

  /// How many cases failed because the cloud refused for rate limits (the run should be repeated).
  public var rateLimited: Int {
    results.filter { ($0.modelDetail ?? "").contains("429") || ($0.modelDetail ?? "").contains("resourceExhausted") }.count
  }

  public static let markdownHeader = """
  | Variant | Route | Passed | Held-out | Right tips | Wrong tips shown | Unsafe tips shown | Follow-ups | On device / cloud / app | Avg model s |
  |---|---|---|---|---|---|---|---|---|---|
  """

  public var markdownRow: String {
    let partial = (complete ? "" : " (stopped)") + (rateLimited > 0 ? " (\(rateLimited) rate-limited)" : "")
    let tips = hasTipCounts ? "\(rightTips)/\(tipCases) | \(wrongTips)" : "– | –"
    let timing = isReference == true ? "– | –" : "\(onDevice) / \(cloud) / \(appOnly) | \(String(format: "%.1f", meanModelSeconds))"
    return "| \(variant.title) | \(routeTitle)\(partial) | \(passed)/\(total) | \(heldoutPassed)/\(heldoutTotal) | "
      + "\(tips) | \(unsafe) | \(followUpText) | \(timing) |"
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

  /// - Parameter used: notes already used in this conversation. Pointing leaves them out
  ///   the way the app does; the writing variants simply don't see them.
  public func answer(_ c: EvalCase, notes: [AskNote], variant: AskVariant, route: AskRoute,
                     cloudAllowed: Bool, excluding used: Set<UUID> = [], now: Date) async -> AskAnswer {
    switch variant {
    case .modelPoints:
      await HybridAsk(model: pointer).answer(question: c.question, child: c.child, notes: notes,
                                             route: route, cloudAllowed: cloudAllowed, excluding: used, now: now)
    case .modelWrites, .modelWritesChecked:
      await BaselineAsk(model: writer).answer(question: c.question, child: c.child,
                                              notes: notes.filter { !used.contains($0.id) }, route: route,
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
    var stopped = false
    /// One answer, paced so cloud calls stay within the free tier. Nil if the run was stopped.
    func ask(_ c: EvalCase, _ notes: [AskNote], used: Set<UUID>) async -> (AskAnswer, Double)? {
      if let lastModelCall, pace > .zero {
        let wait = pace - (clock.now - lastModelCall)
        if wait > .zero { try? await Task.sleep(for: wait) }
      }
      if Task.isCancelled { return nil }
      let start = clock.now
      let answer = await answer(c, notes: notes, variant: variant, route: route,
                                cloudAllowed: cloudAllowed, excluding: used, now: now)
      let elapsed = clock.now - start
      if answer.source != .app || answer.detail != nil { lastModelCall = clock.now }
      return (answer, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }
    func shown(_ a: AskAnswer) -> String {
      switch a.outcome {
      case let .tip(text, _): text
      case let .floor(reason): "[\(reason.rawValue)]"
      }
    }

    for (index, c) in cases.enumerated() {
      if Task.isCancelled { break }
      await progress(index, cases.count)
      let built = c.askNotes(now: now)
      guard let (answer, seconds) = await ask(c, built.notes, used: []) else { break }
      let graded = c.grade(answer, caseIdFor: built.caseIdFor)
      var gaveTip = false
      if case .tip = answer.outcome { gaveTip = true }

      guard let followUps = c.followUps, !followUps.isEmpty else {
        results.append(EvalCaseResult(
          id: c.id, split: c.split, passed: graded.passed, unsafe: graded.unsafe, grade: graded.detail,
          shown: shown(answer), source: answer.source, escalated: answer.escalated, seconds: seconds,
          modelDetail: answer.detail, expected: c.expect.outcome.rawValue, gaveTip: gaveTip
        ))
        continue
      }

      // A conversation: the first answer, then each follow-up while the last answer was a tip.
      var passed = graded.passed, unsafe = graded.unsafe, wrongShown = gaveTip && !graded.passed
      var grades = ["1: \(graded.detail)"], shownSteps = [shown(answer)]
      var details = [answer.detail].compactMap { $0 }
      var total = seconds, escalated = answer.escalated
      var usedIds: Set<UUID> = [], usedCaseIds: Set<String> = []
      var last = answer
      for (step, followUp) in followUps.enumerated() {
        guard case let .tip(_, note) = last.outcome else {
          // No tip, so the app shows no follow-up buttons. Fine only if no tip was wanted.
          grades.append("\(step + 2)–: no follow-ups (no tip to follow up)")
          break
        }
        usedIds.insert(note.id)
        if let id = built.caseIdFor[note.id] { usedCaseIds.insert(id) }
        guard let (next, s) = await ask(c, built.notes, used: usedIds) else { stopped = true; break }
        let g = c.grade(next, followUp: followUp, alreadyUsed: usedCaseIds, caseIdFor: built.caseIdFor)
        var tipped = false
        if case .tip = next.outcome { tipped = true }
        passed = passed && g.passed
        unsafe = unsafe || g.unsafe
        wrongShown = wrongShown || (tipped && !g.passed)
        gaveTip = gaveTip || tipped
        grades.append("\(step + 2) “\(followUp.say)”: \(g.detail)")
        shownSteps.append(shown(next))
        if let d = next.detail { details.append(d) }
        total += s
        escalated = escalated || next.escalated
        last = next
      }
      if stopped { break }
      results.append(EvalCaseResult(
        id: c.id, split: c.split, passed: passed, unsafe: unsafe, grade: grades.joined(separator: " · "),
        shown: shownSteps.joined(separator: " → "), source: answer.source, escalated: escalated, seconds: total,
        modelDetail: details.isEmpty ? nil : details.joined(separator: "\n"),
        expected: c.expect.outcome.rawValue, gaveTip: gaveTip, wrongTipShown: wrongShown, steps: shownSteps.count
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

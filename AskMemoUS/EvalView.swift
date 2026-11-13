import SwiftUI
import UIKit
import HybridAskCore
import HybridAskFirebase

/// Runs the bundled eval cases (fictional children and notes) through each way of
/// answering, on each route, and keeps the latest numbers for each pair on this phone.
struct EvalView: View {
  @AppStorage(CloudChecks.consentKey) private var cloudConsent = "undecided"
  private var cloudAllowed: Bool { cloudConsent == "allowed" }

  @State private var variant: AskVariant = .modelPoints
  @State private var route: AskRoute = .onDeviceOnly
  @State private var heldoutOnly = false
  @State private var reports: [EvalReport] = EvalStore.load()
  @State private var running: Task<Void, Never>?
  @State private var progress = (done: 0, total: 0)
  @State private var loadError: String?
  @State private var references: [EvalReport] = []

  private let runner: EvalRunner = {
    let model = FirebaseAskModel()
    return EvalRunner(pointer: model, writer: model)
  }()

  var body: some View {
    Form {
      Section {
        Picker("Answering", selection: $variant) {
          ForEach(AskVariant.allCases) { Text($0.title).tag($0) }
        }
        Picker("Route", selection: $route) {
          ForEach(AskRoute.allCases) { Text($0.rawValue).tag($0) }
        }
        Toggle("Held-out cases only", isOn: $heldoutOnly)
        if running == nil {
          Button("Run") { start() }
        } else {
          HStack {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
            Text("\(progress.done)/\(progress.total)").monospacedDigit().font(.caption)
          }
          Button("Stop", role: .destructive) { running?.cancel() }
        }
      } footer: {
        Text(runFooter)
      }

      if let loadError { Section { Text(loadError).foregroundStyle(.red) } }

      Section {
        if reports.isEmpty {
          Text("No runs yet.").foregroundStyle(.secondary)
        }
        ForEach(sortedReports) { report in
          NavigationLink { EvalReportView(report: report) } label: { ReportRow(report: report) }
        }
      } header: {
        Text("Latest run of each")
      } footer: {
        Text("Passed = the answer a parent would see matches what the case expects. Right tips = cases that need a tip and got the right one. Wrong tips = a tip shown that the case says is wrong. Unsafe = a tip containing one of the case's forbidden phrases was shown. Model-written tips can be unsafe in words no case lists, so that number is a floor.")
      }

      Section {
        ForEach(references) { ReportRow(report: $0) }
      } header: {
        Text("If the model never gave a tip")
      } footer: {
        Text("Worked out on the phone, no model called. Many cases pass by giving no tip at all, so a real run only helps parents if it beats these numbers with right tips.")
      }

      if !reports.isEmpty {
        Section {
          ShareLink("Share as a table", item: EvalStore.markdown(sortedReports + references))
          ShareLink("Share details", item: EvalStore.details(sortedReports))
          Button("Clear results", role: .destructive) {
            reports = []
            EvalStore.save([])
          }
        }
      }
    }
    .navigationTitle("Eval runner")
    .onDisappear { running?.cancel() }
    .task {
      if references.isEmpty, let cases = try? EvalSet.bundled().cases {
        references = await EvalRunner.neverTipsReports(cases)
      }
    }
  }

  private var runFooter: String {
    var lines = ["Cases are fictional. They run one at a time; the on-device model takes a few seconds each."]
    if route != .onDeviceOnly && !cloudAllowed {
      lines.append("Cloud checks are off, so cloud cases will show the “cloud checks are off” reply. Turn them on in Settings first.")
    }
    return lines.joined(separator: " ")
  }

  private var sortedReports: [EvalReport] {
    reports.sorted {
      ($0.route.rawValue, AskVariant.allCases.firstIndex(of: $0.variant)!) <
        ($1.route.rawValue, AskVariant.allCases.firstIndex(of: $1.variant)!)
    }
  }

  private func start() {
    let cases: [EvalCase]
    do {
      cases = try EvalSet.bundled().cases.filter { !heldoutOnly || $0.split == "heldout" }
    } catch {
      loadError = "Couldn't load the eval cases: \(error.localizedDescription)"
      return
    }
    let variant = variant, route = route, allowed = cloudAllowed, runner = runner
    progress = (0, cases.count)
    UIApplication.shared.isIdleTimerDisabled = true
    running = Task {
      let report = await runner.run(cases, variant: variant, route: route, cloudAllowed: allowed) { done, total in
        await MainActor.run { progress = (done, total) }
      }
      reports.removeAll { $0.id == report.id }
      reports.append(report)
      EvalStore.save(reports)
      UIApplication.shared.isIdleTimerDisabled = false
      running = nil
    }
  }
}

private struct ReportRow: View {
  let report: EvalReport

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(report.variant.title).font(.headline)
        Spacer()
        Text(report.routeTitle).font(.caption).foregroundStyle(.secondary)
      }
      Text("Passed \(report.passed)/\(report.total) · held-out \(report.heldoutPassed)/\(report.heldoutTotal) · unsafe \(report.unsafe)")
        .monospacedDigit()
      if report.hasTipCounts {
        Text("Right tips \(report.rightTips)/\(report.tipCases) · wrong tips shown \(report.wrongTips)")
          .monospacedDigit()
      } else {
        Text("Run again to count right and wrong tips").font(.caption).foregroundStyle(.secondary)
      }
      if report.isReference != true {
        Text("On device \(report.onDevice) · cloud \(report.cloud) · app \(report.appOnly) · avg \(report.meanModelSeconds, format: .number.precision(.fractionLength(1))) s\(report.complete ? "" : " · stopped")")
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
    }
  }
}

private struct EvalReportView: View {
  let report: EvalReport

  var body: some View {
    List {
      Section {
        Text(report.runAt, format: .dateTime.day().month().hour().minute())
      } header: {
        Text("\(report.variant.title) · \(report.route.rawValue)")
      }
      ForEach(report.results) { r in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Image(systemName: r.unsafe ? "exclamationmark.triangle.fill" : r.passed ? "checkmark.circle.fill" : "xmark.circle")
              .foregroundStyle(r.unsafe ? .red : r.passed ? .green : .orange)
            Text(r.id).font(.subheadline.monospaced())
          }
          Text(r.shown).font(.callout)
          Text(r.grade).font(.caption).foregroundStyle(.secondary)
          Text("\(r.source.rawValue)\(r.escalated ? " (escalated)" : "") · \(r.seconds, format: .number.precision(.fractionLength(1))) s")
            .font(.caption2).foregroundStyle(.secondary)
          if let detail = r.modelDetail {
            Text(detail).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
      }
    }
    .navigationTitle(report.variant.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// The latest report for each answering × route pair, in a JSON file on this phone.
enum EvalStore {
  static var url: URL {
    URL.applicationSupportDirectory.appending(path: "eval-reports.json")
  }

  static func load() -> [EvalReport] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([EvalReport].self, from: data)) ?? []
  }

  static func save(_ reports: [EvalReport]) {
    try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
    try? JSONEncoder().encode(reports).write(to: url, options: .atomic)
  }

  /// Every case of every run, for reading failures (fictional cases only).
  static func details(_ reports: [EvalReport]) -> String {
    var lines: [String] = []
    for r in reports {
      lines.append("## \(r.variant.title) · \(r.routeTitle) · \(r.passed)/\(r.total)")
      for c in r.results {
        let mark = c.unsafe ? "UNSAFE" : c.passed ? "ok" : "FAIL"
        lines.append("- \(mark) \(c.id) [\(c.expected ?? "?")] \(c.source.rawValue)\(c.escalated ? "+esc" : ""): \(c.shown)")
        lines.append("  grade: \(c.grade)")
        if let d = c.modelDetail { lines.append("  model: \(d.replacingOccurrences(of: "\n", with: " | "))") }
      }
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }

  static func markdown(_ reports: [EvalReport]) -> String {
    let date = Date.now.formatted(date: .abbreviated, time: .omitted)
    return "AskMemoUS eval, \(date)\n\n" + EvalReport.markdownHeader + "\n"
      + reports.map(\.markdownRow).joined(separator: "\n") + "\n"
  }
}

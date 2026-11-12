import SwiftUI
import HybridAskCore

/// One answer as a parent sees it: the tip (or the app's fixed reply), the note it
/// came from, and where it was answered. Used on Ask and in "Your questions".
struct AnswerSection: View {
  let answer: AskAnswer
  let childName: String

  var body: some View {
    Section {
      switch answer.outcome {
      case let .tip(text, note):
        Text(text)
        VStack(alignment: .leading, spacing: 4) {
          Text("Based on your note").font(.caption).foregroundStyle(.secondary)
          Text("“\(note.text)”").font(.callout).italic()
          Text(note.createdAt, format: .dateTime.day().month(.abbreviated))
            .font(.caption2).foregroundStyle(.secondary)
        }
        Text(FloorText.worryLine).font(.caption).foregroundStyle(.secondary)
      case let .floor(reason):
        Text(FloorText.text(reason, childName: childName))
      }
      #if DEBUG
      DebugLines(answer: answer)
      #endif
    } header: {
      SourceLabel(answer: answer)
    }
  }
}

/// Where the answer came from, always shown.
struct SourceLabel: View {
  let answer: AskAnswer

  var body: some View {
    Label(title, systemImage: symbol)
  }

  var title: String {
    if answer.escalated { return "Checked on this iPhone, answered in the cloud" }
    switch answer.source {
    case .onDevice: return "Answered on this iPhone"
    case .cloud: return "Answered in the cloud"
    case .app: return "Answered by the app"
    }
  }

  var symbol: String {
    if answer.escalated { return "icloud" }
    switch answer.source {
    case .onDevice: return "iphone"
    case .cloud: return "icloud"
    case .app: return "text.book.closed"
    }
  }
}

#if DEBUG
private struct DebugLines: View {
  let answer: AskAnswer

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if case let .floor(reason) = answer.outcome { Text("reason: \(reason.rawValue)") }
      if let version = answer.modelVersion, !version.isEmpty { Text(version) }
      if let detail = answer.detail { Text(detail) }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .textSelection(.enabled)
  }
}
#endif

enum CloudChecks {
  /// "undecided" until the parent answers once; kept on this phone.
  static let consentKey = "cloudConsent"
  static let routeKey = "askRoute"

  static func explainer(childName: String) -> String {
    """
    When on, a question this iPhone can't answer well goes to Google's Gemini through Firebase, \
    with up to 5 of your notes. \(childName)'s name is replaced with "your child" first. \
    On the free plan, Google may use what's sent to improve its products. \
    Your notes and saved questions otherwise stay on this iPhone.
    """
  }
}

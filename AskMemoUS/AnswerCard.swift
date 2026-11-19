import SwiftUI
import HybridAskCore

/// One answer as a parent sees it: the tip (or the app's fixed reply), the note it
/// came from, and where it was answered. Used in "Your questions".
struct AnswerSection: View {
  let answer: AskAnswer
  let childName: String
  var ageLine: AgeContext.Line? = nil
  var noteNudge: String? = nil

  var body: some View {
    Section {
      AnswerBody(answer: answer, childName: childName, ageLine: ageLine, noteNudge: noteNudge)
    } header: {
      SourceLabel(answer: answer)
    }
  }
}

/// The answer's content, shared by the Form section and the Ask conversation.
struct AnswerBody: View {
  let answer: AskAnswer
  let childName: String
  var ageLine: AgeContext.Line? = nil
  var noteNudge: String? = nil
  @State private var isAddingNote = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch answer.outcome {
      case let .tip(text, note):
        Text(text).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
        HStack(spacing: 10) {
          RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3)
          VStack(alignment: .leading, spacing: 4) {
            Text("Based on your note").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text("“\(note.text)”").font(.callout).italic().foregroundStyle(Theme.ink)
            Text(note.createdAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
              .font(.caption2).foregroundStyle(Theme.muted)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soft, in: .rect(cornerRadius: 12))
      case let .floor(reason):
        Text(FloorText.text(reason, childName: childName)).foregroundStyle(Theme.ink)
      }
      if let ageLine {
        AgeContextBlock(line: ageLine, childName: childName)
      }
      if let noteNudge {
        Button { isAddingNote = true } label: {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "square.and.pencil")
            Text(noteNudge)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .font(.footnote)
          .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a new note")
      }
      if case .tip = answer.outcome {
        Text(FloorText.worryLine).font(.caption).foregroundStyle(Theme.muted)
      }
      #if DEBUG
      DebugLines(answer: answer)
      #endif
    }
    .sheet(isPresented: $isAddingNote) { AddNoteSheet() }
  }
}

/// General age context under the tip. Smaller and quieter than the tip, and labelled
/// as coming from the app rather than from this child's notes.
struct AgeContextBlock: View {
  let line: AgeContext.Line
  let childName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(line.label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.muted)
      Text(line.text)
        .font(.footnote)
        .foregroundStyle(Theme.muted)
      Text(line.attribution(childName: childName))
        .font(.caption2)
        .foregroundStyle(Theme.muted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
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

import SwiftUI
import SwiftData
import HybridAskCore
import HybridAskFirebase

/// Ask a question about the child. Every answer is saved to "Your questions".
struct AskView: View {
  let child: Child
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalNote.createdAt, order: .reverse) private var notes: [JournalNote]

  @State private var question = ""
  @State private var answer: AskAnswer?
  /// The saved entry for the answer on screen, so a cloud re-check updates it instead of adding one.
  @State private var saved: SavedQuestion?
  @State private var isAsking = false
  @FocusState private var questionFocused: Bool

  @AppStorage(CloudChecks.consentKey) private var cloudConsent = "undecided"
  @AppStorage(CloudChecks.routeKey) private var route: AskRoute = .hybrid
  private var cloudAllowed: Bool { cloudConsent == "allowed" }

  private let ask = HybridAsk(model: FirebaseAskModel())

  static let suggestions = [
    "She keeps waking at 5am. What could I try this week?",
    "Evenings are hard lately. Any ideas?",
    "How can I get her to eat lunch?",
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Ask about \(child.name)", text: $question, axis: .vertical)
            .focused($questionFocused)
            .lineLimit(2...5)
          Button(isAsking ? "Asking…" : "Ask") { Task { await runAsk() } }
            .disabled(isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
          Text("Answers come only from your notes. \(statusLine)")
        }

        if answer == nil {
          Section("Try asking") {
            ForEach(Self.suggestions, id: \.self) { s in
              Button(s) { question = s }
            }
          }
        }

        if let answer {
          AnswerSection(answer: answer, childName: child.name)
          if answer.cloudCouldHelp && cloudConsent == "undecided" { consentSection }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Ask")
      .toolbar {
        if route != .hybrid {
          ToolbarItem(placement: .topBarTrailing) {
            Text(route.rawValue).font(.caption).foregroundStyle(.orange)
          }
        }
      }
    }
  }

  /// Asked once, the first time a cloud check could help.
  private var consentSection: some View {
    Section("Check this in the cloud?") {
      Text("This iPhone couldn't find a good answer in your notes. A cloud model might.")
      Text(CloudChecks.explainer(childName: child.name)).font(.footnote).foregroundStyle(.secondary)
      Button("Check in the cloud") {
        cloudConsent = "allowed"
        Task { await runAsk(replacingSaved: true) }
      }
      Button("Keep it on this iPhone", role: .cancel) { cloudConsent = "declined" }
    }
  }

  private var statusLine: String {
    switch OnDeviceStatus.current {
    case .available: return cloudAllowed ? "On this iPhone first, cloud if needed." : "On this iPhone only."
    case .deviceNotEligible: return "This iPhone can't run Apple Intelligence."
    case .appleIntelligenceOff: return "Apple Intelligence is off in Settings."
    case .modelDownloading: return "The on-device model is still downloading."
    case .unavailable: return "The on-device model isn't available."
    }
  }

  private func runAsk(replacingSaved: Bool = false) async {
    questionFocused = false
    isAsking = true
    defer { isAsking = false }
    let askedAt = Date.now
    let askChild = child.askChild
    let result = await ask.answer(question: question, child: askChild, notes: notes.map(\.askNote),
                                  route: route, cloudAllowed: cloudAllowed, now: askedAt)
    answer = result
    guard result.outcome != .floor(.emptyQuestion) else { return }
    let record = AskRecord(askedAt: askedAt, question: question, child: askChild, answer: result)
    if replacingSaved, let saved {
      saved.replace(with: record)
    } else {
      let entry = SavedQuestion(record)
      context.insert(entry)
      saved = entry
    }
    try? context.save()
  }
}

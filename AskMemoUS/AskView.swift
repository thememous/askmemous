import SwiftUI
import SwiftData
import HybridAskCore
import HybridAskFirebase

/// Ask about the child as a short conversation. Every turn runs the same checked
/// path (fixed replies, the model points to a note, the app writes the tip), so
/// follow-ups are as safe as the first answer. Answers are saved to "Your questions".
struct AskView: View {
  let child: Child
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalNote.createdAt, order: .reverse) private var notes: [JournalNote]

  /// One exchange: what the parent said, and the reply.
  struct Turn: Identifiable {
    enum Reply { case waiting, answer(AskAnswer), why(String) }
    let id = UUID()
    let said: String
    var reply: Reply
  }

  @State private var turns: [Turn] = []
  /// The question the follow-ups are about, and the notes already used for it.
  @State private var topic: String?
  @State private var used: Set<UUID> = []
  /// The saved entry for the latest answer, so a cloud re-check updates it instead of adding one.
  @State private var saved: SavedQuestion?
  @State private var question = ""
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
      ScrollViewReader { scroller in
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if turns.isEmpty { welcome } else {
              ForEach(turns) { turn in turnView(turn) }
              if let last = lastAnswer, case .tip = last.outcome, !isAsking { followUps }
              if let last = lastAnswer, last.cloudCouldHelp, cloudConsent == "undecided", !isAsking { consentCard }
            }
            Color.clear.frame(height: 1).id("bottom")
          }
          .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: turns.count) { withAnimation { scroller.scrollTo("bottom", anchor: .bottom) } }
        .onChange(of: isAsking) { withAnimation { scroller.scrollTo("bottom", anchor: .bottom) } }
      }
      .safeAreaInset(edge: .bottom) { composer }
      .navigationTitle("Ask")
      .toolbar {
        if route != .hybrid {
          ToolbarItem(placement: .topBarLeading) {
            Text(route.rawValue).font(.caption).foregroundStyle(.orange)
          }
        }
        if !turns.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("New question", systemImage: "square.and.pencil") { startOver() }
              .disabled(isAsking)
          }
        }
      }
    }
  }

  // MARK: - Pieces

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Answers come only from your notes. \(statusLine)")
        .font(.subheadline).foregroundStyle(.secondary)
      Text("Try asking").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
      ForEach(Self.suggestions, id: \.self) { s in
        Button { question = s; questionFocused = true } label: {
          Text(s).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  @ViewBuilder private func turnView(_ turn: Turn) -> some View {
    HStack {
      Spacer(minLength: 48)
      Text(turn.said)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: .rect(cornerRadius: 18))
    }
    VStack(alignment: .leading, spacing: 8) {
      switch turn.reply {
      case .waiting:
        HStack(spacing: 8) { ProgressView(); Text("Reading your notes…").foregroundStyle(.secondary) }
      case let .answer(answer):
        SourceLabel(answer: answer).font(.caption).foregroundStyle(.secondary)
        AnswerBody(answer: answer, childName: child.name)
      case let .why(text):
        Label("Answered by the app", systemImage: "text.book.closed").font(.caption).foregroundStyle(.secondary)
        Text(text)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
    .padding(.trailing, 24)
  }

  private var followUps: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { followUpButtons }
      VStack(alignment: .leading, spacing: 8) { followUpButtons }
    }
    .font(.subheadline)
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
  }

  @ViewBuilder private var followUpButtons: some View {
    Button("Another idea") { Task { await followUp("Another idea?") } }
    Button("Didn't help") { Task { await followUp("That didn't help.") } }
    Button("Why this note?") { explainLastNote() }
  }

  /// Asked once, the first time a cloud check could help.
  private var consentCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Check this in the cloud?").font(.headline)
      Text("This iPhone couldn't find a good answer in your notes. A cloud model might.")
      Text(CloudChecks.explainer(childName: child.name)).font(.footnote).foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        HStack { consentButtons }
        VStack(alignment: .leading) { consentButtons }
      }
    }
    .padding(14)
    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
  }

  @ViewBuilder private var consentButtons: some View {
    Button("Check in the cloud") {
      cloudConsent = "allowed"
      Task { await recheckInCloud() }
    }
    .buttonStyle(.borderedProminent)
    Button("Keep it on this iPhone") { cloudConsent = "declined" }
      .buttonStyle(.bordered)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField(turns.isEmpty ? "Ask about \(child.name)" : "Ask something new", text: $question, axis: .vertical)
        .focused($questionFocused)
        .lineLimit(1...4)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
      Button {
        Task { await askNew() }
      } label: {
        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
      }
      .disabled(isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Ask")
    }
    .padding(.horizontal).padding(.vertical, 8)
    .background(.bar)
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

  // MARK: - Actions

  /// The latest model-path answer ("Why this note?" replies don't count).
  private var lastAnswer: AskAnswer? {
    for turn in turns.reversed() {
      if case let .answer(a) = turn.reply { return a }
    }
    return nil
  }

  private func startOver() {
    turns = []
    topic = nil
    used = []
    saved = nil
    question = ""
  }

  /// A new question starts a new topic; the conversation above stays on screen.
  private func askNew() async {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    question = ""
    topic = q
    used = []
    await run(said: q)
  }

  /// "Another idea?" / "That didn't help.": the same question, leaving out the notes already used.
  private func followUp(_ said: String) async {
    await run(said: said)
  }

  /// Answered by the app from the note's own words. No model.
  private func explainLastNote() {
    guard let last = lastAnswer, case let .tip(_, note) = last.outcome else { return }
    turns.append(Turn(said: "Why this note?", reply: .why(AskCheck.whyThisNote(note.text))))
  }

  /// After the parent allows cloud checks: ask the latest request again and replace that reply.
  private func recheckInCloud() async {
    guard let last = turns.lastIndex(where: { if case .answer = $0.reply { true } else { false } }) else { return }
    let said = turns[last].said
    turns.removeSubrange(last...)
    await run(said: said, replacingSaved: true)
  }

  private func run(said: String, replacingSaved: Bool = false) async {
    guard let topic else { return }
    questionFocused = false
    isAsking = true
    defer { isAsking = false }
    turns.append(Turn(said: said, reply: .waiting))
    let index = turns.count - 1
    let askedAt = Date.now
    let askChild = child.askChild
    let result = await ask.answer(question: topic, child: askChild, notes: notes.map(\.askNote),
                                  route: route, cloudAllowed: cloudAllowed, excluding: used, now: askedAt)
    turns[index].reply = .answer(result)
    if case let .tip(_, note) = result.outcome { used.insert(note.id) }
    guard result.outcome != .floor(.emptyQuestion) else { return }
    let record = AskRecord(askedAt: askedAt, question: topic, child: askChild, answer: result)
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

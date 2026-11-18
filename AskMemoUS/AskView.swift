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
    enum Reply { case waiting, answer(AskAnswer, ageLine: AgeContext.Line?), why(String) }
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
  @Environment(LabUnlock.self) private var lab
  @Environment(RemoteAskSettings.self) private var remote
  /// While the lab is locked, a saved Cloud-only or On-device route does not apply.
  private var activeRoute: AskRoute { route.forParent(labUnlocked: lab.showsLab) }
  /// The kill switch counts as not allowed. It does not change the saved choice.
  private var cloudAllowed: Bool { cloudConsent == "allowed" && remote.cloudEnabled }

  private func asker() -> HybridAsk {
    HybridAsk(model: FirebaseAskModel(cloudModelName: remote.cloudModelName))
  }

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
              if let last = lastAnswer, last.cloudCouldHelp, cloudConsent == "undecided", remote.cloudEnabled, !isAsking { consentCard }
            }
            Color.clear.frame(height: 1).id("bottom")
          }
          .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: turns.count) { withAnimation { scroller.scrollTo("bottom", anchor: .bottom) } }
        .onChange(of: isAsking) { withAnimation { scroller.scrollTo("bottom", anchor: .bottom) } }
      }
      .background(Theme.page)
      .safeAreaInset(edge: .bottom) { composer }
      .navigationTitle("Ask")
      .toolbar {
        if activeRoute != .hybrid {
          ToolbarItem(placement: .topBarLeading) {
            Text(activeRoute.rawValue).font(.caption).foregroundStyle(.orange)
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
      VStack(spacing: 10) {
        MemoMascot(variant: .mascot, size: 120, float: true)
        Text("Hi, I'm Memo! Ask me anything about \(child.name).")
          .font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
        Label("Answers come only from your notes. \(statusLine)", systemImage: statusSymbol)
          .font(.footnote).foregroundStyle(Theme.muted)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 8)
      Text("Try asking").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
      ForEach(Self.suggestions, id: \.self) { s in
        Button { question = s; questionFocused = true } label: { Text(s) }
          .buttonStyle(ChipStyle())
      }
    }
  }

  @ViewBuilder private func turnView(_ turn: Turn) -> some View {
    HStack {
      Spacer(minLength: 48)
      Text(turn.said)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Theme.accent, in: UnevenRoundedRectangle(cornerRadii: .init(
          topLeading: Theme.radius, bottomLeading: Theme.radius, bottomTrailing: 4, topTrailing: Theme.radius)))
    }
    HStack(alignment: .bottom, spacing: 8) {
      MemoMascot(variant: .avatar, size: 30, float: isWaiting(turn))
      reply(turn)
    }
  }

  private func isWaiting(_ turn: Turn) -> Bool {
    if case .waiting = turn.reply { true } else { false }
  }

  @ViewBuilder private func reply(_ turn: Turn) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      switch turn.reply {
      case .waiting:
        HStack(spacing: 8) { ProgressView(); Text("Reading your notes…").foregroundStyle(Theme.muted) }
      case let .answer(answer, ageLine):
        SourceLabel(answer: answer).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
        AnswerBody(answer: answer, childName: child.name, ageLine: ageLine)
      case let .why(text):
        Label("Answered by the app", systemImage: "text.book.closed")
          .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
        Text(text).foregroundStyle(Theme.ink)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeCard(corners: .init(topLeading: Theme.radius, bottomLeading: 4,
                              bottomTrailing: Theme.radius, topTrailing: Theme.radius))
  }

  private var followUps: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { followUpButtons }
      VStack(alignment: .leading, spacing: 8) { followUpButtons }
    }
    .buttonStyle(ChipStyle(compact: true))
    .padding(.leading, 38)
  }

  @ViewBuilder private var followUpButtons: some View {
    Button("Another idea") { Task { await followUp("Another idea?") } }
    Button("Didn't help") { Task { await followUp("That didn't help.") } }
    Button("Why this note?") { explainLastNote() }
  }

  /// Asked once, the first time a cloud check could help.
  private var consentCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Check this in the cloud?", systemImage: "icloud").font(.headline).foregroundStyle(Theme.ink)
      Text("This iPhone couldn't find a good answer in your notes. A cloud model might.")
        .foregroundStyle(Theme.ink)
      Text(CloudChecks.explainer(childName: child.name)).font(.footnote).foregroundStyle(Theme.muted)
      ViewThatFits(in: .horizontal) {
        HStack { consentButtons }
        VStack(alignment: .leading) { consentButtons }
      }
    }
    .padding(14)
    .background(Theme.soft, in: .rect(cornerRadius: Theme.radius))
    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
  }

  @ViewBuilder private var consentButtons: some View {
    Button("Check in the cloud") {
      cloudConsent = "allowed"
      Task { await recheckInCloud() }
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    Button("Keep it on this iPhone") { cloudConsent = "declined" }
      .buttonStyle(ChipStyle())
  }

  private var canSend: Bool {
    !isAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField(turns.isEmpty ? "Ask about \(child.name)" : "Ask something new", text: $question, axis: .vertical)
        .focused($questionFocused)
        .lineLimit(1...4)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.field, lineWidth: 1.5))
      Button {
        Task { await askNew() }
      } label: {
        Group {
          if isAsking { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.headline.weight(.bold)) }
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .background(Theme.accent.opacity(canSend || isAsking ? 1 : 0.45), in: .circle)
      }
      .disabled(!canSend)
      .accessibilityLabel("Ask")
    }
    .padding(.horizontal).padding(.vertical, 8)
    .background(.bar)
  }

  private var statusSymbol: String {
    OnDeviceStatus.current == .available ? (cloudAllowed ? "iphone.and.arrow.forward" : "iphone") : "exclamationmark.circle"
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
      if case let .answer(a, _) = turn.reply { return a }
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
    guard let last = turns.lastIndex(where: { if case .answer(_, _) = $0.reply { true } else { false } }) else { return }
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
    let result = await asker().answer(question: topic, child: askChild, notes: notes.map(\.askNote),
                                      route: activeRoute, cloudAllowed: cloudAllowed, excluding: used,
                                      safety: remote.safety, now: askedAt)
    let ageLine = AgeContext.line(question: topic, child: askChild, outcome: result.outcome, safety: remote.safety)
    turns[index].reply = .answer(result, ageLine: ageLine)
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

import SwiftUI
import FirebaseAppCheck
import HybridAskCore
import HybridAskFirebase

/// Spike screen on top of HybridAskCore: one tip, the note it came from,
/// and app-written replies when the model can't be trusted to answer.
/// Sample notes are fictional — never real child data in this repo.
struct SpikeView: View {
  @State private var question = "She keeps waking at 5am. What could I try this week?"
  @State private var answer: AskAnswer?
  @State private var isAsking = false
  @State private var appCheckStatus: String?
  @State private var route: AskRoute = .hybrid
  @FocusState private var questionFocused: Bool
  /// "undecided" until the parent answers the cloud question once; kept on this phone.
  @AppStorage("cloudConsent") private var cloudConsent = "undecided"
  private var cloudAllowed: Bool { cloudConsent == "allowed" }

  private let ask = HybridAsk(model: FirebaseAskModel())

  private static let child = AskChild(name: "Mia", ageMonths: 14)
  private static let notes: [AskNote] = {
    let day: TimeInterval = 86_400
    let now = Date()
    return [
      AskNote(text: "Up at 5:10 again, happy and chatty in the cot.", category: "sleep", createdAt: now - 2 * day),
      AskNote(text: "Long nap 12–2:30 after the park.", category: "routine", createdAt: now - 4 * day),
      AskNote(text: "Slept to 6:40 on the day we skipped the late snack.", category: "sleep", createdAt: now - 6 * day),
    ]
  }()

  var body: some View {
    NavigationStack {
      Form {
        Section("On-device model") { Text(statusText) }
        Section("Question") {
          TextField("Ask about the notes", text: $question, axis: .vertical)
            .focused($questionFocused)
          Picker("Route", selection: $route) {
            ForEach(AskRoute.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          Button(isAsking ? "Asking…" : "Ask") { Task { await runAsk() } }
            .disabled(isAsking)
        }
        if let answer {
          answerSection(answer)
          if answer.cloudCouldHelp && cloudConsent == "undecided" { consentSection }
        }
        Section {
          Toggle("Allow cloud checks", isOn: Binding(
            get: { cloudAllowed },
            set: { cloudConsent = $0 ? "allowed" : "declined" }
          ))
        } footer: {
          Text(Self.cloudExplainer)
        }
        #if DEBUG
        Section("App Check (debug)") {
          Button("Get App Check token") { Task { await fetchAppCheckToken() } }
          if let appCheckStatus { Text(appCheckStatus).font(.caption) }
        }
        #endif
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("AskMemoUS spike")
    }
  }

  @ViewBuilder
  private func answerSection(_ answer: AskAnswer) -> some View {
    Section(answer.escalated ? "Checked on this iPhone, answered in the cloud" : sourceTitle(answer.source)) {
      switch answer.outcome {
      case let .tip(text, note):
        Text(text)
        VStack(alignment: .leading, spacing: 4) {
          Text("Based on your note").font(.caption).foregroundStyle(.secondary)
          Text("“\(note.text)”").font(.callout).italic()
        }
        Text(FloorText.worryLine).font(.caption).foregroundStyle(.secondary)
      case let .floor(reason):
        Text(FloorText.text(reason, childName: Self.child.name))
        Text("reason: \(reason.rawValue)").font(.caption2).foregroundStyle(.tertiary)
      }
      if let version = answer.modelVersion, !version.isEmpty {
        Text(version).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  /// Asked once, the first time a cloud check could help.
  private var consentSection: some View {
    Section("Check this in the cloud?") {
      Text("This iPhone couldn't find a good answer in your notes. A cloud model might.")
      Text(Self.cloudExplainer).font(.footnote).foregroundStyle(.secondary)
      Button("Check in the cloud") {
        cloudConsent = "allowed"
        Task { await runAsk() }
      }
      Button("Keep it on this iPhone", role: .cancel) { cloudConsent = "declined" }
    }
  }

  static let cloudExplainer = """
  When on, a question this iPhone can't answer well goes to Google's Gemini through Firebase, \
  with up to 5 of your notes. \(child.name)'s name is replaced with "your child" first. \
  On the free plan, Google may use what's sent to improve its products. \
  Your notes and saved questions otherwise stay on this iPhone.
  """

  private func sourceTitle(_ source: AnswerSource) -> String {
    switch source {
    case .onDevice: "Answered on this iPhone"
    case .cloud: "Answered in the cloud"
    case .app: "Answered by the app"
    }
  }

  private var statusText: String {
    switch OnDeviceStatus.current {
    case .available: "Ready"
    case .deviceNotEligible: "This device can't run Apple Intelligence — cloud only"
    case .appleIntelligenceOff: "Apple Intelligence is off in Settings — cloud only"
    case .modelDownloading: "Model still downloading — cloud for now"
    case .unavailable: "Unavailable — cloud only"
    }
  }

  /// Requesting a token makes the debug provider print
  /// "App Check debug token: '…'" in the Xcode console. Never shown on screen.
  private func fetchAppCheckToken() async {
    do {
      _ = try await AppCheck.appCheck().token(forcingRefresh: true)
      appCheckStatus = "Token accepted — App Check is working."
    } catch {
      appCheckStatus = "Check the Xcode console for the debug token, add it in Firebase, then tap again. (\(error.localizedDescription))"
    }
  }

  private func runAsk() async {
    questionFocused = false
    isAsking = true
    defer { isAsking = false }
    answer = await ask.answer(question: question, child: Self.child, notes: Self.notes,
                              route: route, cloudAllowed: cloudAllowed)
  }
}

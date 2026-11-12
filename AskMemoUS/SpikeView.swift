import SwiftUI
import FirebaseAppCheck

/// Spike screen: proves on-device answers, cloud fallback, and the source flag.
/// Sample notes are fictional — never real child data in this repo.
struct SpikeView: View {
  @State private var question = "She keeps waking at 5am. What could I try this week?"
  @State private var answer: AskAnswer?
  @State private var error: String?
  @State private var isAsking = false
  @State private var appCheckStatus: String?
  @State private var route: InferenceRoute = .hybrid

  private let service = HybridAskService()

  private static let sampleNotes = """
  Child: Mia, 14 months, toddler.
  Recent memos (the source for what to try):
  - [2d ago · sleep] Up at 5:10 again, happy and chatty in the cot.
  - [4d ago · routine] Long nap 12–2:30 after the park.
  - [6d ago · sleep] Slept to 6:40 on the day we skipped the late snack.
  """

  private static let rules = """
  Be warm and practical. Plain text only. Under 180 words.
  This child is a toddler (about 1–3 years). Suggest short, physical ideas. No schoolwork.
  Give one small thing they can try soon, tied to a recent memo above. If the memos do not support a tip, say so plainly.
  Do not invent interests, milestones, delays, or events that are not in the memos.
  Do not diagnose or give medical advice; suggest asking their paediatrician if they are worried.
  """

  var body: some View {
    NavigationStack {
      Form {
        Section("On-device model") {
          Text(statusText)
        }
        Section("Question") {
          TextField("Ask about the notes", text: $question, axis: .vertical)
          Picker("Route", selection: $route) {
            ForEach(InferenceRoute.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          Button(isAsking ? "Asking…" : "Ask") { Task { await ask() } }
            .disabled(isAsking || question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if let answer {
          Section(answer.source == .onDevice ? "Answered on this iPhone" : "Answered in the cloud") {
            Text(answer.text)
            Text(answer.modelVersion).font(.caption).foregroundStyle(.secondary)
          }
        }
        if let error {
          Section("Error") { Text(error).foregroundStyle(.red) }
        }
        #if DEBUG
        Section("App Check (debug)") {
          Button("Get App Check token") { Task { await fetchAppCheckToken() } }
          if let appCheckStatus { Text(appCheckStatus).font(.caption) }
        }
        #endif
      }
      .navigationTitle("AskMemoUS spike")
    }
  }

  private var statusText: String {
    switch service.onDeviceStatus() {
    case .available: return "Ready"
    case .deviceNotEligible: return "This device can't run Apple Intelligence — cloud only"
    case .appleIntelligenceOff: return "Apple Intelligence is off in Settings — cloud only"
    case .modelDownloading: return "Model still downloading — cloud for now"
    case let .unavailable(reason): return "Unavailable: \(reason)"
    }
  }

  /// Requesting a token makes the debug provider print
  /// "App Check debug token: '…'" in the Xcode console (register that value
  /// in the Firebase console). The value is never shown on screen.
  private func fetchAppCheckToken() async {
    do {
      _ = try await AppCheck.appCheck().token(forcingRefresh: true)
      appCheckStatus = "Token accepted — App Check is working."
    } catch {
      appCheckStatus = "Check the Xcode console for the debug token, add it in Firebase, then tap again. (\(error.localizedDescription))"
    }
  }

  private func ask() async {
    isAsking = true
    error = nil
    defer { isAsking = false }
    let prompt = "\(Self.rules)\n\n\(Self.sampleNotes)\n\nParent's question: \(question)"
    do {
      answer = try await service.ask(prompt, route: route)
    } catch {
      self.error = String(describing: error)
    }
  }
}

import Foundation
import FirebaseAILogic
import FoundationModels
import HybridAskCore

/// The structured answer both models must return. Asking for an id (not free
/// text about the notes) is what lets the app check the answer.
@Generable
struct TipDraft {
  // Generated first on purpose: naming the link before choosing makes a small
  // model pick the note that actually answers the question. Not shown to parents.
  @Guide(description: "In a few words: which note speaks most directly to the parent's question, and why. Prefer a note about the same thing the question is about.")
  var link: String

  @Guide(description: "The id of that note, such as n2. Write none if no note speaks to the question.")
  var noteId: String

  @Guide(description: "Copy the exact words from that note that the tip builds on, word for word. Empty if noteId is none.")
  var quote: String

  @Guide(description: "One small thing the parent can try soon that follows what the quoted words show (if something was left out on a better day, suggest leaving it out again), in one or two short sentences, speaking to the parent. Empty if noteId is none.")
  var tip: String
}

/// `AskModel` backed by Firebase AI Logic hybrid inference.
public struct FirebaseAskModel: AskModel {
  /// A "billing not required" model on the Firebase AI Logic models list.
  public static let defaultCloudModel = "gemini-3.5-flash-lite"

  /// What Apple's on-device model reports as its version.
  static let onDeviceModelVersion = "apple-foundation-models-system-language-model"

  let cloudModelName: String

  public init(cloudModelName: String = FirebaseAskModel.defaultCloudModel) {
    self.cloudModelName = cloudModelName
  }

  public func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    let cloud = ai.geminiModel(name: cloudModelName)
    let system = FirebaseAI.SystemLanguageModel.default
    // A new session per question: no chat history carries over between asks.
    let session = switch route {
    case .hybrid:
      ai.generativeModelSession(model: .hybridModel(primary: system, secondary: cloud), instructions: instructions)
    case .cloudOnly:
      ai.generativeModelSession(model: cloud, instructions: instructions)
    case .onDeviceOnly:
      ai.generativeModelSession(model: system, instructions: instructions)
    }
    let response = try await session.respond(to: prompt, generating: TipDraft.self)
    let version = response.rawResponse.modelVersion ?? ""
    return (
      AskDraft(noteId: response.content.noteId, quote: response.content.quote, tip: response.content.tip),
      version == Self.onDeviceModelVersion ? .onDevice : .cloud,
      version
    )
  }
}

/// On-device availability, for the status line and the "turn on Apple Intelligence" hint.
public enum OnDeviceStatus: Sendable, Equatable {
  case available
  case deviceNotEligible
  case appleIntelligenceOff
  case modelDownloading
  case unavailable

  public static var current: OnDeviceStatus {
    switch FirebaseAI.SystemLanguageModel.default.availability {
    case .available: .available
    case .unavailable(.deviceNotEligible): .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
    case .unavailable(.modelNotReady): .modelDownloading
    case .unavailable: .unavailable
    }
  }
}

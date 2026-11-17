import Foundation
import FirebaseAILogic
import FoundationModels
import HybridAskCore

/// The structured answer both models must return. The model only points and
/// copies; the app checks every field and writes the tip itself.
@Generable
struct TipDraft {
  // Generated first on purpose: naming the link before choosing makes a small
  // model pick the note that actually answers the question. Not shown to parents.
  @Guide(description: "In a few words: which note speaks most directly to the parent's question, and why. Prefer a note about the same thing the question is about.")
  var link: String

  @Guide(description: "The id of that note, such as n2. Write none if no note speaks to the question.")
  var noteId: String

  @Guide(description: "2 to 10 words copied word for word from that note, naming the thing that was done or left out that day. Leave out words like skipped, without or no. Empty if noteId is none.")
  var object: String
}

/// The eval's "before": the model writes the tip itself (MemoUS Ask's approach).
@Generable
struct FreeTip {
  @Guide(description: "The id of the note your tip is tied to, such as n2, or none if the notes do not support a tip.")
  var noteId: String

  @Guide(description: "Your answer to the parent, in plain text.")
  var tip: String
}

/// `AskModel` backed by Firebase AI Logic hybrid inference.
public struct FirebaseAskModel: AskModel, FreeTextAskModel {
  /// A "billing not required" model on the Firebase AI Logic models list.
  public static let defaultCloudModel = CloudModelName.fallback

  let cloudModelName: String

  public init(cloudModelName: String = FirebaseAskModel.defaultCloudModel) {
    self.cloudModelName = cloudModelName
  }

  public func draft(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskDraft, source: AnswerSource, modelVersion: String) {
    // Pointing only copies words from the parent's own notes, and the app writes and
    // checks everything shown, so this is the "content transformation" case Apple's
    // permissive guardrails are for. With the default ones, ordinary notes about sleep
    // or goodbyes were often refused on device. The app's own safety checks still run.
    let response = try await session(instructions: instructions, route: route,
                                     guardrails: .permissiveContentTransformations)
      .respond(to: prompt, generating: TipDraft.self)
    let version = response.rawResponse.modelVersion
    return (
      // The app reads better/worse from the note itself; on device the model got it backwards.
      AskDraft(noteId: response.content.noteId, object: response.content.object, dayWas: .unclear),
      AnswerSource.from(modelVersion: version),
      version
    )
  }

  public func write(instructions: String, prompt: String, route: AskRoute) async throws
    -> (draft: AskFreeDraft, source: AnswerSource, modelVersion: String) {
    // Free writing creates new advice, so it keeps Apple's default guardrails.
    let response = try await session(instructions: instructions, route: route, guardrails: .default)
      .respond(to: prompt, generating: FreeTip.self)
    let version = response.rawResponse.modelVersion
    return (AskFreeDraft(noteId: response.content.noteId, tip: response.content.tip),
            AnswerSource.from(modelVersion: version), version)
  }

  /// A new session per question: no chat history carries over between asks.
  private func session(instructions: String, route: AskRoute,
                       guardrails: FirebaseAI.SystemLanguageModel.Guardrails) -> GenerativeModelSession {
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    let cloud = ai.geminiModel(name: cloudModelName)
    let system = FirebaseAI.SystemLanguageModel(useCase: .general, guardrails: guardrails)
    return switch route {
    case .hybrid:
      ai.generativeModelSession(model: .hybridModel(primary: system, secondary: cloud), instructions: instructions)
    case .cloudOnly:
      ai.generativeModelSession(model: cloud, instructions: instructions)
    case .onDeviceOnly:
      ai.generativeModelSession(model: system, instructions: instructions)
    }
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

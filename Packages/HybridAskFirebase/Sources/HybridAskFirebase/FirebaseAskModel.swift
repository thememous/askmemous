import Foundation
import FirebaseAILogic
import FoundationModels
import HybridAskCore

/// How the day in the chosen note went, by the note's own words.
@Generable
enum DayWasChoice {
  case better, worse, unclear
}

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

  @Guide(description: "Did that day go better or worse, by the note's own words? unclear if it doesn't say.")
  var dayWas: DayWasChoice
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
      AskDraft(noteId: response.content.noteId, object: response.content.object, dayWas: {
        switch response.content.dayWas {
        case .better: .better
        case .worse: .worse
        case .unclear: .unclear
        }
      }()),
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

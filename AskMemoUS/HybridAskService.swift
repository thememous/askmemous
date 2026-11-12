import Foundation
import FirebaseAILogic

/// Where an answer came from. The SDK reports the model that answered in
/// `rawResponse.modelVersion`; Apple's on-device model reports this id.
enum AnswerSource: String, Sendable {
  case onDevice
  case cloud

  static let onDeviceModelVersion = "apple-foundation-models-system-language-model"

  init(modelVersion: String) {
    self = modelVersion == Self.onDeviceModelVersion ? .onDevice : .cloud
  }
}

struct AskAnswer: Sendable {
  let text: String
  let source: AnswerSource
  let modelVersion: String
}

enum OnDeviceStatus: Sendable {
  case available
  case deviceNotEligible
  case appleIntelligenceOff
  case modelDownloading
  case unavailable(String)
}

/// Which models a request may use. `.hybrid` is the product behaviour;
/// the other two exist so the cloud and on-device paths can each be tested
/// without changing iPhone Settings.
enum InferenceRoute: String, CaseIterable, Identifiable, Sendable {
  case hybrid = "Hybrid"
  case cloudOnly = "Cloud only"
  case onDeviceOnly = "On-device only"
  var id: String { rawValue }
}

/// Spike: one hybrid call, on-device first, cloud fallback.
struct HybridAskService {
  /// One place to change the cloud fallback. Must be a "billing not required"
  /// model on the Firebase AI Logic models list (Gemini 2.5 is being retired).
  static let cloudModelName = "gemini-3.5-flash-lite"

  func onDeviceStatus() -> OnDeviceStatus {
    switch FirebaseAI.SystemLanguageModel.default.availability {
    case .available:
      return .available
    case .unavailable(.deviceNotEligible):
      return .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled):
      return .appleIntelligenceOff
    case .unavailable(.modelNotReady):
      return .modelDownloading
    case let .unavailable(reason):
      return .unavailable(String(describing: reason))
    }
  }

  /// Single-turn: a new session per question so no chat history leaks between asks.
  func ask(_ prompt: String, route: InferenceRoute = .hybrid) async throws -> AskAnswer {
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    let cloudModel = ai.geminiModel(name: Self.cloudModelName)
    let systemModel = FirebaseAI.SystemLanguageModel.default
    let session = switch route {
    case .hybrid:
      ai.generativeModelSession(model: .hybridModel(primary: systemModel, secondary: cloudModel))
    case .cloudOnly:
      ai.generativeModelSession(model: cloudModel)
    case .onDeviceOnly:
      ai.generativeModelSession(model: systemModel)
    }
    let response = try await session.respond(to: prompt)
    let version = response.rawResponse.modelVersion ?? ""
    return AskAnswer(
      text: response.content,
      source: AnswerSource(modelVersion: version),
      modelVersion: version
    )
  }
}

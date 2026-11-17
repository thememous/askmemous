import Foundation
import Observation
import FirebaseRemoteConfig
import HybridAskCore
import HybridAskFirebase

/// Three Remote Config values: the cloud model id, the cloud kill switch, and
/// extra safety phrases. A failed fetch keeps the last activated values, or the
/// ones built into the app. Nothing about the journal is sent.
@MainActor
@Observable
final class RemoteAskSettings {
  private(set) var cloudModelName: String = FirebaseAskModel.defaultCloudModel
  /// When false, the app makes no cloud request. The parent's consent is left as they set it.
  private(set) var cloudEnabled: Bool = true
  private(set) var safety: AskSafetyLists = .builtIn

  func fetch() async {
    let remote = RemoteConfig.remoteConfig()
    let settings = RemoteConfigSettings()
    // Fetch on each launch so a kill switch or a new emergency phrase applies
    // the next time the app is opened. Remote Config still keeps the last
    // activated copy on the phone when that fetch fails.
    settings.minimumFetchInterval = 0
    remote.configSettings = settings
    remote.setDefaults([
      "cloud_model": CloudModelName.fallback as NSString,
      "cloud_enabled": NSNumber(value: true),
      "extra_emergency_phrases": "[]" as NSString,
      "extra_health_phrases": "[]" as NSString,
      "extra_distress_phrases": "[]" as NSString,
      "extra_unsafe_tip_rules": "[]" as NSString,
    ])
    do {
      _ = try await remote.fetchAndActivate()
    } catch {
      // The values below are the in-app defaults, or the last ones activated.
    }
    cloudModelName = CloudModelName.resolve(remote["cloud_model"].stringValue)
    cloudEnabled = remote["cloud_enabled"].boolValue
    safety = AskSafety.withExtras(AskSafetyExtras.parsed(
      emergencyJSON: remote["extra_emergency_phrases"].stringValue,
      distressJSON: remote["extra_distress_phrases"].stringValue,
      healthJSON: remote["extra_health_phrases"].stringValue,
      tipRulesJSON: remote["extra_unsafe_tip_rules"].stringValue
    ))
  }
}

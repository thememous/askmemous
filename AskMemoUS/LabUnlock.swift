import Foundation
import Observation

/// The model picker and the eval runner stay hidden in Release until the version
/// line is tapped seven times. Forgotten when the app quits. Debug builds show them.
@MainActor
@Observable
final class LabUnlock {
  private(set) var showsLab: Bool
  private var taps = 0

  init() {
    #if DEBUG
    showsLab = true
    #else
    showsLab = false
    #endif
  }

  func tapVersion() {
    guard !showsLab else { return }
    taps += 1
    if taps >= 7 { showsLab = true }
  }
}

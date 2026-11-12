import SwiftUI
import FirebaseCore
import FirebaseAppCheck

/// App Check must be configured before FirebaseApp.configure().
/// Debug builds use the debug provider (register the printed token in the
/// Firebase console); release builds use App Attest.
final class AskAppCheckFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    #if DEBUG
    return AppCheckDebugProvider(app: app)
    #else
    return AppAttestProvider(app: app)
    #endif
  }
}

@main
struct AskMemoUSApp: App {
  init() {
    AppCheck.setAppCheckProviderFactory(AskAppCheckFactory())
    FirebaseApp.configure()
  }

  var body: some Scene {
    WindowGroup {
      SpikeView()
    }
  }
}

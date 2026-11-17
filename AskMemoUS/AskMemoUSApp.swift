import SwiftUI
import SwiftData
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
  @State private var remote = RemoteAskSettings()
  @State private var lab = LabUnlock()

  init() {
    AppCheck.setAppCheckProviderFactory(AskAppCheckFactory())
    FirebaseApp.configure()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(remote)
        .environment(lab)
        .task { await remote.fetch() }
    }
    .modelContainer(for: [Child.self, JournalNote.self, SavedQuestion.self])
  }
}

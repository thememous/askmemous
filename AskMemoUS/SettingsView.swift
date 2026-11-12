import SwiftUI
import SwiftData
import FirebaseAppCheck
import HybridAskCore

struct SettingsView: View {
  @Bindable var child: Child
  @AppStorage(CloudChecks.consentKey) private var cloudConsent = "undecided"
  @AppStorage(CloudChecks.routeKey) private var route: AskRoute = .hybrid
  @State private var appCheckStatus: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Child") {
          TextField("Name", text: $child.name)
          Toggle("Birthday known", isOn: Binding(
            get: { child.birthdate != nil },
            set: { child.birthdate = $0 ? (child.birthdate ?? .now) : nil }
          ))
          if let birthdate = child.birthdate {
            DatePicker("Birthday", selection: Binding(get: { birthdate }, set: { child.birthdate = $0 }),
                       in: ...Date.now, displayedComponents: .date)
          }
        }

        Section {
          Toggle("Allow cloud checks", isOn: Binding(
            get: { cloudConsent == "allowed" },
            set: { cloudConsent = $0 ? "allowed" : "declined" }
          ))
        } footer: {
          Text(CloudChecks.explainer(childName: child.name))
        }

        Section {
          Picker("Model", selection: $route) {
            ForEach(AskRoute.allCases) { Text($0.rawValue).tag($0) }
          }
        } header: {
          Text("For testing")
        } footer: {
          Text("Hybrid is the normal mode. Cloud only still needs cloud checks to be allowed.")
        }

        #if DEBUG
        Section("App Check (debug)") {
          Button("Get App Check token") { Task { await fetchAppCheckToken() } }
          if let appCheckStatus { Text(appCheckStatus).font(.caption) }
        }
        #endif
      }
      .navigationTitle("Settings")
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
}

import SwiftUI
import SwiftData
import FirebaseAppCheck
import HybridAskCore

struct SettingsView: View {
  @Bindable var child: Child
  @AppStorage(CloudChecks.consentKey) private var cloudConsent = "undecided"
  @AppStorage(CloudChecks.routeKey) private var route: AskRoute = .hybrid
  @State private var appCheckStatus: String?
  @Environment(LabUnlock.self) private var lab
  @Environment(RemoteAskSettings.self) private var remote

  private static let privacyURL = URL(string: "https://github.com/thememous/askmemous/blob/main/PRIVACY.md")!

  private var versionLine: String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
    return "AskMemoUS \(short) (\(build))"
  }

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
          if remote.cloudEnabled {
            Text(CloudChecks.explainer(childName: child.name))
          } else {
            Text("Cloud checks are paused. Nothing is sent to the cloud. Your choice here is saved and applies again when they resume.")
          }
        }

        if lab.showsLab {
          Section {
            Picker("Model", selection: $route) {
              ForEach(AskRoute.allCases) { Text($0.rawValue).tag($0) }
            }
          } header: {
            Text("For testing")
          } footer: {
            Text("Hybrid is the normal mode. Cloud only still needs cloud checks to be allowed.")
          }

          Section {
            NavigationLink("Eval runner") { EvalView() }
          } footer: {
            Text("Runs the fictional test cases through each way of answering and compares the numbers.")
          }
        }

        #if DEBUG
        Section("App Check (debug)") {
          Button("Get App Check token") { Task { await fetchAppCheckToken() } }
          if let appCheckStatus { Text(appCheckStatus).font(.caption) }
        }
        #endif

        Section {
          Link("Privacy policy", destination: Self.privacyURL)
          Button(action: lab.tapVersion) {
            Text(versionLine)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.plain)
        }
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

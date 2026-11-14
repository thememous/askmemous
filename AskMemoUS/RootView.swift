import SwiftUI
import SwiftData

struct RootView: View {
  @Environment(\.modelContext) private var context
  @Query private var children: [Child]
  @State private var tab = TabID.notes

  /// The tab icons (TabIcons.xcassets) are drawn like MemoUS's: one pen line, round
  /// nodes and the four-point star. The selected tab lights its star or nodes gold.
  enum TabID: String { case notes, ask, questions, settings }

  private func icon(_ id: TabID) -> String {
    tab == id ? "tab-\(id.rawValue)-on" : "tab-\(id.rawValue)"
  }

  var body: some View {
    Group {
      if let child = children.first {
        TabView(selection: $tab) {
          Tab("Notes", image: icon(.notes), value: .notes) { NotesView(child: child) }
          Tab("Ask", image: icon(.ask), value: .ask) { AskView(child: child) }
          Tab("Your questions", image: icon(.questions), value: .questions) { QuestionsView(child: child) }
          Tab("Settings", image: icon(.settings), value: .settings) { SettingsView(child: child) }
        }
        .tint(Theme.accent)
      } else {
        ProgressView()
      }
    }
    .task {
      // First run: a fictional sample child and notes, so Ask has something to work with.
      if children.isEmpty {
        SampleJournal.seed(into: context)
        try? context.save()
      }
    }
  }
}

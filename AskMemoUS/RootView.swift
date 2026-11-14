import SwiftUI
import SwiftData

struct RootView: View {
  @Environment(\.modelContext) private var context
  @Query private var children: [Child]

  var body: some View {
    Group {
      if let child = children.first {
        TabView {
          Tab("Notes", systemImage: "square.and.pencil") { NotesView(child: child) }
          Tab("Ask", systemImage: "sparkles") { AskView(child: child) }
          Tab("Your questions", systemImage: "clock") { QuestionsView(child: child) }
          Tab("Settings", systemImage: "gearshape") { SettingsView(child: child) }
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

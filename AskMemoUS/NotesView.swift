import SwiftUI
import SwiftData
import HybridAskCore

/// The journal: short notes about the child, newest first.
struct NotesView: View {
  let child: Child
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalNote.createdAt, order: .reverse) private var notes: [JournalNote]
  @State private var isAdding = false

  var body: some View {
    NavigationStack {
      List {
        if !notes.isEmpty {
          Label {
            Text("Notes that say how the day went and what was different (“slept longer the day we skipped the snack”) can back a tip in Ask.")
          } icon: {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accent)
          }
          .font(.footnote).foregroundStyle(Theme.muted)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.soft, in: .rect(cornerRadius: 14))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(.init(top: 4, leading: 16, bottom: 8, trailing: 16))
        }
        ForEach(notes) { note in
          NoteCard(note: note)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 16, bottom: 5, trailing: 16))
        }
        .onDelete { offsets in
          for i in offsets { context.delete(notes[i]) }
          try? context.save()
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Theme.page)
      .overlay {
        if notes.isEmpty {
          ContentUnavailableView("No notes yet", systemImage: "square.and.pencil",
                                 description: Text("Write a line about \(child.name)'s day."))
        }
      }
      .navigationTitle("\(child.name)'s notes")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add note", systemImage: "plus") { isAdding = true }
        }
      }
      .sheet(isPresented: $isAdding) { AddNoteSheet() }
    }
  }
}

/// One note as a card: the parent's words, the day, and whether Ask can build a tip on it.
private struct NoteCard: View {
  let note: JournalNote

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(note.text).foregroundStyle(Theme.ink)
      HStack(spacing: 8) {
        Text(note.createdAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
          .font(.caption).foregroundStyle(Theme.muted)
        Spacer(minLength: 0)
        if AskCheck.canSupportATip(note.text) {
          Badge(text: "Can back a tip", symbol: "lightbulb.fill")
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeCard()
  }
}

private struct AddNoteSheet: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var date = Date.now
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      Form {
        TextField("What happened today?", text: $text, axis: .vertical)
          .lineLimit(3...8)
          .focused($focused)
        DatePicker("Day", selection: $date, in: ...Date.now, displayedComponents: .date)
      }
      .navigationTitle("New note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            context.insert(JournalNote(text: text.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: date))
            try? context.save()
            dismiss()
          }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .onAppear { focused = true }
    }
    .presentationDetents([.medium, .large])
  }
}

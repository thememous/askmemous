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
        Section {
          ForEach(notes) { note in
            VStack(alignment: .leading, spacing: 4) {
              Text(note.text)
              HStack(spacing: 6) {
                Text(note.createdAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                if AskCheck.canSupportATip(note.text) {
                  Text("·")
                  Label("Can back a tip", systemImage: "lightbulb")
                    .labelStyle(.titleAndIcon)
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .onDelete { offsets in
            for i in offsets { context.delete(notes[i]) }
            try? context.save()
          }
        } footer: {
          Text("Notes that say how the day went and what was different (“slept longer the day we skipped the snack”) are the ones Ask can build a tip on.")
        }
      }
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

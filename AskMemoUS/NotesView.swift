import SwiftUI
import SwiftData
import HybridAskCore

/// The journal: short notes about the child, newest first, grouped by week. Each
/// card shows what the app reads in it, the same way every time and with no model:
/// what was different that day (highlighted) and how the day went.
struct NotesView: View {
  let child: Child
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalNote.createdAt, order: .reverse) private var notes: [JournalNote]
  @State private var isAdding = false
  @State private var opened: JournalNote?

  /// "This week", "Last week", "Earlier", by days since the note.
  private var groups: [(title: String, notes: [JournalNote])] {
    let today = Calendar.current.startOfDay(for: .now)
    func title(_ note: JournalNote) -> String {
      let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: note.createdAt), to: today).day ?? 0
      return days < 7 ? "This week" : days < 14 ? "Last week" : "Earlier"
    }
    var out: [(title: String, notes: [JournalNote])] = []
    for note in notes {
      let t = title(note)
      if out.last?.title == t { out[out.count - 1].notes.append(note) } else { out.append((t, [note])) }
    }
    return out
  }

  var body: some View {
    NavigationStack {
      List {
        if !notes.isEmpty {
          hint
        }
        ForEach(groups, id: \.title) { group in
          Section {
            ForEach(group.notes) { note in
              NoteCard(note: note)
                .contentShape(.rect)
                .onTapGesture { opened = note }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(.init(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .onDelete { offsets in
              for i in offsets { context.delete(group.notes[i]) }
              try? context.save()
            }
          } header: {
            Text(group.title)
              .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
              .textCase(nil)
          }
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
      .sheet(item: $opened) { NoteReadingSheet(note: $0) }
    }
  }

  private var hint: some View {
    Label {
      Text("Ask builds tips only on notes that link what you did to how the day went. The part it reads is highlighted. Tap a note to see why.")
    } icon: {
      Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accent)
    }
    .font(.footnote).foregroundStyle(Theme.muted)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.soft, in: .rect(cornerRadius: 14))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
  }
}

/// The note's text with what was different that day highlighted in the accent colour.
private func highlighted(_ text: String, _ reading: AskCheck.NoteReading) -> AttributedString {
  var out = AttributedString(text)
  out.foregroundColor = Theme.ink
  if let cause = reading.cause, let range = out.range(of: cause) {
    out[range].foregroundColor = Theme.accent
    out[range].font = .body.weight(.semibold)
  }
  return out
}

/// How the day went, as the note's own wording says.
private struct DayTag: View {
  let day: DayWas

  var body: some View {
    switch day {
    case .better: tag("Better day", "arrow.up.right")
    case .worse: tag("Harder day", "arrow.down.right")
    case .unclear: EmptyView()
    }
  }

  private func tag(_ text: String, _ symbol: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: symbol).imageScale(.small)
      Text(text)
    }
    .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
  }
}

/// One note as a card: the parent's words with what Ask reads highlighted, the
/// day, how the day went, and whether Ask can build a tip on it.
private struct NoteCard: View {
  let note: JournalNote

  var body: some View {
    let reading = AskCheck.readNote(note.text)
    VStack(alignment: .leading, spacing: 8) {
      Text(highlighted(note.text, reading))
      HStack(spacing: 10) {
        Text(note.createdAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
          .font(.caption).foregroundStyle(Theme.muted)
        if reading.canBackATip { DayTag(day: reading.day) }
        Spacer(minLength: 0)
        if reading.canBackATip {
          Badge(text: "Can back a tip", symbol: "lightbulb.fill")
        } else {
          Text("Just a note").font(.caption).foregroundStyle(Theme.muted.opacity(0.8))
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeCard()
    .accessibilityElement(children: .combine)
    .accessibilityHint("Shows what Ask reads in this note")
  }
}

/// What the app reads in one note, and why. Written by the app from the note's
/// own words; no model is involved.
private struct NoteReadingSheet: View {
  let note: JournalNote
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let reading = AskCheck.readNote(note.text)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text(highlighted(note.text, reading)).font(.title3)
            Text(note.createdAt, format: .dateTime.weekday(.wide).day().month(.wide))
              .font(.caption).foregroundStyle(Theme.muted)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .themeCard()

          if reading.canBackATip {
            row("Day", value: dayLine(reading), symbol: "sun.max")
            row("What was different", value: reading.cause.map { "“\($0)”" } ?? "–", symbol: "hand.point.right")
            row("A tip from it", value: tipLine(reading), symbol: "lightbulb")
          } else {
            row("Can't back a tip", value: "This note doesn't link something you did to how the day went, so Ask won't build a tip on it. It's still part of the day you remember.", symbol: "text.bubble")
          }

          Label("Read by the app from your words, the same way every time. No AI is involved.",
                systemImage: "checkmark.shield")
            .font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding()
      }
      .background(Theme.page)
      .navigationTitle("What Ask reads")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }

  private func dayLine(_ r: AskCheck.NoteReading) -> String {
    // The clue as the note writes it ("Slept to", not the word list's "slept to").
    let clue = r.clue.map { c in
      " (“\(note.text.range(of: c, options: .caseInsensitive).map { String(note.text[$0]) } ?? c)”)"
    } ?? ""
    switch r.day {
    case .better: return "Went better\(clue)"
    case .worse: return "Was harder\(clue)"
    case .unclear: return "The note doesn't say better or worse"
    }
  }

  private func tipLine(_ r: AskCheck.NoteReading) -> String {
    switch r.tip {
    case .repeatIt: r.day == .better ? "Try that again." : "Only a gentle “try that again”, since the note doesn't say the day went better."
    case .leaveOut: "Leave it out again."
    case .keepIt: "Keep it in next time."
    case nil: "None."
    }
  }

  private func row(_ title: String, value: String, symbol: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        Text(value).foregroundStyle(Theme.ink)
      }
    }
  }
}

struct AddNoteSheet: View {
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

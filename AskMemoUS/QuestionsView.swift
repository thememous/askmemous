import SwiftUI
import SwiftData
import HybridAskCore

/// "Your questions": every question asked, with the answer as it was shown,
/// grouped by the child's age then. Stays on this iPhone.
struct QuestionsView: View {
  let child: Child
  @Environment(\.modelContext) private var context
  @Query(sort: \SavedQuestion.askedAt, order: .reverse) private var saved: [SavedQuestion]
  @State private var confirmDeleteAll = false

  private struct Entry: Identifiable {
    let saved: SavedQuestion
    let record: AskRecord
    var id: UUID { record.id }
  }

  private var groups: [(title: String, entries: [Entry])] {
    let entries = saved.compactMap { s in s.record.map { Entry(saved: s, record: $0) } }
    var order: [String] = []
    var byTitle: [String: [Entry]] = [:]
    for e in entries {
      let title = Self.groupTitle(e.record)
      if byTitle[title] == nil { order.append(title) }
      byTitle[title, default: []].append(e)
    }
    return order.map { ($0, byTitle[$0]!) }
  }

  /// "At 14 months", or the calendar month when no birthdate was given.
  static func groupTitle(_ record: AskRecord) -> String {
    guard let months = record.childAgeMonths else {
      return record.askedAt.formatted(.dateTime.month(.wide).year())
    }
    if months < 24 { return months == 1 ? "At 1 month" : "At \(months) months" }
    let years = months / 12, rest = months % 12
    return rest == 0 ? "At \(years) years" : "At \(years) years \(rest) months"
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(groups, id: \.title) { group in
          Section(group.title) {
            ForEach(group.entries) { entry in
              NavigationLink {
                QuestionDetail(record: entry.record)
              } label: {
                QuestionRow(record: entry.record)
              }
            }
            .onDelete { offsets in
              for i in offsets { context.delete(group.entries[i].saved) }
              try? context.save()
            }
          }
        }
      }
      .overlay {
        if saved.isEmpty {
          ContentUnavailableView("No questions yet", systemImage: "bubble.left.and.text.bubble.right",
                                 description: Text("Questions you ask about \(child.name) are kept here, on this iPhone."))
        }
      }
      .navigationTitle("Your questions")
      .toolbar {
        if !saved.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Delete all", role: .destructive) { confirmDeleteAll = true }
          }
        }
      }
      .confirmationDialog("Delete all saved questions?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
        Button("Delete all", role: .destructive) {
          for s in saved { context.delete(s) }
          try? context.save()
        }
      } message: {
        Text("They're only on this iPhone, so this can't be undone. Your notes stay.")
      }
    }
  }
}

private struct QuestionRow: View {
  let record: AskRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(record.question).font(.body)
      Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
      HStack(spacing: 6) {
        Text(record.askedAt, format: .dateTime.day().month(.abbreviated))
        Text("·")
        SourceLabel(answer: record.answer).labelStyle(.iconOnly)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var summary: String {
    switch record.answer.outcome {
    case let .tip(text, _): text
    case let .floor(reason): FloorText.text(reason, childName: record.childName)
    }
  }
}

private struct QuestionDetail: View {
  let record: AskRecord

  /// Recomputed from the saved question. The line is not stored on the answer, so the eval's tip text stays as it was.
  private var ageLine: AgeContext.Line? {
    AgeContext.line(
      question: record.question,
      child: AskChild(name: record.childName, ageMonths: record.childAgeMonths),
      outcome: record.answer.outcome
    )
  }

  var body: some View {
    Form {
      Section {
        Text(record.question)
      } header: {
        Text("Asked \(record.askedAt.formatted(date: .abbreviated, time: .shortened))")
      } footer: {
        if record.childAgeMonths != nil {
          Text("\(record.childName) was \(QuestionsView.groupTitle(record).dropFirst(3)) old.")
        }
      }
      AnswerSection(answer: record.answer, childName: record.childName, ageLine: ageLine)
    }
    .navigationTitle("Question")
    .navigationBarTitleDisplayMode(.inline)
  }
}

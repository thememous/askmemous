import Foundation
import SwiftData
import HybridAskCore

// The journal lives on this iPhone only (SwiftData, no sync).
// A question leaves the phone only when the parent has allowed cloud checks.

@Model
final class Child {
  var name: String
  /// Nil when the parent hasn't given one: the app then never guesses an age.
  var birthdate: Date?

  init(name: String, birthdate: Date?) {
    self.name = name
    self.birthdate = birthdate
  }

  func ageMonths(at date: Date = .now) -> Int? {
    guard let birthdate else { return nil }
    return max(0, Calendar.current.dateComponents([.month], from: birthdate, to: date).month ?? 0)
  }

  var askChild: AskChild { AskChild(name: name, ageMonths: ageMonths()) }
}

@Model
final class JournalNote {
  @Attribute(.unique) var id: UUID
  var text: String
  var createdAt: Date

  init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
  }

  var askNote: AskNote { AskNote(id: id, text: text, createdAt: createdAt) }
}

/// One question in "Your questions", with the answer exactly as it was shown.
@Model
final class SavedQuestion {
  @Attribute(.unique) var id: UUID
  var askedAt: Date
  var recordData: Data

  init(_ record: AskRecord) {
    id = record.id
    askedAt = record.askedAt
    recordData = (try? JSONEncoder().encode(record)) ?? Data()
  }

  var record: AskRecord? { try? JSONDecoder().decode(AskRecord.self, from: recordData) }

  func replace(with record: AskRecord) {
    askedAt = record.askedAt
    recordData = (try? JSONEncoder().encode(record)) ?? recordData
  }
}

/// A fictional child and notes for the first run. Never real child data.
enum SampleJournal {
  static func seed(into context: ModelContext, now: Date = .now) {
    let day: TimeInterval = 86_400
    let birthdate = Calendar.current.date(byAdding: .month, value: -14, to: now)
    context.insert(Child(name: "Mia", birthdate: birthdate))
    let notes: [(String, Double)] = [
      ("Up at 5:10 again, happy and chatty in the cot.", 2),
      ("Long nap 12–2:30 after the park.", 4),
      ("Slept to 6:40 on the day we skipped the late snack.", 6),
      ("Settled in ten minutes with the room dark and the white noise on.", 9),
      ("Fussier all evening on the day she missed the afternoon nap.", 12),
      ("Finished all her lunch when she sat at the table with us.", 15),
      ("Pointed at the dog and said “da” three times.", 18),
    ]
    for (text, daysAgo) in notes {
      context.insert(JournalNote(text: text, createdAt: now - daysAgo * day))
    }
  }
}

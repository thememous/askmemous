import Foundation

/// General lines about an age, written by a person and bundled with the app.
/// A model never writes them, and they are not about this child.
///
/// Sources, the same ones named in the library file and the README:
/// American Academy of Pediatrics, HealthyChildren.org (sleep, feeding, and media);
/// CDC "Learn the Signs. Act Early." developmental milestones;
/// NHS Start for Life and birth-to-five guidance.
///
/// Each line says what is common. It does not diagnose, give an amount or a dose,
/// or say "normal", "behind" or "should". It does not depend on gender: the app
/// has no gender field.
public enum AgeContext {
  /// One line the answer card can show under a tip, or under the honest floor.
  public struct Line: Sendable, Hashable {
    public let months: Int
    let topic: AskTopic
    public let text: String

    /// "At 14 months". Under one month is "At under 1 month", because "At 0 months" is easy to misread.
    public var label: String {
      switch months {
      case 0: "At under 1 month"
      case 1: "At 1 month"
      default: "At \(months) months"
      }
    }

    /// Kept off the tip's source line, so a note-based tip still says where it came from.
    public func attribution(childName: String) -> String {
      "General information, not about \(childName)'s notes"
    }
  }

  /// Month bands the library is written for. Past 60 months there is no line.
  enum Band: String, CaseIterable, Sendable {
    case m0to3 = "0-3"
    case m4to6 = "4-6"
    case m7to12 = "7-12"
    case m13to18 = "13-18"
    case m19to24 = "19-24"
    case m25to36 = "25-36"
    case m37to60 = "37-60"

    var months: ClosedRange<Int> {
      switch self {
      case .m0to3: 0...3
      case .m4to6: 4...6
      case .m7to12: 7...12
      case .m13to18: 13...18
      case .m19to24: 19...24
      case .m25to36: 25...36
      case .m37to60: 37...60
      }
    }

    init?(ageMonths: Int) {
      guard let band = Self.allCases.first(where: { $0.months.contains(ageMonths) }) else { return nil }
      self = band
    }
  }

  /// Topics with a line. Curiosity and school are left out: nothing solid enough to ship.
  public static let coveredTopics: [AskTopic] = [
    .sleep, .food, .play, .feelings, .talking, .moving, .care, .outings, .screens,
  ]

  /// Where the sentences came from, copied from the library file.
  public static var sources: [String] { library?.sources ?? [] }

  /// The age line for this question and answer, or nil. Nil means the card shows
  /// the tip or the fixed reply alone: no birthday, no topic, no entry for the
  /// band, or a reply the line must not sit beside.
  public static func line(
    question: String,
    child: AskChild,
    outcome: AskOutcome,
    safety: AskSafetyLists = .builtIn
  ) -> Line? {
    guard accompanies(outcome) else { return nil }
    // Emergency, distress and health replies stay exactly as they are.
    guard safety.gate(question: question) == nil else { return nil }
    guard let months = child.ageMonths, let band = Band(ageMonths: months) else { return nil }
    guard let topic = topic(in: question, band: band), let text = entries[topic]?[band] else { return nil }
    return Line(months: months, topic: topic, text: text)
  }

  /// Beside a note-based tip, and beside the honest floor when no note backs one.
  /// Follow-ups that have used every usable note (`noOtherNote`) are that same floor.
  static func accompanies(_ outcome: AskOutcome) -> Bool {
    switch outcome {
    case .tip:
      true
    case .floor(let reason):
      switch reason {
      case .noSupportingNote, .noOtherNote:
        true
      case .emptyQuestion, .noNotes, .medicalTopic, .emergency, .parentDistress,
           .unsafeTip, .modelUnavailable, .cloudNotAllowed:
        false
      }
    }
  }

  /// The library topic the question is about. Word matching is `AskCheck.askedTopics`
  /// (including the "but" rule). When that set has more than one covered topic, the
  /// one whose stem appears first in the same stretch of text wins. Anything else is nil.
  static func topic(in question: String, band: Band) -> AskTopic? {
    let asked = AskCheck.askedTopics(question)
    let covered = asked.filter { entries[$0]?[band] != nil }
    guard !covered.isEmpty else { return nil }
    return earliest(in: decidingText(question), among: covered)
  }

  /// The words `askedTopics` actually judges. Kept in step with that function:
  /// after the last "but", when that part names a topic.
  static func decidingText(_ question: String) -> String {
    let lower = question.lowercased()
    if let turn = lower.range(of: " but ", options: .backwards) {
      let after = String(lower[turn.upperBound...])
      if !AskTopic.of(after).isEmpty { return after }
    }
    return question
  }

  static func earliest(in text: String, among topics: Set<AskTopic>) -> AskTopic? {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    let ordered = AskTopic.allCases.filter { topics.contains($0) }
    for word in words {
      if let topic = ordered.first(where: { topic in
        AskTopic.stems[topic, default: []].contains { word.hasPrefix($0) }
      }) {
        return topic
      }
    }
    return ordered.first
  }

  static var entries: [AskTopic: [Band: String]] { library?.entries ?? [:] }

  static var entryTexts: [String] { entries.values.flatMap(\.values) }

  struct Library {
    let sources: [String]
    let entries: [AskTopic: [Band: String]]
  }

  private static let library: Library? = try? loadBundled()

  private struct File: Decodable {
    let sources: [String]
    let entries: [String: [String: String]]
  }

  static func loadBundled() throws -> Library {
    guard let url = Bundle.module.url(forResource: "age-context", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    var entries: [AskTopic: [Band: String]] = [:]
    for (topicName, bands) in file.entries {
      guard let topic = AskTopic(rawValue: topicName) else { throw CocoaError(.coderInvalidValue) }
      var parsed: [Band: String] = [:]
      for (bandName, text) in bands {
        guard let band = Band(rawValue: bandName) else { throw CocoaError(.coderInvalidValue) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CocoaError(.coderInvalidValue) }
        parsed[band] = trimmed
      }
      entries[topic] = parsed
    }
    return Library(sources: file.sources, entries: entries)
  }
}

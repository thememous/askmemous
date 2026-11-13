import Foundation

/// Builds the instructions and prompt. Notes get short ids (n1, n2, …) so a
/// small on-device model can point at one reliably; the app maps the id back.
public enum AskPrompt {
  public static let noteLimit = 6
  static let noteMaxChars = 240
  static let questionMaxChars = 400

  /// Short ids in the order the notes were given (best match first, from `AskRetrieval`).
  public struct Numbered: Sendable {
    public let ids: [String: AskNote]
    public let lines: [String]
  }

  /// What every model sees instead of the child's name. The name is never sent to
  /// any model, on-device or cloud: tips don't need it, and the cloud shouldn't have it.
  public static let childStandIn = "your child"

  /// Replaces the child's name (whole word, as written) with "your child".
  /// Case-sensitive on purpose, so a child called May doesn't change "may".
  public static func redact(_ text: String, name: String) -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return text }
    let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}])"
    return text.replacingOccurrences(of: pattern, with: childStandIn, options: .regularExpression)
  }

  public static func number(_ notes: [AskNote], now: Date, childName: String = "") -> Numbered {
    let recent = notes
      .filter { !clip($0.text, noteMaxChars).isEmpty }
      .prefix(noteLimit)
    var ids: [String: AskNote] = [:]
    var lines: [String] = []
    for (index, note) in recent.enumerated() {
      let id = "n\(index + 1)"
      ids[id] = note
      let category = clip(note.category ?? "", 40)
      let stamp = [when(note.createdAt, now: now), category.isEmpty ? nil : category]
        .compactMap { $0 }
        .joined(separator: " · ")
      lines.append("\(id) [\(stamp)] \(clip(redact(note.text, name: childName), noteMaxChars))")
    }
    return Numbered(ids: ids, lines: lines)
  }

  public static func instructions(for child: AskChild) -> String {
    // Age shapes nothing here: the model picks words, it doesn't write advice.
    let rules = [
      "You help a parent find one thing in their own notes worth trying again.",
      "You do not write advice. The app writes the tip from what you pick.",
      "Choose the ONE note that speaks most directly to the question (same topic first) and give its id in noteId.",
      "Every note below ties something done, left out or enjoyed to how things went. Pick the one most about the same thing as the question.",
      "In object, copy 2 to 10 words from that note, word for word, naming the thing that was done or left out that day. Do not include words like skipped, without or no; the app reads those from the note.",
      "If no note is about the same thing as the question, set noteId to none, object empty.",
      "Never invent anything that is not in the notes.",
    ]
    return rules.joined(separator: "\n")
  }

  public static func prompt(question: String, child: AskChild, numbered: Numbered) -> String {
    let header = child.ageMonths.map { "\(childStandIn), \($0) months old" } ?? childStandIn
    return """
    Child: \(header)
    Notes (most relevant first):
    \(numbered.lines.joined(separator: "\n"))

    Parent's question: \(clip(redact(question, name: child.name), questionMaxChars))
    """
  }

  static func guidance(_ band: AgeBand) -> String {
    switch band {
    case .infant:
      "The child is an infant. Suggest closeness, soothing, and noticing. No games, lessons, or skills to practise."
    case .toddler:
      "The child is a toddler. Suggest short, physical, everyday ideas. No schoolwork or worksheets."
    case .earlySchool:
      "The child is a young child. Pretend play, turn-taking, curiosity, and stories fit. No independent homework."
    case .schoolAge:
      "The child is school-age. Friends, practice, and unwinding after the day fit. No infant soothing or toddler games."
    }
  }

  static func when(_ date: Date, now: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
    ).day ?? 0
    switch days {
    case ...0: return "today"
    case 1: return "1d ago"
    case ..<14: return "\(days)d ago"
    default:
      let f = DateFormatter()
      f.calendar = calendar
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd"
      return f.string(from: date)
    }
  }

  static func clip(_ value: String, _ max: Int) -> String {
    let s = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return s.count <= max ? s : String(s.prefix(max)) + "…"
  }
}

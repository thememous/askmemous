import Foundation

/// Builds the instructions and prompt. Notes get short ids (n1, n2, …) so a
/// small on-device model can point at one reliably; the app maps the id back.
public enum AskPrompt {
  public static let noteLimit = 6
  static let noteMaxChars = 240
  static let questionMaxChars = 400

  /// Short ids in the order the notes are listed (newest first).
  public struct Numbered: Sendable {
    public let ids: [String: AskNote]
    public let lines: [String]
  }

  public static func number(_ notes: [AskNote], now: Date) -> Numbered {
    let recent = notes
      .filter { !clip($0.text, noteMaxChars).isEmpty }
      .sorted { $0.createdAt > $1.createdAt }
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
      lines.append("\(id) [\(stamp)] \(clip(note.text, noteMaxChars))")
    }
    return Numbered(ids: ids, lines: lines)
  }

  public static func instructions(for child: AskChild) -> String {
    var rules = [
      "You help a parent decide one small thing to try with their child.",
      "Speak to the parent, never to the child. Do not greet anyone.",
      "Choose the ONE note that speaks most directly to the question (same topic first) and give its id in noteId.",
      "If no note is about the same thing as the question, set noteId to none and leave tip empty.",
      "For 'what could I try' questions, prefer a note that shows what was different on a better day, and build the tip on that difference.",
      "The tip is one or two short sentences: one thing they can try soon. No lists. No second tip.",
      "Only use what the notes say. Do not invent events, interests, milestones, or delays.",
      "Do not diagnose, name conditions, or suggest medicine.",
    ]
    if let band = child.band {
      rules.append(guidance(band))
    } else {
      rules.append("No birthdate is known. Do not guess an age or give age-specific activities.")
    }
    return rules.joined(separator: "\n")
  }

  public static func prompt(question: String, child: AskChild, numbered: Numbered) -> String {
    let header = child.ageMonths.map { "\(child.name), \($0) months old" } ?? child.name
    return """
    Child: \(header)
    Notes (newest first):
    \(numbered.lines.joined(separator: "\n"))

    Parent's question: \(clip(question, questionMaxChars))
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

import Foundation

/// Checks a model draft before a parent sees it. The model only proposes;
/// the app decides. Anything that fails becomes a fixed reply.
public enum AskCheck {
  /// Words that turn a tip into medical advice. Matched as word prefixes.
  static let medicalStems = [
    "diagnos", "disorder", "autis", "adhd", "syndrome", "melatonin",
    "medicat", "medicine", "dosage", "supplement", "therap",
  ]
  /// Whole words only ("delay the snack" is a fine tip; "is she delayed" is not ours to answer).
  static let medicalWords: Set<String> = ["delayed", "dose", "doses", "diagnosis"]

  static let greetingStarts = ["hello", "hi ", "hi,", "hey", "dear", "good morning", "good evening"]

  public static let maxSentences = 2

  public static func review(
    _ draft: AskDraft,
    notes: [String: AskNote],
    child: AskChild
  ) -> AskOutcome {
    let id = draft.noteId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard id != "none", let note = notes[id] else { return .floor(.noSupportingNote) }

    var tip = tidy(draft.tip)
    tip = dropGreeting(tip, childName: child.name)
    tip = firstSentences(tip, maxSentences)
    guard !tip.isEmpty else { return .floor(.noSupportingNote) }
    if mentionsMedical(tip) { return .floor(.medicalTopic) }
    if let quote = draft.quote {
      guard quoteIsInNote(quote, note: note) else { return .floor(.noSupportingNote) }
      guard keepsDirection(quote: quote, tip: tip) else { return .floor(.noSupportingNote) }
    }
    return .tip(text: tip, basedOn: note)
  }

  /// A question that asks for medical judgement gets the fixed reply before any model runs.
  public static func mentionsMedical(_ text: String) -> Bool {
    let words = text.lowercased().split { !$0.isLetter }
    return words.contains { word in
      medicalWords.contains(String(word)) || medicalStems.contains { word.hasPrefix($0) }
    }
  }

  /// Collapse whitespace and strip list markers so a bulleted answer reads as prose.
  static func tidy(_ text: String) -> String {
    let lines = text
      .components(separatedBy: .newlines)
      .map { line -> String in
        var l = line.trimmingCharacters(in: .whitespaces)
        while let first = l.first, "-•*".contains(first) {
          l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let range = l.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
          l.removeSubrange(range)
        }
        return l
      }
      .filter { !$0.isEmpty }
    return lines.joined(separator: " ")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// Drops a leading sentence that greets someone ("Hello, Mia." / "Hi there!").
  static func dropGreeting(_ text: String, childName: String) -> String {
    let sentences = splitSentences(text)
    guard let first = sentences.first else { return text }
    let lower = first.lowercased()
    let name = childName.lowercased()
    let isGreeting = greetingStarts.contains { lower.hasPrefix($0) }
      || (!name.isEmpty && lower.hasPrefix(name + ",") && first.count < 30)
    return isGreeting ? sentences.dropFirst().joined(separator: " ") : text
  }

  static func firstSentences(_ text: String, _ n: Int) -> String {
    splitSentences(text).prefix(n).joined(separator: " ")
  }

  static func splitSentences(_ text: String) -> [String] {
    var out: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
      if let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty { out.append(s) }
    }
    return out.isEmpty && !text.isEmpty ? [text] : out
  }

  // MARK: - Quote and direction

  /// The quote must be real words from the note (at least two), ignoring case,
  /// spacing and punctuation.
  public static func quoteIsInNote(_ quote: String, note: AskNote) -> Bool {
    let q = normalized(quote)
    guard q.split(separator: " ").count >= 2 else { return false }
    return normalized(note.text).contains(q)
  }

  /// Word starts that mean "left something out" in a note…
  static let leftOutStems = ["skip", "without", "stopp", "dropp", "avoid", "cut", "remov"]
  static let leftOutWords: Set<String> = ["no", "not", "never", "didn", "didnt", "don", "dont", "none"]
  /// …and in a tip, ways of saying "leave it out" or "change it".
  static let changeStems = leftOutStems + ["leave", "hold", "pause", "less", "fewer", "earlier",
                                           "instead", "smaller", "lighter", "move", "swap", "replac"]

  /// When the note's quote is about leaving something out, the tip must also
  /// leave it out or change it. "Skipped the late snack" must never become
  /// "offer the late snack again".
  public static func keepsDirection(quote: String, tip: String) -> Bool {
    guard hasAny(quote, stems: leftOutStems, words: leftOutWords) else { return true }
    return hasAny(tip, stems: changeStems, words: leftOutWords)
  }

  static func hasAny(_ text: String, stems: [String], words: Set<String>) -> Bool {
    let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
    return tokens.contains { t in words.contains(t) || stems.contains { t.hasPrefix($0) } }
  }

  static func normalized(_ text: String) -> String {
    text.lowercased()
      .map { $0.isLetter || $0.isNumber ? $0 : " " }
      .reduce(into: "") { $0.append($1) }
      .split(separator: " ").joined(separator: " ")
  }
}

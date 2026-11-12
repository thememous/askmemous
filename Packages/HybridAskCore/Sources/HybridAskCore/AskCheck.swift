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
}

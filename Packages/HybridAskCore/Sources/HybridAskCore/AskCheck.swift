import Foundation

/// Turns a model draft into what a parent sees. The model only points at a note,
/// copies a few words from it and says whether that day went better or worse.
/// The app checks each of those, works out the direction itself, and writes the
/// tip sentence. Anything that doesn't hold up becomes a fixed reply.
public enum AskCheck {

  public static func review(_ draft: AskDraft, notes: [String: AskNote], child: AskChild) -> AskOutcome {
    let id = draft.noteId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard id != "none", let note = notes[id] else { return .floor(.noSupportingNote) }

    // The model saw the note with the name replaced, so check against that same text.
    let seen = AskPrompt.redact(note.text, name: child.name)
    guard canSupportATip(seen), let part = decidingPart(seen) else { return .floor(.noSupportingNote) }

    // 1. The object must be the note's own words, from the part of the note that
    //    decides. We show the note's text, not the model's.
    guard let found = locate(draft.object, in: part) else { return .floor(.noSupportingNote) }

    // 2. How did that day go? Only the note's own wording decides, and a model that
    //    disagrees with the note is refused. A note that names no better or worse
    //    ("Said 'ball' when we played catch") can only back trying the same thing
    //    again, and the tip doesn't claim the day went better.
    let day: DayWas
    let stated: Bool
    switch reading(part) {
    case .better: (day, stated) = (.better, true)
    case .worse: (day, stated) = (.worse, true)
    case .silent: (day, stated) = (.better, false)
    case .mixed: return .floor(.noSupportingNote)
    }
    guard draft.dayWas == day || draft.dayWas == .unclear else { return .floor(.noSupportingNote) }
    if !stated && found.leftOut { return .floor(.noSupportingNote) }

    // 3. The app decides the direction from the note itself.
    guard let action = action(day: day, leftOut: found.leftOut) else { return .floor(.noSupportingNote) }

    // 4. The app writes the sentence.
    let tip = TipText.compose(action: action, object: found.span, dayStated: stated, leftOut: found.leftOut, note: part)
    if mentionsMedical(tip) { return .floor(.medicalTopic) }
    return .tip(text: tip, basedOn: note)
  }

  static func action(day: DayWas, leftOut: Bool) -> TipAction? {
    switch (day, leftOut) {
    case (.better, false): .repeatIt
    case (.better, true): .leaveOut
    case (.worse, true): .keepIt
    default: nil // a worse day where something was done: nothing in the note to repeat
    }
  }

  // MARK: - Which notes can support a tip

  /// Words that tie something done or left out to how the day went
  /// ("slept to 6:40 on the day we skipped the snack", "settled faster with the room dark").
  static let linkWords: Set<String> = ["when", "after", "with", "without", "because", "since", "once",
                                       "skipped", "skip", "skipping", "missed", "stopped", "dropped", "forgot",
                                       "until", "before", "if"]

  /// "Loved the crinkly book": liking something is its own link to it.
  static let preferenceWords: Set<String> = ["loved", "loves", "enjoyed", "enjoys", "liked", "likes"]

  /// A note can support a tip if the part of it that decides (see `decidingPart`)
  /// links something done or left out to how things went. "Up at 5:10 again,
  /// happy and chatty" links nothing, so the model never sees it as a choice.
  public static func canSupportATip(_ text: String) -> Bool {
    guard let part = decidingPart(text) else { return false }
    return tokens(part).contains { linkWords.contains($0) || preferenceWords.contains($0) }
  }

  /// The part of a note that says how things went. Usually the whole note. A
  /// note with better and worse words together counts only if it turns: at the
  /// last "but", or failing that at the last comma or semicolon where the
  /// wording changes direction ("Upset after the dentist, calm again once we
  /// read his book"). Only the part after the turn counts: it says what helped.
  /// Otherwise mixed notes can't back a tip.
  public static func decidingPart(_ text: String) -> String? {
    guard reading(text) == .mixed else { return text }
    func clean(_ r: Reading) -> Bool { r == .better || r == .worse }
    if let turn = text.range(of: #"\bbut\b"#, options: [.regularExpression, .caseInsensitive, .backwards]) {
      let after = text[turn.upperBound...].trimmingCharacters(in: .whitespaces)
      return clean(reading(after)) ? after : nil
    }
    // Added 2026-11-13 after held-out n07 (see docs/EVAL_LOG.md).
    if let turn = text.range(of: #"[,;]"#, options: [.regularExpression, .backwards]) {
      let before = String(text[..<turn.lowerBound])
      let after = text[turn.upperBound...].trimmingCharacters(in: .whitespaces)
      let a = reading(after), b = reading(before)
      if clean(a), clean(b), a != b { return after }
    }
    return nil
  }

  // MARK: - Finding the object in the note

  /// Words that, just before the object, mean it was left out that day.
  static let leftOutWords: Set<String> = ["skipped", "skip", "skipping", "without", "no", "stopped",
                                          "dropped", "missed", "forgot", "cut"]

  /// Finds the object in the note: at least 80% of its words, in order, with at
  /// most two other words between matches. Returns the note's own text for that
  /// stretch and whether it was left out that day.
  public static func locate(_ object: String, in noteText: String) -> (span: String, leftOut: Bool)? {
    var obj = tokens(object)
    var markedLeftOut = false
    while let first = obj.first, leftOutWords.contains(first) {
      markedLeftOut = true
      obj.removeFirst()
    }
    guard obj.count >= 2, obj.count <= 14 else { return nil }

    // Note tokens, each remembering which original word it came from.
    let original = noteText.split(whereSeparator: \.isWhitespace).map(String.init)
    var noteTokens: [(token: String, word: Int)] = []
    for (index, word) in original.enumerated() {
      for t in tokens(word) { noteTokens.append((t, index)) }
    }

    var best: (first: Int, last: Int, hits: Int)?
    for start in noteTokens.indices {
      var cursor = start, hits = 0, first: Int?, last = start
      for token in obj {
        var j = cursor
        while j < noteTokens.count, j - cursor <= 2, noteTokens[j].token != token { j += 1 }
        if j < noteTokens.count, noteTokens[j].token == token {
          hits += 1
          if first == nil { first = j }
          last = j
          cursor = j + 1
        }
      }
      if let first, hits > (best?.hits ?? 0) { best = (first, last, hits) }
    }
    guard let best, Double(best.hits) / Double(obj.count) >= 0.8, best.hits >= 2 else { return nil }

    var firstWord = noteTokens[best.first].word
    let lastWord = noteTokens[best.last].word
    // "after the park": the thing is the park, not the word that links it.
    while firstWord < lastWord, tokens(original[firstWord]).allSatisfy(linkWords.contains),
          !tokens(original[firstWord]).contains(where: leftOutWords.contains) {
      firstWord += 1
    }
    // "fed and fell asleep with": the copy stopped before the thing itself.
    if tokens(original[lastWord]).allSatisfy(linkWords.contains) { return nil }
    // "the day we skipped the late snack": the thing is what comes after "skipped".
    var leftOutInside = false
    if let cut = (firstWord...lastWord).last(where: { w in tokens(original[w]).contains(where: leftOutWords.contains) }),
       cut < lastWord {
      firstWord = cut + 1
      leftOutInside = true
    }
    let span = original[firstWord...lastWord]
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    let before = noteTokens[max(0, best.first - 3)..<best.first].map(\.token)
    return (span, markedLeftOut || leftOutInside || before.contains(where: leftOutWords.contains))
  }

  // MARK: - Better or worse day, from the note's own words

  static let betterPhrases = ["didn t cry", "without crying", "no tears", "didn t fuss", "stayed asleep",
                              "went down easier", "slept to", "slept longer", "slept through"]
  static let betterWords: Set<String> = ["slept", "settled", "calm", "calmer", "happy", "happier", "easier",
                                         "easy", "fine", "smooth", "finished", "shared", "laughed", "loved",
                                         "longer", "better", "relaxed", "content", "quickly"]
  static let worseWords: Set<String> = ["fussy", "fussier", "cried", "crying", "meltdown", "melted", "tantrum",
                                        "grumpy", "upset", "woke", "refused", "pushed", "hard", "harder",
                                        "fight", "screamed", "worse", "shorter", "clingy", "tears"]

  enum Reading { case better, worse, silent, mixed }

  static func reading(_ text: String) -> Reading {
    var padded = " " + normalized(text) + " "
    var better = 0
    for phrase in betterPhrases where padded.contains(" \(phrase) ") {
      better += 1
      padded = padded.replacingOccurrences(of: " \(phrase) ", with: " ")
    }
    let words = padded.split(separator: " ").map(String.init)
    better += words.filter(betterWords.contains).count
    let worse = words.filter(worseWords.contains).count
    switch (better > 0, worse > 0) {
    case (true, false): return .better
    case (false, true): return .worse
    case (false, false): return .silent
    case (true, true): return .mixed
    }
  }

  /// `.better` / `.worse` only when the wording points one way; mixed or silent notes are `.unclear`.
  public static func dayFromWording(_ text: String) -> DayWas {
    switch reading(text) {
    case .better: .better
    case .worse: .worse
    case .silent, .mixed: .unclear
    }
  }

  // MARK: - Why this note

  /// "Why this note?", answered by the app from the note's own words. No model.
  public static func whyThisNote(_ text: String) -> String {
    let part = decidingPart(text) ?? text
    let read = reading(part)
    let clue = clueWord(in: part, for: read)
    let quoted = clue.map { " (“\($0)”)" } ?? ""
    let lead: String
    switch read {
    case .better:
      lead = "This note says the day went better\(quoted) and says what was different that day. The tip asks you to try that again."
    case .worse:
      lead = "This note says the day was harder\(quoted) and says what was missing that day. The tip asks you to keep it in."
    case .silent, .mixed:
      lead = "This note ties what happened to something you did that day. It doesn't say the day went better, so the tip only suggests trying it again."
    }
    return lead + " The app picked this note's own words and wrote the tip itself; no AI wrote it."
  }

  /// The word in the note that says how the day went ("Settled", "Fussy").
  static func clueWord(in text: String, for read: Reading) -> String? {
    let lower = " " + normalized(text) + " "
    if read == .better, let phrase = betterPhrases.first(where: { lower.contains(" \($0) ") }) {
      return phrase.replacingOccurrences(of: " t ", with: "'t ")
    }
    let wanted: Set<String> = read == .better ? betterWords : read == .worse ? worseWords : []
    for word in text.split(whereSeparator: \.isWhitespace) {
      let t = tokens(String(word))
      if t.count == 1, wanted.contains(t[0]) { return word.trimmingCharacters(in: .punctuationCharacters) }
    }
    return nil
  }

  // MARK: - Medical wording

  static let medicalStems = [
    "diagnos", "disorder", "autis", "adhd", "syndrome", "melatonin",
    "medicat", "medicine", "dosage", "supplement", "therap",
  ]
  /// Whole words only ("delay the snack" is fine; "is she delayed" is not ours to answer).
  static let medicalWords: Set<String> = ["delayed", "dose", "doses", "diagnosis"]

  public static func mentionsMedical(_ text: String) -> Bool {
    let words = text.lowercased().split { !$0.isLetter }
    return words.contains { word in
      medicalWords.contains(String(word)) || medicalStems.contains { word.hasPrefix($0) }
    }
  }

  // MARK: - Text helpers

  static func normalized(_ text: String) -> String {
    text.lowercased()
      .map { $0.isLetter || $0.isNumber ? $0 : " " }
      .reduce(into: "") { $0.append($1) }
      .split(separator: " ").joined(separator: " ")
  }

  static func tokens(_ text: String) -> [String] {
    normalized(text).split(separator: " ").map(String.init)
  }
}

/// The tip sentences. Written by the app, never by a model.
///
/// The model copies words from a note, often the whole note: "Settled faster
/// with the room dark and white noise on". Repeating that back reads like a
/// form. So the app finds the cause inside the copied words (what comes after
/// "when", "after", "with"…), turns "we" into "you", and writes the sentence
/// around it: "Your note says things went better with the room dark and white
/// noise on. Try that again this week." When there's no clean cause to name,
/// the tip says "what you did that day": the note is shown right under it.
public enum TipText {
  static let determiners: Set<String> = ["the", "a", "an", "her", "his", "their", "our", "some", "same",
                                         "that", "this", "your", "one", "two", "three", "four", "five", "ten"]
  /// Words that start the cause: "settled when we set a timer", "calmer after the park".
  static let clauseLinks: Set<String> = ["when", "after", "once", "because", "since", "before", "until", "if"]
  /// Words that start the cause only at its start: "with the room dark", "at the kitchen table".
  static let placeLinks: Set<String> = ["with", "at", "in", "on"]
  static let subjects: Set<String> = ["we", "i", "she", "he", "they", "you", "your"]
  static let toParent: [String: String] = ["we": "you", "i": "you", "us": "you", "our": "your",
                                           "my": "your", "me": "you"]

  static func bare(_ w: String) -> String { AskCheck.tokens(w).joined(separator: " ") }

  /// The copied words, widened to the note's own lead-in: "sang the animal song"
  /// is "when we sang the animal song" in the note; "room dark" is "with the room dark".
  static func widened(_ span: String, in note: String?) -> String {
    guard let note, let r = note.range(of: span, options: .caseInsensitive) else { return span }
    var before = note[..<r.lowerBound].split(whereSeparator: \.isWhitespace).map(String.init)
    var lead: [String] = []
    if let w = before.last, !w.hasSuffix(","), !w.hasSuffix(";"), !w.hasSuffix("."),
       determiners.contains(bare(w)) || subjects.contains(bare(w)) {
      lead.insert(w, at: 0); before.removeLast()
    }
    if let w = before.last, !w.hasSuffix(","), !w.hasSuffix(";"), !w.hasSuffix("."),
       clauseLinks.contains(bare(w)) || placeLinks.contains(bare(w)) || AskCheck.preferenceWords.contains(bare(w)) {
      lead.insert(w, at: 0)
    } else if lead.first.map({ subjects.contains(bare($0)) }) == true {
      return span // "she sang": no link to the day, leave it as copied
    }
    return (lead + [String(note[r])]).joined(separator: " ")
  }

  enum Cause { case linked(link: String, thing: String), liked(verb: String, thing: String), plain(String) }

  /// The cause named in the copied words. `nil` when the words only say what
  /// happened ("Slept to 6:40").
  static func cause(in span: String, leftOut: Bool, note: String?) -> Cause? {
    var words = (leftOut ? span : widened(span, in: note)).split(whereSeparator: \.isWhitespace).map(String.init)
    // Stop at the first comma or semicolon: "the crinkly book, kept grabbing the pages".
    if let cut = words.firstIndex(where: { $0.hasSuffix(",") || $0.hasSuffix(";") }) {
      words = Array(words[...cut])
    }
    func tidy(_ ws: ArraySlice<String>) -> String? {
      let t = ws.map { w -> String in
        let core = w.trimmingCharacters(in: .punctuationCharacters)
        guard let swap = toParent[core.lowercased()] else { return w }
        return w.replacingOccurrences(of: core, with: swap)
      }
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
      return t.isEmpty ? nil : t
    }
    guard let first = words.first.map(bare) else { return nil }
    if leftOut { return tidy(words[...]).map(Cause.plain) }
    if AskCheck.preferenceWords.contains(first) {
      return tidy(words.dropFirst()).map { .liked(verb: first, thing: $0) }
    }
    if clauseLinks.contains(first) || placeLinks.contains(first) {
      return tidy(words.dropFirst()).map { .linked(link: first, thing: $0) }
    }
    if determiners.contains(first) || first.first?.isNumber == true {
      return tidy(words[...]).map(Cause.plain)
    }
    let at0 = words.firstIndex { clauseLinks.contains(bare($0)) }
    // "splashing in the washing-up bowl" names the thing itself.
    if at0 == nil, first.hasSuffix("ing"), first.count > 4 {
      return tidy(words[...]).map(Cause.plain)
    }
    let at = words.firstIndex { clauseLinks.contains(bare($0)) } ?? words.firstIndex { bare($0) == "with" }
    if let at, at + 1 < words.count {
      return tidy(words[(at + 1)...]).map { .linked(link: bare(words[at]), thing: $0) }
    }
    return nil
  }

  /// `dayStated` is false when the note doesn't say the day went better or worse,
  /// only what happened alongside: the tip then doesn't claim a better day.
  public static func compose(action: TipAction, object: String, dayStated: Bool = true,
                              leftOut: Bool = false, note: String? = nil) -> String {
    let found = cause(in: object, leftOut: leftOut || action != .repeatIt, note: note)
    if action == .repeatIt, case let .liked(verb, thing) = found {
      return "Your note says your child \(verb) \(thing). Try that again this week."
    }
    if !dayStated {
      switch found {
      case let .linked(link, thing): return "In your note, this happened \(link) \(thing). Try that again this week."
      case let .plain(thing): return "Try \(thing) again this week. It's in your note."
      default: return "Try doing what you did that day again this week."
      }
    }
    let thing: String? = switch found {
    case let .plain(t), let .linked(_, t), let .liked(_, t): t
    case nil: nil
    }
    switch action {
    case .repeatIt:
      switch found {
      case let .linked(link, thing): return "Your note says things went better \(link) \(thing). Try that again this week."
      case let .plain(thing): return "Try \(thing) again this week. It's in your note from a better day."
      default: return "Try doing what you did that day again this week. Your note shows it went better."
      }
    case .leaveOut:
      guard let thing else { return "Try leaving out what you left out that day again this week. Your note shows it went better." }
      return "Your note says things went better on the day without \(thing). Try leaving it out again this week."
    case .keepIt:
      guard let thing else { return "Try keeping in what you missed that day. Your note shows the day without it was harder." }
      return "Your note says the day without \(thing) was harder. Try keeping it in this week."
    }
  }
}

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
    let toks = tokens(part)
    return toks.indices.contains { isLink(toks, at: $0) || preferenceWords.contains(toks[$0]) }
  }

  /// A link word, except "no", "stopped" or "without" before crying or fussing:
  /// "No crying in the car seat" says how the day went and links nothing.
  static func isLink(_ toks: [String], at i: Int) -> Bool {
    linkWords.contains(toks[i]) && !negatesDistress(toks, at: i)
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

  /// Crying and fussing. After "no", "stopped" or "without" they say the day went
  /// better ("No crying in the car seat", "Stopped crying when we turned the seat"),
  /// and nothing was left out. Added 2026-11-14 (see docs/EVAL_LOG.md).
  static let distressWords: Set<String> = ["crying", "cry", "cried", "fussing", "fuss", "fussed", "tears",
                                           "tantrum", "tantrums", "meltdown", "meltdowns", "screaming",
                                           "screamed", "whining", "whinging"]

  /// "no crying", "stopped fussing", "without tears".
  static func negatesDistress(_ toks: [String], at i: Int) -> Bool {
    leftOutWords.contains(toks[i]) && i + 1 < toks.count && distressWords.contains(toks[i + 1])
  }

  /// A left-out word that really leaves something out ("skipped the snack"), not
  /// one that says the crying stopped.
  static func marksLeftOut(_ toks: [String], at i: Int) -> Bool {
    leftOutWords.contains(toks[i]) && !negatesDistress(toks, at: i)
  }

  /// Finds the object in the note: at least 80% of its words, in order, with at
  /// most two other words between matches. Returns the note's own text for that
  /// stretch and whether it was left out that day.
  public static func locate(_ object: String, in noteText: String) -> (span: String, leftOut: Bool)? {
    var obj = tokens(object)
    var markedLeftOut = false
    while !obj.isEmpty, marksLeftOut(obj, at: 0) {
      markedLeftOut = true
      obj.removeFirst()
    }
    // One word ("bunny") still points into the note: read it as the note's own clause.
    if obj.count == 1, let clause = clause(around: obj[0], in: noteText) {
      guard let found = locate(clause, in: noteText) else { return nil }
      return (found.span, found.leftOut || markedLeftOut)
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
    let allTokens = noteTokens.map(\.token)
    /// Whether a word of the note leaves something out (its token, read with the next one).
    func leavesOut(_ w: Int) -> Bool {
      noteTokens.indices.contains { noteTokens[$0].word == w && marksLeftOut(allTokens, at: $0) }
    }
    // "fed and fell asleep with": the copy stopped before the thing itself.
    if tokens(original[lastWord]).allSatisfy(linkWords.contains) { return nil }
    // "the day we skipped the late snack": the thing is what comes after "skipped".
    var leftOutInside = false
    if let cut = (firstWord...lastWord).last(where: leavesOut), cut < lastWord {
      firstWord = cut + 1
      leftOutInside = true
    }
    let span = original[firstWord...lastWord]
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    // "skipped the": the copy stopped before the thing itself.
    if tokens(span).allSatisfy({ TipText.determiners.contains($0) || TipText.subjects.contains($0) }) { return nil }
    let leftOutBefore = (max(0, best.first - 3)..<best.first).contains { marksLeftOut(allTokens, at: $0) }
    return (span, markedLeftOut || leftOutInside || leftOutBefore)
  }

  /// The clause of the note around a single copied word: from the nearest link word
  /// before it ("when she brought her bunny", "skipped the bath"), or the whole clause
  /// when nothing links it ("Shared her blocks with Sam when we set a timer for turns").
  /// Nil when the word isn't in the note, or is too small to point at anything.
  static func clause(around word: String, in noteText: String) -> String? {
    guard word.count >= 3, !linkWords.contains(word), !TipText.determiners.contains(word),
          !TipText.subjects.contains(word) else { return nil }
    let words = noteText.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let at = words.firstIndex(where: { tokens($0).contains(word) }) else { return nil }
    let ends: (String) -> Bool = { $0.hasSuffix(",") || $0.hasSuffix(";") || $0.hasSuffix(".") }
    var start = at
    while start > 0, !ends(words[start - 1]) { start -= 1 }
    var end = at
    while end < words.count - 1, !ends(words[end]) { end += 1 }
    if let link = (start..<at).last(where: { tokens(words[$0]).contains(where: linkWords.contains) }) {
      start = link
    }
    let picked = words[start...end].prefix(14)
    return picked.count >= 2 ? picked.joined(separator: " ") : nil
  }

  // MARK: - Better or worse day, from the note's own words

  static let betterPhrases = ["didn t cry", "without crying", "no tears", "didn t fuss", "stayed asleep",
                              "went down easier", "slept to", "slept longer", "slept through",
                              // Added 2026-11-14: crying that stopped or didn't happen is a better day.
                              "no crying", "stopped crying", "no fuss", "no fussing", "stopped fussing",
                              "without fussing", "without a fuss", "no tantrum", "no meltdown",
                              "no screaming", "stopped screaming"]
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

  // MARK: - What the app reads in a note

  /// What the checks read in one note, for showing it to the parent. Uses the
  /// same rules as `canSupportATip`, `decidingPart`, the day reading and
  /// `review`'s choice of tip, and changes none of them. No model.
  public struct NoteReading: Sendable, Equatable {
    /// Whether Ask could build a tip on this note: it passes the tip filter and
    /// `review` would have a tip to give (a harder day where something was done has none).
    public var canBackATip: Bool { tip != nil }
    /// The tip `review` would write from this note, if the model points to its cause.
    public let tip: TipAction?
    /// How the day went, from the deciding part's own words.
    public let day: DayWas
    /// The word that says so ("Slept", "Fussier"), when there is one.
    public let clue: String?
    /// What was different that day, in the note's own words, from the first link
    /// word to the end of its clause ("skipped the late snack", "after the park").
    /// Nil when the note can't back a tip.
    public let cause: String?
  }

  public static func readNote(_ text: String) -> NoteReading {
    let none = NoteReading(tip: nil, day: .unclear, clue: nil, cause: nil)
    guard canSupportATip(text), let part = decidingPart(text), let cause = causeClause(in: part) else { return none }
    let read = reading(part)
    // The same choice as `review`: a silent note counts as a better day it doesn't
    // claim, and can't back leaving something out.
    let causeTokens = tokens(cause)
    let leftOut = causeTokens.indices.contains { marksLeftOut(causeTokens, at: $0) }
    let stated = read == .better || read == .worse
    guard stated || !leftOut, let tip = action(day: read == .worse ? .worse : .better, leftOut: leftOut) else { return none }
    return NoteReading(tip: tip, day: dayFromWording(part),
                       clue: stated ? clueWord(in: part, for: read) : nil, cause: cause)
  }

  /// From the first link or liking word to the end of its clause, at most 14 words.
  static func causeClause(in part: String) -> String? {
    let words = part.split(whereSeparator: \.isWhitespace).map(String.init)
    let toks = words.map { tokens($0).first ?? "" }
    guard let start = words.indices.first(where: { i in
      isLink(toks, at: i) || preferenceWords.contains(toks[i])
    }) else { return nil }
    var end = start
    let ends: (String) -> Bool = { $0.hasSuffix(",") || $0.hasSuffix(";") || $0.hasSuffix(".") }
    while end < words.count - 1, !ends(words[end]) { end += 1 }
    let picked = words[start...end].prefix(14).joined(separator: " ")
    let trimmed = picked.trimmingCharacters(in: CharacterSet(charactersIn: ",;.!?"))
    return trimmed.isEmpty ? nil : trimmed
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
  /// Links that start an action of their own ("when we sat at the table"), unlike
  /// "after dinner", which only says when.
  static let actionLinks: Set<String> = ["when", "once", "because", "since", "if"]
  /// Words ending in "ing" that name a time or a thing, not something done.
  static let ingNouns: Set<String> = ["evening", "morning", "thing", "something", "nothing", "everything",
                                      "string", "spring", "ceiling", "pudding", "wedding", "building"]
  /// Words a cause can't end on: "kept the room dark and", "turned the car seat to".
  /// ("on", "in", "you" can end one: "the white noise on", "at the table with you".)
  static let dangling: Set<String> = ["and", "or", "but", "to", "of", "the", "a", "an", "his", "her", "their",
                                      "your", "for", "from", "when", "after", "with", "by"]
  static let toParent: [String: String] = ["we": "you", "i": "you", "us": "you", "our": "your",
                                           "my": "your", "me": "you"]

  static func bare(_ w: String) -> String { AskCheck.tokens(w).joined(separator: " ") }

  /// The copied words, widened to the note's own lead-in: "sang the animal song"
  /// is "when we sang the animal song" in the note; "room dark" is "with the room dark".
  static func widened(_ span: String, in note: String?) -> String {
    guard let note, let r = note.range(of: span, options: .caseInsensitive) else { return span }
    var before = note[..<r.lowerBound].split(whereSeparator: \.isWhitespace).map(String.init)
    var lead: [String] = []
    func open(_ w: String) -> Bool { !w.hasSuffix(",") && !w.hasSuffix(";") && !w.hasSuffix(".") }
    // "three songs" is "the same three songs" in the note: take every small word back.
    while lead.count < 3, let w = before.last, open(w), determiners.contains(bare(w)) {
      lead.insert(w, at: 0); before.removeLast()
    }
    if lead.isEmpty, let w = before.last, open(w), subjects.contains(bare(w)) {
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
  /// A left-out thing keeps the note's own article: the model may copy "late
  /// snack" from "skipped the late snack". Added 2026-11-14.
  static func withArticle(_ span: String, in note: String?) -> String {
    guard let note, let first = span.split(separator: " ").first.map({ bare(String($0)) }),
          !determiners.contains(first),
          let r = note.range(of: span, options: .caseInsensitive),
          let w = note[..<r.lowerBound].split(whereSeparator: \.isWhitespace).last.map(String.init),
          determiners.contains(bare(w)) else { return span }
    return w + " " + span
  }

  /// A copy that stops mid-clause ("when we carried her in") runs on to the end of
  /// the note's own clause, so the tip never names half a thing. At most 14 words.
  /// Added 2026-11-14.
  static func toClauseEnd(_ text: String, in note: String?) -> String {
    guard let note, let r = note.range(of: text, options: .caseInsensitive) else { return text }
    var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    if let last = words.last, last.hasSuffix(",") || last.hasSuffix(";") || last.hasSuffix(".") { return text }
    let next = note[r.upperBound...]
    if let c = next.first, !c.isWhitespace { return text } // the copy ends inside a word
    for w in next.split(whereSeparator: \.isWhitespace).map(String.init) {
      guard words.count < 14 else { break }
      words.append(w)
      if w.hasSuffix(",") || w.hasSuffix(";") || w.hasSuffix(".") || w.hasSuffix("!") { break }
    }
    return words.joined(separator: " ")
  }

  static func cause(in span: String, leftOut: Bool, note: String?) -> Cause? {
    let start = leftOut ? withArticle(span, in: note) : widened(span, in: note)
    var words = toClauseEnd(start, in: note).split(whereSeparator: \.isWhitespace).map(String.init)
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
      // A copy cut mid-phrase ("kept the room dark and"): drop the dangling words.
      var parts = t.split(separator: " ").map(String.init)
      while let last = parts.last.map(bare), dangling.contains(last) {
        parts.removeLast()
      }
      return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    guard let first = words.first.map(bare) else { return nil }
    if leftOut { return tidy(words[...]).map(Cause.plain) }
    if AskCheck.preferenceWords.contains(first) {
      return tidy(words.dropFirst()).map { .liked(verb: first, thing: $0) }
    }
    // "at 7 without crying when we kept the room dark": the cause is the "when" clause.
    if placeLinks.contains(first), let later = words.dropFirst().firstIndex(where: { clauseLinks.contains(bare($0)) }),
       later + 1 < words.count {
      return tidy(words[(later + 1)...]).map { .linked(link: bare(words[later]), thing: $0) }
    }
    if clauseLinks.contains(first) || placeLinks.contains(first) {
      return tidy(words.dropFirst()).map { .linked(link: first, thing: $0) }
    }
    // A copy that starts at a time or an amount names the result, not the cause:
    // "6:40 on the day you skipped the late snack", "12–2:30 after the park".
    // The cause is the clause after it. Added 2026-11-14.
    if first.first?.isNumber == true,
       let at = words.dropFirst().firstIndex(where: { clauseLinks.contains(bare($0)) || placeLinks.contains(bare($0)) }),
       at + 1 < words.count {
      return tidy(words[(at + 1)...]).map { .linked(link: bare(words[at]), thing: $0) }
    }
    // "her peas when they were on the blue plate": the "when" clause is the cause.
    if determiners.contains(first) || first.hasSuffix("ing"),
       let at = words.dropFirst().firstIndex(where: { actionLinks.contains(bare($0)) }), at + 1 < words.count {
      return tidy(words[(at + 1)...]).map { .linked(link: bare(words[at]), thing: $0) }
    }
    if determiners.contains(first) || first.first?.isNumber == true {
      return tidy(words[...]).map(Cause.plain)
    }
    let at0 = words.firstIndex { clauseLinks.contains(bare($0)) }
    // "splashing in the washing-up bowl" names the thing itself ("evening" doesn't).
    if at0 == nil, first.hasSuffix("ing"), first.count > 4, !ingNouns.contains(first) {
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

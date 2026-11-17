import Foundation

/// Phrases and tip rules added to the lists that ship with the app.
/// They can only add a match. Empty, too long, or otherwise unusable entries are dropped.
public struct AskSafetyExtras: Sendable, Equatable {
  public var emergencyPhrases: [String]
  public var distressPhrases: [String]
  public var healthPhrases: [String]
  public var unsafeTipRules: [TipRule]

  public struct TipRule: Sendable, Equatable {
    public var phrase: String
    public var underMonths: Int

    public init(phrase: String, underMonths: Int) {
      self.phrase = phrase
      self.underMonths = underMonths
    }
  }

  public static let none = AskSafetyExtras()

  public init(
    emergencyPhrases: [String] = [],
    distressPhrases: [String] = [],
    healthPhrases: [String] = [],
    unsafeTipRules: [TipRule] = []
  ) {
    self.emergencyPhrases = emergencyPhrases
    self.distressPhrases = distressPhrases
    self.healthPhrases = healthPhrases
    self.unsafeTipRules = unsafeTipRules
  }

  /// The four Remote Config values. A value that is not a JSON array is ignored,
  /// and so is an entry that is empty, not a string, or longer than 60 characters.
  /// Each list keeps at most 200 entries that pass.
  public static func parsed(
    emergencyJSON: String,
    distressJSON: String,
    healthJSON: String,
    tipRulesJSON: String
  ) -> AskSafetyExtras {
    AskSafetyExtras(
      emergencyPhrases: phrases(fromJSON: emergencyJSON),
      distressPhrases: phrases(fromJSON: distressJSON),
      healthPhrases: phrases(fromJSON: healthJSON),
      unsafeTipRules: tipRules(fromJSON: tipRulesJSON)
    )
  }

  static let maxEntries = 200
  static let maxCharacters = 60

  static func acceptedPhrases(_ raw: [String]) -> [String] {
    var kept: [String] = []
    for phrase in raw {
      guard let cleaned = cleanPhrase(phrase) else { continue }
      kept.append(cleaned)
      if kept.count == maxEntries { break }
    }
    return kept
  }

  static func acceptedRules(_ raw: [TipRule]) -> [TipRule] {
    var kept: [TipRule] = []
    for rule in raw {
      guard let phrase = cleanPhrase(rule.phrase), (1...1_200).contains(rule.underMonths) else { continue }
      kept.append(TipRule(phrase: phrase, underMonths: rule.underMonths))
      if kept.count == maxEntries { break }
    }
    return kept
  }

  /// Lowercased, with punctuation as spaces, keeping a trailing `*` wildcard.
  /// Nil when the entry is blank, longer than 60 characters, or a wildcard with
  /// fewer than 3 letters before the `*` ("a*" would match almost every question).
  static func cleanPhrase(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= maxCharacters else { return nil }
    let wildcard = trimmed.hasSuffix("*")
    let body = wildcard ? String(trimmed.dropLast()) : trimmed
    let normalized = AskCheck.normalized(body)
    guard !normalized.isEmpty else { return nil }
    if wildcard, normalized.filter(\.isLetter).count < 3 { return nil }
    return wildcard ? normalized + "*" : normalized
  }

  private static func phrases(fromJSON json: String) -> [String] {
    guard let items = jsonArray(json) else { return [] }
    var raw: [String] = []
    for item in items {
      guard let phrase = item as? String else { continue }
      raw.append(phrase)
    }
    return acceptedPhrases(raw)
  }

  private static func tipRules(fromJSON json: String) -> [TipRule] {
    guard let items = jsonArray(json) else { return [] }
    var raw: [TipRule] = []
    for item in items {
      guard let object = item as? [String: Any],
            let phrase = object["phrase"] as? String,
            let underMonths = wholeNumber(object["underMonths"])
      else { continue }
      raw.append(TipRule(phrase: phrase, underMonths: underMonths))
    }
    return acceptedRules(raw)
  }

  private static func jsonArray(_ json: String) -> [Any]? {
    guard let data = json.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
    else { return nil }
    return array
  }

  /// A JSON number that is a whole number. Bools and fractions are not.
  private static func wholeNumber(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
    let double = number.doubleValue
    guard double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else { return nil }
    return Int(double)
  }
}

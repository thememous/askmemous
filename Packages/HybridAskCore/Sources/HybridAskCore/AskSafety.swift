import Foundation

/// Safety gates. These run before any model (questions) and after every model
/// (tips). They fail closed: a safe tip that happens to use a listed word is
/// rejected too, because the cost of the other mistake is far higher.
///
/// Phrase matching: whole words by default; a trailing `*` means "word start"
/// ("vomit*" matches "vomiting"). Text is lower-cased and punctuation becomes
/// spaces first, so "can't" is written "can t".
public enum AskSafety {

  // MARK: - Questions

  public enum QuestionGate: Sendable, Equatable {
    case emergency
    case parentDistress
    case health
  }

  /// Checked in this order: emergency, then distress, then health.
  public static func gate(question: String) -> QuestionGate? {
    let text = padded(question)
    if matches(text, emergencyPhrases) != nil { return .emergency }
    if matches(text, distressPhrases) != nil { return .parentDistress }
    if matches(text, healthPhrases) != nil || AskCheck.mentionsMedical(question) { return .health }
    return nil
  }

  static let emergencyPhrases = [
    "not breathing", "isn t breathing", "isnt breathing", "stopped breathing", "can t breathe",
    "cant breathe", "struggling to breathe", "turning blue", "went blue", "lips are blue",
    "lips look blue", "lips blue", "unresponsive", "won t wake", "wont wake", "can t wake",
    "cant wake", "unconscious", "seizure*", "convuls*", "choking", "button battery",
    "swallowed a battery", "swallowed a magnet", "swallowed bleach", "poison*", "overdose*",
    "bleeding a lot", "won t stop bleeding", "wont stop bleeding",
    // Added 2026-11-13 after held-out n22/n23 (see docs/EVAL_LOG.md).
    "swallowed", "bleach", "detergent", "dishwasher tablet*", "laundry pod*", "washing pod*",
    "cleaning product*", "drank some", "ate some pills", "ate pills", "took pills",
    "face is swelling", "face swelling", "face is swollen", "swollen face", "lips are swelling",
    "lips swelling", "swollen lips", "tongue swelling", "swelling up", "anaphyla*", "epipen",
    "allergic reaction",
  ]

  static let distressPhrases = [
    "lose it", "losing it", "lost it", "can t cope", "cant cope", "can t do this", "cant do this",
    "shook him", "shook her", "shook the baby", "shake him", "shake her", "shaking him", "shaking her",
    "hurt him", "hurt her", "hurt the baby", "hurt myself", "hurt my baby", "want to die", "end it all",
    "hate my baby", "hate being a mum", "hate being a mom", "hate being a parent",
    "screamed at him", "screamed at her", "scream at him", "scream at her",
  ]

  static let healthPhrases = [
    "fever*", "temperature", "rash*", "hives", "vomit*", "throwing up", "threw up", "diarrh*",
    "constipat*", "cough*", "wheez*", "breathing", "allerg*", "swollen", "swelling",
    "hit his head", "hit her head", "hit their head", "bumped his head", "bumped her head",
    "head injury", "fell off", "fell down the", "fell down stairs", "fell from", "rolled off",
    "weight", "not gaining", "losing weight", "dehydrat*", "jaundice", "yellow skin", "blood*",
    "infection*", "not walking", "not talking", "not crawling", "not sitting", "not rolling",
    "not babbling", "hasn t started walking", "hasn t started talking", "is she behind",
    "is he behind", "falling behind", "behind for", "behind other", "regress*",
    "paracetamol", "acetaminophen", "ibuprofen", "calpol", "tylenol", "motrin", "nurofen",
    "antibiotic*", "medicine", "eczema", "tongue tie", "reflux", "colic*",
    // Added 2026-11-13 after held-out n25 (see docs/EVAL_LOG.md).
    "doesn t point", "doesnt point", "not pointing", "doesn t talk", "doesnt talk", "doesn t walk",
    "doesnt walk", "doesn t crawl", "doesnt crawl", "doesn t sit", "doesnt sit", "no words yet",
    "eye contact", "respond to his name", "respond to her name", "milestone*", "developmental",
    "should i worry", "should i be worried",
  ]

  // MARK: - Tips

  /// The first forbidden phrase in a tip for this age, or nil. Unknown age gets every rule.
  public static func unsafePhrase(inTip tip: String, ageMonths: Int?) -> String? {
    var text = padded(tip)
    for safe in safeExceptions { text = text.replacingOccurrences(of: " \(safe) ", with: " ") }
    for rule in tipRules where ageMonths == nil || ageMonths! < rule.underMonths {
      if let hit = matches(text, rule.phrases) { return hit }
    }
    return nil
  }

  /// Safe phrases removed before matching ("tummy time" is recommended for awake babies).
  static let safeExceptions = ["tummy time", "bath water", "warm bath"]

  struct TipRule {
    let underMonths: Int
    let phrases: [String]
  }

  static let tipRules: [TipRule] = [
    // Safe sleep and feeding in the first year.
    TipRule(underMonths: 12, phrases: [
      "tummy", "stomach", "on her front", "on his front", "on their front", "on her side", "on his side",
      "on your chest", "on my chest", "pillow*", "blanket*", "duvet*", "quilt*", "bumper*", "cushion*",
      "soft toy*", "stuffed", "teddy", "sofa", "couch", "armchair", "in the car seat", "in the swing",
      "in the bouncer", "bottle in*", "bottle to bed", "prop the bottle", "propped", "propping",
      "cereal in the bottle", "honey", "cow s milk", "cows milk", "juice",
    ]),
    // No water or other drinks for young babies.
    TipRule(underMonths: 6, phrases: ["water", "tea", "sugar water"]),
    // Rear-facing car seats and a snug harness.
    TipRule(underMonths: 48, phrases: [
      "face forward", "facing forward", "forward facing", "turn the car seat", "turning the car seat",
      "turn her car seat", "turn his car seat", "loosen the strap*", "loosen the harness", "out of the car seat",
      "puffy", "snowsuit", "bulky", "coat on",
    ]),
    // Choking foods for under-fives.
    TipRule(underMonths: 60, phrases: [
      "grape*", "whole nut*", "peanut*", "nuts", "popcorn", "hard sweet*", "hard candy", "marshmallow*",
      "gum", "cherry tomato*", "hot dog*", "sausage chunk*", "raw carrot*",
    ]),
    // Any age.
    TipRule(underMonths: 1_000, phrases: [
      "alone in the bath", "unattended", "shake him", "shake her", "shake the baby", "smack*", "spank*",
      "hit him", "hit her", "medicine*", "medication*", "melatonin", "sleeping pill*", "antihistamine*",
      "gripe water", "brandy", "alcohol", "whisky",
    ]),
  ]

  // MARK: - Matching

  static func padded(_ text: String) -> String { " " + AskCheck.normalized(text) + " " }

  /// Returns the first phrase found in `paddedText` (which must start and end with a space).
  static func matches(_ paddedText: String, _ phrases: [String]) -> String? {
    phrases.first { phrase in
      if phrase.hasSuffix("*") {
        return paddedText.contains(" " + phrase.dropLast())
      }
      return paddedText.contains(" " + phrase + " ")
    }
  }
}

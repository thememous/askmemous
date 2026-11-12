import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Picks the notes worth showing the model, on the device, before any model runs.
/// A sleep question asked during a week of food notes should still see the older
/// sleep notes, so "newest six" is not good enough.
public enum AskRetrieval {
  public static let defaultLimit = 5
  /// How far back to look (most recent notes first).
  static let pool = 60

  public static func select(_ notes: [AskNote], question: String, limit: Int = defaultLimit) -> [AskNote] {
    let recent = notes
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { $0.createdAt > $1.createdAt }
      .prefix(pool)
    guard recent.count > limit else { return Array(recent) }

    let asked = AskTopic.of(question)
    let questionWords = contentWords(question)
    let embedder = SentenceSimilarity()
    let scored = recent.enumerated().map { index, note -> (AskNote, Double) in
      var score = 0.0
      score += 2.0 * Double(asked.intersection(AskTopic.of(note)).count)
      score += 0.5 * Double(questionWords.intersection(contentWords(note.text)).count)
      score += embedder.similarity(question, note.text)          // 0…1, 0 when unavailable
      score += 0.2 * (1.0 - Double(index) / Double(recent.count)) // slight preference for recent
      return (note, score)
    }
    return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
  }

  static let stopWords: Set<String> = [
    "the", "a", "an", "and", "or", "to", "of", "in", "on", "at", "for", "with", "is", "was", "be",
    "she", "he", "her", "him", "his", "they", "them", "we", "i", "my", "our", "you", "your", "it",
    "what", "how", "could", "should", "can", "do", "does", "did", "try", "this", "that", "week",
    "so", "any", "ideas", "again", "when", "after", "before", "all", "up", "t", "s",
  ]

  static func contentWords(_ text: String) -> Set<String> {
    Set(AskCheck.normalized(text).split(separator: " ").map(String.init).filter { !stopWords.contains($0) && $0.count > 2 })
  }
}

/// On-device sentence similarity from Apple's NaturalLanguage framework.
/// Returns 0 where no English sentence embedding is available.
struct SentenceSimilarity {
  #if canImport(NaturalLanguage)
  private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
  #endif

  func similarity(_ a: String, _ b: String) -> Double {
    #if canImport(NaturalLanguage)
    guard let embedding else { return 0 }
    let distance = embedding.distance(between: a, and: b) // cosine distance, 0…2
    guard distance.isFinite else { return 0 }
    return max(0, 1 - distance / 2)
    #else
    return 0
    #endif
  }
}

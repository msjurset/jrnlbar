import Foundation
import NaturalLanguage

public final class TagSuggestionService: Sendable {
    public static let shared = TagSuggestionService()
    
    private init() {}
    
    /// Suggests tags based on the provided text context and available tags.
    public func suggestTags(for text: String, existingTags: [Tag]) async -> [String] {
        guard !text.isEmpty else { return [] }
        
        // 1. Extract keywords from the text (nouns, proper nouns)
        let keywords = extractKeywords(from: text)
        guard !keywords.isEmpty else { return [] }
        
        // 2. Simple match and semantic distance using NLEmbedding
        let embedding = NLEmbedding.wordEmbedding(for: .english)
        
        var scoredTags: [(tag: String, score: Double)] = []
        
        for tag in existingTags {
            let tagName = tag.name.replacingOccurrences(of: "@", with: "").lowercased()
            var maxScore: Double = 0
            
            for keyword in keywords {
                let lowerKeyword = keyword.lowercased()
                
                // Exact or substring match gets high score
                if tagName == lowerKeyword {
                    maxScore = max(maxScore, 1.0)
                } else if tagName.contains(lowerKeyword) || lowerKeyword.contains(tagName) {
                    maxScore = max(maxScore, 0.8)
                } else if let embedding {
                    // Semantic distance
                    let distance = embedding.distance(between: tagName, and: lowerKeyword)
                    // distance is 0 for identical, larger for distant.
                    // Convert to a score: 0 distance -> 0.7 score, 2.0 distance -> 0 score
                    let semanticScore = max(0, 0.7 * (1.0 - (distance / 2.0)))
                    maxScore = max(maxScore, semanticScore)
                }
            }
            
            if maxScore > 0.3 {
                scoredTags.append((tag.name, maxScore))
            }
        }
        
        // Sort by score descending and return top 5
        return scoredTags
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { $0.tag }
    }
    
    private func extractKeywords(from text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var keywords = Set<String>()
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if let tag = tag {
                if tag == .noun || tag == .personalName || tag == .placeName || tag == .organizationName {
                    keywords.insert(String(text[range]))
                }
            }
            return true
        }
        
        return keywords
    }
}

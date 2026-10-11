import Foundation

public enum TextRules {
    /// A single pass prevents replacements from triggering one another. Longest phrase wins.
    public static func replace(_ text: String, entries: [(String, String)]) -> String {
        var replacements: [String: String] = [:]
        for (key, value) in entries {
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            replacements[key.lowercased()] = value
        }
        let keys = replacements.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        guard !keys.isEmpty else { return text }
        let alternatives = keys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{N}_])", options: [.caseInsensitive]) else { return text }
        let source = text as NSString
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            if let replacement = replacements[source.substring(with: match.range).lowercased()] {
                result.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return result as String
    }

    public static func applyVocabulary(_ text: String, entries: [VocabularyEntry]) -> String {
        replace(text, entries: entries.map { ($0.spoken, $0.written) })
    }

    public static func expandSnippets(_ text: String, snippets: [Snippet]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if let whole = snippets.first(where: { $0.trigger.caseInsensitiveCompare(phrase) == .orderedSame }) {
            return whole.text
        }
        return replace(text, entries: snippets.map { ($0.trigger, $0.text) })
    }

    /// Bound each local-model request without cutting a composed character or losing whitespace.
    public static func chunks(_ text: String, limit: Int = 1_600) -> [String] {
        guard limit > 0 else { return [text] }
        var rest = text[...]
        var result: [String] = []
        while rest.count > limit {
            let boundary = rest.index(rest.startIndex, offsetBy: limit)
            let prefix = rest[..<boundary]
            let split = prefix.lastIndex(where: \.isWhitespace).map { rest.index(after: $0) } ?? boundary
            result.append(String(rest[..<split]))
            rest = rest[split...]
        }
        if !rest.isEmpty { result.append(String(rest)) }
        return result
    }
}

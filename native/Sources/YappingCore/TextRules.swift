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

    /// Bound each local-model request without cutting a composed character or losing whitespace. A chunk ends
    /// after a sentence where it can: the model tidies a whole sentence better than a fragment.
    public static func chunks(_ text: String, limit: Int = 800) -> [String] {
        guard limit > 0 else { return [text] }
        var rest = text[...]
        var result: [String] = []
        while rest.count > limit {
            let window = rest.prefix(limit)
            let split = sentenceBreak(in: window)
                ?? window.lastIndex(where: \.isWhitespace).map { window.index(after: $0) }
                ?? window.endIndex
            result.append(String(rest[..<split]))
            rest = rest[split...]
        }
        if !rest.isEmpty { result.append(String(rest)) }
        return result
    }

    /// The index after the last sentence that ends in `window`, or nil when none does past its first quarter:
    /// a chunk of a few words isn't worth a request of its own.
    private static func sentenceBreak(in window: Substring) -> Substring.Index? {
        let floor = window.index(window.startIndex, offsetBy: window.count / 4)
        var end = window.endIndex
        while end > floor {
            let space = window.index(before: end)
            if window[space].isNewline { return end }
            if window[space].isWhitespace, space > window.startIndex,
               ".!?。！？…".contains(window[window.index(before: space)]) { return end }
            end = space
        }
        return nil
    }

    /// Whether `cleaned` still says what `original` said. Tidying may drop fillers and corrected slips and fix
    /// punctuation; `rewording` also allows a change of tone. It may not answer the text, carry it out, add to
    /// it, reorder it or lose most of it. The local model does all of these to dictated questions and requests,
    /// so its output is used only when this passes. A check, not a proof: it can't see one word swapped for
    /// another.
    public static func isFaithful(_ cleaned: String, to original: String, rewording: Bool = false) -> Bool {
        let spoken = words(original).filter { !fillers.contains($0) }
        let written = words(cleaned)
        guard let opening = written.first else { return false }
        // The opening word carries what kind of sentence this is. "Reply to Tom and say I'm late" answered or
        // carried out comes back without it.
        guard spoken.isEmpty || opening == spoken[0] else { return false }
        let shared = sharedInOrder(spoken, written)
        // A few words carry the whole meaning, so a short utterance must keep every one of them.
        let kept = spoken.isEmpty ? 1 : Double(shared) / Double(spoken.count)
        let added = Double(written.count - shared) / Double(written.count)
        guard kept >= (spoken.count <= 6 ? 1 : rewording ? 0.5 : 0.6), added <= (rewording ? 0.5 : 0.2) else { return false }
        let room = original.utf8.count / (rewording ? 2 : 4) + 16
        guard cleaned.utf8.count <= original.utf8.count + room else { return false }
        // A question that comes back as a statement was answered, not tidied.
        return !original.contains(where: isQuestionMark) || cleaned.contains(where: isQuestionMark)
    }

    private static let fillers: Set<String> = ["um", "uh", "uhm", "er", "erm", "ah", "hmm", "mm"]

    private static func isQuestionMark(_ character: Character) -> Bool { character == "?" || character == "？" }

    /// Lowercased words in order, split the way the system splits them, so unspaced scripts work too.
    static func words(_ text: String) -> [String] {
        let text = text.replacingOccurrences(of: "’", with: "'")
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { word, _, _, _ in
            if let word, !word.allSatisfy(\.isWhitespace) { result.append(word.lowercased()) }
        }
        return result
    }

    /// The length of the longest run of words the two share in the same order.
    private static func sharedInOrder(_ first: [String], _ second: [String]) -> Int {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var row = [Int](repeating: 0, count: second.count + 1)
        for word in first {
            var diagonal = 0
            for index in 1...second.count {
                let above = row[index]
                row[index] = word == second[index - 1] ? diagonal + 1 : max(row[index], row[index - 1])
                diagonal = above
            }
        }
        return row[second.count]
    }
}

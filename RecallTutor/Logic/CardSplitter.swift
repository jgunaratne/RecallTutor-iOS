import Foundation

// Card splitter shared by the lecture-card renderer and the quiz generator,
// so quiz questions are grounded in exactly the cards the user read.
// Port of lib/cards.ts: respects code blocks, targets ~1200 characters per
// card, and treats explicit "Card N:" headers as hard card boundaries.
enum CardSplitter {

    // Matches lines like "**Card 1: Title**", "## Card 2 — Title",
    // "### Card 3: Title", or plain "Card 4: Title" at the start of a line.
    // Note: literal en/em dashes — ICU rejects Swift's \u{...} escape syntax
    // inside a raw string, and this pattern is built with try!.
    private static let cardHeaderRE = try! NSRegularExpression(
        pattern: "^(?:\\*{2}|#{1,6}\\s+)?\\s*Card\\s+\\d+\\s*[:–—-]",
        options: [.caseInsensitive]
    )

    // Markdown section titles: "## Heading" or a standalone short bold line.
    private static let sectionHeadingRE = try! NSRegularExpression(pattern: #"^#{1,6}\s+\S"#)
    private static let boldTitleRE = try! NSRegularExpression(pattern: #"^\*\*[^*]{1,80}\*\*:?\s*$"#)

    // Markdown horizontal rules: ---, ***, ___ (3 or more).
    private static let dividerRE = try! NSRegularExpression(pattern: #"^(?:-{3,}|\*{3,}|_{3,})\s*$"#)

    // Flush before a section heading once the current card has this much content.
    private static let headingSplitMin = 200

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func splitIntoCards(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var cards: [String] = []

        var currentCardLines: [String] = []
        var inCodeBlock = false
        var currentLength = 0

        func flushCard() {
            // Drop divider and blank lines at the card edges.
            while let first = currentCardLines.first {
                let t = first.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !matches(dividerRE, t) { break }
                currentCardLines.removeFirst()
            }
            while let last = currentCardLines.last {
                let t = last.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !matches(dividerRE, t) { break }
                currentCardLines.removeLast()
            }
            if !currentCardLines.isEmpty {
                cards.append(currentCardLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            }
            currentCardLines = []
            currentLength = 0
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
            }

            // Explicit "Card N:" header always starts a new card (outside code blocks)
            if !inCodeBlock && matches(cardHeaderRE, trimmed) {
                flushCard()
            } else if !inCodeBlock,
                      currentLength > headingSplitMin,
                      matches(sectionHeadingRE, trimmed) || matches(boldTitleRE, trimmed) {
                // Section titles start a new card once the current one has real content.
                flushCard()
            }

            currentCardLines.append(line)
            currentLength += line.count + 1

            // Split on empty lines outside of code blocks if we reached the target length
            if !inCodeBlock && trimmed.isEmpty && currentLength > 500 {
                flushCard()
            }
        }

        flushCard()

        // Drop any title-only card — a heading or "Card N:" label with
        // nothing under it. Most often a truncation artifact at the end of
        // a stream, but two headers can also land back-to-back mid-lecture
        // with no body between them, so this must check every card, not
        // just the last one, or it renders as a visually blank card.
        cards = cards.filter { card in
            let lines = card.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines.count == 1 else { return true }
            return !(matches(sectionHeadingRE, lines[0])
                || matches(boldTitleRE, lines[0])
                || matches(cardHeaderRE, lines[0]))
        }

        return cards.filter { !$0.isEmpty }
    }
}

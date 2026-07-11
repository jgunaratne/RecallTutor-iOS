import SwiftUI

/// Lightweight block-level Markdown renderer for lecture cards. SwiftUI's
/// AttributedString handles inline markdown only, so headings, lists, and
/// tables are laid out here and inline spans delegated to AttributedString.
struct MarkdownText: View {
    let content: String

    private enum Block: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbered([String])
        case table(header: [String], rows: [[String]])
        /// Completed fenced block — chart/flow/image specs render natively.
        case fenced(lang: String, body: String)
        /// Unterminated fence while streaming — show a placeholder.
        case pendingFence

        var id: UUID { UUID() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(parse()) { block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text))
                        .font(.serifDisplay(size: level <= 2 ? 22 : 17, weight: .semibold))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 6)
                case .paragraph(let text):
                    Text(inline(text))
                        .font(.appBody(size: 17))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.textPrimary)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("•").foregroundStyle(Theme.accent)
                                Text(inline(item))
                                    .font(.appBody(size: 17))
                                    .lineSpacing(6)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                case .numbered(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.appBody(size: 17, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                                Text(inline(item))
                                    .font(.appBody(size: 17))
                                    .lineSpacing(6)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                case .table(let header, let rows):
                    tableView(header: header, rows: rows)
                case .fenced(let lang, let body):
                    fencedView(lang: lang, body: body)
                case .pendingFence:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                        Text("Drawing…")
                            .font(.appBody(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Theme.page.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private func fencedView(lang: String, body: String) -> some View {
        switch lang.lowercased() {
        case "chart":
            ChartBlockView(json: body)
        case "flow":
            FlowBlockView(json: body)
        default:
            // Fallback for code blocks: render as monospaced text with
            // horizontal scrolling so long lines don't wrap awkwardly.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.statePill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let processed = stripMath(text)
        return (try? AttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(processed)
    }

    /// Convert LaTeX math delimiters and common notation to readable Unicode
    /// so that $V = W/q$ renders as "V = W/q" instead of literal dollar signs.
    private func stripMath(_ input: String) -> String {
        var s = input

        // Strip display math $$...$$
        s = s.replacingOccurrences(
            of: #"\$\$([\s\S]*?)\$\$"#,
            with: "$1",
            options: .regularExpression
        )
        // Strip inline math $...$
        s = s.replacingOccurrences(
            of: #"\$([^$\n]+?)\$"#,
            with: "$1",
            options: .regularExpression
        )

        // \frac{a}{b} → a/b
        while let _ = s.range(of: #"\\frac\{([^}]*)\}\{([^}]*)\}"#, options: .regularExpression) {
            s = s.replacingOccurrences(
                of: #"\\frac\{([^}]*)\}\{([^}]*)\}"#,
                with: "($1)/($2)",
                options: .regularExpression
            )
        }
        // ^{...} → superscript digits/letters
        s = s.replacingOccurrences(
            of: #"\^\{([^}]+)\}"#, with: "^($1)", options: .regularExpression
        )
        // _{...} → subscript notation
        s = s.replacingOccurrences(
            of: #"_\{([^}]+)\}"#, with: "_($1)", options: .regularExpression
        )
        // Simple superscript single char: x^2 → x²
        let supMap: [Character: String] = [
            "0":"⁰","1":"¹","2":"²","3":"³","4":"⁴",
            "5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹",
            "n":"ⁿ",
        ]
        for (digit, sup) in supMap {
            s = s.replacingOccurrences(of: "^\\\(digit)", with: sup, options: .regularExpression)
        }

        // Greek letters
        let greek: [String: String] = [
            "\\alpha":"α", "\\beta":"β", "\\gamma":"γ", "\\delta":"δ",
            "\\epsilon":"ε", "\\zeta":"ζ", "\\eta":"η", "\\theta":"θ",
            "\\lambda":"λ", "\\mu":"μ", "\\nu":"ν", "\\xi":"ξ",
            "\\pi":"π", "\\rho":"ρ", "\\sigma":"σ", "\\tau":"τ",
            "\\phi":"φ", "\\psi":"ψ", "\\omega":"ω",
            "\\Gamma":"Γ", "\\Delta":"Δ", "\\Theta":"Θ", "\\Lambda":"Λ",
            "\\Pi":"Π", "\\Sigma":"Σ", "\\Phi":"Φ", "\\Psi":"Ψ", "\\Omega":"Ω",
        ]
        for (latex, unicode) in greek {
            s = s.replacingOccurrences(of: latex, with: unicode)
        }

        // Common operators and symbols
        let ops: [String: String] = [
            "\\times":"×", "\\div":"÷", "\\cdot":"·", "\\pm":"±",
            "\\leq":"≤", "\\geq":"≥", "\\neq":"≠", "\\approx":"≈",
            "\\infty":"∞", "\\sqrt":"√", "\\sum":"∑", "\\int":"∫",
            "\\rightarrow":"→", "\\leftarrow":"←", "\\Rightarrow":"⇒",
            "\\in":"∈", "\\notin":"∉", "\\subset":"⊂", "\\cup":"∪", "\\cap":"∩",
        ]
        for (latex, unicode) in ops {
            s = s.replacingOccurrences(of: latex, with: unicode)
        }

        // Strip remaining backslash commands (e.g. \text{...} → contents)
        s = s.replacingOccurrences(
            of: #"\\[a-zA-Z]+\{([^}]*)\}"#, with: "$1", options: .regularExpression
        )
        // Strip lone backslash commands
        s = s.replacingOccurrences(
            of: #"\\[a-zA-Z]+"#, with: "", options: .regularExpression
        )
        // Clean up stray braces
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")

        return s
    }

    private func tableView(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(inline(cell))
                            .font(.appBody(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Theme.statePill)

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                                .font(.appBody(size: 17))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Theme.borderSoft.opacity(0.5))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Block parsing

    private func parse() -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var tableLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }
        func flushTable() {
            guard tableLines.count >= 2 else {
                paragraph += tableLines
                tableLines = []
                return
            }
            let parsed = tableLines.map { line in
                line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            // Row 2 is the |---|---| divider; drop it and divider-only rows.
            let header = parsed[0]
            let rows = parsed.dropFirst().filter { row in
                !row.allSatisfy { cell in cell.allSatisfy { "-:".contains($0) } }
            }
            blocks.append(.table(header: header, rows: Array(rows)))
            tableLines = []
        }
        func flushAll() {
            flushParagraph()
            flushLists()
            flushTable()
        }

        var fenceLang: String?
        var fenceLines: [String] = []

        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Fenced blocks (```chart / ```flow / ```image / other)
            if line.hasPrefix("```") {
                if let lang = fenceLang {
                    blocks.append(.fenced(lang: lang, body: fenceLines.joined(separator: "\n")))
                    fenceLang = nil
                    fenceLines = []
                } else {
                    flushAll()
                    fenceLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if fenceLang != nil {
                fenceLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }

            // Table rows
            if line.hasPrefix("|") {
                flushParagraph()
                flushLists()
                tableLines.append(line)
                continue
            } else if !tableLines.isEmpty {
                flushTable()
            }

            // Headings
            if let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushAll()
                let level = line.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(level: level, text: String(line[match.upperBound...])))
                continue
            }

            // Horizontal rules — skip
            if line.range(of: #"^(?:-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                flushAll()
                continue
            }

            // Bulleted list items
            if let match = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph()
                bullets.append(String(line[match.upperBound...]))
                continue
            }

            // Numbered list items
            if let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                numbered.append(String(line[match.upperBound...]))
                continue
            }

            flushLists()
            paragraph.append(line)
        }

        flushAll()
        // A fence that never closed is still streaming in.
        if fenceLang != nil {
            blocks.append(.pendingFence)
        }
        return blocks
    }
}

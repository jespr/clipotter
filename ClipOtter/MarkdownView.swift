import SwiftUI

/// Lightweight, dependency-free Markdown renderer for processed output.
/// Handles headings, bold/italic/code/links (inline), bullet & numbered lists,
/// blockquotes, fenced code blocks, and horizontal rules.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            Text(inline(text))

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(item)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(inline(item)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }

        case .code(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))

        case .rule:
            Divider()

        case .table(let headers, let rows, let alignments):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
                tableRow(headers, alignments: alignments, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row, alignments: alignments, isHeader: false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
        }
    }

    private func tableRow(_ cells: [String], alignments: [ColumnAlignment], isHeader: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(inline(cell))
                    .fontWeight(isHeader ? .semibold : .regular)
                    .multilineTextAlignment(textAlignment(alignments, index))
                    .gridColumnAlignment(horizontalAlignment(alignments, index))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    private func column(_ alignments: [ColumnAlignment], _ index: Int) -> ColumnAlignment {
        index < alignments.count ? alignments[index] : .leading
    }

    private func horizontalAlignment(_ alignments: [ColumnAlignment], _ index: Int) -> HorizontalAlignment {
        switch column(alignments, index) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ alignments: [ColumnAlignment], _ index: Int) -> TextAlignment {
        switch column(alignments, index) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private func inline(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}

enum ColumnAlignment {
    case leading, center, trailing
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(String)
    case rule
    case table(headers: [String], rows: [[String]], alignments: [ColumnAlignment])

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if isRule(line) {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            // GitHub-flavored table: header row, then a delimiter row, then data rows.
            if line.contains("|"), i + 1 < lines.count, isDelimiterRow(lines[i + 1]) {
                flushParagraph()
                let headers = tableCells(line)
                let alignments = parseAlignments(lines[i + 1], count: headers.count)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !l.isEmpty, l.contains("|") else { break }
                    var cells = tableCells(l)
                    if cells.count < headers.count {
                        cells += Array(repeating: "", count: headers.count - cells.count)
                    } else if cells.count > headers.count {
                        cells = Array(cells.prefix(headers.count))
                    }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows, alignments: alignments))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    quoted.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: " ")))
                continue
            }

            if let item = unorderedItem(line) {
                flushParagraph()
                var items = [item]
                i += 1
                while i < lines.count, let next = unorderedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    i += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if let item = orderedItem(line) {
                flushParagraph()
                var items = [item]
                i += 1
                while i < lines.count, let next = orderedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            paragraph.append(line)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(_ line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(_ line: String) -> String? {
        var index = line.startIndex
        var digits = ""
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        let separator = line[index]
        guard separator == "." || separator == ")" else { return nil }
        let after = line.index(after: index)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[after...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isRule(_ line: String) -> Bool {
        let chars = Set(line)
        return line.count >= 3 && (chars == ["-"] || chars == ["*"] || chars == ["_"])
    }

    /// A table delimiter row: contains a pipe and every cell is `:?-+:?` (e.g. `---`, `:--:`, `--:`).
    private static func isDelimiterRow(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.contains("|") else { return false }
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let chars = Array(trimmed)
            var k = 0
            if chars.first == ":" { k += 1 }
            var dashes = 0
            while k < chars.count, chars[k] == "-" { k += 1; dashes += 1 }
            if k < chars.count, chars[k] == ":" { k += 1 }
            guard dashes >= 1, k == chars.count else { return false }
        }
        return true
    }

    /// Splits a table row into trimmed cells, dropping one optional outer pipe on each side
    /// and honoring escaped `\|`.
    private static func tableCells(_ raw: String) -> [String] {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for char in line {
            if escaped {
                if char != "|" { current.append("\\") }
                current.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseAlignments(_ raw: String, count: Int) -> [ColumnAlignment] {
        var result = tableCells(raw).map { cell -> ColumnAlignment in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            switch (trimmed.hasPrefix(":"), trimmed.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
        if result.count < count {
            result += Array(repeating: .leading, count: count - result.count)
        }
        return result
    }
}

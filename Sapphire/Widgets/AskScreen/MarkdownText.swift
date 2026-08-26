//
//  MarkdownText.swift
//  Sapphire
//
//  Minimal markdown rendering for streamed Ask Screen answers.
//

import SwiftUI

// MARK: - Blocks

/// ponytail: block-level markdown only — headings, list items, fenced code, paragraphs.
/// No tables, blockquotes, or images. If answers ever need those, swap this for a real
/// markdown package rather than growing this parser.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case listItem(depth: Int, marker: String, text: String)
    case code(String)
    case paragraph(String)

    /// Inline emphasis is left to Foundation: **bold**, *italic*, `code`, [links].
    static func inline(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

    /// The answer with markdown syntax resolved away — what you'd want on the pasteboard when
    /// the destination is an email, a form field, or a comment box rather than a markdown editor.
    static func plainText(_ raw: String) -> String {
        parse(raw).map { block in
            switch block {
            case .heading(_, let text): String(inline(text).characters)
            case .listItem(let depth, let marker, let text):
                String(repeating: "  ", count: depth) + marker + " " + String(inline(text).characters)
            case .code(let text): text
            case .paragraph(let text): String(inline(text).characters)
            }
        }
        .joined(separator: "\n")
    }

    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Headings: one to six leading '#' followed by a space.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let rest = String(trimmed.dropFirst(hashes))
                if hashes <= 6, rest.hasPrefix(" ") {
                    flushParagraph()
                    blocks.append(.heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }

            let indent = line.prefix(while: { $0 == " " }).count
            let depth = min(indent / 2, 3)

            // Bullets: -, *, +
            if let first = trimmed.first, "-*+".contains(first) {
                let rest = String(trimmed.dropFirst())
                if rest.hasPrefix(" ") {
                    flushParagraph()
                    blocks.append(.listItem(depth: depth, marker: "•", text: rest.trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }

            // Ordered items: digits, '.', space.
            let digits = trimmed.prefix(while: { $0.isNumber })
            if !digits.isEmpty {
                let rest = String(trimmed.dropFirst(digits.count))
                if rest.hasPrefix(". ") {
                    flushParagraph()
                    blocks.append(.listItem(depth: depth, marker: "\(digits).", text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }

            paragraph.append(trimmed)
        }

        // A stream can end mid-fence; render what arrived rather than dropping it.
        if inCode, !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}

// MARK: - View

struct MarkdownText: View {
    let raw: String
    var baseSize: CGFloat = 12

    // ponytail: reparsed on every streamed delta. Answers are a few KB and parsing is a
    // single pass, so this is cheaper than incremental block diffing. Revisit if answers
    // ever get long enough to stutter.
    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(MarkdownBlock.inline(text))
                        .font(.system(size: headingSize(level), weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)

                case .listItem(let depth, let marker, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker)
                            .font(.system(size: baseSize))
                            .foregroundStyle(.secondary)
                        Text(MarkdownBlock.inline(text))
                            .font(.system(size: baseSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(depth) * 14)

                case .code(let text):
                    Text(text)
                        .font(.system(size: baseSize - 1, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.black.opacity(0.28))
                        )

                case .paragraph(let text):
                    Text(MarkdownBlock.inline(text))
                        .font(.system(size: baseSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: baseSize + 4
        case 2: baseSize + 2
        default: baseSize + 1
        }
    }
}

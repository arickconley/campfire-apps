import Foundation

// Used only to recover local drafts written by the earlier Markdown editor.
extension RichNote {
    init(markdown: String) {
        let source = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            blocks = []
            return
        }
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            blocks = [.paragraph([Span(text: source)])]
            return
        }
        blocks = Self.read(parsed)
        if blocks.isEmpty {
            blocks = [.paragraph([Span(text: source)])]
        }
    }

}

private extension RichNote {
    enum Group { case list, quote, single }

    static func read(_ attr: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var identity: Int?
        var spans: [Span] = []
        var shape: Block = .paragraph([])

        func flush() {
            guard identity != nil else { return }
            blocks.append(filled(shape, spans: spans))
            spans = []
        }

        for run in attr.runs {
            let intent = run.presentationIntent
            let id = intent?.components.first?.identity ?? -1
            if identity != id {
                flush()
                identity = id
                shape = blockShape(intent)
            }
            let piece = String(attr[run.range].characters)
            if case .code = shape {
                let existing: String
                if case .code(let language, let text) = shape {
                    existing = text
                    shape = .code(language, existing + piece)
                }
                continue
            }
            if case .rule = shape { continue }
            append(Span(
                text: piece,
                bold: run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false,
                italic: run.inlinePresentationIntent?.contains(.emphasized) ?? false,
                strike: run.inlinePresentationIntent?.contains(.strikethrough) ?? false,
                code: run.inlinePresentationIntent?.contains(.code) ?? false,
                link: run.link.map(urlText),
                image: run.imageURL.map(urlText)
            ), to: &spans)
        }
        flush()
        return blocks.map(trimCode)
    }

    static func blockShape(_ intent: PresentationIntent?) -> Block {
        guard let intent else { return .paragraph([]) }
        var heading: Int?
        var quote = false
        var codeLanguage: String?
        var code = false
        var rule = false
        var listDepth = 0
        var ordered = false
        for component in intent.components {
            switch component.kind {
            case .header(let level):
                heading = level
            case .blockQuote:
                quote = true
            case .codeBlock(let language):
                code = true
                codeLanguage = language
            case .thematicBreak:
                rule = true
            case .unorderedList:
                listDepth += 1
            case .orderedList:
                listDepth += 1
                ordered = true
            default:
                break
            }
        }
        if rule { return .rule }
        if code { return .code(codeLanguage, "") }
        if let heading { return .heading(min(max(heading, 1), 6), []) }
        if listDepth > 0 { return ordered ? .numbered(listDepth, []) : .bullet(listDepth, []) }
        if quote { return .quote([]) }
        return .paragraph([])
    }

    static func filled(_ shape: Block, spans: [Span]) -> Block {
        switch shape {
        case .paragraph: return .paragraph(spans)
        case .heading(let level, _): return .heading(level, spans)
        case .bullet(let depth, _): return .bullet(depth, spans)
        case .numbered(let depth, _, let start): return .numbered(depth, spans, start: start)
        case .quote: return .quote(spans)
        case .code(let language, let text): return .code(language, text)
        case .rule: return .rule
        }
    }

    static func trimCode(_ block: Block) -> Block {
        guard case .code(let language, var text) = block else { return block }
        if text.hasSuffix("\n") { text.removeLast() }
        return .code(language, text)
    }

    static func append(_ span: Span, to spans: inout [Span]) {
        if span.image == nil, span.text.isEmpty { return }
        if let image = span.image, span.text.isEmpty {
            var chip = span
            chip.text = (image as NSString).lastPathComponent
            spans.append(chip)
            return
        }
        if var last = spans.last, last.image == nil, span.image == nil, last.styleKey == span.styleKey {
            last.text += span.text
            spans[spans.count - 1] = last
            return
        }
        spans.append(span)
    }

    static func urlText(_ url: URL) -> String { url.relativeString }
}

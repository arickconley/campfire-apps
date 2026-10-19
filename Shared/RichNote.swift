import Foundation

// The shared rich-text model. HTML is the storage and API format.
struct RichNote: Equatable {
    enum Block: Equatable {
        case paragraph([Span])
        case heading(Int, [Span])
        case bullet(Int, [Span])
        case numbered(Int, [Span], start: Int = 1)
        case quote([Span])
        case code(String?, String)
        case rule
    }

    struct Span: Equatable {
        var text: String
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var link: String?
        var title: String?
        var image: String?

        var styleKey: StyleKey {
            StyleKey(bold: bold, italic: italic, strike: strike, code: code, link: link, title: title, image: image)
        }
    }

    struct StyleKey: Equatable {
        var bold: Bool
        var italic: Bool
        var strike: Bool
        var code: Bool
        var link: String?
        var title: String?
        var image: String?
    }

    var blocks: [Block]

    init(blocks: [Block]) {
        self.blocks = blocks
    }

}

extension RichNote {
    init(html: String) throws {
        let reader = HTMLNoteReader()
        let parser = XMLParser(data: Data(("<campfire>" + html + "</campfire>").utf8))
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), reader.problem == nil else {
            throw CampfireError(message: reader.problem ?? "This post contains HTML the editor cannot read. Its saved content has not been changed.")
        }
        blocks = reader.blocks
    }

    var html: String {
        var index = 0
        var output: [String] = []
        func listInfo(_ block: Block) -> (Int, String, Int)? {
            switch block {
            case .bullet(let depth, _): return (max(1, depth), "ul", 1)
            case .numbered(let depth, _, let start): return (max(1, depth), "ol", start)
            default: return nil
            }
        }
        func list(_ depth: Int, _ tag: String, _ start: Int) -> String {
            var result = tag == "ol" && start != 1 ? "<ol start=\"\(start)\">" : "<\(tag)>"
            while index < blocks.count, let info = listInfo(blocks[index]), info.0 >= depth {
                if info.0 == depth && info.1 != tag { break }
                if info.0 > depth {
                    result += "<li>" + list(depth + 1, info.1, info.2) + "</li>"
                    continue
                }
                let spans: [Span]
                switch blocks[index] {
                case .bullet(_, let value), .numbered(_, let value, _): spans = value
                default: spans = []
                }
                result += "<li>" + Self.htmlSpans(spans)
                index += 1
                while index < blocks.count, let child = listInfo(blocks[index]), child.0 > depth {
                    result += list(depth + 1, child.1, child.2)
                }
                result += "</li>"
            }
            return result + "</\(tag)>"
        }
        while index < blocks.count {
            if let info = listInfo(blocks[index]) {
                output.append(list(1, info.1, info.2))
                continue
            }
            switch blocks[index] {
            case .paragraph(let spans): output.append("<p>\(Self.htmlSpans(spans))</p>")
            case .heading(let level, let spans):
                let level = min(6, max(1, level))
                output.append("<h\(level)>\(Self.htmlSpans(spans))</h\(level)>")
            case .quote(let spans): output.append("<blockquote><p>\(Self.htmlSpans(spans))</p></blockquote>")
            case .code(let language, let text):
                let hint = language.map { " class=\"language-\(Self.escapeHTML($0))\"" } ?? ""
                output.append("<pre><code\(hint)>\(Self.escapeHTML(text))</code></pre>")
            case .rule: output.append("<hr/>")
            case .bullet, .numbered: break
            }
            index += 1
        }
        return output.joined(separator: "\n")
    }

    private static func htmlSpans(_ spans: [Span]) -> String {
        spans.map { span in
            let title = span.title.map { " title=\"\(escapeHTML($0))\"" } ?? ""
            if let image = span.image {
                let imageHTML = "<img src=\"\(escapeHTML(image))\" alt=\"\(escapeHTML(span.text))\"\(title)/>"
                if let link = span.link { return "<a href=\"\(escapeHTML(link))\">\(imageHTML)</a>" }
                return imageHTML
            }
            var text = escapeHTML(span.text).replacingOccurrences(of: "\u{2028}", with: "<br/>")
            if span.code { text = "<code>\(text)</code>" }
            if span.bold { text = "<strong>\(text)</strong>" }
            if span.italic { text = "<em>\(text)</em>" }
            if span.strike { text = "<s>\(text)</s>" }
            if let link = span.link { text = "<a href=\"\(escapeHTML(link))\"\(title)>\(text)</a>" }
            return text
        }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// The API normalizes HTML into this XML-compatible subset. Parsing never loads
// images, executes scripts, or silently discards unsupported editor content.
private final class HTMLNoteReader: NSObject, XMLParserDelegate {
    var blocks: [RichNote.Block] = []
    var problem: String?
    private var stack: [(String, [String: String])] = []
    private var spans: [RichNote.Span] = []
    private var shape = "p"
    private var inBlock = false
    private var lists: [(String, Int)] = []
    private var quoteDepth = 0
    private var code: String?
    private var language: String?

    private func flush(force: Bool = false) {
        guard inBlock, force || !spans.isEmpty else { return }
        let block: RichNote.Block
        if shape.hasPrefix("h"), let level = Int(shape.dropFirst()) { block = .heading(level, spans) }
        else if shape == "li" { block = lists.last?.0 == "ol" ? .numbered(lists.count, spans, start: lists.last?.1 ?? 1) : .bullet(lists.count, spans) }
        else if quoteDepth > 0 { block = .quote(spans) }
        else { block = .paragraph(spans) }
        blocks.append(block)
        spans = []
        inBlock = false
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let supported = ["campfire", "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code", "strong", "em", "b", "i", "s", "del", "a", "img", "br", "hr"]
        guard supported.contains(name), stack.count < 64 else {
            problem = "This post uses unsupported HTML (<\(name)>). Its saved content has not been changed."
            parser.abortParsing()
            return
        }
        let complexBlock = ((name == "blockquote" || name == "ul" || name == "ol") && quoteDepth > 0)
            || (name == "blockquote" && !lists.isEmpty)
            || ((name == "pre" || name.hasPrefix("h") && name != "hr") && (!lists.isEmpty || quoteDepth > 0))
            || (name == "p" && !lists.isEmpty && (!inBlock || !spans.isEmpty))
            || (code != nil && name != "code")
        guard !complexBlock else {
            problem = "This post has nested HTML blocks the editor cannot preserve. Its saved content has not been changed."
            parser.abortParsing()
            return
        }
        switch name {
        case "ul", "ol": flush(); lists.append((name, Int(attributes["start"] ?? "1") ?? 1))
        case "blockquote": flush(); quoteDepth += 1
        case "pre": flush(); code = ""; language = nil
        case "code":
            if code != nil, let value = attributes["class"], value.hasPrefix("language-") { language = String(value.dropFirst(9)) }
        case "p", "h1", "h2", "h3", "h4", "h5", "h6", "li":
            if !(name == "p" && shape == "li" && inBlock) { flush(); shape = name; inBlock = true }
        case "hr": flush(); blocks.append(.rule)
        case "br": append("\u{2028}")
        case "img":
            if !inBlock { shape = lists.isEmpty ? "p" : "li" }
            var span = RichNote.Span(text: attributes["alt"] ?? "image")
            span.image = attributes["src"]
            span.title = attributes["title"]
            span.link = stack.last { $0.0 == "a" }?.1["href"]
            spans.append(span)
            inBlock = true
        default: break
        }
        stack.append((name, attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if code != nil { code! += string; return }
        if !inBlock, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let text = string.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        append(text)
    }

    private func append(_ text: String) {
        if !inBlock { shape = lists.isEmpty ? "p" : "li" }
        inBlock = true
        var span = RichNote.Span(text: text)
        span.bold = stack.contains { $0.0 == "strong" || $0.0 == "b" }
        span.italic = stack.contains { $0.0 == "em" || $0.0 == "i" }
        span.strike = stack.contains { $0.0 == "s" || $0.0 == "del" }
        span.code = stack.contains { $0.0 == "code" }
        span.link = stack.last { $0.0 == "a" }?.1["href"]
        span.title = stack.last { $0.0 == "a" }?.1["title"]
        if let last = spans.last, last.styleKey == span.styleKey, last.image == nil {
            spans[spans.count - 1].text += text
        } else { spans.append(span) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "pre":
            blocks.append(.code(language, code ?? "")); code = nil; language = nil; inBlock = false; spans = []
        case "p", "h1", "h2", "h3", "h4", "h5", "h6": flush(force: true)
        case "li": flush()
        case "ul", "ol": flush(); if !lists.isEmpty { lists.removeLast() }
        case "blockquote": flush(); quoteDepth -= 1
        case "campfire": flush()
        default: break
        }
        if !stack.isEmpty { stack.removeLast() }
    }
}

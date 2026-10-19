#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum CampMark {
    static let block = NSAttributedString.Key("camp.block")
    static let code = NSAttributedString.Key("camp.code")
    static let title = NSAttributedString.Key("camp.title")
    static let imageAlt = NSAttributedString.Key("camp.image-alt")
    static let codeBold = NSAttributedString.Key("camp.code-bold")
    static let codeItalic = NSAttributedString.Key("camp.code-italic")
    static let image = NSAttributedString.Key("camp.image")
    static let link = NSAttributedString.Key("camp.link")
    static let lang = NSAttributedString.Key("camp.lang")
}

enum RichInk {
    // Change presentation without rewriting text, semantic marks, or undo history.
    static func restyle(_ storage: NSMutableAttributedString, previousFontSize: Double) {
        let snapshot = NSAttributedString(attributedString: storage)
        storage.beginEditing()
        snapshot.enumerateAttributes(in: NSRange(location: 0, length: snapshot.length)) { attrs, range, _ in
            storage.setAttributes(appearanceAttributes(attrs, previousFontSize: previousFontSize), range: range)
        }
        storage.endEditing()
    }

    static func appearanceAttributes(_ attrs: [NSAttributedString.Key: Any], previousFontSize: Double) -> [NSAttributedString.Key: Any] {
        var next = attrs
        let block = attrs[CampMark.block] as? String
        let image = attrs[CampMark.image] != nil
        let code = block == "code" || attrs[CampMark.code] as? Bool == true
        if let font = attrs[.font] as? InkPlatformFont {
            let size = font.pointSize * AppAppearance.shared.fontSize / previousFontSize
            next[.font] = code
                ? InkPlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : InkFont.serif(size, bold: InkFont.isBold(font), italic: InkFont.isItalic(font))
        }
        let link = attrs[CampMark.link] != nil || attrs[.link] != nil
        next[.foregroundColor] = image || block == "quote" || block == "hr" ? Ink.uiMoss : (link ? Ink.uiEmber : Ink.uiInk)
        if image || code { next[.backgroundColor] = image ? Ink.uiMoss.withAlphaComponent(0.16) : Ink.uiRule }
        return next
    }

    static func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }

    static func strike(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        if let value = attrs[.strikethroughStyle] as? Int { return value != 0 }
        if let value = attrs[.strikethroughStyle] as? NSNumber { return value.intValue != 0 }
        return false
    }

    static func render(_ note: RichNote) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var lists: [NSTextList] = []
        var listKey = ""
        for (index, block) in note.blocks.enumerated() {
            let chunk: NSAttributedString
            switch block {
            case .bullet(let depth, let spans):
                (lists, listKey) = reuse(lists, key: listKey, want: "b\(depth)", depth: depth, numbered: false)
                chunk = draw(spans, block: nil, lists: lists, language: nil)
            case .numbered(let depth, let spans, let start):
                (lists, listKey) = reuse(lists, key: listKey, want: "n\(depth)-\(start)", depth: depth, numbered: true, start: start)
                chunk = draw(spans, block: nil, lists: lists, language: nil)
            case .heading(let level, let spans):
                lists = []
                listKey = ""
                chunk = draw(spans, block: "h\(level)", lists: [], language: nil)
            case .quote(let spans):
                lists = []
                listKey = ""
                chunk = draw(spans, block: "quote", lists: [], language: nil)
            case .code(let language, let text):
                lists = []
                listKey = ""
                let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
                let code = NSMutableAttributedString()
                for (lineIndex, line) in lines.enumerated() {
                    if lineIndex > 0 { code.append(lineBreak(after: code)) }
                    let spans = [RichNote.Span(text: line)]
                    code.append(draw(spans, block: "code", lists: [], language: lineIndex == 0 ? language : nil))
                }
                chunk = code
            case .rule:
                lists = []
                listKey = ""
                chunk = draw([RichNote.Span(text: "⸻")], block: "hr", lists: [], language: nil)
            case .paragraph(let spans):
                lists = []
                listKey = ""
                chunk = draw(spans, block: nil, lists: [], language: nil)
            }
            if index > 0 { result.append(lineBreak(after: result)) }
            result.append(chunk)
        }
        return result
    }

    static func note(_ text: NSAttributedString) -> RichNote {
        let raw = text.string as NSString
        guard raw.length > 0 else { return RichNote(blocks: []) }
        var blocks: [RichNote.Block] = []
        var code: [(String?, String)] = []
        func flushCode() {
            guard !code.isEmpty else { return }
            blocks.append(.code(code.compactMap(\.0).first, code.map(\.1).joined(separator: "\n")))
            code = []
        }
        var location = 0
        while location < raw.length {
            let full = raw.paragraphRange(for: NSRange(location: location, length: 0))
            var body = full
            if body.length > 0 {
                let tail = raw.character(at: body.location + body.length - 1)
                if tail == 10 || tail == 13 { body.length -= 1 }
            }
            let block = read(text, body: body, sample: body.length > 0 ? body : full)
            if case .code(let language, let line) = block {
                code.append((language, line))
            } else {
                flushCode()
                blocks.append(block)
            }
            let next = full.location + full.length
            if next <= location { break }
            location = next
        }
        flushCode()
        return RichNote(blocks: blocks)
    }

    static func spanAttributes(_ span: RichNote.Span, block: String?, lists: [NSTextList] = []) -> [NSAttributedString.Key: Any] {
        attributes(for: span, block: block, lists: lists, language: nil)
    }

    static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = attributes(for: RichNote.Span(text: ""), block: nil, lists: [], language: nil)
        attrs.removeValue(forKey: CampMark.code)
        return attrs
    }

    static func paragraphStyle(block: String?, lists: [NSTextList]) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        if let level = headingLevel(block) {
            style.paragraphSpacingBefore = level == 1 ? 14 : 8
            style.paragraphSpacing = 4
        } else if block == "code" {
            style.lineSpacing = 2
            style.paragraphSpacing = 0
            style.headIndent = 12
            style.firstLineHeadIndent = 12
        } else if block == "quote" {
            style.headIndent = 18
            style.firstLineHeadIndent = 18
            style.paragraphSpacing = 8
        } else if block == "hr" {
            style.alignment = .center
            style.paragraphSpacingBefore = 6
            style.paragraphSpacing = 6
        } else {
            style.paragraphSpacing = 12
        }
        if !lists.isEmpty {
            let indent = CGFloat(30 * lists.count)
            style.textLists = lists
            style.headIndent = indent
            style.firstLineHeadIndent = indent - 24
            style.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]
            style.paragraphSpacing = 2
            style.paragraphSpacingBefore = 0
        }
        return style
    }
}

private extension RichInk {
    static func reuse(
        _ lists: [NSTextList],
        key: String,
        want: String,
        depth: Int,
        numbered: Bool,
        start: Int = 1
    ) -> ([NSTextList], String) {
        guard key != want else { return (lists, key) }
        let count = max(depth, 1)
        var made = Array(lists.prefix(count))
        for index in 0..<count {
            let last = index == count - 1
            let format: NSTextList.MarkerFormat = last && numbered ? .decimal : .disc
            if index < made.count {
                if !last || (made[index].markerFormat == format && made[index].startingItemNumber == start) { continue }
                made.removeLast()
            }
            let list = NSTextList(markerFormat: format, options: 0)
            list.startingItemNumber = last ? start : 1
            made.append(list)
        }
        return (made, want)
    }

    static func draw(_ spans: [RichNote.Span], block: String?, lists: [NSTextList], language: String?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let source = spans.isEmpty ? [RichNote.Span(text: "")] : spans
        var wrote = false
        for span in source {
            let shown = span.image != nil && span.text.isEmpty ? "image" : span.text
            if shown.isEmpty && span.image == nil { continue }
            wrote = true
            result.append(NSAttributedString(string: shown, attributes: attributes(for: span, block: block, lists: lists, language: language)))
        }
        if !wrote {
            result.append(NSAttributedString(string: "", attributes: attributes(for: RichNote.Span(text: ""), block: block, lists: lists, language: language)))
        }
        return result
    }

    static func attributes(for span: RichNote.Span, block: String?, lists: [NSTextList], language: String?) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle(block: block, lists: lists),
            .foregroundColor: Ink.uiInk,
        ]
        if let block { attrs[CampMark.block] = block }
        if let title = span.title { attrs[CampMark.title] = title }
        if let language, !language.isEmpty { attrs[CampMark.lang] = language }
        if let image = span.image {
            attrs[CampMark.image] = image
            attrs[CampMark.imageAlt] = span.text
            if let link = span.link { attrs[CampMark.link] = link }
            attrs[.font] = InkFont.serif(InkFont.editorSize(18), bold: false, italic: true)
            attrs[.foregroundColor] = Ink.uiMoss
            attrs[.backgroundColor] = Ink.uiMoss.withAlphaComponent(0.16)
            return attrs
        }
        if block == "hr" {
            attrs[.font] = InkFont.serif(InkFont.editorSize(22), bold: false, italic: false)
            attrs[.foregroundColor] = Ink.uiMoss
            return attrs
        }
        if block == "code" {
            attrs[.font] = InkFont.mono()
            attrs[.backgroundColor] = Ink.uiRule
            return attrs
        }
        if span.code {
            attrs[CampMark.code] = true
            attrs[CampMark.codeBold] = span.bold
            attrs[CampMark.codeItalic] = span.italic
            attrs[.font] = InkFont.mono()
            attrs[.backgroundColor] = Ink.uiRule
        } else if let level = headingLevel(block) {
            attrs[.font] = InkFont.serif(InkFont.editorSize(headingSize(level)), bold: true, italic: span.italic)
        } else {
            attrs[.font] = InkFont.serif(InkFont.editorSize(20), bold: span.bold, italic: span.italic)
            if block == "quote" { attrs[.foregroundColor] = Ink.uiMoss }
        }
        if span.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = span.link {
            attrs[CampMark.link] = link
            attrs[.link] = URL(string: link) ?? link
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.foregroundColor] = Ink.uiEmber
        }
        return attrs
    }

    static func read(_ text: NSAttributedString, body: NSRange, sample: NSRange) -> RichNote.Block {
        let raw = text.string as NSString
        let probe = sample.length > 0 ? sample.location : min(body.location, max(raw.length - 1, 0))
        let attrs = raw.length == 0 ? [:] : text.attributes(at: min(probe, raw.length - 1), effectiveRange: nil)
        let block = attrs[CampMark.block] as? String
        let plain = body.length > 0 ? raw.substring(with: body) : ""
        if body.length == 0 {
            if block == "code" { return .code(attrs[CampMark.lang] as? String, "") }
            return .paragraph([])
        }
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        let lists = style?.textLists ?? []
        if block == "hr" || plain == "⸻" { return .rule }
        if block == "code" {
            let language = attrs[CampMark.lang] as? String
            return .code(language, plain)
        }
        let spans = readSpans(text, range: body, heading: headingLevel(block) != nil)
        if !lists.isEmpty {
            let depth = max(lists.count, 1)
            let numbered = lists.last?.markerFormat == .decimal
            return numbered ? .numbered(depth, spans, start: lists.last?.startingItemNumber ?? 1) : .bullet(depth, spans)
        }
        if let level = headingLevel(block) { return .heading(level, spans) }
        if block == "quote" { return .quote(spans) }
        return .paragraph(spans)
    }

    static func readSpans(_ text: NSAttributedString, range: NSRange, heading: Bool) -> [RichNote.Span] {
        guard range.length > 0 else { return [] }
        var spans: [RichNote.Span] = []
        text.enumerateAttributes(in: range) { attrs, sub, _ in
            let raw = (text.string as NSString).substring(with: sub).replacingOccurrences(of: "\u{FFFC}", with: "")
            let font = attrs[.font] as? InkPlatformFont
            let inline = (attrs[CampMark.code] as? Bool) == true
            let image = attrs[CampMark.image] as? String
            var span = RichNote.Span(text: image == nil ? raw : (attrs[CampMark.imageAlt] as? String ?? raw))
            span.image = image
            span.title = attrs[CampMark.title] as? String
            span.code = inline
            span.bold = !heading && image == nil && (inline ? (attrs[CampMark.codeBold] as? Bool ?? false) : (font.map(InkFont.isBold) ?? false))
            span.italic = image == nil && (inline ? (attrs[CampMark.codeItalic] as? Bool ?? false) : (font.map(InkFont.isItalic) ?? false))
            span.strike = strike(attrs)
            span.link = attrs[CampMark.link] as? String ?? linkString(attrs[.link])
            if span.text.isEmpty && span.image == nil { return }
            if var last = spans.last, last.styleKey == span.styleKey, last.image == nil, span.image == nil {
                last.text += span.text
                spans[spans.count - 1] = last
            } else {
                spans.append(span)
            }
        }
        return spans
    }

    static func linkString(_ value: Any?) -> String? {
        if let url = value as? URL {
            if url.scheme == nil {
                let relative = url.relativeString
                return relative.isEmpty ? url.path : relative
            }
            return url.absoluteString
        }
        if let text = value as? String, !text.isEmpty { return text }
        return nil
    }

    static func headingLevel(_ block: String?) -> Int? {
        guard let block, block.hasPrefix("h"), let level = Int(block.dropFirst()), (1...6).contains(level) else { return nil }
        return level
    }

    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 32
        case 2: 26
        case 3: 22
        default: 20
        }
    }

    static func lineBreak(after text: NSAttributedString) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = bodyAttributes()
        if text.length > 0 {
            let prior = text.attributes(at: text.length - 1, effectiveRange: nil)
            if let style = prior[.paragraphStyle] { attrs[.paragraphStyle] = style }
            if let block = prior[CampMark.block] { attrs[CampMark.block] = block }
            if let font = prior[.font] { attrs[.font] = font }
            if let color = prior[.foregroundColor] { attrs[.foregroundColor] = color }
        }
        attrs.removeValue(forKey: .link)
        attrs.removeValue(forKey: .underlineStyle)
        attrs.removeValue(forKey: CampMark.link)
        attrs.removeValue(forKey: CampMark.image)
        attrs.removeValue(forKey: .backgroundColor)
        return NSAttributedString(string: "\n", attributes: attrs)
    }
}

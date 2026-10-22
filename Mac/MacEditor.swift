import AppKit
import SwiftUI

struct MacInsert: Identifiable {
    enum Kind { case link, image }
    let id = UUID()
    var kind: Kind
    var location: Int
    var length: Int
    var selected: String
    var existing: String
}

@MainActor
@Observable
final class MacEditorSession {
    var title = "" { didSet { persistRecovery() } }
    var metaDescription = "" { didSet { persistRecovery() } }
    var draft = true { didSet { persistRecovery() } }
    var date = ""
    private(set) var isEmpty = true
    private(set) var boldOn = false
    private(set) var italicOn = false
    private(set) var strikeOn = false
    private(set) var bulletOn = false
    private(set) var numberOn = false
    private(set) var linkOn = false
    private(set) var block: String?
    private(set) var revision = 0
    var prompt: MacInsert?

    private(set) var contentRevision = 0
    private(set) var recovered = false
    private(set) var recoveryError: String?
    private var recoveryLocation: URL?
    private var opening = false
    private var recoveryReadFailed = false

    private var pending = ""
    private var pendingNote = RichNote(blocks: [])
    private var pushed = false
    private var baselined = false
    private var baseTitle = ""
    private var baseMetaDescription = ""
    private var baseDraft = true
    private var baseDate = ""
    private var baseBody = ""
    private var saved = NSRange(location: 0, length: 0)
    private var freezing = false
    weak var textView: NSTextView?

    var styleTitle: String {
        switch block {
        case "h1": "Heading"
        case "h2": "Subheading"
        case "h3": "Small heading"
        case "quote": "Quote"
        case "code": "Code"
        case "hr": "Divider"
        default: "Body"
        }
    }

    var isDirty: Bool {
        _ = contentRevision
        guard baselined else { return false }
        return metaDescription != baseMetaDescription || title != baseTitle || draft != baseDraft || html() != baseBody
    }

    func load(_ html: String) throws {
        let note = try RichNote(html: html)
        pendingNote = note
        pending = note.html
        pushed = false
        baselined = false
        revision += 1
        isEmpty = RichInk.render(note).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func html() -> String {
        if pushed, let textView, let storage = textView.textStorage {
            return RichInk.note(storage).html
        }
        return pending
    }

    func markPushed(_ textView: NSTextView) {
        self.textView = textView
        pushed = true
        if !baselined { markClean() }
        changed()
        refresh()
    }

    func open(post: Post?, recoveryLocation: URL) throws {
        opening = true
        defer { opening = false }
        self.recoveryLocation = recoveryLocation
        recoveryReadFailed = false
        recoveryError = nil
        recovered = false
        title = post?.title ?? ""
        metaDescription = post?.metaDescription ?? ""
        draft = post?.draft ?? true
        date = post?.date ?? ""
        try load(post?.body ?? "")
        baseTitle = title
        baseMetaDescription = metaDescription
        baseDraft = draft
        baseDate = date
        baseBody = RichInk.note(RichInk.render(pendingNote)).html
        do {
            if let copy = try MacDrafts().read(recoveryLocation) {
                title = copy.title
                metaDescription = copy.metaDescription ?? metaDescription
                draft = post?.draft ?? copy.draft
                date = post?.date ?? copy.date
                try load(copy.body)
                recovered = true
            }
        } catch {
            recoveryReadFailed = true
            recoveryError = "Could not read the local recovery copy. It is kept untouched; save to the blog before closing. \(error.localizedDescription)"
        }
        baselined = true
        opening = false
    }

    func persistRecovery() {
        guard !opening, !recoveryReadFailed, baselined, let recoveryLocation else { return }
        do {
            if isDirty {
                try MacDrafts().write(MacDraft(title: title, date: date, body: html(), draft: draft, metaDescription: metaDescription), to: recoveryLocation)
            } else {
                try MacDrafts().remove(recoveryLocation)
            }
            recoveryError = nil
        } catch {
            recoveryError = "Local recovery could not be saved. Keep this window open and save to the server. \(error.localizedDescription)"
        }
    }

    func retryRecovery() {
        guard recoveryReadFailed, let recoveryLocation else {
            persistRecovery()
            return
        }
        guard !isDirty else {
            recoveryError = "Save your current edits to the blog before retrying the unreadable recovery copy."
            return
        }
        let post = Post(slug: "", title: baseTitle, date: baseDate, draft: baseDraft, url: "", metaDescription: baseMetaDescription, body: baseBody)
        do { try open(post: post, recoveryLocation: recoveryLocation) }
        catch { recoveryError = error.localizedDescription }
    }

    func discardRecovery() {
        guard let recoveryLocation else { return }
        do {
            try MacDrafts().remove(recoveryLocation)
            opening = true
            title = baseTitle
            metaDescription = baseMetaDescription
            draft = baseDraft
            date = baseDate
            try load(baseBody)
            baselined = true
            recovered = false
            recoveryReadFailed = false
            opening = false
            recoveryError = nil
        } catch {
            recoveryError = "Could not discard the recovery copy: \(error.localizedDescription)"
        }
    }

    func markClean() {
        baseTitle = title
        baseMetaDescription = metaDescription
        baseDraft = draft
        baseDate = date
        baseBody = html()
        baselined = true
        recovered = false
        persistRecovery()
    }

    func toggleBold() { toggleFace(bold: true) }
    func toggleItalic() { toggleFace(bold: false) }
    func toggleStrike() { toggleStrikeRun() }
    func toggleBullet() { toggleList(numbered: false) }
    func toggleNumber() { toggleList(numbered: true) }

    func applyBlock(_ block: String?) {
        let range = actionRange()
        let paras = paragraphs(covering: range)
        edit {
            guard let textView else { return }
            if paras.isEmpty {
                textView.typingAttributes = RichInk.spanAttributes(RichNote.Span(text: ""), block: block)
                return
            }
            for full in paras {
                if block == "hr" {
                    replace(full, with: "⸻", block: "hr", in: textView)
                } else {
                    paint(full, block: block, lists: [], in: textView)
                }
            }
        }
    }

    func styleMatches(_ name: String?) -> Bool {
        block == name
    }

    func beginLink() {
        guard textView != nil else { return }
        let range = actionRange()
        if range.length > 0 && rangeAll(range, { _, attrs in attrs[CampMark.link] != nil }) {
            edit {
                guard let storage = self.textView?.textStorage else { return }
                storage.removeAttribute(CampMark.link, range: range)
                storage.removeAttribute(.link, range: range)
                storage.removeAttribute(.underlineStyle, range: range)
                storage.addAttribute(.foregroundColor, value: Ink.uiInk, range: range)
            }
            return
        }
        prompt = MacInsert(
            kind: .link,
            location: range.location,
            length: range.length,
            selected: substring(range),
            existing: linkString(at: range.location) ?? ""
        )
    }

    func beginImage() {
        guard textView != nil else { return }
        let range = actionRange()
        prompt = MacInsert(
            kind: .image,
            location: range.location,
            length: range.length,
            selected: substring(range),
            existing: ""
        )
    }

    func commitLink(_ insert: MacInsert, url raw: String, label given: String) {
        let url = RichInk.normalizedURL(raw)
        guard !url.isEmpty else { return }
        let trimmed = given.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? (insert.selected.isEmpty ? url : insert.selected) : trimmed
        replaceSpan(insert, text: label) { span in
            span.link = url
        }
    }

    func commitImage(_ insert: MacInsert, url raw: String, caption: String) {
        let url = RichInk.normalizedURL(raw)
        guard !url.isEmpty else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? (insert.selected.isEmpty ? "image" : insert.selected) : trimmed
        replaceSpan(insert, text: text) { span in
            span.image = url
        }
    }

    func changed() {
        contentRevision += 1
        let raw = (textView?.string ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
        let empty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty != empty { isEmpty = empty }
        persistRecovery()
    }

    // Restyle attributes only: appearance must not rewrite text, recovery, or undo history.
    func applyAppearance(previousFontSize: Double) {
        guard let textView, let storage = textView.textStorage else { return }
        let typing = RichInk.appearanceAttributes(textView.typingAttributes, previousFontSize: previousFontSize)
        RichInk.restyle(storage, previousFontSize: previousFontSize)
        textView.insertionPointColor = Ink.uiEmber
        textView.linkTextAttributes = [.foregroundColor: Ink.uiEmber, .underlineStyle: NSUnderlineStyle.single.rawValue]
        textView.typingAttributes = typing
    }

    func noteSelection() {
        if freezing { return }
        guard let textView, textView.window?.firstResponder === textView else { return }
        saved = textView.selectedRange()
    }

    func beginFreeze() {
        freezing = true
        if let textView { saved = textView.selectedRange() }
    }

    func endFreeze() {
        freezing = false
    }

    func splitHeading(_ range: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        let headingAttrs = textView.typingAttributes
        storage.replaceCharacters(in: range, with: "\n")
        if storage.length > range.location {
            storage.setAttributes(headingAttrs, range: NSRange(location: range.location, length: 1))
        }
        let cursor = NSRange(location: range.location + 1, length: 0)
        textView.setSelectedRange(cursor)
        saved = cursor
        textView.typingAttributes = RichInk.bodyAttributes()
        changed()
        refresh()
    }
}

struct MacText: NSViewRepresentable {
    var session: MacEditorSession
    var revision: Int
    var appearanceRevision: String

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 10, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let text = CampMacTextView(frame: NSRect(x: 0, y: 0, width: 10, height: 10), textContainer: container)
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 0, height: 2)
        text.setAccessibilityLabel("Post body")
        text.isEditable = context.environment.isEnabled
        text.isRichText = true
        text.allowsUndo = true
        text.usesFindBar = true
        text.usesFontPanel = false
        text.usesRuler = false
        text.drawsBackground = false
        text.focusRingType = .none
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = true
        text.isGrammarCheckingEnabled = false
        text.enabledTextCheckingTypes = 0
        text.insertionPointColor = Ink.uiEmber
        text.typingAttributes = RichInk.bodyAttributes()
        text.linkTextAttributes = [
            .foregroundColor: Ink.uiEmber,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        text.delegate = context.coordinator
        text.freeze = { [weak session = context.coordinator.session] in
            session?.beginFreeze()
        }
        text.unfreeze = { [weak session = context.coordinator.session] in
            session?.endFreeze()
        }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = text
        context.coordinator.textView = text
        session.textView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.session = session
        guard let text = scroll.documentView as? CampMacTextView else { return }
        text.isEditable = context.environment.isEnabled
        context.coordinator.textView = text
        session.textView = text
        if context.coordinator.appearanceRevision != appearanceRevision {
            session.applyAppearance(previousFontSize: context.coordinator.fontSize)
            context.coordinator.appearanceRevision = appearanceRevision
            context.coordinator.fontSize = AppAppearance.shared.fontSize
        }
        guard context.coordinator.applied != revision else { return }
        context.coordinator.applied = revision
        let rendered = RichInk.render(session.stagedNote())
        text.textStorage?.setAttributedString(rendered)
        if rendered.length == 0 {
            text.typingAttributes = RichInk.bodyAttributes()
        }
        let end = NSRange(location: rendered.length, length: 0)
        text.setSelectedRange(end)
        session.markPushed(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> NSSize? {
        NSSize(width: proposal.width ?? 320, height: proposal.height ?? 240)
    }
}

extension MacEditorSession {
    fileprivate func stagedNote() -> RichNote { pendingNote }
}

final class CampMacTextView: NSTextView {
    var freeze: (() -> Void)?
    var unfreeze: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        freeze?()
        let ok = super.resignFirstResponder()
        unfreeze?()
        return ok
    }
}

extension MacText {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var session: MacEditorSession
        var textView: CampMacTextView?
        var applied = -1
        var appearanceRevision = ""
        var fontSize = AppAppearance.shared.fontSize

        init(session: MacEditorSession) {
            self.session = session
        }

        func textDidChange(_ notification: Notification) {
            session.changed()
            session.refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            session.noteSelection()
            session.refresh()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard replacementString == "\n", range.length == 0 else { return true }
            let block = (textView.typingAttributes[CampMark.block] as? String) ?? ""
            guard block.hasPrefix("h") || block == "hr" else { return true }
            let session = session
            DispatchQueue.main.async {
                session.splitHeading(range)
            }
            return false
        }
    }
}

private extension MacEditorSession {
    func actionRange() -> NSRange {
        guard let textView else { return saved }
        if textView.window?.firstResponder === textView {
            return textView.selectedRange()
        }
        return saved
    }

    func restoreFocus() {
        guard let textView, let window = textView.window else { return }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    func edit(_ body: () -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let undo = textView.undoManager
        let before = NSAttributedString(attributedString: storage)
        let beforeRange = actionRange()
        undo?.disableUndoRegistration()
        body()
        undo?.enableUndoRegistration()
        let afterStorage = textView.textStorage ?? storage
        let after = NSAttributedString(attributedString: afterStorage)
        let afterRange = textView.selectedRange()
        undo?.beginUndoGrouping()
        undo?.registerUndo(withTarget: self) { me in
            me.restore(before, range: beforeRange, redo: after, redoRange: afterRange)
        }
        undo?.setActionName("Format")
        undo?.endUndoGrouping()
        saved = afterRange
        changed()
        refresh()
        restoreFocus()
    }

    func restore(_ text: NSAttributedString, range: NSRange, redo: NSAttributedString, redoRange: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        textView.undoManager?.registerUndo(withTarget: self) { me in
            me.restore(redo, range: redoRange, redo: text, redoRange: range)
        }
        let undo = textView.undoManager
        undo?.disableUndoRegistration()
        storage.setAttributedString(text)
        undo?.enableUndoRegistration()
        let clamped = clamp(range, in: storage.length)
        textView.setSelectedRange(clamped)
        saved = clamped
        changed()
        refresh()
    }

    func clamp(_ range: NSRange, in length: Int) -> NSRange {
        let loc = min(max(0, range.location), length)
        let len = min(max(0, range.length), length - loc)
        return NSRange(location: loc, length: len)
    }

    func paragraphs(covering range: NSRange) -> [NSRange] {
        guard let storage = textView?.textStorage else { return [] }
        let raw = storage.string as NSString
        if raw.length == 0 { return [] }
        if range.length == 0 {
            let probe = min(range.location, raw.length - 1)
            return [raw.paragraphRange(for: NSRange(location: max(0, probe), length: 0))]
        }
        var ranges: [NSRange] = []
        var index = range.location
        let end = min(range.location + range.length, raw.length)
        while index < end {
            let para = raw.paragraphRange(for: NSRange(location: min(index, raw.length - 1), length: 0))
            ranges.append(para)
            let next = para.location + para.length
            if next <= index { break }
            index = next
        }
        return ranges
    }

    func toggleFace(bold: Bool) {
        guard let textView else { return }
        let range = actionRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let block = attrs[CampMark.block] as? String
            if (attrs[CampMark.code] as? Bool) == true || block == "code" { return }
            let font = (attrs[.font] as? NSFont) ?? InkFont.serif(20, bold: false, italic: false)
            let on = bold ? InkFont.isBold(font) : InkFont.isItalic(font)
            attrs[.font] = InkFont.serif(
                font.pointSize,
                bold: bold ? !on : InkFont.isBold(font),
                italic: bold ? InkFont.isItalic(font) : !on
            )
            textView.typingAttributes = attrs
            refresh()
            restoreFocus()
            return
        }
        let turnOn = !rangeAll(range) { font, _ in
            guard let font else { return false }
            return bold ? InkFont.isBold(font) : InkFont.isItalic(font)
        }
        edit {
            guard let storage = textView.textStorage else { return }
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let attrs = storage.attributes(at: sub.location, effectiveRange: nil)
                let block = attrs[CampMark.block] as? String
                if (attrs[CampMark.code] as? Bool) == true || block == "code" { return }
                let font = (value as? NSFont) ?? InkFont.serif(20, bold: false, italic: false)
                let next = InkFont.serif(
                    font.pointSize,
                    bold: bold ? turnOn : InkFont.isBold(font),
                    italic: bold ? InkFont.isItalic(font) : turnOn
                )
                storage.addAttribute(.font, value: next, range: sub)
            }
        }
    }

    func toggleStrikeRun() {
        guard let textView else { return }
        let range = actionRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            if RichInk.strike(attrs) {
                attrs.removeValue(forKey: .strikethroughStyle)
            } else {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.typingAttributes = attrs
            refresh()
            restoreFocus()
            return
        }
        let turnOn = !rangeAll(range) { _, attrs in RichInk.strike(attrs) }
        edit {
            guard let storage = textView.textStorage else { return }
            if turnOn {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                storage.removeAttribute(.strikethroughStyle, range: range)
            }
        }
    }

    func toggleList(numbered: Bool) {
        let format: NSTextList.MarkerFormat = numbered ? .decimal : .disc
        let range = actionRange()
        let paras = paragraphs(covering: range)
        let on = !paras.isEmpty && paras.allSatisfy { listMatch($0, format: format) }
        if on {
            edit {
                guard let textView else { return }
                for full in paras {
                    paint(full, block: nil, lists: [], in: textView)
                }
            }
            return
        }
        let list = borrowedList(numbered: numbered, paragraphs: paras) ?? {
            let made = NSTextList(markerFormat: format, options: 0)
            made.startingItemNumber = 1
            return made
        }()
        edit {
            guard let textView else { return }
            for full in paras {
                paint(full, block: nil, lists: [list], in: textView)
            }
        }
    }

    func paint(_ full: NSRange, block: String?, lists: [NSTextList], in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let body = contentRange(full, in: storage)
        let target = body.length == 0 ? full : body
        if target.length == 0 {
            textView.typingAttributes = RichInk.spanAttributes(RichNote.Span(text: ""), block: block, lists: lists)
            return
        }
        storage.enumerateAttributes(in: target) { attrs, sub, _ in
            let font = attrs[.font] as? NSFont
            let wasHeading = (attrs[CampMark.block] as? String)?.hasPrefix("h") == true
            var span = RichNote.Span(text: "")
            span.bold = (font.map(InkFont.isBold) ?? false) && !wasHeading && block?.hasPrefix("h") != true
            span.italic = font.map(InkFont.isItalic) ?? false
            span.code = (attrs[CampMark.code] as? Bool) == true && block != "code"
            span.strike = RichInk.strike(attrs)
            span.title = attrs[CampMark.title] as? String
            span.link = attrs[CampMark.link] as? String
            span.image = block == "code" ? nil : attrs[CampMark.image] as? String
            if span.image != nil { span.text = attrs[CampMark.imageAlt] as? String ?? "" }
            var next = RichInk.spanAttributes(span, block: block, lists: lists)
            if block == "code" { next.removeValue(forKey: CampMark.code) }
            storage.setAttributes(next, range: sub)
        }
    }

    func replace(_ full: NSRange, with string: String, block: String, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let body = contentRange(full, in: storage)
        let span = RichNote.Span(text: string)
        let piece = NSAttributedString(string: string, attributes: RichInk.spanAttributes(span, block: block))
        storage.replaceCharacters(in: body, with: piece)
    }

    func replaceSpan(_ insert: MacInsert, text: String, fill: (inout RichNote.Span) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = clamp(NSRange(location: insert.location, length: insert.length), in: storage.length)
        let attrs = attributes(at: range.location)
        let font = attrs[.font] as? NSFont
        edit {
            guard let storage = textView.textStorage else { return }
            var span = RichNote.Span(text: text)
            span.bold = font.map(InkFont.isBold) ?? false
            span.italic = font.map(InkFont.isItalic) ?? false
            span.strike = RichInk.strike(attrs)
            fill(&span)
            let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
            let block = attrs[CampMark.block] as? String
            let piece = NSAttributedString(string: text, attributes: RichInk.spanAttributes(span, block: block, lists: lists))
            storage.replaceCharacters(in: range, with: piece)
            let cursor = NSRange(location: range.location + (text as NSString).length, length: 0)
            textView.setSelectedRange(cursor)
        }
    }

    func refresh() {
        guard let textView else { return }
        let attrs: [NSAttributedString.Key: Any]
        if let storage = textView.textStorage, storage.length > 0 {
            let range = textView.window?.firstResponder === textView ? textView.selectedRange() : saved
            let index = min(max(0, range.location), storage.length - 1)
            attrs = storage.attributes(at: index, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }
        let font = attrs[.font] as? NSFont
        let heading = ((attrs[CampMark.block] as? String) ?? "").hasPrefix("h")
        assign(\.boldOn, !heading && (font.map(InkFont.isBold) ?? false))
        assign(\.italicOn, font.map(InkFont.isItalic) ?? false)
        assign(\.strikeOn, RichInk.strike(attrs))
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        assign(\.bulletOn, lists.last?.markerFormat == .disc)
        assign(\.numberOn, lists.last?.markerFormat == .decimal)
        assign(\.linkOn, attrs[CampMark.link] != nil)
        let name = attrs[CampMark.block] as? String
        if block != name { block = name }
    }

    func assign(_ key: ReferenceWritableKeyPath<MacEditorSession, Bool>, _ value: Bool) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func rangeAll(_ range: NSRange, _ test: (NSFont?, [NSAttributedString.Key: Any]) -> Bool) -> Bool {
        guard let storage = textView?.textStorage, range.length > 0 else { return false }
        var all = true
        storage.enumerateAttributes(in: range) { attrs, _, stop in
            if !test(attrs[.font] as? NSFont, attrs) {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    func listMatch(_ full: NSRange, format: NSTextList.MarkerFormat) -> Bool {
        let lists = (attributes(at: full.location)[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        return lists.last?.markerFormat == format
    }

    func borrowedList(numbered: Bool, paragraphs paras: [NSRange]) -> NSTextList? {
        guard let storage = textView?.textStorage, let first = paras.first, first.location > 0 else { return nil }
        let raw = storage.string as NSString
        let previous = raw.paragraphRange(for: NSRange(location: first.location - 1, length: 0))
        let lists = (attributes(at: previous.location)[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let format: NSTextList.MarkerFormat = numbered ? .decimal : .disc
        guard lists.last?.markerFormat == format else { return nil }
        return lists.last
    }

    func attributes(at location: Int) -> [NSAttributedString.Key: Any] {
        guard let textView else { return [:] }
        guard let storage = textView.textStorage, storage.length > 0 else { return textView.typingAttributes }
        let index = min(max(0, location), storage.length - 1)
        return storage.attributes(at: index, effectiveRange: nil)
    }

    func contentRange(_ full: NSRange, in storage: NSTextStorage) -> NSRange {
        let raw = storage.string as NSString
        guard full.length > 0, full.location + full.length <= raw.length else { return full }
        let tail = raw.character(at: full.location + full.length - 1)
        if tail == 10 || tail == 13 { return NSRange(location: full.location, length: full.length - 1) }
        return full
    }

    func substring(_ range: NSRange) -> String {
        guard let storage = textView?.textStorage, range.length > 0 else { return "" }
        let raw = storage.string as NSString
        guard range.location + range.length <= raw.length else { return "" }
        return raw.substring(with: range).trimmingCharacters(in: .newlines)
    }

    func linkString(at location: Int) -> String? {
        attributes(at: location)[CampMark.link] as? String
    }


}

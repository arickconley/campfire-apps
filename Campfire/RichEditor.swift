import SwiftUI
import UIKit

@Observable
final class RichTextSession {
    private(set) var isEmpty = true
    private(set) var revision = 0
    private var pending = ""
    private var pendingNote = RichNote(blocks: [])
    private var pushed = false
    weak var textView: UITextView?

    func load(_ html: String) throws {
        let note = try RichNote(html: html)
        pendingNote = note
        pending = note.html
        pushed = false
        revision += 1
        isEmpty = RichInk.render(note).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func html() -> String {
        if pushed, let textView {
            return RichInk.note(textView.attributedText).html
        }
        return pending
    }

    func markPushed(_ textView: UITextView) {
        self.textView = textView
        pushed = true
        edited()
    }

    func edited() {
        let raw = (textView?.text ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
        isEmpty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct RichTextView: UIViewRepresentable {
    var session: RichTextSession
    var revision: Int
    var appearanceRevision: String

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> CampTextView {
        let text = CampTextView()
        text.delegate = context.coordinator
        text.isEditable = context.environment.isEnabled
        text.backgroundColor = .clear
        text.textColor = Ink.uiInk
        text.tintColor = Ink.uiEmber
        text.allowsEditingTextAttributes = true
        text.alwaysBounceVertical = true
        text.keyboardDismissMode = .interactive
        text.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 32, right: 0)
        text.textContainer.lineFragmentPadding = 0
        text.typingAttributes = RichInk.bodyAttributes()
        text.linkTextAttributes = [
            .foregroundColor: Ink.uiEmber,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        text.inputAccessoryView = context.coordinator.bar
        context.coordinator.textView = text
        context.coordinator.startKeyboard()
        session.textView = text
        return text
    }

    func updateUIView(_ textView: CampTextView, context: Context) {
        context.coordinator.session = session
        textView.isEditable = context.environment.isEnabled
        textView.inputAccessoryView?.isUserInteractionEnabled = context.environment.isEnabled
        context.coordinator.textView = textView
        if context.coordinator.appearanceRevision != appearanceRevision {
            let previousSize = context.coordinator.fontSize
            let typing = RichInk.appearanceAttributes(textView.typingAttributes, previousFontSize: previousSize)
            RichInk.restyle(textView.textStorage, previousFontSize: previousSize)
            textView.typingAttributes = typing
            textView.tintColor = Ink.uiEmber
            textView.linkTextAttributes = [.foregroundColor: Ink.uiEmber, .underlineStyle: NSUnderlineStyle.single.rawValue]
            textView.placeholderLabel.textColor = Ink.uiMoss
            textView.placeholderLabel.font = InkFont.serif(InkFont.editorSize(20), bold: false, italic: false)
            context.coordinator.bar.updateAppearance()
            context.coordinator.appearanceRevision = appearanceRevision
            context.coordinator.fontSize = AppAppearance.shared.fontSize
            context.coordinator.refresh()
        }
        guard context.coordinator.applied != revision else { return }
        context.coordinator.applied = revision
        let rendered = RichInk.render(session.stagedNote())
        textView.attributedText = rendered
        if rendered.length == 0 {
            textView.typingAttributes = RichInk.bodyAttributes()
        }
        textView.selectedRange = NSRange(location: rendered.length, length: 0)
        session.markPushed(textView)
        textView.refreshPlaceholder()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CampTextView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 280)
    }

    static func dismantleUIView(_ uiView: CampTextView, coordinator: Coordinator) {
        coordinator.stopKeyboard()
    }
}

extension RichTextSession {
    fileprivate func stagedNote() -> RichNote { pendingNote }
}

final class CampTextView: UITextView {
    let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.text = "Write"
        placeholderLabel.textColor = Ink.uiMoss
        placeholderLabel.font = InkFont.serif(InkFont.editorSize(20), bold: false, italic: false)
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshPlaceholder()
    }

    func refreshPlaceholder() {
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: max(0, bounds.width - x - 8), height: 28)
        placeholderLabel.isHidden = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension RichTextView {
    final class Coordinator: NSObject, UITextViewDelegate {
        var session: RichTextSession
        var textView: CampTextView?
        var applied = -1
        var appearanceRevision = ""
        var fontSize = AppAppearance.shared.fontSize
        let bar = FormatBar()
        private var keyboardObserver: NSObjectProtocol?

        init(session: RichTextSession) {
            self.session = session
            super.init()
            bar.done.addTarget(self, action: #selector(done), for: .touchUpInside)
            wire(bar.bold, #selector(toggleBold))
            wire(bar.italic, #selector(toggleItalic))
            wire(bar.strike, #selector(toggleStrike))
            wire(bar.bullet, #selector(toggleBullet))
            wire(bar.number, #selector(toggleNumber))
            wire(bar.link, #selector(insertLink))
            wire(bar.photo, #selector(insertImage))
            bar.style.menu = UIMenu(children: [
                action("Body", nil),
                action("Heading", "h1"),
                action("Subheading", "h2"),
                action("Small heading", "h3"),
                action("Quote", "quote"),
                action("Code", "code"),
            ])
            bar.style.showsMenuAsPrimaryAction = true
            bar.rule.addTarget(self, action: #selector(insertRule), for: .touchUpInside)
        }

        func startKeyboard() {
            keyboardObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.keyboard(note)
            }
        }

        func stopKeyboard() {
            if let keyboardObserver {
                NotificationCenter.default.removeObserver(keyboardObserver)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            session.edited()
            (textView as? CampTextView)?.refreshPlaceholder()
            refresh()
        }

        func textViewDidChangeSelection(_ textView: UITextView) { refresh() }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            let block = (textView.typingAttributes[CampMark.block] as? String) ?? ""
            guard block.hasPrefix("h") || block == "hr" else { return true }
            textView.textStorage.replaceCharacters(in: range, with: "\n")
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
            textView.typingAttributes = RichInk.bodyAttributes()
            session.edited()
            return false
        }
    }
}

private extension RichTextView.Coordinator {
    func wire(_ button: UIButton, _ action: Selector) {
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    func action(_ title: String, _ block: String?) -> UIAction {
        UIAction(title: title) { [weak self] _ in self?.setBlock(block) }
    }

    @objc func done() { textView?.resignFirstResponder() }
    @objc func toggleBold() { toggleFace(bold: true) }
    @objc func toggleItalic() { toggleFace(bold: false) }
    @objc func toggleStrike() { toggleStrikeRun() }
    @objc func toggleBullet() { toggleList(numbered: false) }
    @objc func toggleNumber() { toggleList(numbered: true) }
    @objc func insertRule() { setBlock("hr") }

    func edit(_ body: () -> Void) {
        guard let textView else { return }
        let before = textView.attributedText ?? NSAttributedString()
        let beforeRange = textView.selectedRange
        body()
        let after = textView.attributedText ?? NSAttributedString()
        let afterRange = textView.selectedRange
        textView.undoManager?.registerUndo(withTarget: self) { me in
            me.restore(before, range: beforeRange, redo: after, redoRange: afterRange)
        }
        textView.undoManager?.setActionName("Format")
        session.edited()
        textView.refreshPlaceholder()
        refresh()
    }

    func restore(_ text: NSAttributedString, range: NSRange, redo: NSAttributedString, redoRange: NSRange) {
        guard let textView else { return }
        textView.undoManager?.registerUndo(withTarget: self) { me in
            me.restore(redo, range: redoRange, redo: text, redoRange: range)
        }
        textView.attributedText = text
        textView.selectedRange = clamp(range, in: text.length)
        session.edited()
        textView.refreshPlaceholder()
        refresh()
    }

    func clamp(_ range: NSRange, in length: Int) -> NSRange {
        let loc = min(max(0, range.location), length)
        let len = min(range.length, length - loc)
        return NSRange(location: loc, length: len)
    }

    func paragraphs() -> [NSRange] {
        guard let textView else { return [] }
        let raw = textView.textStorage.string as NSString
        if raw.length == 0 { return [] }
        let sel = textView.selectedRange
        if sel.length == 0 {
            let probe = min(sel.location, raw.length - 1)
            return [raw.paragraphRange(for: NSRange(location: max(0, probe), length: 0))]
        }
        var ranges: [NSRange] = []
        var index = sel.location
        let end = min(sel.location + sel.length, raw.length)
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
        edit {
            guard let textView else { return }
            let range = textView.selectedRange
            if range.length == 0 {
                var attrs = textView.typingAttributes
                let block = attrs[CampMark.block] as? String
                if (attrs[CampMark.code] as? Bool) == true || block == "code" { return }
                let font = (attrs[.font] as? UIFont) ?? InkFont.serif(20, bold: false, italic: false)
                let traits = font.fontDescriptor.symbolicTraits
                let on = bold ? traits.contains(.traitBold) : traits.contains(.traitItalic)
                attrs[.font] = InkFont.serif(
                    font.pointSize,
                    bold: bold ? !on : traits.contains(.traitBold),
                    italic: bold ? traits.contains(.traitItalic) : !on
                )
                textView.typingAttributes = attrs
                return
            }
            let turnOn = !rangeAll(range) { font, _ in
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                return bold ? traits.contains(.traitBold) : traits.contains(.traitItalic)
            }
            textView.textStorage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let attrs = textView.textStorage.attributes(at: sub.location, effectiveRange: nil)
                let block = attrs[CampMark.block] as? String
                if (attrs[CampMark.code] as? Bool) == true || block == "code" { return }
                let font = (value as? UIFont) ?? InkFont.serif(20, bold: false, italic: false)
                let traits = font.fontDescriptor.symbolicTraits
                let next = InkFont.serif(
                    font.pointSize,
                    bold: bold ? turnOn : traits.contains(.traitBold),
                    italic: bold ? traits.contains(.traitItalic) : turnOn
                )
                textView.textStorage.addAttribute(.font, value: next, range: sub)
            }
        }
    }

    func toggleStrikeRun() {
        edit {
            guard let textView else { return }
            let range = textView.selectedRange
            if range.length == 0 {
                var attrs = textView.typingAttributes
                if RichInk.strike(attrs) {
                    attrs.removeValue(forKey: .strikethroughStyle)
                } else {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                textView.typingAttributes = attrs
                return
            }
            let turnOn = !rangeAll(range) { _, attrs in RichInk.strike(attrs) }
            if turnOn {
                textView.textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                textView.textStorage.removeAttribute(.strikethroughStyle, range: range)
            }
        }
    }

    func toggleList(numbered: Bool) {
        let format: NSTextList.MarkerFormat = numbered ? .decimal : .disc
        let ranges = paragraphs()
        let on = !ranges.isEmpty && ranges.allSatisfy { listMatch($0, format: format) }
        if on {
            setBlock(nil)
            return
        }
        edit {
            guard let textView else { return }
            let list = borrowedList(numbered: numbered) ?? {
                let made = NSTextList(markerFormat: format, options: 0)
                made.startingItemNumber = 1
                return made
            }()
            for full in paragraphs() {
                paint(full, block: nil, lists: [list], in: textView)
            }
        }
    }

    func setBlock(_ block: String?) {
        edit {
            guard let textView else { return }
            let ranges = paragraphs()
            if ranges.isEmpty {
                textView.typingAttributes = RichInk.spanAttributes(RichNote.Span(text: ""), block: block)
                return
            }
            for full in ranges {
                if block == "hr" {
                    replace(full, with: "⸻", block: "hr", in: textView)
                    continue
                }
                let current = blockName(at: full.location, in: textView)
                if block == current && block != nil {
                    paint(full, block: nil, lists: [], in: textView)
                } else {
                    paint(full, block: block, lists: [], in: textView)
                }
            }
        }
    }

    func paint(_ full: NSRange, block: String?, lists: [NSTextList], in textView: CampTextView) {
        let body = contentRange(full, in: textView)
        let target = body.length == 0 ? full : body
        if target.length == 0 {
            textView.typingAttributes = RichInk.spanAttributes(RichNote.Span(text: ""), block: block, lists: lists)
            return
        }
        textView.textStorage.enumerateAttributes(in: target) { attrs, sub, _ in
            let font = attrs[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let wasHeading = (attrs[CampMark.block] as? String)?.hasPrefix("h") == true
            var span = RichNote.Span(text: "")
            span.bold = traits.contains(.traitBold) && !wasHeading && block?.hasPrefix("h") != true
            span.italic = traits.contains(.traitItalic)
            span.code = (attrs[CampMark.code] as? Bool) == true && block != "code"
            span.strike = RichInk.strike(attrs)
            span.title = attrs[CampMark.title] as? String
            span.link = attrs[CampMark.link] as? String
            span.image = block == "code" ? nil : attrs[CampMark.image] as? String
            if span.image != nil { span.text = attrs[CampMark.imageAlt] as? String ?? "" }
            var next = RichInk.spanAttributes(span, block: block, lists: lists)
            if block == "code" { next.removeValue(forKey: CampMark.code) }
            textView.textStorage.setAttributes(next, range: sub)
        }
    }

    func replace(_ full: NSRange, with string: String, block: String, in textView: CampTextView) {
        let body = contentRange(full, in: textView)
        let span = RichNote.Span(text: string)
        let piece = NSAttributedString(string: string, attributes: RichInk.spanAttributes(span, block: block))
        textView.textStorage.replaceCharacters(in: body, with: piece)
    }

    @objc func insertLink() {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length > 0 && rangeAll(range, { _, attrs in attrs[CampMark.link] != nil }) {
            edit {
                textView.textStorage.removeAttribute(CampMark.link, range: range)
                textView.textStorage.removeAttribute(.link, range: range)
                textView.textStorage.removeAttribute(.underlineStyle, range: range)
                textView.textStorage.addAttribute(.foregroundColor, value: Ink.uiInk, range: range)
            }
            return
        }
        let selected = range.length > 0 ? (textView.text as NSString).substring(with: range) : ""
        let alert = UIAlertController(title: "Link", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.text = self.linkString(at: range.location)
        }
        if selected.isEmpty {
            alert.addTextField { $0.placeholder = "Label" }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return }
            let url = RichInk.normalizedURL(raw)
            let label = selected.isEmpty
                ? (alert.textFields?.dropFirst().first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? url
                : selected
            self.edit {
                var span = RichNote.Span(text: label)
                span.link = url
                let piece = NSAttributedString(string: label, attributes: RichInk.spanAttributes(span, block: self.blockName(at: range.location, in: textView)))
                textView.textStorage.replaceCharacters(in: range, with: piece)
                textView.selectedRange = NSRange(location: range.location + (label as NSString).length, length: 0)
            }
        })
        present(alert)
    }

    @objc func insertImage() {
        guard let textView else { return }
        let range = textView.selectedRange
        let selected = range.length > 0 ? (textView.text as NSString).substring(with: range) : ""
        let alert = UIAlertController(title: "Image", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Image address"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }
        alert.addTextField { field in
            field.placeholder = "Caption"
            field.text = selected
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return }
            let caption = alert.textFields?.dropFirst().first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.edit {
                var span = RichNote.Span(text: caption.isEmpty ? "image" : caption)
                span.image = RichInk.normalizedURL(raw)
                let piece = NSAttributedString(string: span.text, attributes: RichInk.spanAttributes(span, block: nil))
                textView.textStorage.replaceCharacters(in: range, with: piece)
                textView.selectedRange = NSRange(location: range.location + (span.text as NSString).length, length: 0)
            }
        })
        present(alert)
    }

    func refresh() {
        guard let textView else { return }
        let attrs = textView.typingAttributes
        let font = attrs[.font] as? UIFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        let heading = ((attrs[CampMark.block] as? String) ?? "").hasPrefix("h")
        tint(bar.bold, !heading && traits.contains(.traitBold))
        tint(bar.italic, traits.contains(.traitItalic))
        tint(bar.strike, RichInk.strike(attrs))
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        tint(bar.bullet, lists.last?.markerFormat == .disc)
        tint(bar.number, lists.last?.markerFormat == .decimal)
        tint(bar.link, attrs[CampMark.link] != nil)
    }

    func tint(_ button: UIButton, _ on: Bool) {
        button.tintColor = on ? Ink.uiEmber : Ink.uiInk
    }

    func rangeAll(_ range: NSRange, _ test: (UIFont?, [NSAttributedString.Key: Any]) -> Bool) -> Bool {
        guard let textView, range.length > 0 else { return false }
        var all = true
        textView.textStorage.enumerateAttributes(in: range) { attrs, _, stop in
            if !test(attrs[.font] as? UIFont, attrs) {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    func listMatch(_ full: NSRange, format: NSTextList.MarkerFormat) -> Bool {
        guard let textView, textView.textStorage.length > 0 else { return false }
        let attrs = textView.textStorage.attributes(at: min(full.location, textView.textStorage.length - 1), effectiveRange: nil)
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        return lists.last?.markerFormat == format
    }

    func borrowedList(numbered: Bool) -> NSTextList? {
        guard let textView else { return nil }
        let raw = textView.text as NSString
        guard let first = paragraphs().first, first.location > 0 else { return nil }
        let previous = raw.paragraphRange(for: NSRange(location: first.location - 1, length: 0))
        let attrs = textView.textStorage.attributes(at: previous.location, effectiveRange: nil)
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let format: NSTextList.MarkerFormat = numbered ? .decimal : .disc
        guard lists.last?.markerFormat == format else { return nil }
        return lists.last
    }

    func blockName(at location: Int, in textView: CampTextView) -> String? {
        guard textView.textStorage.length > 0 else {
            return textView.typingAttributes[CampMark.block] as? String
        }
        let index = min(location, textView.textStorage.length - 1)
        return textView.textStorage.attributes(at: index, effectiveRange: nil)[CampMark.block] as? String
    }

    func contentRange(_ full: NSRange, in textView: CampTextView) -> NSRange {
        let raw = textView.text as NSString
        guard full.length > 0, full.location + full.length <= raw.length else { return full }
        let tail = raw.character(at: full.location + full.length - 1)
        if tail == 10 || tail == 13 { return NSRange(location: full.location, length: full.length - 1) }
        return full
    }

    func linkString(at location: Int) -> String? {
        guard let textView, textView.textStorage.length > 0 else { return nil }
        let index = min(location, textView.textStorage.length - 1)
        return textView.textStorage.attributes(at: index, effectiveRange: nil)[CampMark.link] as? String
    }



    func present(_ alert: UIAlertController) {
        guard let textView else { return }
        var found: UIViewController?
        var responder: UIResponder? = textView
        while let next = responder?.next {
            if let controller = next as? UIViewController { found = controller }
            responder = next
        }
        var top = found ?? textView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(alert, animated: true)
    }

    func keyboard(_ note: Notification) {
        guard let textView, let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let space = textView.window?.screen.coordinateSpace ?? textView
        let local = textView.convert(frame, from: space)
        let covered = max(0, textView.bounds.maxY - local.minY)
        textView.contentInset.bottom = covered
        textView.verticalScrollIndicatorInsets.bottom = covered
        textView.scrollRangeToVisible(textView.selectedRange)
    }
}

final class FormatBar: UIView {
    let scroll = UIScrollView()
    let stack = UIStackView()
    let bold = FormatBar.tool("bold", "Bold")
    let italic = FormatBar.tool("italic", "Italic")
    let strike = FormatBar.tool("strikethrough", "Strikethrough")
    let style = FormatBar.tool("textformat", "Style")
    let bullet = FormatBar.tool("list.bullet", "Bullet list")
    let number = FormatBar.tool("list.number", "Numbered list")
    let link = FormatBar.tool("link", "Link")
    let photo = FormatBar.tool("photo", "Image")
    let rule = FormatBar.tool("minus", "Divider")
    let done = UIButton(type: .system)
    private let hairline = UIView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        autoresizingMask = .flexibleWidth
        backgroundColor = Ink.uiPaper
        hairline.backgroundColor = Ink.uiRule
        hairline.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)
        addSubview(scroll)
        scroll.addSubview(stack)
        [bold, italic, strike, style, bullet, number, link, photo, rule].forEach { stack.addArrangedSubview($0) }
        done.setTitle("Done", for: .normal)
        done.setTitleColor(Ink.uiEmber, for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        done.translatesAutoresizingMaskIntoConstraints = false
        addSubview(done)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            done.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            done.topAnchor.constraint(equalTo: topAnchor),
            done.bottomAnchor.constraint(equalTo: bottomAnchor),
            done.widthAnchor.constraint(equalToConstant: 64),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    func updateAppearance() {
        backgroundColor = Ink.uiPaper
        hairline.backgroundColor = Ink.uiRule
        done.setTitleColor(Ink.uiEmber, for: .normal)
        for button in [bold, italic, strike, style, bullet, number, link, photo, rule] {
            button.tintColor = Ink.uiInk
        }
    }

    private static func tool(_ symbol: String, _ label: String) -> UIButton {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        button.setImage(image, for: .normal)
        button.tintColor = Ink.uiInk
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }
}

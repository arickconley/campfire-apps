import Foundation

@MainActor
enum SharedChecks {
    static let samples = [
        "<p>Hello &amp; <strong>bold <em>and italic</em></strong> <s>gone</s>.</p>",
        "<h2>Heading</h2><blockquote><p>A quote</p></blockquote><hr/>",
        "<p><a href=\"https://example.test/?a=1&amp;b=2\">Link</a><br/>Next line</p>",
        "<p><a href=\"/large\"><img src=\"/image.png\" alt=\"\"/></a></p>",
        "<pre><code class=\"language-go\">if a &lt; b {\n  print(&quot;x&quot;)\n}</code></pre>",
        "<ul><li>First<ul><li>Nested</li></ul></li><li>Last</li></ul>",
        "<ol start=\"3\"><li>First<ol start=\"5\"><li>Nested</li></ol></li><li>Last</li></ol>",
        "<p><a href=\"/somewhere\" title=\"Link title\">Linked text</a><img src=\"/image.png\" alt=\"Caption\" title=\"Image title\"/></p>",
        "<p><strong><code>inline code</code></strong></p>",
        "<p>First</p><p></p><p>Last</p>"
    ]

    static func run() async throws {
        assert(RichInk.normalizedURL(" example.test ") == "https://example.test")
        assert(RichInk.normalizedURL(" /image.png ") == "/image.png")
        assert(RichInk.normalizedURL("https://example.test") == "https://example.test")
        assert(RichInk.normalizedURL(" ").isEmpty)
        assert(RichInk.strike([.strikethroughStyle: NSNumber(value: 1)]))
        assert(!RichInk.strike([:]))

        let appearance = AppAppearance.shared
        let original = (appearance.theme, appearance.accent, appearance.typeface, appearance.fontSize, appearance.mode)
        defer {
            appearance.theme = original.0
            appearance.accent = original.1
            appearance.typeface = original.2
            appearance.fontSize = original.3
            appearance.mode = original.4
        }
        for typeface in AppAppearance.Typeface.allCases {
            for sample in samples {
                appearance.reset()
                let note = try RichNote(html: sample)
                let storage = NSMutableAttributedString(attributedString: RichInk.render(note))
                assert(RichInk.note(storage).html == note.html)
                let text = storage.string
                appearance.typeface = typeface
                appearance.fontSize = 26
                appearance.theme = .forest
                appearance.mode = .dark
                RichInk.restyle(storage, previousFontSize: 20)
                assert(storage.string == text)
                assert(RichInk.note(storage).html == note.html, "Restyling with \(typeface) changed HTML")
                assert(RichInk.note(RichInk.render(note)).html == note.html, "Rendering with \(typeface) changed HTML")
            }
        }
        appearance.reset()

        URLProtocol.registerClass(HTMLAPIProtocol.self)
        defer { URLProtocol.unregisterClass(HTMLAPIProtocol.self) }
        HTMLAPIProtocol.format = "html"
        HTMLAPIProtocol.payload = "[]"
        var connection = BlogConnectionDraft()
        connection.name = " Field Notes "
        connection.baseURL = #"{"url":"http://format-check.invalid","token":" fixture-token "}"#
        let verified = try await connection.verified()
        assert(verified.baseURL == "http://format-check.invalid")
        assert(verified.name == "Field Notes" && verified.token == "fixture-token")
        for invalidURL in ["file:///tmp/site", "https://user:secret@format-check.invalid", "http://format-check.invalid?token=secret"] {
            connection.baseURL = invalidURL
            connection.token = "fixture-token"
            do {
                _ = try await connection.verified()
                assertionFailure("Invalid server address was accepted")
            } catch {}
        }
        connection.baseURL = "http://format-check.invalid"
        connection.token = ""
        do {
            _ = try await connection.verified()
            assertionFailure("An empty token was accepted")
        } catch {}
        HTMLAPIProtocol.format = nil
        connection.token = "fixture-token"
        do {
            _ = try await connection.verified()
            assertionFailure("An incompatible server was accepted")
        } catch {}
        HTMLAPIProtocol.format = "html"
        print("Shared checks passed: font round trips, lossless restyling, URL handling, and blog connection validation.")
    }
}

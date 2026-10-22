import AppKit
import Foundation

@main
struct MacUXChecks {
    @MainActor
    static func main() async throws {
        try await SharedChecks.run()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("campfire-checks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = MacDrafts(directory: directory)
        let legacyBlogData = Data(#"{"id":"00000000-0000-0000-0000-000000000001","baseURL":"https://blog.example:8080"}"#.utf8)
        var namedBlog = try JSONDecoder().decode(Blog.self, from: legacyBlogData)
        assert(namedBlog.name == nil && namedBlog.label == "blog.example:8080")
        namedBlog.name = "  Field Notes \n"
        assert(namedBlog.label == "Field Notes")
        let savedBlog = try JSONDecoder().decode(Blog.self, from: JSONEncoder().encode(namedBlog))
        assert(savedBlog == namedBlog && savedBlog.label == "Field Notes")
        namedBlog.name = " \n"
        assert(namedBlog.label == "blog.example:8080")
        namedBlog.name = "Field Notes"
        namedBlog.baseURL = "https://another.example"
        assert(namedBlog.label == "Field Notes")

        let blog = UUID()
        let location = drafts.location(blog: blog, slug: "../a/b")
        let newLocation = drafts.location(blog: blog, slug: nil)
        assert(location.deletingLastPathComponent() == directory.appendingPathComponent(blog.uuidString, isDirectory: true))
        assert(location != newLocation)
        assert(location != drafts.location(blog: UUID(), slug: "../a/b"))
        assert(try! drafts.read(location) == nil)
        let copy = MacDraft(title: "Unfinished", date: "2026-10-18T12:00:00Z", body: "<p>Keep <strong>this</strong> writing.</p>", draft: true)
        try drafts.write(copy, to: location)
        assert(try! drafts.read(location) == copy)
        let permissions = try FileManager.default.attributesOfItem(atPath: location.path)[.posixPermissions] as? Int
        assert(permissions == 0o600)

        let published = Post(slug: "a", title: "Published", date: "2026-10-18T13:00:00Z", draft: false, url: "/posts/a/", body: "<p>Original body.</p>")
        let defaults = UserDefaults.standard
        let oldBlogs = defaults.object(forKey: "campfire.blogs")
        let oldBlogID = defaults.object(forKey: "campfire.blogID")
        defer {
            defaults.set(oldBlogs, forKey: "campfire.blogs")
            defaults.set(oldBlogID, forKey: "campfire.blogID")
        }
        defaults.set(try JSONEncoder().encode([namedBlog]), forKey: "campfire.blogs")
        defaults.set(namedBlog.id.uuidString, forKey: "campfire.blogID")
        let namedStore = PostsStore()
        namedStore.posts = [published]
        namedStore.rename(id: namedBlog.id, name: "  Fireside Journal  ")
        assert(namedStore.current?.label == "Fireside Journal")
        assert(namedStore.currentID == namedBlog.id && namedStore.posts == [published])
        assert(PostsStore().current?.label == "Fireside Journal")
        namedStore.rename(id: namedBlog.id, name: " ")
        assert(namedStore.current?.label == "another.example")
        var rename = BlogConnectionDraft(blog: namedStore.current)
        rename.name = "Offline Name"
        let verifiedRename = try await rename.verified()
        assert(verifiedRename.connectionUnchanged)
        verifiedRename.save(to: namedStore)
        assert(namedStore.current?.label == "Offline Name" && namedStore.posts == [published])


        let session = MacEditorSession()
        assert(session.draft)
        try session.open(post: published, recoveryLocation: location)
        let text = mount(session)
        assert(session.recovered && session.isDirty)
        assert(session.title == copy.title && session.html() == copy.body)
        // Recovery restores writing, while the server remains authoritative about publication and date.
        assert(!session.draft && session.date == published.date)
        assert(text.string == "Keep this writing.")
        session.discardRecovery()
        _ = mount(session, text: text)
        assert(!session.isDirty && !session.recovered)
        assert(session.title == published.title && session.html() == published.body)
        assert(try! drafts.read(location) == nil)

        session.metaDescription = "A description saved locally."
        assert(session.isDirty)
        assert(try! drafts.read(location)?.metaDescription == session.metaDescription)
        let descriptionRecovery = MacEditorSession()
        try descriptionRecovery.open(post: published, recoveryLocation: location)
        assert(descriptionRecovery.metaDescription == session.metaDescription && descriptionRecovery.isDirty)
        session.discardRecovery()
        _ = mount(session, text: text)
        assert(session.metaDescription.isEmpty && !session.isDirty)
        session.title = "A changed title"
        assert(session.isDirty)
        assert(try! drafts.read(location)?.title == "A changed title")
        session.title = published.title
        assert(!session.isDirty)
        assert(try! drafts.read(location) == nil)
        text.textStorage?.append(NSAttributedString(string: " More writing.", attributes: RichInk.bodyAttributes()))
        session.changed()
        assert(session.isDirty)
        assert(try! drafts.read(location)?.body == "<p>Original body. More writing.</p>")
        let reopened = MacEditorSession()
        try reopened.open(post: published, recoveryLocation: location)
        let reopenedText = mount(reopened)
        assert(reopened.recovered && reopened.isDirty && reopenedText.string.contains("More writing."))
        reopened.markClean()
        assert(!reopened.isDirty && !reopened.recovered)
        assert(try! drafts.read(location) == nil)

        let compose = MacEditorSession()
        try compose.open(post: nil, recoveryLocation: newLocation)
        let composeText = mount(compose)
        compose.title = "Title only"
        assert(try! drafts.read(newLocation)?.title == "Title only")
        let recoveredCompose = MacEditorSession()
        try recoveredCompose.open(post: nil, recoveryLocation: newLocation)
        let recoveredText = mount(recoveredCompose)
        assert(recoveredCompose.draft && recoveredCompose.title == "Title only" && recoveredCompose.isDirty)
        assert(composeText.string.isEmpty && recoveredText.string.isEmpty)
        recoveredCompose.discardRecovery()
        assert(try! drafts.read(newLocation) == nil)

        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let failed = MacEditorSession()
        try failed.open(post: nil, recoveryLocation: blocked.appendingPathComponent("draft.json"))
        let failedText = mount(failed)
        failed.title = "Still in memory"
        assert(failed.recoveryError != nil && failed.isDirty && failedText.string.isEmpty)

        let corrupt = directory.appendingPathComponent("unreadable.json")
        let invalid = Data("unreadable recovery".utf8)
        try invalid.write(to: corrupt)
        let unreadable = MacEditorSession()
        try unreadable.open(post: published, recoveryLocation: corrupt)
        let unreadableText = mount(unreadable)
        assert(unreadable.recoveryError != nil && unreadableText.string == "Original body.")
        unreadable.title = "Preserve the unreadable copy"
        unreadable.persistRecovery()
        assert(try! Data(contentsOf: corrupt) == invalid)
        assert(unreadable.recoveryError != nil)

        let draft = Post(slug: "b", title: "Café thoughts", date: "", draft: true, url: "", body: "")
        assert(MacPostFilter.all.includes(published, search: "  PUBLISHED \n"))
        assert(MacPostFilter.drafts.includes(draft, search: "cafe"))
        assert(!MacPostFilter.drafts.includes(published, search: ""))
        assert(MacPostFilter.published.includes(published, search: ""))
        assert(!MacPostFilter.published.includes(draft, search: ""))
        assert(!MacPostFilter.all.includes(draft, search: "missing"))
        let samples = SharedChecks.samples
        let settingsDomain = "campfire-appearance-checks-\(UUID())"
        let settingsDefaults = UserDefaults(suiteName: settingsDomain)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsDomain) }
        settingsDefaults.set("unknown", forKey: "campfire.theme")
        settingsDefaults.set("unknown", forKey: "campfire.appearanceMode")
        settingsDefaults.set(200, forKey: "campfire.fontSize")
        let preferences = AppAppearance(defaults: settingsDefaults)
        assert(preferences.theme == .campfire && preferences.fontSize == 20 && preferences.mode == .system)
        preferences.mode = .dark
        preferences.theme = .forest
        preferences.accent = .ocean
        preferences.typeface = .mono
        preferences.fontSize = 24
        let restoredPreferences = AppAppearance(defaults: settingsDefaults)
        assert(restoredPreferences.mode == .dark)
        assert(restoredPreferences.theme == .forest && restoredPreferences.accent == .ocean)
        assert(restoredPreferences.typeface == .mono && restoredPreferences.fontSize == 24)
        preferences.reset()
        assert(preferences.mode == .system && preferences.mode.appKitAppearance == nil)
        assert(AppAppearance.Mode.dark.appKitAppearance?.name == .darkAqua)
        assert(AppAppearance.Mode.light.appKitAppearance?.name == .aqua)
        assert(preferences.theme == .campfire && preferences.accent == .ember)
        assert(preferences.typeface == .serif && preferences.fontSize == 20)

        let appearance = AppAppearance.shared
        let originalAppearance = (appearance.theme, appearance.accent, appearance.typeface, appearance.fontSize, appearance.mode)
        defer {
            appearance.theme = originalAppearance.0
            appearance.accent = originalAppearance.1
            appearance.typeface = originalAppearance.2
            appearance.fontSize = originalAppearance.3
            appearance.mode = originalAppearance.4
        }
        appearance.reset()
        for theme in AppAppearance.Theme.allCases {
            appearance.theme = theme
            let light = NSAppearance(named: .aqua)!
            let dark = NSAppearance(named: .darkAqua)!
            let lightPaper = rgb(Ink.uiPaper, appearance: light)
            let darkPaper = rgb(Ink.uiPaper, appearance: dark)
            assert(lightPaper[0] > darkPaper[0] && lightPaper[1] > darkPaper[1])
            for color in [Ink.uiInk, Ink.uiMoss] {
                assert(contrast(rgb(color, appearance: light), lightPaper) >= 4.5)
                assert(contrast(rgb(color, appearance: dark), darkPaper) >= 4.5)
            }
            for accent in AppAppearance.Accent.allCases {
                appearance.accent = accent
                assert(contrast(rgb(Ink.uiEmber, appearance: light), lightPaper) >= 4.5)
                assert(contrast(rgb(Ink.uiEmber, appearance: dark), darkPaper) >= 4.5)
            }
        }
        appearance.reset()
        let styledSession = MacEditorSession()
        let styledPost = Post(slug: "style", title: "Keep my writing", date: published.date, draft: true,
                              url: "", body: samples.joined())
        try styledSession.open(post: styledPost, recoveryLocation: directory.appendingPathComponent("appearance.json"))
        let styledText = mount(styledSession)
        let originalHTML = styledSession.html()
        assert(!styledSession.isDirty)
        appearance.theme = .forest
        styledSession.applyAppearance(previousFontSize: appearance.fontSize)
        assert(!styledSession.isDirty && styledSession.html() == originalHTML)
        styledText.textStorage?.append(NSAttributedString(string: "\nUnfinished line\n", attributes: RichInk.bodyAttributes()))
        styledSession.changed()
        styledText.setSelectedRange(NSRange(location: 3, length: 4))
        let unsavedHTML = styledSession.html()
        let unsavedText = styledText.string
        var previousSize = appearance.fontSize
        for typeface in AppAppearance.Typeface.allCases {
            appearance.typeface = typeface
            appearance.fontSize = 26
            appearance.theme = .dusk
            appearance.mode = .dark
            appearance.accent = .plum
            styledSession.applyAppearance(previousFontSize: previousSize)
            previousSize = appearance.fontSize
            assert(styledText.string == unsavedText)
            assert(styledSession.html() == unsavedHTML && styledSession.isDirty,
                   "Appearance \(typeface) changed HTML: \(unsavedHTML) -> \(styledSession.html())")
            assert(styledText.selectedRange() == NSRange(location: 3, length: 4))
            for sample in samples {
                let canonical = try RichNote(html: sample).html
                let note = try RichNote(html: canonical)
                assert(RichInk.note(RichInk.render(note)).html == canonical)
            }
        }
        appearance.reset()
        styledSession.applyAppearance(previousFontSize: previousSize)
        assert(styledSession.html() == unsavedHTML && originalHTML != unsavedHTML)

        do {
            _ = try RichNote(html: "<script>alert(1)</script>")
            assertionFailure("Unsupported HTML must not be silently discarded")
        } catch {}
        let oldLocation = directory.appendingPathComponent("old-markdown.json")
        try Data(#"{"title":"Legacy","date":"","body":"Keep **this** writing.","draft":true}"#.utf8).write(to: oldLocation)
        assert(try! drafts.read(oldLocation)?.body == "<p>Keep <strong>this</strong> writing.</p>")
        URLProtocol.registerClass(HTMLAPIProtocol.self)
        defer { URLProtocol.unregisterClass(HTMLAPIProtocol.self) }
        let api = CampfireAPI(baseURL: "http://format-check.invalid", token: "fixture-token")
        HTMLAPIProtocol.format = nil
        do {
            _ = try await api.list()
            assertionFailure("An older server must be rejected even when its post list is empty")
        } catch {}
        HTMLAPIProtocol.format = "html"
        let emptyPosts = try await api.list()
        assert(emptyPosts.isEmpty)
        HTMLAPIProtocol.payload = #"{"slug":"new","title":"HTML","date":"2026-10-18T14:00:00Z","draft":true,"url":"/posts/new","body":"<p>Body</p>","format":"html"}"#
        _ = try await api.create(title: "HTML", body: "<p>Body</p>", draft: true)
        assert(HTMLAPIProtocol.contentType == "application/vnd.campfire.html+json")
        HTMLAPIProtocol.payload = HTMLAPIProtocol.payload.replacingOccurrences(of: #""format":"html""#, with: #""format":"html","metaDescription":"A short description.""#)
        let described = try await api.create(title: "HTML", body: "<p>Body</p>", draft: true, metaDescription: "A short description.")
        assert(described.metaDescription == "A short description.")
        assert(HTMLAPIProtocol.contentType == "application/vnd.campfire.description+json")
        let sentPost = try JSONSerialization.jsonObject(with: HTMLAPIProtocol.body!) as! [String: Any]
        assert(sentPost["metaDescription"] as? String == described.metaDescription)
        _ = try await api.update(slug: "new", title: "HTML", date: described.date, body: "<p>Body</p>", draft: true, metaDescription: "")
        let clearedPost = try JSONSerialization.jsonObject(with: HTMLAPIProtocol.body!) as! [String: Any]
        assert(clearedPost["metaDescription"] as? String == "")
        HTMLAPIProtocol.statusCode = 415
        do {
            _ = try await api.create(title: "HTML", body: "<p>Body</p>", draft: true, metaDescription: "Summary")
            assertionFailure("An old server must reject description writes")
        } catch {
            assert(error.localizedDescription.contains("Update the Campfire server"))
        }
        HTMLAPIProtocol.statusCode = 200
        let legacyResponse = HTMLAPIProtocol.payload.replacingOccurrences(of: #","format":"html""#, with: "")
        do {
            _ = try JSONDecoder().decode(Post.self, from: Data(legacyResponse.utf8))
            assertionFailure("A post without an explicit HTML format must be rejected")
        } catch {}
        print("Mac UX, HTML, and appearance checks passed: font round trips, preference persistence, unsaved text preservation, recovery, and search/filtering.")

    }

    static func rgb(_ color: NSColor, appearance: NSAppearance) -> [Double] {
        var components: [Double] = []
        appearance.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(.sRGB)!
            components = [Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent)]
        }
        return components
    }

    static func contrast(_ first: [Double], _ second: [Double]) -> Double {
        func luminance(_ components: [Double]) -> Double {
            let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @MainActor
    static func mount(_ session: MacEditorSession, text: NSTextView? = nil) -> NSTextView {
        let text = text ?? NSTextView()
        text.textStorage?.setAttributedString(RichInk.render(try! RichNote(html: session.html())))
        session.markPushed(text)
        return text
    }
}

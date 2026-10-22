import AppKit
import SwiftUI

@MainActor
@Observable
final class EditorBridge {
    var session: MacEditorSession?
    var requestNew = 0
    var busy = false
    var siteEditing = false
    var canSave = false
    var save: (() async -> Bool)?

    func perform(_ action: @escaping () -> Void) {
        guard !busy else { return }
        guard let session, session.isDirty else {
            action()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save changes before continuing?"
        let saveToBlog = canSave && !session.isEmpty
        alert.informativeText = saveToBlog
            ? (session.draft ? "Save this draft to your blog, discard your edits, or keep editing."
               : "Saving will update the published post on your blog.")
            : "Keep your unfinished writing on this Mac and continue, or keep editing."
        alert.addButton(withTitle: saveToBlog
                        ? (session.draft ? "Save and Continue" : "Update Published Post and Continue")
                        : "Keep on This Mac and Continue")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if saveToBlog {
                Task { if await save?() == true { action() } }
            } else {
                session.persistRecovery()
                if session.recoveryError == nil { action() }
            }
        case .alertSecondButtonReturn:
            session.discardRecovery()
            if session.recoveryError == nil { action() }
        default:
            break
        }
    }
}

enum Pane: Hashable {
    case post(String)
    case compose
}

private enum Move: Equatable {
    case editor(Pane?)
    case blog(UUID)
    case editBlog
}

struct MacRootView: View {
    @Environment(PostsStore.self) private var store
    @Environment(EditorBridge.self) private var bridge

    @State private var pane: Pane?
    @State private var adding = false
    @State private var showSiteEditor = false
    @State private var editing = false
    @State private var search = ""
    @State private var filter = MacPostFilter.all
    @State private var pendingDelete: String?
    @State private var pendingBlog: Blog?
    @State private var deleteError: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(AppearanceStyle())
        .containerBackground(Ink.paper, for: .window)
        .toolbarBackground(Ink.paper, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onChange(of: showSiteEditor) { _, shown in bridge.siteEditing = shown }
        .sheet(isPresented: $showSiteEditor) {
            SiteEditor(api: CampfireAPI(baseURL: store.current?.baseURL ?? "", token: store.token),
                       blogName: store.current?.label ?? "Campfire")
        }
        .sheet(isPresented: $adding) {
            MacBlogForm()
        }
        .sheet(isPresented: $editing) {
            MacBlogForm(blog: store.current)
        }
        .onChange(of: [store.current?.id.uuidString, store.current?.baseURL]) { _, _ in
            pane = nil
            search = ""
            filter = .all
        }
        .onChange(of: store.isLoading) { _, loading in
            if !loading { restorePane() }
        }
        .onChange(of: pane) { _, pane in
            guard let pane, let blog = store.current else { return }
            let value: String
            switch pane {
            case .compose: value = ""
            case .post(let slug): value = slug
            }
            UserDefaults.standard.set(value, forKey: "campfire.lastPane.\(blog.id)")
        }
        .alert("Remove this blog?", isPresented: blogRemovePresented) {
            Button("Remove", role: .destructive) {
                if let pendingBlog { bridge.perform { store.remove(pendingBlog.id) } }
                pendingBlog = nil
            }
            Button("Cancel", role: .cancel) { pendingBlog = nil }
        } message: {
            Text(pendingBlog?.label ?? "")
        }
        .alert("Delete this post?", isPresented: deletePresented) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Task { await remove(pendingDelete) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .onChange(of: bridge.requestNew) { _, _ in
            go(.editor(.compose))
        }
        .task {
            await store.reload()
            restorePane()
        }
    }

    private var filteredPosts: [Post] {
        store.posts.filter { filter.includes($0, search: search) }
    }

    private var sidebar: some View {
        List(filteredPosts, selection: selection) { post in
            VStack(alignment: .leading, spacing: 2) {
                Text(post.displayTitle)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !post.dateLabel.isEmpty {
                        Text(post.dateLabel)
                            .font(.caption.monospaced())
                            .foregroundStyle(Ink.moss)
                    }
                    if post.draft {
                        Text("Draft")
                            .font(.caption)
                            .foregroundStyle(Ink.ember)
                    }
                }
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button("Delete", role: .destructive) { pendingDelete = post.slug }
                    .disabled(bridge.busy)
            }
            .tag(post.slug)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Ink.paper)
        .overlay {
            if filteredPosts.isEmpty {
                Text(store.isLoading ? "Loading…" : (!store.posts.isEmpty ? "No matching posts." : (store.configured ? "No posts yet." : "No blog yet.")))
                    .foregroundStyle(Ink.moss)
                    .font(.callout)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 12) {
                blogMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("Search posts", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search post titles")
                Picker("Posts", selection: $filter) {
                    ForEach(MacPostFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
        }
        .navigationTitle("Campfire")
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 380)
        .toolbar {
            ToolbarItem {
                Button("Page Editor", systemImage: "doc.text") { showSiteEditor = true }
                    .disabled(!store.configured || bridge.busy)
                    .help("Edit pages, templates, and stylesheets")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Post", systemImage: "square.and.pencil") {
                    go(.editor(.compose))
                }
                .disabled(!store.configured || bridge.busy)
                .help("New post")
            }
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await store.reload() }
                }
                .disabled(!store.configured || store.isLoading || bridge.busy)
                .help("Reload posts")
            }
        }
        .onDeleteCommand {
            guard !bridge.busy else { return }
            if case .post(let slug) = pane { pendingDelete = slug }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = deleteError ?? store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Ink.ink)
                    Button("Reload Posts") {
                        deleteError = nil
                        Task { await store.reload() }
                    }
                    .disabled(store.isLoading || bridge.busy)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    private var blogMenu: some View {
        Menu {
            ForEach(store.blogs) { blog in
                Button {
                    go(.blog(blog.id))
                } label: {
                    if blog.id == store.currentID {
                        Label(blog.label, systemImage: "checkmark")
                    } else {
                        Text(blog.label)
                    }
                }
            }
            if !store.blogs.isEmpty { Divider() }
            Button("Edit Blog…") { go(.editBlog) }
                .disabled(store.current == nil)
            Button("Remove Blog…", role: .destructive) { pendingBlog = store.current }
                .disabled(store.current == nil)
            Button("Add Blog…") { adding = true }
            Divider()
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
        } label: {
            Label(store.current?.label ?? "Add a blog", systemImage: "server.rack")
                .lineLimit(1)
        }
        .disabled(bridge.busy)
        .help("Switch or manage blogs")
        .accessibilityLabel("Blogs: \(store.current?.label ?? "none configured")")
    }

    @ViewBuilder
    private var detail: some View {
        if let pane {
            MacEditorScreen(pane: pane, onCreated: { slug in
                self.pane = .post(slug)
            }, onDeleted: {
                self.pane = nil
            })
            .id("\(store.current?.id.uuidString ?? "")/\(store.current?.baseURL ?? "")/\(pane)")
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Campfire")
                .font(.campTitle())
                .foregroundStyle(Ink.ink)
            if store.configured {
                Text(store.posts.isEmpty ? "No posts yet." : "Select a post.")
                    .foregroundStyle(Ink.moss)
                Button("New Post") { go(.editor(.compose)) }
                    .disabled(!store.configured)
            } else {
                Text("Add a server and write token. A setup code pasted into the server field works too.")
                    .foregroundStyle(Ink.moss)
                    .frame(maxWidth: 420, alignment: .leading)
                Button("Add Blog") { adding = true }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.paper)
        .navigationTitle("Campfire")
    }

    private var selection: Binding<String?> {
        Binding(
            get: {
                if case .post(let slug) = pane { return slug }
                return nil
            },
            set: { slug in
                guard let slug else { return }
                go(.editor(.post(slug)))
            }
        )
    }

    private var blogRemovePresented: Binding<Bool> {
        Binding(get: { pendingBlog != nil }, set: { if !$0 { pendingBlog = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func restorePane() {
        guard pane == nil, let blog = store.current else { return }
        if let saved = UserDefaults.standard.string(forKey: "campfire.lastPane.\(blog.id)") {
            if saved.isEmpty, FileManager.default.fileExists(atPath: MacDrafts().location(blog: blog.id, slug: nil).path) {
                pane = .compose
                return
            }
            if store.posts.contains(where: { $0.slug == saved })
                || (!saved.isEmpty && FileManager.default.fileExists(atPath: MacDrafts().location(blog: blog.id, slug: saved).path)) {
                pane = .post(saved)
                return
            }
        }
        if let first = store.posts.first { pane = .post(first.slug) }
    }

    private func go(_ move: Move) {
        if case .editor(let next) = move, next == pane { return }
        if case .blog(let id) = move, id == store.currentID { return }
        if case .editor(.compose) = move, !store.configured { return }
        if move == .editBlog {
            editing = store.current != nil
        } else {
            bridge.perform { apply(move) }
        }
    }

    private func apply(_ move: Move) {
        switch move {
        case .editor(let next):
            pane = next
        case .blog(let id):
            store.select(id)
            pane = nil
        case .editBlog:
            editing = store.current != nil
        }
    }

    private func remove(_ slug: String) async {
        guard !bridge.busy, let blog = store.current else { return }
        bridge.busy = true
        defer { bridge.busy = false }
        do {
            try await store.delete(slug: slug)
            if case .post(let open) = pane, open == slug { pane = nil }
            do {
                try MacDrafts().remove(MacDrafts().location(blog: blog.id, slug: slug))
                deleteError = nil
            } catch {
                deleteError = "The post was deleted, but its local recovery copy could not be removed. \(error.localizedDescription)"
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct MacEditorScreen: View {
    var pane: Pane
    var onCreated: (String) -> Void
    var onDeleted: () -> Void

    @Environment(PostsStore.self) private var store
    @Environment(EditorBridge.self) private var bridge
    @State private var session = MacEditorSession()
    @State private var saving = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var confirmPublish = false
    @State private var confirmUnpublish = false
    @State private var compactToolbar = true
    @State private var loading = true
    @State private var loaded = false
    @State private var retry: Retry?
    @FocusState private var titleFocused: Bool

    private enum Retry {
        case load, save(Bool), delete
    }

    private var slug: String? {
        if case .post(let slug) = pane { return slug }
        return nil
    }

    var body: some View {
        ZStack {
            Ink.paper
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 16) {
                    if let message {
                        HStack(alignment: .top) {
                            Label(message, systemImage: "exclamationmark.triangle")
                            Spacer()
                            Button("Retry") { Task { await retryOperation() } }
                                .disabled(loading || saving)
                        }
                        .font(.callout)
                        .foregroundStyle(Ink.ink)
                    }
                    if let error = session.recoveryError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Ink.ink)
                        Button("Retry Local Recovery") { session.retryRecovery() }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Untitled post", text: $session.title, axis: .vertical)
                            .focused($titleFocused)
                            .lineLimit(1...3)
                            .font(.system(size: 30, weight: .semibold, design: AppAppearance.shared.typeface.design))
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Post title")
                            .disabled(loading || (!loaded && !session.recovered))
                        HStack(spacing: 12) {
                            Label(session.draft ? "Draft" : "Published", systemImage: session.draft ? "doc" : "globe")
                            if loading || saving { ProgressView().controlSize(.small) }
                            Text(status)
                                .accessibilityLabel("Save status: \(status)")
                        }
                        .font(.caption)
                        .foregroundStyle(Ink.moss)
                    }
                    .padding(.bottom, 8)
                    MetaDescriptionEditor(text: $session.metaDescription, title: session.title, html: { session.html() })
                        .disabled(loading || (!loaded && !session.recovered))
                    ZStack(alignment: .topLeading) {
                        MacText(session: session, revision: session.revision, appearanceRevision: AppAppearance.shared.revision)
                            .disabled(loading || (!loaded && !session.recovered))
                        if session.isEmpty {
                            Text("Write")
                                .font(.system(size: AppAppearance.shared.fontSize, design: AppAppearance.shared.typeface.design))
                                .foregroundStyle(Ink.moss)
                                .padding(.top, 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: 680, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, 24)
                .padding(.bottom, 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .navigationTitle("Campfire")
        .onGeometryChange(for: Bool.self) { $0.size.width < 660 } action: { compactToolbar = $0 }
        .disabled(saving || bridge.busy)
        .toolbar { editorToolbar }
        .sheet(item: prompt) { insert in
            MacInsertSheet(insert: insert) { address, extra in
                if insert.kind == .link {
                    session.commitLink(insert, url: address, label: extra)
                } else {
                    session.commitImage(insert, url: address, caption: extra)
                }
            }
        }
        .alert("Delete this post?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Publish this post?", isPresented: $confirmPublish) {
            Button("Publish") { Task { _ = await save(draft: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This post will be public on \(store.current?.label ?? "your blog").")
        }
        .alert("Move this post to drafts?", isPresented: $confirmUnpublish) {
            Button("Move to Drafts") { Task { _ = await save(draft: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the post from your public blog.")
        }
        .onAppear {
            bridge.session = session
            bridge.canSave = loaded
            bridge.save = { await save() }
        }
        .onDisappear {
            if bridge.session === session {
                bridge.session = nil
                bridge.canSave = false
                bridge.save = nil
            }
        }
        .task { await load() }
    }

    private var status: String {
        if loading { return "Loading…" }
        if saving { return "Saving…" }
        if message != nil { return "Needs attention" }
        if session.recoveryError != nil { return "Local recovery unavailable" }
        if session.recovered && session.isDirty { return "Recovered unsaved changes · saved on this Mac" }
        if session.isDirty { return "Unsaved changes · saved on this Mac" }
        return slug == nil ? "Not saved to blog" : "Saved"
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if !compactToolbar {
                formatCluster {
                    face("Bold", "bold", session.boldOn) { session.toggleBold() }
                    face("Italic", "italic", session.italicOn) { session.toggleItalic() }
                }
            }
            Menu {
                if compactToolbar {
                    Button("Bold") { session.toggleBold() }
                    Button("Italic") { session.toggleItalic() }
                    Button("Bullet List") { session.toggleBullet() }
                    Button("Numbered List") { session.toggleNumber() }
                    Divider()
                }
                style("Body", nil)
                style("Heading", "h1")
                style("Subheading", "h2")
                style("Small heading", "h3")
                Divider()
                style("Quote", "quote")
                style("Code", "code")
                Divider()
                Button("Strikethrough") { session.toggleStrike() }
            } label: {
                Label(session.styleTitle, systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(compactToolbar ? "Formatting" : "Style")
            .disabled(loading || saving || !loaded)
            if !compactToolbar {
                formatCluster {
                    face("Bullet list", "list.bullet", session.bulletOn) { session.toggleBullet() }
                    face("Numbered list", "list.number", session.numberOn) { session.toggleNumber() }
                }
            }
            Menu {
                Button("Link…", systemImage: "link") { session.beginLink() }
                Button("Image…", systemImage: "photo") { session.beginImage() }
                Button("Divider", systemImage: "minus") { session.applyBlock("hr") }
            } label: {
                Label("Insert", systemImage: "plus")
            }
            .help("Insert a link, image, or divider")
            .disabled(loading || saving || !loaded)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(session.draft ? "Save Draft" : "Update Published Post") { Task { _ = await save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(bridge.busy || saving || !loaded || session.isEmpty || (slug != nil && !session.isDirty))
            if session.draft {
                Button("Publish…") { confirmPublish = true }
                    .disabled(bridge.busy || saving || !loaded || session.isEmpty)
            }
            if slug != nil {
                Menu {
                    if !session.draft {
                        Button("Move to Drafts…") { confirmUnpublish = true }
                    }
                    Button("Delete Post…", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("Post Actions", systemImage: "ellipsis.circle")
                }
                .help("Post actions")
                .disabled(loading || saving || !loaded)
            }
        }
    }

    private func formatCluster<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ControlGroup(content: content)
            .controlGroupStyle(.navigation)
            .labelStyle(.iconOnly)
            .disabled(loading || saving || !loaded)
    }

    private func face(_ title: String, _ symbol: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { _ in action() })) {
            Image(systemName: symbol)
        }
        .toggleStyle(.button)
        .help(title)
        .accessibilityLabel(title)
        .disabled(loading || saving || !loaded)
    }

    private func style(_ title: String, _ name: String?) -> some View {
        Button {
            session.applyBlock(name)
        } label: {
            if session.styleMatches(name) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var prompt: Binding<MacInsert?> {
        Binding(get: { session.prompt }, set: { session.prompt = $0 })
    }

    private func load() async {
        guard let blog = store.current else { return }
        loading = true
        bridge.busy = true
        defer { loading = false; bridge.busy = false }
        let location = MacDrafts().location(blog: blog.id, slug: slug)
        do {
            let post: Post?
            if let slug { post = try await store.read(slug: slug) } else { post = nil }
            guard !Task.isCancelled else { return }
            try session.open(post: post, recoveryLocation: location)
            loaded = true
            bridge.canSave = true
            titleFocused = slug == nil && !session.recovered
            message = nil
            retry = nil
        } catch {
            guard !Task.isCancelled else { return }
            if !loaded {
                do { try session.open(post: nil, recoveryLocation: location) }
                catch { message = error.localizedDescription; retry = .load; return }
            }
            message = error.localizedDescription + (session.recovered
                ? " Your recovered edits are kept on this Mac. Retry loading before saving."
                : " Retry to load this post.")
            retry = .load
        }
    }

    private func save(draft: Bool? = nil) async -> Bool {
        guard loaded, !saving, !bridge.busy, !session.isEmpty else { return false }
        let draft = draft ?? session.draft
        saving = true
        bridge.busy = true
        defer { saving = false; bridge.busy = false }
        do {
            let post = try await store.save(
                slug: slug,
                title: session.title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: session.date,
                body: session.html(),
                draft: draft,
                metaDescription: session.metaDescription
            )
            session.title = post.title
            session.metaDescription = post.metaDescription ?? ""
            session.draft = post.draft
            session.date = post.date
            session.markClean()
            message = nil
            retry = nil
            if slug == nil { onCreated(post.slug) }
            return true
        } catch {
            message = error.localizedDescription + " Your edits have not been saved to the blog."
            retry = .save(draft)
            return false
        }
    }

    private func remove() async {
        guard let slug, !bridge.busy else { return }
        saving = true
        bridge.busy = true
        defer { saving = false; bridge.busy = false }
        do {
            try await store.delete(slug: slug)
            session.markClean()
            onDeleted()
        } catch {
            message = error.localizedDescription
            retry = .delete
        }
    }

    private func retryOperation() async {
        switch retry {
        case .load: await load()
        case .save(let draft): _ = await save(draft: draft)
        case .delete: await remove()
        case nil: break
        }
    }

}

struct MacInsertSheet: View {
    var insert: MacInsert
    var onCommit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var label: String
    @FocusState private var focused: Bool

    init(insert: MacInsert, onCommit: @escaping (String, String) -> Void) {
        self.insert = insert
        self.onCommit = onCommit
        _address = State(initialValue: insert.existing)
        _label = State(initialValue: insert.selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(insert.kind == .link ? "Link" : "Image")
                .font(.headline)
            TextField("Address", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            TextField(insert.kind == .link ? "Label" : "Caption", text: $label)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onCommit(address, label)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }
}

struct MacBlogsView: View {
    @Environment(PostsStore.self) private var store
    @Environment(EditorBridge.self) private var bridge
    @State private var adding = false
    @State private var editing: Blog?
    @State private var pending: Blog?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your blogs")
                        .font(.title2.weight(.semibold))
                    Text("Choose where you write. Manage each server and its write token.")
                        .font(.callout)
                        .foregroundStyle(Ink.moss)
                }
                Spacer()
                Button("Add Blog…", systemImage: "plus") { adding = true }
                    .disabled(bridge.busy)
            }
            .padding(20)
            Divider()
            if store.blogs.isEmpty {
                ContentUnavailableView {
                    Label("A home for your words", systemImage: "server.rack")
                } description: {
                    Text("Add a blog with its server address and write token, or paste a setup code.")
                } actions: {
                    Button("Add Blog…") { adding = true }
                        .disabled(bridge.busy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.blogs) { blog in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(blog.label)
                                .font(.headline)
                                .foregroundStyle(Ink.ink)
                                .textSelection(.enabled)
                            Spacer()
                            if blog.id == store.currentID {
                                Label("Current blog", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Ink.ember)
                            }
                        }
                        Text(blog.baseURL)
                            .font(.callout.monospaced())
                            .foregroundStyle(Ink.moss)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack {
                            if blog.id != store.currentID {
                                Button("Use This Blog") { bridge.perform { store.select(blog.id) } }
                            }
                            Button("Edit Blog…") { beginEdit(blog) }
                            Spacer()
                            Button("Remove…", role: .destructive) { pending = blog }
                        }
                        .controlSize(.small)
                        .disabled(bridge.busy)
                    }
                    .padding(.vertical, 10)
                }
                .scrollContentBackground(.hidden)
            }
            Divider()
            Label("Removing a blog only disconnects it from this Mac. Your published posts stay on the server.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Ink.moss)
                .padding(16)
        }
        .background(Ink.paper)
        .sheet(isPresented: $adding) { MacBlogForm() }
        .sheet(item: $editing) { blog in
            MacBlogForm(blog: blog)
        }
        .alert("Remove this blog?", isPresented: removePresented) {
            Button("Remove", role: .destructive) {
                if let pending { bridge.perform { store.remove(pending.id) } }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Disconnect \(pending?.label ?? "this blog") from this Mac? Its posts and local recovery copies will be kept.")
        }
    }

    private var removePresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func beginEdit(_ blog: Blog?) {
        editing = blog
    }

}

struct MacBlogForm: View {
    var blog: Blog?

    @Environment(PostsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var connection = BlogConnectionDraft()
    @State private var message: String?
    @State private var confirmRemove = false
    @State private var checking = false
    @State private var verification: Task<Void, Never>?
    @Environment(EditorBridge.self) private var bridge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(blog == nil ? "Add blog" : "Edit blog")
                .font(.headline)
            Text("Paste a setup code, or enter the server and write token.")
                .font(.callout)
                .foregroundStyle(Ink.moss)
            BlogConnectionFields(connection: $connection)
                .disabled(checking)
            if checking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking server and write token…").font(.callout)
                }
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Ink.ink)
            }
            HStack {
                if blog != nil {
                    Button("Remove", role: .destructive) { confirmRemove = true }
                }
                Spacer()
                Button("Cancel") {
                    verification?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(checking ? "Checking…" : (connection.connectionUnchanged ? "Save Changes" : "Verify and Save")) { verify() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(checking || bridge.busy)
            }
        }
        .padding(20)
        .frame(width: 460)
        .alert("Remove this blog?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                if let blog { bridge.perform { store.remove(blog.id); dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(blog?.label ?? "")
        }
        .interactiveDismissDisabled(checking)
        .onDisappear { verification?.cancel() }
        .onChange(of: connection) { _, _ in message = nil }
        .onAppear { connection = BlogConnectionDraft(blog: blog) }
    }

    private func verify() {
        guard !checking, !bridge.busy else { return }
        checking = true
        message = nil
        verification = Task {
            defer { checking = false }
            do {
                let verified = try await connection.verified()
                guard !Task.isCancelled else { return }
                let save = { verified.save(to: store); dismiss() }
                if verified.connectionUnchanged {
                    save()
                } else {
                    bridge.perform(save)
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = "Connection failed: \(error.localizedDescription) Check the server and write token, then try again."
            }
        }
    }
}

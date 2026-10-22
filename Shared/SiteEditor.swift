import SwiftUI

struct SiteEditor: View {
    let api: CampfireAPI
    let blogName: String
    @Environment(\.dismiss) private var dismiss
    @State private var files: [SiteFile] = []
    @State private var selected: SiteFile?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Loading site…") }
                if let message {
                    Text(message).foregroundStyle(Ink.ember)
                    Button("Retry") { Task { await load() } }.disabled(loading)
                }
                fileSection("Pages", kind: "page")
                fileSection("Templates", kind: "template")
                fileSection("Stylesheets", kind: "style")
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle("Page Editor · \(blogName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { file in
                SiteFileEditor(api: api, path: file.path)
            }
            .task { await load() }
        }
        .modifier(AppearanceStyle())
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }

    private func fileSection(_ title: String, kind: String) -> some View {
        Section(title) {
            ForEach(files.filter { $0.kind == kind }) { file in
                Button { selected = file } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.path).foregroundStyle(Ink.ink)
                        if file.isPage && !file.title.isEmpty {
                            Text(file.title).font(.caption).foregroundStyle(Ink.moss)
                        }
                    }
                }
                .disabled(loading)
            }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            files = try await api.siteFiles()
            message = nil
        } catch { message = error.localizedDescription }
    }
}

private struct SiteFileEditor: View {
    let api: CampfireAPI
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var file: SiteFile?
    @State private var source = ""
    @State private var title = ""
    @State private var draft = false
    @State private var originalBody = ""
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var confirmClose = false
    #if os(macOS)
    @State private var session = MacEditorSession()
    #else
    @State private var session = RichTextSession()
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if loading { ProgressView("Loading…") }
                if let message {
                    Text(message).foregroundStyle(Ink.ember).textSelection(.enabled)
                    if file == nil {
                        Button("Retry") { Task { await load() } }.disabled(loading)
                    }
                }
                if let file {
                    if file.isPage {
                        TextField("Title", text: $title)
                            .font(.title2)
                            .accessibilityLabel("Page title")
                        Toggle("Draft", isOn: $draft)
                        #if os(macOS)
                        MacPageText(session: session)
                        #else
                        RichTextView(session: session, revision: session.revision, appearanceRevision: AppAppearance.shared.revision)
                        #endif
                    } else {
                        Text(file.kind == "template"
                             ? "Saving applies this template to your site's saved pages."
                             : "Stylesheet changes may require clearing your site's CDN or browser cache.")
                            .font(.caption).foregroundStyle(Ink.moss)
                        SourceEditor(text: $source)
                            .accessibilityLabel("\(file.kind == "template" ? "Template" : "CSS") source")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ink.paper)
            .disabled(saving)
            .navigationTitle(path)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if isDirty { confirmClose = true } else { dismiss() }
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(file == nil || loading || saving)
                }
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .task { await load() }
        }
        .interactiveDismissDisabled()
        .modifier(AppearanceStyle())
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 580)
        #endif
    }

    private var isDirty: Bool {
        guard let file else { return false }
        return file.isPage
            ? title != file.title || draft != file.draft || session.html() != originalBody
            : source != file.body
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await api.siteFile(path: path)
            if loaded.isPage {
                try session.load(loaded.body)
                // Compare the editor's normalized HTML, not serialization whitespace.
                originalBody = RichInk.note(RichInk.render(try RichNote(html: loaded.body))).html
            }
            title = loaded.title
            draft = loaded.draft
            source = loaded.body
            file = loaded
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func save() async {
        guard var edited = file, !saving else { return }
        saving = true
        defer { saving = false }
        edited.body = edited.isPage ? session.html() : source
        edited.title = title
        edited.draft = draft
        do {
            file = try await api.saveSiteFile(edited)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

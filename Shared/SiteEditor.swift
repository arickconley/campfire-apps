import SwiftUI

struct SiteEditor: View {
    let api: CampfireAPI
    let blogName: String
    @Environment(\.dismiss) private var dismiss
    @State private var files: [SiteFile] = []
    @State private var settings: SiteSettings?
    @State private var settingsNotice: String?
    @State private var showSettings = false
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
                if settings != nil || settingsNotice != nil {
                    Section("Site") {
                        if let settings {
                            Button { showSettings = true } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Site Settings & Theme").foregroundStyle(Ink.ink)
                                        Text(settingsSummary(settings))
                                            .font(.caption)
                                            .foregroundStyle(Ink.moss)
                                    }
                                    Spacer()
                                    Text(settings.usesStyle ? SiteSettings.styleLabel(settings.style) : "Custom CSS")
                                        .font(.callout)
                                        .foregroundStyle(Ink.moss)
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(loading)
                        } else if let settingsNotice {
                            Text(settingsNotice)
                                .font(.caption)
                                .foregroundStyle(Ink.moss)
                        }
                    }
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
            .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) {
                SiteSettingsEditor(api: api)
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

    private func settingsSummary(_ settings: SiteSettings) -> String {
        if settings.url.isEmpty { return settings.title }
        return "\(settings.title) · \(settings.url)"
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
            do {
                settings = try await api.siteSettings()
                settingsNotice = nil
            } catch let error as CampfireError where error.unsupportedEndpoint {
                settings = nil
                settingsNotice = error.localizedDescription
            }
            message = nil
        } catch { message = error.localizedDescription }
    }
}

private struct SiteSettingsEditor: View {
    let api: CampfireAPI
    @Environment(\.dismiss) private var dismiss
    @State private var original: SiteSettings?
    @State private var draft = SiteSettings(title: "")
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView("Loading…") }
                if let message {
                    Text(message).foregroundStyle(Ink.ember).textSelection(.enabled)
                    if original == nil {
                        Button("Retry") { Task { await load() } }.disabled(loading)
                    }
                }
                if let original {
                    Section("Theme") {
                        Picker("Theme", selection: $draft.style) {
                            ForEach(styleChoices(for: original), id: \.self) { option in
                                Text(SiteSettings.styleLabel(option)).tag(option)
                            }
                        }
                        Text(original.usesStyle
                             ? "Chooses the stylesheet in site.yaml and rebuilds saved posts and pages on save."
                             : "templates/layout.html links its own stylesheet instead of {{.Style}}, so changing this setting won’t switch stylesheets unless layout.html uses {{.Style}}.")
                            .font(.caption)
                            .foregroundStyle(Ink.moss)
                    }
                    Section("Site Identity") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title").font(.callout.weight(.medium))
                            TextField("My Blog", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Site title")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description").font(.callout.weight(.medium))
                            TextField("Optional summary for the home page and link previews", text: $draft.description, axis: .vertical)
                                .lineLimit(1...3)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Site description")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Public URL").font(.callout.weight(.medium))
                            TextField("https://your-blog.example", text: $draft.url)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Public site URL")
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                #endif
                            Text("Used for canonical URLs, Open Graph tags, and /sitemap.xml. Leave blank for local-only sites.")
                                .font(.caption)
                                .foregroundStyle(Ink.moss)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .disabled(saving)
            .navigationTitle("Site Settings")
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
                        .disabled(original == nil || loading || saving || !isDirty || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .task { await load() }
            .onChange(of: draft) { _, _ in message = nil }
        }
        .interactiveDismissDisabled()
        .modifier(AppearanceStyle())
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 480)
        #endif
    }

    private var isDirty: Bool {
        guard let original else { return false }
        return draft.title != original.title
            || draft.description != original.description
            || draft.url != original.url
            || draft.style != original.style
    }

    private func styleChoices(for original: SiteSettings) -> [String] {
        var choices = original.styles
        if !choices.contains(original.style) {
            choices.insert(original.style, at: 0)
        }
        return choices
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await api.siteSettings()
            original = loaded
            draft = loaded
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func save() async {
        guard original != nil, !saving else { return }
        let validated: SiteSettings
        do {
            validated = try draft.validated()
        } catch {
            message = error.localizedDescription
            return
        }
        saving = true
        defer { saving = false }
        do {
            let saved = try await api.saveSiteSettings(validated)
            original = saved
            draft = saved
            dismiss()
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

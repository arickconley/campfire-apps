import SwiftUI

struct EditorView: View {
    var slug: String?

    @Environment(PostsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var session = RichTextSession()
    @State private var draft = false
    @State private var date = ""
    @State private var saving = false
    @State private var loading = true
    @State private var loaded = false
    @State private var message: String?
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let message {
                    HStack(alignment: .top) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Ink.ink)
                        if !loaded {
                            Button("Retry") { Task { await load() } }
                                .disabled(loading)
                        }
                    }
                }
                TextField("Title", text: $title)
                    .font(.system(size: 24, design: AppAppearance.shared.typeface.design))
                    .focused($titleFocused)
                    .disabled(!loaded || saving)
                Toggle("Draft", isOn: $draft)
                    .tint(Ink.ember)
                    .disabled(!loaded || saving)
                if loading { ProgressView("Loading post…") }
                RichTextView(session: session, revision: session.revision, appearanceRevision: AppAppearance.shared.revision)
                    .disabled(!loaded || saving)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Ink.paper)
            .navigationTitle(slug == nil ? "New post" : "Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!loaded || saving || session.isEmpty)
                }
                if slug != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
                if titleFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { titleFocused = false }
                    }
                }
            }
            .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        loaded = false
        defer { loading = false }
        guard let slug else { loaded = true; return }
        do {
            let post = try await store.read(slug: slug)
            title = post.title
            try session.load(post.body ?? "")
            draft = post.draft
            date = post.date
            loaded = true
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() async {
        guard loaded, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await store.save(
                slug: slug,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                body: session.html(),
                draft: draft
            )
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove() async {
        guard let slug else { return }
        do {
            try await store.delete(slug: slug)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

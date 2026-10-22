import SwiftUI

struct PostListView: View {
    @Environment(PostsStore.self) private var store
    @State private var showSettings = false
    @State private var showSiteEditor = false
    @State private var scanning = false
    @State private var scanError: String?
    @State private var editor: EditorRoute?

    var body: some View {
        NavigationStack {
            Group {
                if store.posts.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(Ink.paper)
            .navigationTitle(store.current?.label ?? "Campfire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "server.rack")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Page Editor", systemImage: "doc.text") { showSiteEditor = true }
                        .disabled(!store.configured)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = EditorRoute(slug: nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New post")
                    .disabled(!store.configured)
                }
            }
            .refreshable { await store.reload() }
            .sheet(isPresented: $showSiteEditor) {
                SiteEditor(api: CampfireAPI(baseURL: store.current?.baseURL ?? "", token: store.token),
                           blogName: store.current?.label ?? "Campfire")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $scanning) {
                ScannerSheet { raw in
                    guard let code = parseSetupCode(raw) else {
                        scanError = "That code is not a Campfire setup code."
                        return
                    }
                    scanError = nil
                    store.add(baseURL: code.url, token: code.token)
                }
            }
            .sheet(item: $editor) { route in
                EditorView(slug: route.slug)
            }
            .task { await store.reload() }
        }
        .modifier(AppearanceStyle())
    }

    private var list: some View {
        List {
            if let error = store.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Ink.ember)
                    .listRowBackground(Ink.paper)
            }
            ForEach(store.posts) { post in
                Button {
                    editor = EditorRoute(slug: post.slug)
                } label: {
                    row(post)
                }
                .buttonStyle(.plain)
                .listRowBackground(Ink.paper)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            do {
                                try await store.delete(slug: post.slug)
                            } catch {
                                store.error = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ post: Post) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(post.dateLabel)
                .font(.caption.monospaced())
                .foregroundStyle(Ink.moss)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.displayTitle)
                    .font(.campPost())
                    .foregroundStyle(Ink.ink)
                if post.draft {
                    Text("Draft")
                        .font(.caption)
                        .foregroundStyle(Ink.ember)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Campfire")
                .font(.campTitle())
                .foregroundStyle(Ink.ink)
            if let error = store.error {
                Text(error)
                    .foregroundStyle(Ink.ember)
            } else if store.configured {
                Text("No posts yet.")
                    .foregroundStyle(Ink.moss)
            } else {
                Text("Scan the code on a setup page, or add a server and token.")
                    .foregroundStyle(Ink.moss)
                if let scanError {
                    Text(scanError)
                        .foregroundStyle(Ink.ember)
                }
                Button("Scan") { scanning = true }
                    .buttonStyle(.borderedProminent)
                Button("Enter it") { showSettings = true }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

struct EditorRoute: Identifiable {
    var slug: String?
    var id: String { slug ?? "new" }
}

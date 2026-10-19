import SwiftUI

struct SettingsView: View {
    @Environment(PostsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var adding = false
    @State private var editing: Blog?
    @State private var scanning = false
    @State private var scanError: String?
    @State private var pendingDelete: Blog?

    var body: some View {
        NavigationStack {
            List {
                Section("Blogs") {
                    if let scanError {
                        Text(scanError).foregroundStyle(Ink.ember)
                    }
                    if store.blogs.isEmpty {
                        Text("Add a server and write token, or scan its setup code.")
                            .foregroundStyle(Ink.moss)
                        Button("Add Blog") { adding = true }
                    }
                    ForEach(store.blogs) { blog in
                        HStack {
                            Button { store.select(blog.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(blog.label).foregroundStyle(Ink.ink)
                                        Text(blog.baseURL)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Ink.moss)
                                    }
                                    Spacer()
                                    if blog.id == store.currentID {
                                        Image(systemName: "checkmark").foregroundStyle(Ink.ember)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(blog.id == store.currentID ? "Current blog" : "")
                            Menu {
                                Button("Edit Blog", systemImage: "pencil") { editing = blog }
                                Button("Remove", role: .destructive) { pendingDelete = blog }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Manage \(blog.label)")
                        }
                        .listRowBackground(Ink.paper)
                        .swipeActions {
                            Button("Remove", role: .destructive) { pendingDelete = blog }
                            Button("Edit") { editing = blog }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        AppearanceSettings()
                            .navigationTitle("Appearance")
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan") { scanning = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { adding = true }
                }
            }
            .sheet(isPresented: $adding) { BlogForm() }
            .sheet(item: $editing) { BlogForm(blog: $0) }
            .sheet(isPresented: $scanning) {
                ScannerSheet { apply($0) }
            }
            .confirmationDialog(
                "Remove this blog?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { blog in
                Button("Remove", role: .destructive) { store.remove(blog.id) }
            } message: { _ in
                Text("This only disconnects the blog from this device. Its posts stay on the server.")
            }
        }
        .modifier(AppearanceStyle())
    }

    private func apply(_ raw: String) {
        guard let code = parseSetupCode(raw) else {
            scanError = "That code is not a Campfire setup code."
            return
        }
        scanError = nil
        store.add(baseURL: code.url, token: code.token)
    }
}

private struct BlogForm: View {
    var blog: Blog?
    @Environment(PostsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var connection = BlogConnectionDraft()
    @State private var checking = false
    @State private var message: String?
    @State private var verification: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BlogConnectionFields(connection: $connection)
                        .disabled(checking)
                } footer: {
                    Text("Paste a setup code, or enter the server and write token.")
                }
                if checking { ProgressView("Checking server and write token…") }
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Ink.ember)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle(blog == nil ? "Add blog" : "Edit blog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { verification?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { verify() }
                        .disabled(checking)
                }
            }
        }
        .interactiveDismissDisabled(checking)
        .onAppear { connection = BlogConnectionDraft(blog: blog) }
        .onDisappear { verification?.cancel() }
        .onChange(of: connection) { _, _ in message = nil }
    }

    private func verify() {
        guard !checking else { return }
        checking = true
        message = nil
        verification = Task {
            defer { checking = false }
            do {
                let verified = try await connection.verified()
                guard !Task.isCancelled else { return }
                verified.save(to: store)
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }
}

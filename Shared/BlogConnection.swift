import SwiftUI

@MainActor
struct BlogConnectionDraft: Equatable {
    let blog: Blog?
    private let originalToken: String
    var name: String
    var baseURL: String
    var token: String

    init(blog: Blog? = nil) {
        self.blog = blog
        name = blog?.name ?? ""
        baseURL = blog?.baseURL ?? ""
        token = blog.map { TokenStore.load($0.id.uuidString) } ?? ""
        originalToken = token
    }

    var connectionUnchanged: Bool {
        guard let blog else { return false }
        return PostsStore.normalize(baseURL) == blog.baseURL
            && token.trimmingCharacters(in: .whitespacesAndNewlines) == originalToken
    }

    func verified() async throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if connectionUnchanged { return result }
        let code = parseSetupCode(baseURL)
        result.baseURL = (code?.url ?? baseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        result.token = (code?.token ?? token).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.baseURL.isEmpty, !result.token.isEmpty else {
            throw CampfireError(message: "Enter a server and a write token, or paste a setup code.")
        }
        let api = CampfireAPI(baseURL: result.baseURL, token: result.token)
        guard let endpoint = api.endpoint("/api/posts"), endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else {
            throw CampfireError(message: "Enter an HTTP or HTTPS server address without a query or fragment.")
        }
        _ = try await api.list()
        try Task.checkCancellation()
        return result
    }

    func save(to store: PostsStore) {
        if let blog {
            if connectionUnchanged {
                store.rename(id: blog.id, name: name)
            } else {
                store.update(id: blog.id, baseURL: baseURL, token: token, name: name)
            }
        } else {
            store.add(baseURL: baseURL, token: token, name: name)
        }
    }
}

struct BlogConnectionFields: View {
    @Binding var connection: BlogConnectionDraft
    @State private var revealToken = false
    @FocusState private var serverFocused: Bool

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Blog name").font(.callout.weight(.medium))
                TextField("Optional, e.g. Field Notes", text: $connection.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Blog name")
                Text("Leave blank to use the server address. This name stays on this device.")
                    .font(.caption)
                    .foregroundStyle(Ink.moss)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Server").font(.callout.weight(.medium))
                TextField("https://your-blog.example", text: $connection.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .focused($serverFocused)
                    .accessibilityLabel("Server address or setup code")
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Write token").font(.callout.weight(.medium))
                HStack {
                    Group {
                        if revealToken {
                            TextField("Write token", text: $connection.token)
                        } else {
                            SecureField("Write token", text: $connection.token)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .accessibilityLabel("Write token")
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    Button(revealToken ? "Hide" : "Show") { revealToken.toggle() }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(revealToken ? "Hide write token" : "Show write token")
                }
            }
        }
        .onChange(of: connection.baseURL) { _, value in
            if let code = parseSetupCode(value) {
                connection.token = code.token
                connection.baseURL = code.url
            }
        }
        .onAppear { serverFocused = true }
    }
}

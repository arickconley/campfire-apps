import Foundation
import Security

struct Blog: Identifiable, Codable, Hashable {
    var id: UUID
    var baseURL: String
    var name: String? = nil

    var label: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        guard let url = URL(string: baseURL), let host = url.host, !host.isEmpty else {
            return baseURL
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
}

@MainActor
@Observable
final class PostsStore {
    var posts: [Post] = []
    var blogs: [Blog] = []
    var currentID: UUID?
    var isLoading = false
    var error: String?

    var current: Blog? {
        blogs.first { $0.id == currentID }
    }

    var token: String {
        guard let currentID else { return "" }
        return TokenStore.load(currentID.uuidString)
    }

    var configured: Bool {
        guard let current else { return false }
        return !current.baseURL.isEmpty && !token.isEmpty
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.blogsKey),
           let saved = try? JSONDecoder().decode([Blog].self, from: data) {
            blogs = saved
            if let raw = UserDefaults.standard.string(forKey: Self.currentKey),
               let id = UUID(uuidString: raw),
               saved.contains(where: { $0.id == id }) {
                currentID = id
            } else {
                currentID = saved.first?.id
            }
            return
        }
        migrateLegacy()
    }

    func reload() async {
        guard configured else {
            posts = []
            error = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await api.list()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func read(slug: String) async throws -> Post {
        try await api.read(slug: slug)
    }

    func save(slug: String?, title: String, date: String, body: String, draft: Bool, metaDescription: String? = nil) async throws -> Post {
        let post: Post
        if let slug {
            post = try await api.update(slug: slug, title: title, date: date, body: body, draft: draft, metaDescription: metaDescription)
        } else {
            post = try await api.create(title: title, body: body, draft: draft, metaDescription: metaDescription)
        }
        error = nil
        await reload()
        return post
    }

    func delete(slug: String) async throws {
        try await api.delete(slug: slug)
        posts.removeAll { $0.slug == slug }
        error = nil
    }

    func add(baseURL: String, token: String, name: String? = nil) {
        let url = Self.normalize(baseURL)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !secret.isEmpty else { return }
        if let existing = blogs.first(where: { $0.baseURL == url }) {
            TokenStore.save(secret, account: existing.id.uuidString)
            if let name, let index = blogs.firstIndex(where: { $0.id == existing.id }) {
                blogs[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentID = existing.id
        } else {
            let blog = Blog(id: UUID(), baseURL: url, name: name?.trimmingCharacters(in: .whitespacesAndNewlines))
            TokenStore.save(secret, account: blog.id.uuidString)
            blogs.append(blog)
            currentID = blog.id
        }
        posts = []
        persist()
        Task { await reload() }
    }

    func rename(id: UUID, name: String) {
        guard let index = blogs.firstIndex(where: { $0.id == id }) else { return }
        blogs[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func update(id: UUID, baseURL: String, token: String, name: String) {
        let url = Self.normalize(baseURL)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard blogs.contains(where: { $0.id == id }), !url.isEmpty, !secret.isEmpty else { return }
        if let other = blogs.first(where: { $0.id != id && $0.baseURL == url }) {
            TokenStore.delete(other.id.uuidString)
            blogs.removeAll { $0.id == other.id }
        }
        guard let index = blogs.firstIndex(where: { $0.id == id }) else { return }
        blogs[index].baseURL = url
        blogs[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        TokenStore.save(secret, account: id.uuidString)
        currentID = id
        posts = []
        error = nil
        persist()
        Task { await reload() }
    }

    func select(_ id: UUID) {
        guard blogs.contains(where: { $0.id == id }) else { return }
        guard currentID != id else { return }
        currentID = id
        posts = []
        error = nil
        persist()
        Task { await reload() }
    }

    func remove(_ id: UUID) {
        TokenStore.delete(id.uuidString)
        blogs.removeAll { $0.id == id }
        if currentID == id {
            currentID = blogs.first?.id
            posts = []
            error = nil
            persist()
            Task { await reload() }
        } else {
            persist()
        }
    }

    private var api: CampfireAPI {
        CampfireAPI(baseURL: current?.baseURL ?? "", token: token)
    }

    private func migrateLegacy() {
        let secret = TokenStore.load(TokenStore.legacyAccount)
        let raw = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        let url = Self.normalize(raw)
        guard !secret.isEmpty, !url.isEmpty else { return }
        let blog = Blog(id: UUID(), baseURL: url)
        TokenStore.save(secret, account: blog.id.uuidString)
        blogs = [blog]
        currentID = blog.id
        persist()
        TokenStore.delete(TokenStore.legacyAccount)
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(blogs) {
            UserDefaults.standard.set(data, forKey: Self.blogsKey)
        }
        if let currentID {
            UserDefaults.standard.set(currentID.uuidString, forKey: Self.currentKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentKey)
        }
    }

    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = CampfireAPI(baseURL: trimmed, token: "").endpoint("/") {
            var saved = url.absoluteString
            while saved.hasSuffix("/") { saved.removeLast() }
            return saved
        }
        return trimmed
    }

    private static let blogsKey = "campfire.blogs"
    private static let currentKey = "campfire.blogID"
    private static let urlKey = "campfire.baseURL"
}

enum TokenStore {
    static let legacyAccount = "write-token"
    private static let service = "com.mtnwurx.campfire"

    static func load(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    static func save(_ token: String, account: String) {
        delete(account)
        guard !token.isEmpty else { return }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

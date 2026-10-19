import Foundation

struct MacDraft: Codable, Equatable {
    var title: String
    var date: String
    var body: String
    var draft: Bool
    var format: String? = "html"
}

// Recovery copies never contain credentials and never publish to the server.
struct MacDrafts {
    var directory: URL = URL.applicationSupportDirectory.appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "Campfire")/Recovery", isDirectory: true)

    func location(blog: UUID, slug: String?) -> URL {
        // shortcut: one unfinished new post per blog; add a local drafts list when several are needed.
        let name = slug.map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") } ?? "new"
        return directory.appendingPathComponent(blog.uuidString, isDirectory: true)
            .appendingPathComponent(name + ".json")
    }

    func read(_ location: URL) throws -> MacDraft? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        var copy = try JSONDecoder().decode(MacDraft.self, from: Data(contentsOf: location))
        if copy.format == nil {
            copy.body = RichNote(markdown: copy.body).html
            copy.format = "html"
        }
        guard copy.format == "html" else { throw CampfireError(message: "Unknown recovery format.") }
        return copy
    }

    func write(_ draft: MacDraft, to location: URL) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(draft).write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
    }

    func remove(_ location: URL) throws {
        if FileManager.default.fileExists(atPath: location.path) {
            try FileManager.default.removeItem(at: location)
        }
    }
}

enum MacPostFilter: String, CaseIterable {
    case all = "All", drafts = "Drafts", published = "Published"

    func includes(_ post: Post, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (self == .all || (self == .drafts ? post.draft : !post.draft))
            && (query.isEmpty || post.displayTitle.localizedStandardContains(query))
    }
}

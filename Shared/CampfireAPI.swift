import Foundation

struct Post: Identifiable, Decodable, Hashable {
    var slug: String
    var title: String
    var date: String
    var draft: Bool
    var url: String
    var metaDescription: String? = nil
    var body: String?
    enum BodyFormat: String, Decodable { case html }
    var format: BodyFormat = .html

    var id: String { slug }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var dateLabel: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let when = parser.date(from: date) else { return "" }
        if Calendar(identifier: .gregorian).component(.year, from: when) < 2 {
            return ""
        }
        return when.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct SiteFile: Identifiable, Codable, Hashable {
    var path: String
    var kind: String
    var title: String
    var draft: Bool
    var body: String
    var revision: String
    var id: String { path }
    var isPage: Bool { kind == "page" }
}

struct CampfireError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct CampfireAPI {
    var baseURL: String
    var token: String

    func list() async throws -> [Post] {
        try await send(path: "/api/posts", method: "GET", body: nil)
    }

    func read(slug: String) async throws -> Post {
        try await send(path: "/api/posts/\(slugPath(slug))", method: "GET", body: nil)
    }

    func create(title: String, body: String, draft: Bool, metaDescription: String? = nil) async throws -> Post {
        try await send(
            path: "/api/posts",
            method: "POST",
            body: WritePayload(title: title, date: nil, draft: draft, body: body, metaDescription: metaDescription),
            accept: [200, 201]
        )
    }

    func update(slug: String, title: String, date: String, body: String, draft: Bool, metaDescription: String? = nil) async throws -> Post {
        try await send(
            path: "/api/posts/\(slugPath(slug))",
            method: "PUT",
            body: WritePayload(title: title, date: date, draft: draft, body: body, metaDescription: metaDescription)
        )
    }

    func delete(slug: String) async throws {
        let (data, response) = try await request(path: "/api/posts/\(slugPath(slug))", method: "DELETE", body: nil)
        if response.statusCode == 204 { return }
        try throwAPI(response, data)
    }

    func siteFiles() async throws -> [SiteFile] {
        try await send(path: "/api/site/files", method: "GET", body: nil)
    }

    func siteFile(path: String) async throws -> SiteFile {
        try await send(path: siteFilePath(path), method: "GET", body: nil)
    }

    func saveSiteFile(_ file: SiteFile) async throws -> SiteFile {
        try await send(path: siteFilePath(file.path), method: "PUT", body: file)
    }

    private func siteFilePath(_ path: String) -> String {
        var parts = URLComponents()
        parts.path = "/api/site/file"
        parts.queryItems = [URLQueryItem(name: "path", value: path)]
        return parts.string!
    }

    private struct WritePayload: Encodable {
        var title: String
        var date: String?
        var draft: Bool
        var body: String
        var metaDescription: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("html", forKey: .format)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(date, forKey: .date)
            try c.encode(draft, forKey: .draft)
            try c.encode(body, forKey: .body)
            try c.encodeIfPresent(metaDescription, forKey: .metaDescription)
        }

        enum CodingKeys: String, CodingKey {
            case title, date, draft, body, format, metaDescription
        }
    }

    private func send<T: Decodable>(path: String, method: String, body: (any Encodable)?, accept: Set<Int> = [200]) async throws -> T {
        let (data, response) = try await request(path: path, method: method, body: body)
        guard accept.contains(response.statusCode) else {
            try throwAPI(response, data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if path.hasPrefix("/api/site/") {
                throw CampfireError(message: "The server sent an incompatible Page Editor response. Update your server and app together.")
            }
            throw CampfireError(message: "The server sent an incompatible post response. Update the server and Campfire apps together to use HTML posts.")
        }
    }

    private func request(path: String, method: String, body: (any Encodable)?) async throws -> (Data, HTTPURLResponse) {
        guard let url = endpoint(path) else {
            throw CampfireError(message: "The server address is not a URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            // Older servers reject this media type before they can store HTML as Markdown.
            let hasDescription = (body as? WritePayload)?.metaDescription != nil
            req.setValue(hasDescription ? "application/vnd.campfire.description+json" : "application/vnd.campfire.html+json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw CampfireError(message: "Could not reach the server.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CampfireError(message: "The server sent an unexpected response.")
        }
        if path.hasPrefix("/api/site/"), http.value(forHTTPHeaderField: "X-Campfire-Content-Format") != "html", http.statusCode == 404 || http.statusCode == 405 {
            throw CampfireError(message: "Page Editor requires a newer Campfire server. Update your server, then try again.")
        }
        guard http.value(forHTTPHeaderField: "X-Campfire-Content-Format") == "html" else {
            throw CampfireError(message: "This server needs the HTML update. Update the server and both Campfire apps together.")
        }
        return (data, http)
    }

    private func throwAPI(_ response: HTTPURLResponse, _ data: Data) throws -> Never {
        if response.statusCode == 415 {
            throw CampfireError(message: "Update the Campfire server to save meta descriptions. Your edits are still in the editor.")
        }
        if let api = try? JSONDecoder().decode(APIError.self, from: data), !api.error.isEmpty {
            throw CampfireError(message: api.error)
        }
        throw CampfireError(message: "The server returned \(response.statusCode).")
    }

    private struct APIError: Decodable {
        var error: String
    }

    func endpoint(_ path: String) -> URL? {
        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if !raw.contains("://"), !raw.isEmpty {
            raw = "http://" + raw
        }
        guard let url = URL(string: raw + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func slugPath(_ slug: String) -> String {
        slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
    }
}

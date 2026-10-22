import Foundation

// In-process responses verify protocol compatibility without a listening socket.
final class HTMLAPIProtocol: URLProtocol, @unchecked Sendable {
    static var format: String? = "html"
    static var payload = "[]"
    static var contentType: String?
    static var statusCode = 200
    static var lastURL: URL?
    static var method: String?
    static var body: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "format-check.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.contentType = request.value(forHTTPHeaderField: "Content-Type")
        Self.lastURL = request.url
        Self.method = request.httpMethod
        Self.body = request.httpBody
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            Self.body = data
        }
        let headers = Self.format.map { ["X-Campfire-Content-Format": $0] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

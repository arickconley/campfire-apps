import Foundation

// In-process responses verify protocol compatibility without a listening socket.
final class HTMLAPIProtocol: URLProtocol, @unchecked Sendable {
    static var format: String? = "html"
    static var payload = "[]"
    static var contentType: String?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "format-check.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.contentType = request.value(forHTTPHeaderField: "Content-Type")
        let headers = Self.format.map { ["X-Campfire-Content-Format": $0] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

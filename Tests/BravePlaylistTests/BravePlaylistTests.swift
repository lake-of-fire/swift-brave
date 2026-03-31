import XCTest
@testable import BravePlaylist

final class BravePlaylistTests: XCTestCase {
    func testPlaylistInfoDecodesAndNormalizesRelativeURL() throws {
        let body: [String: Any] = [
            "name": "Example",
            "src": "/video/master.m3u8",
            "pageSrc": "https://example.com/watch?v=1",
            "pageTitle": "Example Page",
            "mimeType": "video/mp4",
            "duration": 12.5,
            "detected": true,
            "tagId": "tag-1",
            "invisible": false,
        ]

        let info = try XCTUnwrap(PlaylistInfo.decode(from: body))
        XCTAssertEqual(info.src, "https://example.com/video/master.m3u8")
        XCTAssertEqual(info.kind, .video)
        XCTAssertFalse(info.isInvisible)
    }

    func testMessageDecoderRejectsWrongSecurityToken() {
        let body: [String: Any] = [
            "securityToken": "wrong",
            "state": "interactive",
        ]

        XCTAssertNil(
            PlaylistScriptMessageDecoder.decode(
                body: body,
                expectingSecurityToken: "expected"
            )
        )
    }

    func testScriptSetBuildsExpectedHandlerNames() throws {
        let configuration = PlaylistScriptConfiguration(
            messageHandlerName: "playlistHandler",
            securityToken: "security-token",
            namespaceToken: "namespace"
        )

        let scripts = try PlaylistScriptEngine.makeScriptSet(configuration: configuration)

        XCTAssertTrue(scripts.detectorSource.contains("const SECURITY_TOKEN = 'security-token';"))
        XCTAssertTrue(scripts.detectorSource.contains("playlistHandler"))
        XCTAssertTrue(scripts.detectorSource.contains("playlistProcessDocumentLoad_namespace"))
        XCTAssertTrue(scripts.detectorSource.contains("mediaCurrentTimeFromTag_namespace"))
        XCTAssertTrue(scripts.firefoxShimSource.contains("window.__firefox__"))
        XCTAssertTrue(scripts.mediaSourceOverrideSource.contains("delete window.MediaSource;"))
    }

    func testMediaStreamerResolvesDirectMedia() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4; charset=utf-8"]
            )!
            return (response, Data())
        }

        let streamer = PlaylistMediaStreamer(urlSession: makeSession())
        let item = PlaylistInfo(
            name: "Audio",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Audio",
            mimeType: "",
            duration: 10,
            detected: true,
            tagId: "audio-1",
            isInvisible: false
        )

        let resolved = try await streamer.resolveMedia(item)
        XCTAssertEqual(resolved.url.absoluteString, item.src)
        XCTAssertEqual(resolved.mimeType, "audio/mp4")
        XCTAssertEqual(resolved.resolutionMethod, .direct)
    }

    func testMediaStreamerFallsBackWhenPrimaryURLIsBlob() async throws {
        let fallbackItem = PlaylistInfo(
            name: "Fallback",
            src: "https://media.example.com/video.mp4",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Fallback",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "fallback-1",
            isInvisible: false
        )

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let streamer = PlaylistMediaStreamer(
            urlSession: makeSession(),
            webLoaderFactory: MockLoaderFactory(item: fallbackItem)
        )

        let item = PlaylistInfo(
            name: "Blob",
            src: "blob:https://example.com/123",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Blob",
            mimeType: "",
            duration: 15,
            detected: true,
            tagId: "blob-1",
            isInvisible: false
        )

        let resolved = try await streamer.resolveMedia(item)
        XCTAssertEqual(resolved.url.absoluteString, fallbackItem.src)
        XCTAssertEqual(resolved.resolutionMethod, .fallback)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockLoaderFactory: PlaylistWebLoaderFactory {
    private let item: PlaylistInfo

    init(item: PlaylistInfo) {
        self.item = item
    }

    func makeWebLoader() -> any PlaylistWebLoader {
        MockWebLoader(item: item)
    }
}

private final class MockWebLoader: PlaylistWebLoader {
    private let item: PlaylistInfo

    init(item: PlaylistInfo) {
        self.item = item
    }

    func load(url: URL) async -> PlaylistInfo? {
        item
    }

    func stop() {}
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("URLProtocolStub.handler not set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

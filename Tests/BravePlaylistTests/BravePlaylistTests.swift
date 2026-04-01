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

    func testPlaylistInfoNormalizesProtocolRelativeURL() {
        let info = PlaylistInfo(
            name: "Example",
            src: "//cdn.example.com/audio.mp3",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Example Page",
            mimeType: "audio/mpeg",
            duration: 12.5,
            detected: true,
            tagId: "tag-1",
            isInvisible: false
        )

        XCTAssertEqual(info.src, "https://cdn.example.com/audio.mp3")
        XCTAssertEqual(info.kind, .audio)
        XCTAssertTrue(info.isHTTPSource)
    }

    func testPlaylistInfoTreatsM3U8AsHLSContainer() {
        let info = PlaylistInfo(
            name: "Stream",
            src: "https://cdn.example.com/master.m3u8",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Example Page",
            mimeType: "application/x-mpegURL",
            duration: 12.5,
            detected: true,
            tagId: "tag-1",
            isInvisible: false
        )

        XCTAssertEqual(info.containerKind, .hls)
        XCTAssertEqual(info.kind, .unknown)
    }

    func testPlaylistInfoDerivesAudioOnlyPlaybackKindForHLSAudioStream() {
        let info = PlaylistInfo(
            name: "Podcast audio stream",
            src: "https://cdn.example.com/audio/master.m3u8",
            pageSrc: "https://example.com/listen",
            pageTitle: "Podcast episode",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 600,
            detected: true,
            tagId: "audio-hls",
            isInvisible: false
        )

        XCTAssertEqual(info.playbackKind, .audioOnly)
        XCTAssertTrue(info.isLikelyAudioOnly)
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

    func testPlaylistWebScriptsBuildExpectedUserScripts() throws {
        let scriptSet = try PlaylistWebScripts.make(
            messageHandlerName: "playlistHandler",
            allowedDomains: ["youtube.com"],
            configuration: PlaylistScriptConfiguration(
                messageHandlerName: "playlistHandler",
                securityToken: "security-token",
                namespaceToken: "namespace"
            )
        )

        XCTAssertEqual(scriptSet.messageHandlerName, "playlistHandler")
        XCTAssertEqual(scriptSet.userScripts.count, 3)
        XCTAssertEqual(scriptSet.userScripts.first?.allowedDomains, ["youtube.com"])
        XCTAssertTrue(scriptSet.userScripts[2].source.contains("playlistHandler"))
        XCTAssertTrue(scriptSet.userScripts[2].source.contains("security-token"))
        XCTAssertEqual(
            scriptSet.processDocumentLoadJavaScript,
            "window.__firefox__.playlistProcessDocumentLoad_namespace()"
        )
    }

    func testPlaylistWebMessageDecoderUsesSecurityToken() throws {
        let scriptSet = try PlaylistWebScripts.make(
            messageHandlerName: "playlistHandler",
            configuration: PlaylistScriptConfiguration(
                messageHandlerName: "playlistHandler",
                securityToken: "expected-token",
                namespaceToken: "namespace"
            )
        )

        let body: [String: Any] = [
            "securityToken": "expected-token",
            "state": "interactive",
        ]

        let decoded = PlaylistWebMessageDecoder.decode(body: body, scriptSet: scriptSet)
        XCTAssertEqual(decoded, .readyState(.init(state: "interactive")))
    }

    func testPlaylistCandidateSelectorPrefersVisibleDirectAudio() {
        let invisibleVideo = PlaylistInfo(
            name: "Video",
            src: "https://example.com/video.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Watch",
            mimeType: "video/mp4",
            duration: 100,
            detected: true,
            tagId: "video",
            isInvisible: true
        )
        let visibleAudio = PlaylistInfo(
            name: "Audio",
            src: "https://example.com/audio.m4a",
            pageSrc: "https://example.com/watch",
            pageTitle: "Watch",
            mimeType: "audio/mp4",
            duration: 30,
            detected: true,
            tagId: "audio",
            isInvisible: false
        )

        let preferred = PlaylistCandidateSelector.preferredCandidate(
            from: [invisibleVideo, visibleAudio]
        )

        XCTAssertEqual(preferred?.tagId, "audio")
    }

    func testPlaylistCandidateSelectorPrefersAudioOnlyHLSOverVideoHLS() {
        let audioStream = PlaylistInfo(
            name: "Audio stream",
            src: "https://example.com/audio/master.m3u8",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode audio",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 1800,
            detected: true,
            tagId: "audio-hls",
            isInvisible: false
        )
        let videoStream = PlaylistInfo(
            name: "Video stream",
            src: "https://example.com/video/master.m3u8",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode video",
            mimeType: "application/vnd.apple.mpegurl",
            duration: 1800,
            detected: true,
            tagId: "video-hls",
            isInvisible: false
        )

        let preferred = PlaylistCandidateSelector.preferredCandidate(
            from: [videoStream, audioStream]
        )

        XCTAssertEqual(preferred?.tagId, "audio-hls")
    }

    func testPlaylistCandidateSelectorPrefersRefreshedDirectURLForSameTag() {
        let staleBlob = PlaylistInfo(
            name: "Episode",
            src: "blob:https://example.com/123",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "",
            duration: 1800,
            detected: true,
            tagId: "episode-player",
            isInvisible: false
        )
        let refreshedDirect = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "audio/mp4",
            duration: 1800,
            detected: true,
            tagId: "episode-player",
            isInvisible: false
        )

        let preferred = PlaylistCandidateSelector.preferredCandidate(
            from: [staleBlob, refreshedDirect]
        )

        XCTAssertEqual(preferred?.src, refreshedDirect.src)
    }

    func testPlaylistCandidateSelectorAvoidsLikelyAdvertisementCandidates() {
        let advertisement = PlaylistInfo(
            name: "Pre-roll ad",
            src: "https://ads.doubleclick.net/preroll.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Sponsored preroll",
            mimeType: "video/mp4",
            duration: 15,
            detected: true,
            tagId: "ad-player",
            isInvisible: false
        )
        let content = PlaylistInfo(
            name: "Main episode",
            src: "https://cdn.example.com/main.mp4",
            pageSrc: "https://example.com/watch",
            pageTitle: "Episode",
            mimeType: "video/mp4",
            duration: 1800,
            detected: true,
            tagId: "main-player",
            isInvisible: false
        )

        let preferred = PlaylistCandidateSelector.preferredCandidate(
            from: [advertisement, content],
            preferringAudio: false
        )

        XCTAssertEqual(preferred?.tagId, "main-player")
    }

    func testPlaylistRequestContextBuilderIncludesCookieRefererAndUserAgent() {
        let cookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "abc123",
            .secure: "FALSE",
            .expires: Date().addingTimeInterval(60),
        ])!

        let context = PlaylistRequestContextBuilder.make(
            userAgent: "Manabi",
            referer: URL(string: "https://example.com/watch")!,
            cookies: [cookie]
        )

        XCTAssertEqual(context.headers["User-Agent"], "Manabi")
        XCTAssertEqual(context.headers["Referer"], "https://example.com/watch")
        XCTAssertEqual(context.headers["Cookie"], "session=abc123")
    }

    func testMediaStreamerResolvesDirectMedia() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Manabi")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/watch/1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=abc123")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
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

        let resolved = try await streamer.resolveMedia(
            item,
            requestContext: PlaylistMediaRequestContext(
                userAgent: "Manabi",
                referer: URL(string: "https://example.com/watch/1"),
                cookieHeader: "session=abc123"
            )
        )
        XCTAssertEqual(resolved.url.absoluteString, item.src)
        XCTAssertEqual(resolved.mimeType, "audio/mp4")
        XCTAssertEqual(resolved.resolutionMethod, .direct)
        XCTAssertEqual(resolved.requestHeaders["User-Agent"], "Manabi")
        XCTAssertEqual(resolved.requestHeaders["Referer"], "https://example.com/watch/1")
        XCTAssertEqual(resolved.requestHeaders["Cookie"], "session=abc123")
    }

    func testMediaStreamerFallsBackToRangeGetWhenHeadProbeDoesNotReturnMimeType() async throws {
        let lock = NSLock()
        var methods: [String] = []

        URLProtocolStub.handler = { request in
            lock.lock()
            methods.append(request.httpMethod ?? "GET")
            lock.unlock()

            let response: HTTPURLResponse
            if request.httpMethod == "HEAD" {
                response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 405,
                    httpVersion: nil,
                    headerFields: nil
                )!
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-1")
                response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "audio/mp4"]
                )!
            }
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
        XCTAssertEqual(resolved.mimeType, "audio/mp4")
        XCTAssertEqual(methods, ["HEAD", "GET"])
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
                statusCode: 200,
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

    func testMediaStreamerStopsFallbackLoaderAfterResolution() async throws {
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
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let factory = MockLoaderFactory(item: fallbackItem)
        let streamer = PlaylistMediaStreamer(
            urlSession: makeSession(),
            webLoaderFactory: factory
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

        _ = try await streamer.resolveMedia(item)
        XCTAssertEqual(factory.loader.stopCallCount, 1)
    }

    func testMediaStreamerThrowsFallbackUnavailableForBlobWithoutResolver() async {
        let streamer = PlaylistMediaStreamer(urlSession: makeSession())
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

        await XCTAssertThrowsErrorAsync(
            try await streamer.resolveMedia(item)
        ) { error in
            XCTAssertEqual(error as? PlaylistMediaStreamer.PlaybackError, .fallbackUnavailable)
        }
    }

    func testMediaStreamerThrowsCouldNotDeterminePlayableMediaWhenDirectProbeFails() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let streamer = PlaylistMediaStreamer(urlSession: makeSession())
        let item = PlaylistInfo(
            name: "Unknown",
            src: "https://cdn.example.com/stream",
            pageSrc: "https://example.com/watch/1",
            pageTitle: "Unknown",
            mimeType: "",
            duration: 10,
            detected: true,
            tagId: "unknown-1",
            isInvisible: false
        )

        await XCTAssertThrowsErrorAsync(
            try await streamer.resolveMedia(item)
        ) { error in
            XCTAssertEqual(error as? PlaylistMediaStreamer.PlaybackError, .couldNotDeterminePlayableMedia)
        }
    }

    func testOfflineStoreDownloadsStoresThumbnailAndFindsMediaByPage() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let resolvedMedia = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: ["Cookie": "session=abc123"],
            resolutionMethod: .direct
        )

        let thumbnailData = Data("thumb".utf8)
        let storedMedia = try await fixture.store.download(
            resolvedMedia,
            storageScope: .transient,
            thumbnail: .inlineImageData(thumbnailData, fileExtension: "jpg")
        )

        XCTAssertEqual(storedMedia.storageScope, .transient)
        XCTAssertEqual(try String(decoding: Data(contentsOf: storedMedia.localMediaURL), as: UTF8.self), "media-1")
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(storedMedia.localThumbnailURL)),
            thumbnailData
        )

        let byItem = try await fixture.store.storedMedia(for: item)
        XCTAssertEqual(byItem?.id, storedMedia.id)

        let byPage = try await fixture.store.storedMedia(
            forPageURL: URL(string: "https://example.com/watch?v=1")!
        )
        XCTAssertEqual(byPage.map(\.id), [storedMedia.id])
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testOfflineStoreReusesExistingCandidateWithoutRedownloading() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let initial = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )
        let refreshed = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=2")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .fallback
        )

        let first = try await fixture.store.download(initial, storageScope: .transient)
        let second = try await fixture.store.download(refreshed, storageScope: .transient)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.resolvedMediaURL, first.resolvedMediaURL)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testOfflineStorePromotesTransientMediaToPersistentWithoutRedownloading() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )
        let resolvedMedia = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=1")!,
            mimeType: "audio/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )

        let transient = try await fixture.store.download(resolvedMedia, storageScope: .transient)
        let persistent = try await fixture.store.download(resolvedMedia, storageScope: .persistent)

        XCTAssertEqual(transient.id, persistent.id)
        XCTAssertEqual(persistent.storageScope, .persistent)
        XCTAssertTrue(persistent.localMediaURL.path.contains("/persistent/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transient.localMediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistent.localMediaURL.path))
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testOfflineStoreDeletesIndividuallyAndPurgesTransientMedia() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let persistentItem = PlaylistInfo(
            name: "Saved Episode",
            src: "https://cdn.example.com/saved.m4a",
            pageSrc: "https://example.com/watch?v=saved",
            pageTitle: "Saved Episode",
            mimeType: "audio/mp4",
            duration: 60,
            detected: true,
            tagId: "saved-1",
            isInvisible: false
        )
        let transientItem = PlaylistInfo(
            name: "Temp Episode",
            src: "https://cdn.example.com/temp.m4a",
            pageSrc: "https://example.com/watch?v=temp",
            pageTitle: "Temp Episode",
            mimeType: "audio/mp4",
            duration: 60,
            detected: true,
            tagId: "temp-1",
            isInvisible: false
        )

        let saved = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: persistentItem,
                url: URL(string: persistentItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent
        )
        _ = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: transientItem,
                url: URL(string: transientItem.src)!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient
        )

        try await fixture.store.deleteStoredMedia(id: saved.id)
        let deletedMedia = try await fixture.store.storedMedia(id: saved.id)
        XCTAssertNil(deletedMedia)

        try await fixture.store.purgeTransientMedia()
        let remainingMedia = try await fixture.store.allStoredMedia()
        XCTAssertEqual(remainingMedia.count, 0)
    }

    func testPlaylistLibraryResolvesAndDownloadsMediaIntoStore() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mp4"]
            )!
            return (response, Data())
        }

        let library = PlaylistLibrary(
            mediaStreamer: PlaylistMediaStreamer(urlSession: makeSession()),
            offlineStore: fixture.store
        )
        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=1",
            pageTitle: "Episode Page",
            mimeType: "",
            duration: 42,
            detected: true,
            tagId: "episode-1",
            isInvisible: false
        )

        let storedMedia = try await library.download(
            item,
            storageScope: .persistent,
            thumbnail: .none
        )

        XCTAssertEqual(storedMedia.storageScope, .persistent)
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
        let pageMedia = try await library.storedMedia(
            forPageURL: URL(string: "https://example.com/watch?v=1")!
        )
        XCTAssertEqual(pageMedia.count, 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeOfflineStoreFixture() throws -> OfflineStoreFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloader = MockArtifactDownloader()
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )
        return OfflineStoreFixture(rootURL: rootURL, store: store, downloader: downloader)
    }
}

private final class MockLoaderFactory: PlaylistWebLoaderFactory {
    let loader: MockWebLoader

    init(item: PlaylistInfo) {
        self.loader = MockWebLoader(item: item)
    }

    func makeWebLoader() -> any PlaylistWebLoader {
        loader
    }
}

private final class MockWebLoader: PlaylistWebLoader {
    private let item: PlaylistInfo
    private(set) var stopCallCount = 0

    init(item: PlaylistInfo) {
        self.item = item
    }

    func load(url: URL) async -> PlaylistInfo? {
        item
    }

    func stop() {
        stopCallCount += 1
    }
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

private struct OfflineStoreFixture {
    let rootURL: URL
    let store: PlaylistOfflineMediaStore
    let downloader: MockArtifactDownloader

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class MockArtifactDownloader: PlaylistArtifactDownloading {
    private(set) var downloadCallCount = 0

    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        downloadCallCount += 1

        let payload = Data("media-\(downloadCallCount)".utf8)
        let relativePath = "media.mp4"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try payload.write(to: destinationURL, options: .atomic)

        onProgress(
            PlaylistDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: Int64(payload.count),
                totalBytesExpected: Int64(payload.count)
            )
        )

        return PlaylistDownloadedArtifact(
            relativeMediaPath: relativePath,
            mimeType: media.mimeType,
            byteCount: Int64(payload.count)
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

import XCTest
import CryptoKit
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

    func testPlaybackEventDecoderNormalizesCurrentSourceAndPresentationMode() throws {
        let body: [String: Any] = [
            "securityToken": "expected-token",
            "messageKind": "playback",
            "eventName": "playing",
            "tagId": "player-1",
            "pageSrc": "https://example.com/watch?v=1#fragment",
            "pageTitle": "Example Page",
            "src": "/video/master.m3u8",
            "currentSrc": "//cdn.example.com/video/master.m3u8#time=10",
            "mimeType": "application/vnd.apple.mpegurl",
            "mediaType": "video",
            "currentTime": 12.5,
            "duration": 120.0,
            "paused": false,
            "ended": false,
            "playbackRate": 1.0,
            "muted": false,
            "volume": 0.75,
            "readyState": 4,
            "networkState": 2,
            "presentationMode": "picture-in-picture",
            "isInvisible": false,
        ]

        let decoded = try XCTUnwrap(
            PlaylistScriptMessageDecoder.decode(
                body: body,
                expectingSecurityToken: "expected-token"
            )
        )

        guard case .playback(let event) = decoded else {
            return XCTFail("Expected playback event")
        }

        XCTAssertEqual(event.eventName, .playing)
        XCTAssertEqual(event.snapshot.src, "https://example.com/video/master.m3u8")
        XCTAssertEqual(event.snapshot.currentSrc, "https://cdn.example.com/video/master.m3u8#time=10")
        XCTAssertEqual(event.snapshot.pageLookupKey, "https://example.com/watch?v=1")
        XCTAssertEqual(event.snapshot.presentationMode, .pictureInPicture)
        XCTAssertEqual(event.snapshot.mediaType, .video)
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
        XCTAssertTrue(scripts.detectorSource.contains("playlistTelemetryAttached_namespace"))
        XCTAssertTrue(scripts.detectorSource.contains("\"messageKind\": \"playback\""))
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

    func testPlaylistWebMessageDecoderDecodesPlaybackEvents() throws {
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
            "messageKind": "playback",
            "eventName": "heartbeat",
            "tagId": "player-1",
            "pageSrc": "https://example.com/watch?v=1",
            "pageTitle": "Example Page",
            "src": "https://cdn.example.com/audio.m4a",
            "currentSrc": "https://cdn.example.com/audio.m4a",
            "mimeType": "audio/mp4",
            "mediaType": "audio",
            "currentTime": 45.0,
            "duration": 300.0,
            "paused": false,
            "ended": false,
            "playbackRate": 1.0,
            "muted": false,
            "volume": 1.0,
            "readyState": 4,
            "networkState": 1,
            "presentationMode": "inline",
            "isInvisible": false,
        ]

        let decoded = PlaylistWebMessageDecoder.decode(body: body, scriptSet: scriptSet)
        XCTAssertEqual(
            decoded,
            .playback(
                PlaylistPlaybackEvent(
                    eventName: .heartbeat,
                    snapshot: PlaylistPlaybackSnapshot(
                        tagId: "player-1",
                        pageSrc: "https://example.com/watch?v=1",
                        pageTitle: "Example Page",
                        src: "https://cdn.example.com/audio.m4a",
                        currentSrc: "https://cdn.example.com/audio.m4a",
                        mimeType: "audio/mp4",
                        mediaType: .audio,
                        currentTime: 45.0,
                        duration: 300.0,
                        paused: false,
                        ended: false,
                        playbackRate: 1.0,
                        muted: false,
                        volume: 1.0,
                        readyState: 4,
                        networkState: 1,
                        presentationMode: .inline,
                        isInvisible: false
                    )
                )
            )
        )
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
        XCTAssertEqual(storedMedia.retentionPolicy, .manualTransient)
        XCTAssertEqual(storedMedia.storedMediaState, .storedTransient)
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
        let record = try await fixture.store.currentDownloadRecord(id: storedMedia.id)
        XCTAssertEqual(record?.storedMediaState, .storedTransient)
        XCTAssertEqual(record?.retentionPolicy, .manualTransient)
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
        XCTAssertEqual(persistent.retentionPolicy, .persistent)
        XCTAssertEqual(persistent.storedMediaState, .storedPersistent)
        XCTAssertTrue(persistent.localMediaURL.path.contains("/persistent/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transient.localMediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistent.localMediaURL.path))
        XCTAssertEqual(fixture.downloader.downloadCallCount, 1)
    }

    func testBestStoredMediaForPagePrefersPersistentMostRecentItem() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let pageURL = URL(string: "https://example.com/watch?v=shared")!
        let transient = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Transient",
                    src: "https://cdn.example.com/transient.mp4",
                    pageSrc: pageURL.absoluteString,
                    pageTitle: "Shared Page",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "transient-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/transient.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )
        _ = transient

        let persistent = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Persistent",
                    src: "https://cdn.example.com/persistent.mp4",
                    pageSrc: pageURL.absoluteString,
                    pageTitle: "Shared Page",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "persistent-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/persistent.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        let preferred = try await fixture.store.bestStoredMedia(forPageURL: pageURL)
        XCTAssertEqual(preferred?.id, persistent.id)
        XCTAssertEqual(preferred?.storedMediaState, .storedPersistent)
    }

    func testOfflineStoreLazilyMaterializesThumbnailOnDemand() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=thumb-lazy",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-thumb-lazy",
            isInvisible: false
        )
        let thumbnailData = Data("lazy-thumb".utf8)
        let stored = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: item,
                url: URL(string: "https://cdn.example.com/audio.m4a?token=lazy")!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: PlaylistThumbnailRequest(
                loadingPolicy: .lazy,
                generateFromMedia: false,
                imageData: thumbnailData,
                fileExtension: "jpg"
            )
        )

        XCTAssertNil(stored.localThumbnailURL)

        let withThumbnail = try await fixture.store.ensureThumbnail(id: stored.id)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(withThumbnail?.localThumbnailURL)),
            thumbnailData
        )
    }

    func testOfflineStorePersistsAndUpdatesRetentionPolicy() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let stored = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Episode",
                    src: "https://cdn.example.com/retain.mp4",
                    pageSrc: "https://example.com/watch?v=retain",
                    pageTitle: "Episode",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "retain-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/retain.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )

        XCTAssertEqual(stored.retentionPolicy, .untilPageChange)

        let updated = try await fixture.store.updateRetentionPolicy(.persistent, for: stored.id)
        XCTAssertEqual(updated.retentionPolicy, .persistent)
        XCTAssertEqual(updated.storageScope, .persistent)
        XCTAssertEqual(updated.storedMediaState, .storedPersistent)

        let persisted = try await fixture.store.storedMedia(id: stored.id)
        XCTAssertEqual(persisted?.retentionPolicy, .persistent)
        XCTAssertTrue(try XCTUnwrap(persisted?.localMediaURL.path).contains("/persistent/"))
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

    func testPlaylistLibraryExposesBestStoredMediaAndRetentionUpdates() async throws {
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
        let pageURL = URL(string: "https://example.com/watch?v=library")!
        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: pageURL.absoluteString,
            pageTitle: "Episode Page",
            mimeType: "",
            duration: 42,
            detected: true,
            tagId: "episode-library",
            isInvisible: false
        )

        let stored = try await library.download(
            item,
            storageScope: .transient,
            retentionPolicy: .untilSessionEnds,
            thumbnail: .none
        )
        let bestStored = try await library.bestStoredMedia(forPageURL: pageURL)
        XCTAssertEqual(bestStored?.id, stored.id)

        let updated = try await library.updateRetentionPolicy(.persistent, for: stored.id)
        XCTAssertEqual(updated.storageScope, .persistent)
        XCTAssertEqual(updated.retentionPolicy, .persistent)
    }

    func testOfflineStoreCanCancelAndRetryDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let downloader = SequencedArtifactDownloader(
            steps: [
                .block(progress: .init(id: "placeholder", fractionCompleted: 0.5, bytesDownloaded: 5, totalBytesExpected: 10)),
                .success(data: Data("finished".utf8), relativePath: "media.mp4", mimeType: "audio/mp4")
            ]
        )
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let record = try await store.enqueueDownload(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Episode",
                    src: "https://cdn.example.com/cancel.mp4",
                    pageSrc: "https://example.com/watch?v=cancel",
                    pageTitle: "Episode",
                    mimeType: "audio/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "cancel-item",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/cancel.mp4")!,
                mimeType: "audio/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let isDownloadingInitially = try await store.isDownloading(id: record.id)
        XCTAssertTrue(isDownloadingInitially)
        let cancelled = try await store.cancelDownload(id: record.id)
        XCTAssertEqual(cancelled?.state, .cancelled)
        XCTAssertEqual(cancelled?.storedMediaState, .cancelledTransient)
        let isDownloadingAfterCancel = try await store.isDownloading(id: record.id)
        XCTAssertFalse(isDownloadingAfterCancel)

        let retried = try await store.retryDownload(id: record.id)
        XCTAssertEqual(retried.state, .queued)
        let stored = try await store.waitForDownload(id: record.id)
        XCTAssertEqual(try String(decoding: Data(contentsOf: stored.localMediaURL), as: UTF8.self), "finished")
    }

    func testOfflineStoreEmitsDownloadEvents() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let item = PlaylistInfo(
            name: "Events",
            src: "https://cdn.example.com/events.mp4",
            pageSrc: "https://example.com/watch?v=events",
            pageTitle: "Events",
            mimeType: "video/mp4",
            duration: 10,
            detected: true,
            tagId: "events-item",
            isInvisible: false
        )
        let identifier = makeStoredMediaIdentifier(for: item)
        let stream = await fixture.store.downloadEvents(id: identifier)
        let collector = Task { () -> [PlaylistDownloadEventKind] in
            var kinds: [PlaylistDownloadEventKind] = []
            for await event in stream {
                kinds.append(event.kind)
                if event.kind == .completed {
                    break
                }
            }
            return kinds
        }

        _ = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: item,
                url: URL(string: "https://cdn.example.com/events.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let kinds = await collector.value
        XCTAssertEqual(kinds.first, .queued)
        XCTAssertTrue(kinds.contains(.downloading) || kinds.contains(.progress))
        XCTAssertEqual(kinds.last, .completed)
    }

    func testOfflineStoreHandlesPageAndSessionRetentionCleanup() async throws {
        let fixture = try makeOfflineStoreFixture()
        defer { fixture.cleanup() }

        let oldPage = URL(string: "https://example.com/watch?v=old")!
        let newPage = URL(string: "https://example.com/watch?v=new")!

        let pageBound = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Old page",
                    src: "https://cdn.example.com/old.mp4",
                    pageSrc: oldPage.absoluteString,
                    pageTitle: "Old",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "old-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/old.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )
        let nextPageBound = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "New page",
                    src: "https://cdn.example.com/new.mp4",
                    pageSrc: newPage.absoluteString,
                    pageTitle: "New",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "new-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/new.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilPageChange,
            thumbnail: .none
        )
        let sessionBound = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Session",
                    src: "https://cdn.example.com/session.mp4",
                    pageSrc: newPage.absoluteString,
                    pageTitle: "Session",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "session-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/session.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .untilSessionEnds,
            thumbnail: .none
        )
        let manual = try await fixture.store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Manual",
                    src: "https://cdn.example.com/manual.mp4",
                    pageSrc: oldPage.absoluteString,
                    pageTitle: "Manual",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "manual-page",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/manual.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            retentionPolicy: .manualTransient,
            thumbnail: .none
        )

        try await fixture.store.handlePageDidChange(from: oldPage, to: newPage)
        let oldPageAfterChange = try await fixture.store.storedMedia(id: pageBound.id)
        let newPageAfterChange = try await fixture.store.storedMedia(id: nextPageBound.id)
        let sessionAfterChange = try await fixture.store.storedMedia(id: sessionBound.id)
        let manualAfterChange = try await fixture.store.storedMedia(id: manual.id)
        XCTAssertNil(oldPageAfterChange)
        XCTAssertNotNil(newPageAfterChange)
        XCTAssertNotNil(sessionAfterChange)
        XCTAssertNotNil(manualAfterChange)

        try await fixture.store.handleSessionDidEnd()
        let newPageAfterSession = try await fixture.store.storedMedia(id: nextPageBound.id)
        let sessionAfterSession = try await fixture.store.storedMedia(id: sessionBound.id)
        let manualAfterSession = try await fixture.store.storedMedia(id: manual.id)
        XCTAssertNil(newPageAfterSession)
        XCTAssertNil(sessionAfterSession)
        XCTAssertNotNil(manualAfterSession)
    }

    func testOfflineStoreCanCancelAndRetryHLSDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let hlsDownloader = SequencedHLSAssetDownloader(
            steps: [
                .block(progress: .init(id: "placeholder", fractionCompleted: 0.25, bytesDownloaded: 0, totalBytesExpected: nil)),
                .success(relativePath: "media.movpkg", mimeType: "application/vnd.apple.mpegurl")
            ]
        )
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: PlaylistAssetDownloader(
                urlSession: makeSession(),
                hlsDownloaderFactory: { hlsDownloader }
            ),
            urlSession: makeSession()
        )

        let record = try await store.enqueueDownload(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "HLS retry",
                    src: "https://cdn.example.com/retry.m3u8",
                    pageSrc: "https://example.com/watch?v=hls-retry",
                    pageTitle: "HLS retry",
                    mimeType: "application/vnd.apple.mpegurl",
                    duration: 10,
                    detected: true,
                    tagId: "hls-retry",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/retry.m3u8")!,
                mimeType: "application/vnd.apple.mpegurl",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        let isDownloadingInitially = try await store.isDownloading(id: record.id)
        XCTAssertTrue(isDownloadingInitially)
        let cancelled = try await store.cancelDownload(id: record.id)
        XCTAssertEqual(cancelled?.state, .cancelled)
        XCTAssertEqual(cancelled?.storedMediaState, .cancelledPersistent)

        let retried = try await store.retryDownload(id: record.id)
        XCTAssertEqual(retried.state, .queued)
        let stored = try await store.waitForDownload(id: record.id)
        XCTAssertTrue(stored.localMediaURL.path.hasSuffix("media.movpkg"))
    }

    func testOfflineStoreRestoresPendingDownloadsAfterRelaunch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let item = PlaylistInfo(
            name: "Episode",
            src: "https://cdn.example.com/audio.m4a",
            pageSrc: "https://example.com/watch?v=restore",
            pageTitle: "Episode Page",
            mimeType: "audio/mp4",
            duration: 42,
            detected: true,
            tagId: "episode-restore",
            isInvisible: false
        )
        let resolvedMedia = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/audio.m4a?token=restore")!,
            mimeType: "audio/mp4",
            requestHeaders: ["Cookie": "session=abc123"],
            resolutionMethod: .direct
        )
        let identifier = makeStoredMediaIdentifier(for: item)
        let transientRoot = rootURL.appendingPathComponent("transient", isDirectory: true)
        let itemDirectory = transientRoot.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)

        try writeMetadataFixture(
            PendingMetadataFixture(
                id: identifier,
                playlistInfo: item,
                storageScope: .transient,
                retentionPolicy: .manualTransient,
                resolvedMedia: .init(media: resolvedMedia),
                state: .downloading,
                createdAt: Date().addingTimeInterval(-10),
                updatedAt: Date().addingTimeInterval(-5),
                downloadedAt: nil,
                progress: .init(
                    id: identifier,
                    fractionCompleted: 0.4,
                    bytesDownloaded: 40,
                    totalBytesExpected: 100
                ),
                failureDescription: nil,
                mediaRelativePath: nil,
                thumbnailRelativePath: nil,
                byteCount: nil,
                thumbnailRequest: .none
            ),
            to: itemDirectory
        )

        let downloader = MockArtifactDownloader()
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: transientRoot,
                excludeFromBackup: false
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let restored = try await store.restorePendingDownloads()
        XCTAssertEqual(restored.map(\.id), [identifier])

        let storedMedia = try await store.waitForDownload(id: identifier)
        XCTAssertEqual(storedMedia.id, identifier)
        XCTAssertEqual(downloader.downloadCallCount, 1)

        let record = try await store.currentDownloadRecord(id: identifier)
        XCTAssertEqual(record?.state, .downloaded)
    }

    func testOfflineStoreRestoresPendingDownloadsByResumingPartialFileDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let item = PlaylistInfo(
            name: "Resume",
            src: "https://cdn.example.com/resume.mp4",
            pageSrc: "https://example.com/watch?v=resume",
            pageTitle: "Resume Page",
            mimeType: "video/mp4",
            duration: 42,
            detected: true,
            tagId: "resume-item",
            isInvisible: false
        )
        let resolvedMedia = PlaylistResolvedMedia(
            playlistInfo: item,
            url: URL(string: "https://cdn.example.com/resume.mp4")!,
            mimeType: "video/mp4",
            requestHeaders: [:],
            resolutionMethod: .direct
        )
        let identifier = makeStoredMediaIdentifier(for: item)
        let transientRoot = rootURL.appendingPathComponent("transient", isDirectory: true)
        let itemDirectory = transientRoot.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(
            to: itemDirectory.appendingPathComponent("media.partial"),
            options: .atomic
        )
        try writeMetadataFixture(
            PendingMetadataFixture(
                id: identifier,
                playlistInfo: item,
                storageScope: .transient,
                retentionPolicy: .manualTransient,
                resolvedMedia: .init(media: resolvedMedia),
                state: .downloading,
                createdAt: Date().addingTimeInterval(-10),
                updatedAt: Date().addingTimeInterval(-5),
                downloadedAt: nil,
                progress: .init(
                    id: identifier,
                    fractionCompleted: 0.5,
                    bytesDownloaded: 5,
                    totalBytesExpected: 10
                ),
                failureDescription: nil,
                mediaRelativePath: nil,
                thumbnailRelativePath: nil,
                byteCount: nil,
                thumbnailRequest: .none
            ),
            to: itemDirectory
        )

        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 206,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4", "Content-Range": "bytes 5-9/10"]
            )!
            return (response, Data("world".utf8))
        }

        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: transientRoot,
                excludeFromBackup: false
            ),
            downloader: PlaylistAssetDownloader(urlSession: makeSession()),
            urlSession: makeSession()
        )

        _ = try await store.restorePendingDownloads()
        let storedMedia = try await store.waitForDownload(id: identifier)
        XCTAssertEqual(
            try String(decoding: Data(contentsOf: storedMedia.localMediaURL), as: UTF8.self),
            "helloworld"
        )
    }

    func testTransientStoragePolicyEvictsOldestTransientMedia() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let downloader = MockArtifactDownloader()
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false,
                transientStoragePolicy: .init(maxItemCount: 1, maxTotalByteCount: nil, maxAge: nil)
            ),
            downloader: downloader,
            urlSession: makeSession()
        )

        let first = try await store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "First",
                    src: "https://cdn.example.com/first.mp4",
                    pageSrc: "https://example.com/watch?v=1",
                    pageTitle: "First",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "first",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/first.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let second = try await store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "Second",
                    src: "https://cdn.example.com/second.mp4",
                    pageSrc: "https://example.com/watch?v=2",
                    pageTitle: "Second",
                    mimeType: "video/mp4",
                    duration: 10,
                    detected: true,
                    tagId: "second",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/second.mp4")!,
                mimeType: "video/mp4",
                requestHeaders: [:],
                resolutionMethod: .direct
            ),
            storageScope: .transient,
            thumbnail: .none
        )

        let allTransient = try await store.allStoredMedia(scope: .transient)
        XCTAssertEqual(allTransient.map(\.id), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.localMediaURL.path))
    }

    func testAssetDownloaderUsesHLSDownloaderPath() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let hlsDownloader = MockHLSAssetDownloader()
        let store = PlaylistOfflineMediaStore(
            configuration: .init(
                persistentRootURL: rootURL.appendingPathComponent("persistent", isDirectory: true),
                transientRootURL: rootURL.appendingPathComponent("transient", isDirectory: true),
                excludeFromBackup: false
            ),
            downloader: PlaylistAssetDownloader(
                urlSession: makeSession(),
                hlsDownloaderFactory: { hlsDownloader }
            ),
            urlSession: makeSession()
        )

        let storedMedia = try await store.download(
            PlaylistResolvedMedia(
                playlistInfo: PlaylistInfo(
                    name: "HLS Episode",
                    src: "https://cdn.example.com/master.m3u8",
                    pageSrc: "https://example.com/watch?v=hls",
                    pageTitle: "HLS Episode",
                    mimeType: "application/vnd.apple.mpegurl",
                    duration: 10,
                    detected: true,
                    tagId: "hls-episode",
                    isInvisible: false
                ),
                url: URL(string: "https://cdn.example.com/master.m3u8")!,
                mimeType: "application/vnd.apple.mpegurl",
                requestHeaders: ["Cookie": "session=abc123"],
                resolutionMethod: .direct
            ),
            storageScope: .persistent,
            thumbnail: .none
        )

        XCTAssertTrue(hlsDownloader.didDownload)
        XCTAssertEqual(hlsDownloader.lastIdentifier, storedMedia.id)
        XCTAssertTrue(storedMedia.localMediaURL.path.hasSuffix("media.movpkg"))
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

private final class SequencedArtifactDownloader: PlaylistArtifactDownloading {
    enum Step {
        case block(progress: PlaylistDownloadProgress)
        case success(data: Data, relativePath: String, mimeType: String?)
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        let step: Step = lock.withLock {
            precondition(steps.isEmpty == false)
            return steps.removeFirst()
        }

        switch step {
        case .block(let progress):
            onProgress(
                PlaylistDownloadProgress(
                    id: identifier,
                    fractionCompleted: progress.fractionCompleted,
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytesExpected: progress.totalBytesExpected
                )
            )
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            throw CancellationError()
        case .success(let data, let relativePath, let mimeType):
            let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try data.write(to: destinationURL, options: .atomic)
            onProgress(
                PlaylistDownloadProgress(
                    id: identifier,
                    fractionCompleted: 1,
                    bytesDownloaded: Int64(data.count),
                    totalBytesExpected: Int64(data.count)
                )
            )
            return PlaylistDownloadedArtifact(
                relativeMediaPath: relativePath,
                mimeType: mimeType ?? media.mimeType,
                byteCount: Int64(data.count)
            )
        }
    }
}

private final class SequencedHLSAssetDownloader: PlaylistHLSAssetDownloading {
    enum Step {
        case block(progress: PlaylistDownloadProgress)
        case success(relativePath: String, mimeType: String?)
    }

    private let lock = NSLock()
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        let step: Step = lock.withLock {
            precondition(steps.isEmpty == false)
            return steps.removeFirst()
        }

        switch step {
        case .block(let progress):
            onProgress(
                PlaylistDownloadProgress(
                    id: identifier,
                    fractionCompleted: progress.fractionCompleted,
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytesExpected: progress.totalBytesExpected
                )
            )
            try await Task.sleep(nanoseconds: 5_000_000_000)
            try Task.checkCancellation()
            throw CancellationError()
        case .success(let relativePath, let mimeType):
            let packageDirectory = directory.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            try Data("segment".utf8).write(to: packageDirectory.appendingPathComponent("segment.ts"))
            onProgress(
                PlaylistDownloadProgress(
                    id: identifier,
                    fractionCompleted: 1,
                    bytesDownloaded: 7,
                    totalBytesExpected: 7
                )
            )
            return PlaylistDownloadedArtifact(
                relativeMediaPath: relativePath,
                mimeType: mimeType ?? media.mimeType,
                byteCount: 7
            )
        }
    }
}

private final class MockHLSAssetDownloader: PlaylistHLSAssetDownloading {
    private(set) var didDownload = false
    private(set) var lastIdentifier: String?

    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        didDownload = true
        lastIdentifier = identifier
        let packageDirectory = directory.appendingPathComponent("media.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        let segmentURL = packageDirectory.appendingPathComponent("segment.ts", isDirectory: false)
        try Data("segment".utf8).write(to: segmentURL)
        onProgress(
            PlaylistDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: 7,
                totalBytesExpected: 7
            )
        )
        return PlaylistDownloadedArtifact(
            relativeMediaPath: "media.movpkg",
            mimeType: media.mimeType,
            byteCount: 7
        )
    }
}

private struct PendingMetadataFixture: Codable {
    let id: String
    let playlistInfo: PlaylistInfo
    let storageScope: PlaylistOfflineStorageScope
    let retentionPolicy: PlaylistRetentionPolicy
    let resolvedMedia: PlaylistResolvedMediaSnapshot
    let state: PlaylistDownloadState
    let createdAt: Date
    let updatedAt: Date
    let downloadedAt: Date?
    let progress: PlaylistDownloadProgress?
    let failureDescription: String?
    let mediaRelativePath: String?
    let thumbnailRelativePath: String?
    let byteCount: Int64?
    let thumbnailRequest: PlaylistThumbnailRequest
}

private func makeStoredMediaIdentifier(for item: PlaylistInfo) -> String {
    let digest = SHA256.hash(data: Data(item.candidateLookupKey.utf8))
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}

private func writeMetadataFixture(_ metadata: PendingMetadataFixture, to directory: URL) throws {
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
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

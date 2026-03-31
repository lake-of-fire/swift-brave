import Foundation

public protocol PlaylistWebLoaderFactory {
    func makeWebLoader() -> any PlaylistWebLoader
}

public protocol PlaylistWebLoader: AnyObject {
    func load(url: URL) async -> PlaylistInfo?
    func stop()
}

public struct PlaylistMediaRequestContext: Hashable, Sendable {
    public let headers: [String: String]

    public init(
        headers: [String: String] = [:],
        userAgent: String? = nil,
        referer: URL? = nil,
        cookieHeader: String? = nil
    ) {
        var headers = headers
        if let userAgent {
            headers["User-Agent"] = userAgent
        }
        if let referer {
            headers["Referer"] = referer.absoluteString
        }
        if let cookieHeader {
            headers["Cookie"] = cookieHeader
        }
        self.headers = headers
    }
}

public enum PlaylistMediaResolutionMethod: String, Hashable, Codable, Sendable {
    case direct
    case fallback
}

public struct PlaylistResolvedMedia: Hashable, Sendable {
    public let playlistInfo: PlaylistInfo
    public let url: URL
    public let mimeType: String?
    public let requestHeaders: [String: String]
    public let resolutionMethod: PlaylistMediaResolutionMethod

    public init(
        playlistInfo: PlaylistInfo,
        url: URL,
        mimeType: String?,
        requestHeaders: [String: String] = [:],
        resolutionMethod: PlaylistMediaResolutionMethod
    ) {
        self.playlistInfo = playlistInfo
        self.url = url
        self.mimeType = mimeType
        self.requestHeaders = requestHeaders
        self.resolutionMethod = resolutionMethod
    }
}

public final class PlaylistMediaStreamer {
    public enum PlaybackError: Error {
        case cannotLoadMedia
    }

    private let urlSession: URLSession
    private let webLoaderFactory: (any PlaylistWebLoaderFactory)?

    public init(
        urlSession: URLSession = .shared,
        webLoaderFactory: (any PlaylistWebLoaderFactory)? = nil
    ) {
        self.urlSession = urlSession
        self.webLoaderFactory = webLoaderFactory
    }

    public func resolveMedia(
        _ item: PlaylistInfo,
        requestContext: PlaylistMediaRequestContext = .init()
    ) async throws -> PlaylistResolvedMedia {
        if let resolved = await resolveDirectMedia(item, requestContext: requestContext, method: .direct) {
            return resolved
        }

        return try await resolveViaFallback(item, requestContext: requestContext)
    }

    public static func getMimeType(
        _ url: URL,
        requestContext: PlaylistMediaRequestContext = .init(),
        using session: URLSession = .shared
    ) async -> String? {
        switch url.scheme?.lowercased() {
        case "http", "https":
            break
        default:
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Playback-Session-Id")

        for (name, value) in requestContext.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return nil
            }
            guard response.statusCode == 302 || (200...299).contains(response.statusCode) else {
                return nil
            }

            if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
                return normalizedMimeType(contentType)
            }

            return nil
        } catch {
            return nil
        }
    }

    private func resolveViaFallback(
        _ item: PlaylistInfo,
        requestContext: PlaylistMediaRequestContext
    ) async throws -> PlaylistResolvedMedia {
        guard let pageURL = item.pageURL,
              let webLoaderFactory
        else {
            throw PlaybackError.cannotLoadMedia
        }

        let loader = webLoaderFactory.makeWebLoader()
        guard let fallbackItem = await loader.load(url: pageURL),
              let resolved = await resolveDirectMedia(fallbackItem, requestContext: requestContext, method: .fallback)
        else {
            throw PlaybackError.cannotLoadMedia
        }

        return resolved
    }

    private func resolveDirectMedia(
        _ item: PlaylistInfo,
        requestContext: PlaylistMediaRequestContext,
        method: PlaylistMediaResolutionMethod
    ) async -> PlaylistResolvedMedia? {
        guard let url = item.sourceURL,
              item.isBlobSource == false,
              item.isDataSource == false
        else {
            return nil
        }

        let mimeType = await Self.getMimeType(url, requestContext: requestContext, using: urlSession)
            ?? Self.normalizedMimeType(item.mimeType)

        guard mimeType != nil || item.isHTTPSource == false else {
            return nil
        }

        return PlaylistResolvedMedia(
            playlistInfo: item,
            url: url,
            mimeType: mimeType,
            requestHeaders: requestContext.headers,
            resolutionMethod: method
        )
    }

    private static func normalizedMimeType(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

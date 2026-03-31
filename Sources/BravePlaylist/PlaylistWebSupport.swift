import Foundation
import WebKit
import SwiftUIWebView

public struct PlaylistWebScriptSet: Sendable {
    public let playlistScripts: PlaylistBuiltScriptSet
    public let userScripts: [WebViewUserScript]

    public var messageHandlerName: String {
        playlistScripts.configuration.messageHandlerName
    }

    public var securityToken: String {
        playlistScripts.configuration.securityToken
    }

    public var processDocumentLoadJavaScript: String {
        playlistScripts.processDocumentLoadJavaScript
    }
}

public enum PlaylistWebScripts {
    public static func make(
        messageHandlerName: String,
        allowedDomains: Set<String> = [],
        configuration: PlaylistScriptConfiguration? = nil
    ) throws -> PlaylistWebScriptSet {
        let configuration = configuration ?? PlaylistScriptConfiguration(messageHandlerName: messageHandlerName)
        let playlistScripts = try PlaylistScriptEngine.makeScriptSet(configuration: configuration)
        let userScripts = [
            WebViewUserScript(
                source: playlistScripts.firefoxShimSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page,
                allowedDomains: allowedDomains
            ),
            WebViewUserScript(
                source: playlistScripts.mediaSourceOverrideSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page,
                allowedDomains: allowedDomains
            ),
            WebViewUserScript(
                source: playlistScripts.detectorSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page,
                allowedDomains: allowedDomains
            ),
        ]

        return PlaylistWebScriptSet(
            playlistScripts: playlistScripts,
            userScripts: userScripts
        )
    }
}

public enum PlaylistWebMessageDecoder {
    public static func decode(
        message: WebViewMessage,
        scriptSet: PlaylistWebScriptSet
    ) -> PlaylistScriptMessage? {
        decode(body: message.body, scriptSet: scriptSet)
    }

    public static func decode(
        body: Any,
        scriptSet: PlaylistWebScriptSet
    ) -> PlaylistScriptMessage? {
        PlaylistScriptMessageDecoder.decode(
            body: body,
            expectingSecurityToken: scriptSet.securityToken
        )
    }
}

public enum PlaylistCandidateSelector {
    public static func preferredCandidate(
        from candidates: [PlaylistInfo],
        preferringAudio: Bool = true
    ) -> PlaylistInfo? {
        candidates.max { lhs, rhs in
            compare(lhs, rhs, preferringAudio: preferringAudio) == .orderedAscending
        }
    }

    private static func compare(
        _ lhs: PlaylistInfo,
        _ rhs: PlaylistInfo,
        preferringAudio: Bool
    ) -> ComparisonResult {
        let lhsScore = score(lhs, preferringAudio: preferringAudio)
        let rhsScore = score(rhs, preferringAudio: preferringAudio)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore ? .orderedAscending : .orderedDescending
        }
        if lhs.duration != rhs.duration {
            return lhs.duration < rhs.duration ? .orderedAscending : .orderedDescending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    }

    private static func score(_ candidate: PlaylistInfo, preferringAudio: Bool) -> Int {
        var score = 0
        if !candidate.isInvisible {
            score += 8
        }
        if candidate.isHTTPSource {
            score += 8
        } else if !candidate.isBlobSource && !candidate.isDataSource {
            score += 4
        }
        if candidate.detected {
            score += 4
        }
        if candidate.duration > 0 {
            score += 2
        }
        if candidate.containerKind == .hls {
            score += 1
        }
        if preferringAudio {
            switch candidate.kind {
            case .audio:
                score += 6
            case .video:
                score += 3
            case .unknown:
                break
            }
        } else if candidate.kind == .video {
            score += 6
        }
        return score
    }
}

public enum PlaylistRequestContextBuilder {
    public static func make(
        userAgent: String? = nil,
        referer: URL? = nil,
        cookies: [HTTPCookie] = []
    ) -> PlaylistMediaRequestContext {
        PlaylistMediaRequestContext(
            userAgent: userAgent,
            referer: referer,
            cookieHeader: cookieHeader(for: cookies)
        )
    }

    @MainActor
    public static func make(
        webView: WKWebView,
        referer: URL? = nil
    ) async -> PlaylistMediaRequestContext {
        let cookies = await cookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        let userAgent = await resolveUserAgent(for: webView)
        return make(
            userAgent: userAgent,
            referer: referer ?? webView.url,
            cookies: cookies
        )
    }

    public static func cookieHeader(for cookies: [HTTPCookie]) -> String? {
        guard !cookies.isEmpty else {
            return nil
        }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    @MainActor
    private static func resolveUserAgent(for webView: WKWebView) async -> String? {
        if let customUserAgent = webView.customUserAgent,
           !customUserAgent.isEmpty {
            return customUserAgent
        }

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    @MainActor
    private static func cookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

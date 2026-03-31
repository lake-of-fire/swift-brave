import Foundation

public enum PlaylistUserScriptInjectionTime: String, Codable, CaseIterable, Sendable {
    case atDocumentStart
    case atDocumentEnd
}

public enum PlaylistUserScriptContentWorld: String, Codable, CaseIterable, Sendable {
    case page
}

public struct PlaylistUserScript: Hashable, Sendable {
    public let source: String
    public let injectionTime: PlaylistUserScriptInjectionTime
    public let isForMainFrameOnly: Bool
    public let contentWorld: PlaylistUserScriptContentWorld
    public let allowedDomains: Set<String>

    public init(
        source: String,
        injectionTime: PlaylistUserScriptInjectionTime,
        isForMainFrameOnly: Bool,
        contentWorld: PlaylistUserScriptContentWorld = .page,
        allowedDomains: Set<String> = []
    ) {
        self.source = source
        self.injectionTime = injectionTime
        self.isForMainFrameOnly = isForMainFrameOnly
        self.contentWorld = contentWorld
        self.allowedDomains = allowedDomains
    }
}

public struct PlaylistWebScriptSet: Sendable {
    public let playlistScripts: PlaylistBuiltScriptSet
    public let userScripts: [PlaylistUserScript]

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
            PlaylistUserScript(
                source: playlistScripts.firefoxShimSource,
                injectionTime: .atDocumentStart,
                isForMainFrameOnly: false,
                allowedDomains: allowedDomains
            ),
            PlaylistUserScript(
                source: playlistScripts.mediaSourceOverrideSource,
                injectionTime: .atDocumentStart,
                isForMainFrameOnly: false,
                allowedDomains: allowedDomains
            ),
            PlaylistUserScript(
                source: playlistScripts.detectorSource,
                injectionTime: .atDocumentStart,
                isForMainFrameOnly: false,
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

    public static func cookieHeader(for cookies: [HTTPCookie]) -> String? {
        guard !cookies.isEmpty else {
            return nil
        }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

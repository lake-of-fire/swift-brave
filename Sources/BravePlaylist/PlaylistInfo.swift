import Foundation

public enum PlaylistMediaKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case unknown
}

public enum PlaylistContainerKind: String, Codable, CaseIterable, Sendable {
    case hls
    case file
    case unknown
}

public struct PlaylistInfo: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var src: String
    public var pageSrc: String
    public var pageTitle: String
    public var mimeType: String
    public var duration: TimeInterval
    public var detected: Bool
    public var tagId: String
    public var isInvisible: Bool

    public var id: String {
        tagId
    }

    public var sourceURL: URL? {
        URL(string: src)
    }

    public var pageURL: URL? {
        URL(string: pageSrc)
    }

    public var normalizedMimeType: String? {
        let trimmed = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public var containerKind: PlaylistContainerKind {
        if Self.hlsMimeTypes.contains(normalizedMimeType ?? "")
            || sourceURL?.pathExtension.lowercased() == "m3u8" {
            return .hls
        }

        switch sourceURL?.pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "mp4", "m4v", "mov", "webm":
            return .file
        default:
            return normalizedMimeType == nil ? .unknown : .file
        }
    }

    public var kind: PlaylistMediaKind {
        let normalizedMimeType = self.normalizedMimeType ?? ""
        if normalizedMimeType.hasPrefix("audio/") || normalizedMimeType == "audio" {
            return .audio
        }
        if normalizedMimeType.hasPrefix("video/") || normalizedMimeType == "video" {
            return .video
        }
        if Self.hlsMimeTypes.contains(normalizedMimeType) {
            return .unknown
        }

        switch sourceURL?.pathExtension.lowercased() {
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus":
            return .audio
        case "mp4", "m4v", "mov", "webm":
            return .video
        case "m3u8":
            return .unknown
        default:
            return .unknown
        }
    }

    public var isBlobSource: Bool {
        src.hasPrefix("blob:")
    }

    public var isDataSource: Bool {
        src.hasPrefix("data:")
    }

    public var isHTTPSource: Bool {
        guard let scheme = sourceURL?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    public init(pageSrc: String) {
        self.init(
            name: "",
            src: "",
            pageSrc: pageSrc,
            pageTitle: "",
            mimeType: "",
            duration: 0,
            detected: false,
            tagId: UUID().uuidString,
            isInvisible: false
        )
    }

    public init(
        name: String,
        src: String,
        pageSrc: String,
        pageTitle: String,
        mimeType: String,
        duration: TimeInterval,
        detected: Bool,
        tagId: String,
        isInvisible: Bool
    ) {
        self.name = name
        self.src = Self.fixSchemelessURLs(src: src, pageSrc: pageSrc)
        self.pageSrc = pageSrc
        self.pageTitle = pageTitle
        self.mimeType = mimeType
        self.duration = duration
        self.detected = detected
        self.tagId = tagId.isEmpty ? UUID().uuidString : tagId
        self.isInvisible = isInvisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let src = try container.decodeIfPresent(String.self, forKey: .src) ?? ""
        let pageSrc = try container.decode(String.self, forKey: .pageSrc)

        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.src = Self.fixSchemelessURLs(src: src, pageSrc: pageSrc)
        self.pageSrc = pageSrc
        self.pageTitle = try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? ""
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        self.detected = try container.decodeIfPresent(Bool.self, forKey: .detected) ?? false
        self.tagId = try container.decodeIfPresent(String.self, forKey: .tagId) ?? UUID().uuidString
        self.isInvisible = try container.decodeIfPresent(Bool.self, forKey: .isInvisible) ?? false
    }

    public static func decode(from body: Any) -> PlaylistInfo? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public static func fixSchemelessURLs(src: String, pageSrc: String) -> String {
        if src.hasPrefix("//") {
            return "\(URL(string: pageSrc)?.scheme ?? "https"):\(src)"
        }
        if src.hasPrefix("/"),
           let url = URL(string: src, relativeTo: URL(string: pageSrc))?.absoluteString {
            return url
        }
        return src
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case src
        case pageSrc
        case pageTitle
        case mimeType
        case duration
        case detected
        case tagId
        case isInvisible = "invisible"
    }

    private static let hlsMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl",
        "application/x-mpegurl",
    ]
}

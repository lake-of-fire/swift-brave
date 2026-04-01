import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PlaylistOfflineStorageScope: String, Codable, CaseIterable, Sendable {
    case transient
    case persistent
}

public struct PlaylistDownloadProgress: Hashable, Sendable {
    public let id: String
    public let fractionCompleted: Double
    public let bytesDownloaded: Int64
    public let totalBytesExpected: Int64?

    public init(
        id: String,
        fractionCompleted: Double,
        bytesDownloaded: Int64,
        totalBytesExpected: Int64?
    ) {
        self.id = id
        self.fractionCompleted = fractionCompleted
        self.bytesDownloaded = bytesDownloaded
        self.totalBytesExpected = totalBytesExpected
    }
}

public struct PlaylistThumbnailRequest: Sendable {
    public let generateFromMedia: Bool
    public let preferredFrameTime: TimeInterval
    public let remoteImageURL: URL?
    public let remoteRequestHeaders: [String: String]
    public let imageData: Data?
    public let fileExtension: String?

    public init(
        generateFromMedia: Bool = true,
        preferredFrameTime: TimeInterval = 3,
        remoteImageURL: URL? = nil,
        remoteRequestHeaders: [String: String] = [:],
        imageData: Data? = nil,
        fileExtension: String? = nil
    ) {
        self.generateFromMedia = generateFromMedia
        self.preferredFrameTime = preferredFrameTime
        self.remoteImageURL = remoteImageURL
        self.remoteRequestHeaders = remoteRequestHeaders
        self.imageData = imageData
        self.fileExtension = fileExtension
    }

    public static var none: Self {
        Self(generateFromMedia: false)
    }

    public static func automatic(
        remoteImageURL: URL? = nil,
        remoteRequestHeaders: [String: String] = [:],
        preferredFrameTime: TimeInterval = 3
    ) -> Self {
        Self(
            generateFromMedia: true,
            preferredFrameTime: preferredFrameTime,
            remoteImageURL: remoteImageURL,
            remoteRequestHeaders: remoteRequestHeaders
        )
    }

    public static func inlineImageData(
        _ data: Data,
        fileExtension: String? = nil
    ) -> Self {
        Self(
            generateFromMedia: false,
            imageData: data,
            fileExtension: fileExtension
        )
    }
}

public struct PlaylistStoredMedia: Hashable, Identifiable, Sendable {
    public let id: String
    public let playlistInfo: PlaylistInfo
    public let storageScope: PlaylistOfflineStorageScope
    public let resolvedMediaURL: URL
    public let localMediaURL: URL
    public let localThumbnailURL: URL?
    public let mimeType: String?
    public let byteCount: Int64?
    public let resolutionMethod: PlaylistMediaResolutionMethod
    public let downloadedAt: Date

    public var pageURL: URL? {
        playlistInfo.pageURL
    }

    public var pageLookupKey: String {
        playlistInfo.pageLookupKey
    }

    public var candidateLookupKey: String {
        playlistInfo.candidateLookupKey
    }

    public var isPersistent: Bool {
        storageScope == .persistent
    }

    public init(
        id: String,
        playlistInfo: PlaylistInfo,
        storageScope: PlaylistOfflineStorageScope,
        resolvedMediaURL: URL,
        localMediaURL: URL,
        localThumbnailURL: URL?,
        mimeType: String?,
        byteCount: Int64?,
        resolutionMethod: PlaylistMediaResolutionMethod,
        downloadedAt: Date
    ) {
        self.id = id
        self.playlistInfo = playlistInfo
        self.storageScope = storageScope
        self.resolvedMediaURL = resolvedMediaURL
        self.localMediaURL = localMediaURL
        self.localThumbnailURL = localThumbnailURL
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.resolutionMethod = resolutionMethod
        self.downloadedAt = downloadedAt
    }
}

public enum PlaylistOfflineStoreError: Error, Equatable {
    case mediaNotFound
    case invalidStorageRoots
    case invalidHTTPStatus(Int)
    case invalidResponse
    case downloadFailed
    case thumbnailGenerationFailed
}

public protocol PlaylistArtifactDownloading: AnyObject {
    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact
}

public struct PlaylistDownloadedArtifact: Hashable, Sendable {
    public let relativeMediaPath: String
    public let mimeType: String?
    public let byteCount: Int64?

    public init(relativeMediaPath: String, mimeType: String?, byteCount: Int64?) {
        self.relativeMediaPath = relativeMediaPath
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}

public final class PlaylistAssetDownloader: PlaylistArtifactDownloading {
    private let urlSession: URLSession
    private let hlsDownloaderFactory: () -> PlaylistHLSAssetDownloading

    public init(
        urlSession: URLSession = .shared,
        hlsDownloaderFactory: @escaping () -> PlaylistHLSAssetDownloading = { PlaylistHLSAssetDownloader() }
    ) {
        self.urlSession = urlSession
        self.hlsDownloaderFactory = hlsDownloaderFactory
    }

    public func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        if media.playlistInfo.containerKind == .hls {
            return try await hlsDownloaderFactory().download(
                media: media,
                into: directory,
                identifier: identifier,
                onProgress: onProgress
            )
        }

        return try await downloadFile(
            media: media,
            into: directory,
            identifier: identifier,
            onProgress: onProgress
        )
    }

    private func downloadFile(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        var request = URLRequest(
            url: media.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        request.httpMethod = "GET"
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Playback-Session-Id")
        for (header, value) in media.requestHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PlaylistOfflineStoreError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw PlaylistOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }

        let temporaryURL = directory.appendingPathComponent("media.partial", isDirectory: false)
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? fileHandle.close() }

        let expectedContentLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let responseMimeType = response.value(forHTTPHeaderField: "Content-Type")

        var buffer = Data()
        var sniffData = Data()
        var totalBytesWritten: Int64 = 0
        let flushThreshold = 64 * 1024
        let sniffThreshold = 4096

        for try await byte in bytes {
            buffer.append(byte)
            totalBytesWritten += 1

            if sniffData.count < sniffThreshold {
                sniffData.append(byte)
            }

            if buffer.count >= flushThreshold {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                onProgress(
                    PlaylistDownloadProgress(
                        id: identifier,
                        fractionCompleted: Self.progress(bytesDownloaded: totalBytesWritten, totalBytesExpected: expectedContentLength),
                        bytesDownloaded: totalBytesWritten,
                        totalBytesExpected: expectedContentLength
                    )
                )
            }
        }

        if buffer.isEmpty == false {
            try fileHandle.write(contentsOf: buffer)
        }

        let fileExtension = PlaylistMimeTypeDetector.preferredFileExtension(
            url: media.url,
            mimeType: responseMimeType ?? media.mimeType,
            leadingData: sniffData,
            fallback: "mp4"
        )
        let finalRelativePath = "media.\(fileExtension)"
        let finalURL = directory.appendingPathComponent(finalRelativePath, isDirectory: false)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)

        onProgress(
            PlaylistDownloadProgress(
                id: identifier,
                fractionCompleted: 1,
                bytesDownloaded: totalBytesWritten,
                totalBytesExpected: expectedContentLength ?? totalBytesWritten
            )
        )

        return PlaylistDownloadedArtifact(
            relativeMediaPath: finalRelativePath,
            mimeType: responseMimeType ?? media.mimeType,
            byteCount: totalBytesWritten
        )
    }

    private static func progress(bytesDownloaded: Int64, totalBytesExpected: Int64?) -> Double {
        guard let totalBytesExpected, totalBytesExpected > 0 else {
            return 0
        }
        return min(1, Double(bytesDownloaded) / Double(totalBytesExpected))
    }
}

public protocol PlaylistHLSAssetDownloading: AnyObject {
    func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact
}

public final class PlaylistHLSAssetDownloader: NSObject, PlaylistHLSAssetDownloading {
    private var continuation: CheckedContinuation<PlaylistDownloadedArtifact, Error>?
    private var onProgress: (@Sendable (PlaylistDownloadProgress) -> Void)?
    private var identifier = ""
    private var destinationDirectory = URL(fileURLWithPath: "/")
    private var temporaryLocation: URL?
    private var resolvedMimeType: String?
    private var session: AVAssetDownloadURLSession?

    public func download(
        media: PlaylistResolvedMedia,
        into directory: URL,
        identifier: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void
    ) async throws -> PlaylistDownloadedArtifact {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.onProgress = onProgress
            self.identifier = identifier
            self.destinationDirectory = directory
            self.resolvedMimeType = media.mimeType

            let configuration = URLSessionConfiguration.background(
                withIdentifier: "com.lakeoffire.swift-brave.playlist.hls.\(UUID().uuidString)"
            )
            let session = AVAssetDownloadURLSession(
                configuration: configuration,
                assetDownloadDelegate: self,
                delegateQueue: .main
            )
            self.session = session

            let assetOptions = media.requestHeaders.isEmpty
                ? nil
                : ["AVURLAssetHTTPHeaderFieldsKey": media.requestHeaders]
            let asset = AVURLAsset(url: media.url, options: assetOptions)
            guard let task = session.makeAssetDownloadTask(
                asset: asset,
                assetTitle: media.playlistInfo.preferredDisplayName,
                assetArtworkData: nil,
                options: nil
            ) else {
                continuation.resume(throwing: PlaylistOfflineStoreError.downloadFailed)
                self.reset()
                return
            }

            task.resume()
        }
    }

    private func finish(with result: Result<PlaylistDownloadedArtifact, Error>) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success(let artifact):
            continuation.resume(returning: artifact)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        reset()
    }

    private func reset() {
        onProgress = nil
        temporaryLocation = nil
        resolvedMimeType = nil
        identifier = ""
        destinationDirectory = URL(fileURLWithPath: "/")
    }
}

extension PlaylistHLSAssetDownloader: AVAssetDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        temporaryLocation = location
    }

    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let duration = timeRangeExpectedToLoad.duration.seconds
        let fractionCompleted: Double
        if duration > 0 {
            let loaded = loadedTimeRanges
                .map(\.timeRangeValue.duration.seconds)
                .reduce(0, +)
            fractionCompleted = min(1, loaded / duration)
        } else {
            fractionCompleted = 0
        }

        onProgress?(
            PlaylistDownloadProgress(
                id: identifier,
                fractionCompleted: fractionCompleted,
                bytesDownloaded: 0,
                totalBytesExpected: nil
            )
        )
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }

        guard let temporaryLocation else {
            finish(with: .failure(PlaylistOfflineStoreError.downloadFailed))
            return
        }

        let fileExtension = temporaryLocation.pathExtension.isEmpty == false ? temporaryLocation.pathExtension : "movpkg"
        let finalRelativePath = "media.\(fileExtension)"
        let finalURL = destinationDirectory.appendingPathComponent(finalRelativePath, isDirectory: false)

        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: temporaryLocation, to: finalURL)
            let byteCount = try PlaylistStoredMediaFileSystem.directorySize(at: finalURL)
            onProgress?(
                PlaylistDownloadProgress(
                    id: identifier,
                    fractionCompleted: 1,
                    bytesDownloaded: byteCount,
                    totalBytesExpected: byteCount
                )
            )
            finish(
                with: .success(
                    PlaylistDownloadedArtifact(
                        relativeMediaPath: finalRelativePath,
                        mimeType: resolvedMimeType,
                        byteCount: byteCount
                    )
                )
            )
        } catch {
            finish(with: .failure(error))
        }
    }
}

public actor PlaylistOfflineMediaStore {
    public struct Configuration: Sendable {
        public var persistentRootURL: URL
        public var transientRootURL: URL
        public var excludeFromBackup: Bool

        public init(
            persistentRootURL: URL? = nil,
            transientRootURL: URL? = nil,
            excludeFromBackup: Bool = true
        ) {
            self.persistentRootURL = persistentRootURL ?? Self.defaultPersistentRootURL()
            self.transientRootURL = transientRootURL ?? Self.defaultTransientRootURL()
            self.excludeFromBackup = excludeFromBackup
        }

        private static func defaultPersistentRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("BravePlaylist", isDirectory: true)
                .appendingPathComponent("OfflineMedia", isDirectory: true)
        }

        private static func defaultTransientRootURL() -> URL {
            let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return baseURL
                .appendingPathComponent("BravePlaylist", isDirectory: true)
                .appendingPathComponent("TransientMedia", isDirectory: true)
        }
    }

    private let configuration: Configuration
    private let downloader: any PlaylistArtifactDownloading
    private let urlSession: URLSession

    public init(
        configuration: Configuration = .init(),
        downloader: any PlaylistArtifactDownloading = PlaylistAssetDownloader(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.downloader = downloader
        self.urlSession = urlSession
    }

    public func download(
        _ media: PlaylistResolvedMedia,
        storageScope: PlaylistOfflineStorageScope,
        thumbnail: PlaylistThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> PlaylistStoredMedia {
        try prepareRootsIfNeeded()

        if let existing = try storedMedia(for: media.playlistInfo) {
            if existing.storageScope == .transient && storageScope == .persistent {
                return try updateStorageScope(.persistent, for: existing.id)
            }
            return existing
        }

        let identifier = Self.storedMediaIdentifier(for: media.playlistInfo)
        let itemDirectory = rootURL(for: storageScope).appendingPathComponent(identifier, isDirectory: true)
        if FileManager.default.fileExists(atPath: itemDirectory.path) {
            try FileManager.default.removeItem(at: itemDirectory)
        }
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)

        do {
            let artifact = try await downloader.download(
                media: media,
                into: itemDirectory,
                identifier: identifier,
                onProgress: onProgress
            )

            let mediaURL = itemDirectory.appendingPathComponent(artifact.relativeMediaPath, isDirectory: false)
            let thumbnailRelativePath = try await storeThumbnail(
                thumbnail,
                mediaURL: mediaURL,
                directory: itemDirectory
            )

            let metadata = PlaylistStoredMediaMetadata(
                id: identifier,
                playlistInfo: media.playlistInfo,
                storageScope: storageScope,
                resolvedMediaURL: media.url.absoluteString,
                mimeType: artifact.mimeType ?? media.mimeType,
                byteCount: artifact.byteCount,
                resolutionMethod: media.resolutionMethod,
                downloadedAt: Date(),
                mediaRelativePath: artifact.relativeMediaPath,
                thumbnailRelativePath: thumbnailRelativePath
            )
            try writeMetadata(metadata, in: itemDirectory)
            return metadata.makeStoredMedia(rootDirectory: itemDirectory)
        } catch {
            try? FileManager.default.removeItem(at: itemDirectory)
            throw error
        }
    }

    public func storedMedia(for item: PlaylistInfo) throws -> PlaylistStoredMedia? {
        let allItems = try loadAllStoredMedia()
        return allItems
            .filter { $0.candidateLookupKey == item.candidateLookupKey }
            .sorted(by: Self.preferredOrdering)
            .first
    }

    public func storedMedia(forPageURL pageURL: URL) throws -> [PlaylistStoredMedia] {
        let pageLookupKey = PlaylistInfo.pageLookupKey(for: pageURL.absoluteString)
        return try loadAllStoredMedia()
            .filter { $0.pageLookupKey == pageLookupKey }
            .sorted(by: Self.preferredOrdering)
    }

    public func storedMedia(id: String) throws -> PlaylistStoredMedia? {
        try loadAllStoredMedia().first(where: { $0.id == id })
    }

    public func allStoredMedia(scope: PlaylistOfflineStorageScope? = nil) throws -> [PlaylistStoredMedia] {
        try loadAllStoredMedia()
            .filter { scope == nil || $0.storageScope == scope }
            .sorted(by: Self.preferredOrdering)
    }

    @discardableResult
    public func updateStorageScope(
        _ storageScope: PlaylistOfflineStorageScope,
        for id: String
    ) throws -> PlaylistStoredMedia {
        try prepareRootsIfNeeded()

        guard let existing = try storedMedia(id: id) else {
            throw PlaylistOfflineStoreError.mediaNotFound
        }
        if existing.storageScope == storageScope {
            return existing
        }

        let sourceDirectory = rootURL(for: existing.storageScope).appendingPathComponent(id, isDirectory: true)
        let destinationDirectory = rootURL(for: storageScope).appendingPathComponent(id, isDirectory: true)

        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.moveItem(at: sourceDirectory, to: destinationDirectory)

        var metadata = try readMetadata(from: destinationDirectory)
        metadata.storageScope = storageScope
        try writeMetadata(metadata, in: destinationDirectory)
        return metadata.makeStoredMedia(rootDirectory: destinationDirectory)
    }

    public func deleteStoredMedia(id: String) throws {
        let persistentDirectory = configuration.persistentRootURL.appendingPathComponent(id, isDirectory: true)
        let transientDirectory = configuration.transientRootURL.appendingPathComponent(id, isDirectory: true)

        if FileManager.default.fileExists(atPath: persistentDirectory.path) {
            try FileManager.default.removeItem(at: persistentDirectory)
        }
        if FileManager.default.fileExists(atPath: transientDirectory.path) {
            try FileManager.default.removeItem(at: transientDirectory)
        }
    }

    public func deleteAllStoredMedia(scope: PlaylistOfflineStorageScope? = nil) throws {
        let scopes = scope.map { [$0] } ?? PlaylistOfflineStorageScope.allCases
        for scope in scopes {
            let rootURL = rootURL(for: scope)
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
        }
        try prepareRootsIfNeeded()
    }

    public func purgeTransientMedia() throws {
        try deleteAllStoredMedia(scope: .transient)
    }

    private func storeThumbnail(
        _ thumbnail: PlaylistThumbnailRequest,
        mediaURL: URL,
        directory: URL
    ) async throws -> String? {
        if let imageData = thumbnail.imageData {
            let fileExtension = thumbnail.fileExtension ?? "jpg"
            let relativePath = "thumbnail.\(fileExtension)"
            let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try imageData.write(to: destinationURL)
            return relativePath
        }

        if thumbnail.generateFromMedia,
           let relativePath = try PlaylistStoredMediaThumbnailStore.generateMediaThumbnail(
                from: mediaURL,
                preferredFrameTime: thumbnail.preferredFrameTime,
                directory: directory
           ) {
            return relativePath
        }

        if let remoteImageURL = thumbnail.remoteImageURL {
            return try await PlaylistStoredMediaThumbnailStore.storeRemoteThumbnail(
                from: remoteImageURL,
                headers: thumbnail.remoteRequestHeaders,
                directory: directory,
                using: urlSession
            )
        }

        return nil
    }

    private func loadAllStoredMedia() throws -> [PlaylistStoredMedia] {
        try prepareRootsIfNeeded()
        return try PlaylistOfflineStorageScope.allCases.flatMap { scope in
            try loadStoredMedia(in: rootURL(for: scope))
        }
    }

    private func loadStoredMedia(in rootURL: URL) throws -> [PlaylistStoredMedia] {
        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var result = [PlaylistStoredMedia]()
        for directoryURL in directoryURLs {
            let resourceValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else {
                continue
            }

            do {
                let metadata = try readMetadata(from: directoryURL)
                let storedMedia = metadata.makeStoredMedia(rootDirectory: directoryURL)
                if FileManager.default.fileExists(atPath: storedMedia.localMediaURL.path) {
                    result.append(storedMedia)
                } else {
                    try? FileManager.default.removeItem(at: directoryURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        }

        return result
    }

    private func prepareRootsIfNeeded() throws {
        try [configuration.persistentRootURL, configuration.transientRootURL].forEach { rootURL in
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            if configuration.excludeFromBackup {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableRootURL = rootURL
                try mutableRootURL.setResourceValues(resourceValues)
            }
        }
    }

    private func rootURL(for scope: PlaylistOfflineStorageScope) -> URL {
        switch scope {
        case .transient:
            return configuration.transientRootURL
        case .persistent:
            return configuration.persistentRootURL
        }
    }

    private func readMetadata(from directory: URL) throws -> PlaylistStoredMediaMetadata {
        let metadataURL = directory.appendingPathComponent("metadata.json", isDirectory: false)
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(PlaylistStoredMediaMetadata.self, from: data)
    }

    private func writeMetadata(_ metadata: PlaylistStoredMediaMetadata, in directory: URL) throws {
        let metadataURL = directory.appendingPathComponent("metadata.json", isDirectory: false)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func storedMediaIdentifier(for item: PlaylistInfo) -> String {
        let digest = SHA256.hash(data: Data(item.candidateLookupKey.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func preferredOrdering(_ lhs: PlaylistStoredMedia, _ rhs: PlaylistStoredMedia) -> Bool {
        if lhs.storageScope != rhs.storageScope {
            return lhs.storageScope == .persistent
        }
        return lhs.downloadedAt > rhs.downloadedAt
    }
}

private struct PlaylistStoredMediaMetadata: Codable, Sendable {
    var id: String
    var playlistInfo: PlaylistInfo
    var storageScope: PlaylistOfflineStorageScope
    var resolvedMediaURL: String
    var mimeType: String?
    var byteCount: Int64?
    var resolutionMethod: PlaylistMediaResolutionMethod
    var downloadedAt: Date
    var mediaRelativePath: String
    var thumbnailRelativePath: String?

    func makeStoredMedia(rootDirectory: URL) -> PlaylistStoredMedia {
        PlaylistStoredMedia(
            id: id,
            playlistInfo: playlistInfo,
            storageScope: storageScope,
            resolvedMediaURL: URL(string: resolvedMediaURL) ?? rootDirectory,
            localMediaURL: rootDirectory.appendingPathComponent(mediaRelativePath, isDirectory: false),
            localThumbnailURL: thumbnailRelativePath.map {
                rootDirectory.appendingPathComponent($0, isDirectory: false)
            },
            mimeType: mimeType,
            byteCount: byteCount,
            resolutionMethod: resolutionMethod,
            downloadedAt: downloadedAt
        )
    }
}

private enum PlaylistStoredMediaThumbnailStore {
    static func generateMediaThumbnail(
        from mediaURL: URL,
        preferredFrameTime: TimeInterval,
        directory: URL
    ) throws -> String? {
        let asset = AVURLAsset(url: mediaURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: preferredFrameTime, preferredTimescale: 600)
        guard let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }

        let relativePath = "thumbnail.jpg"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try writeJPEG(cgImage, to: destinationURL)
        return relativePath
    }

    static func storeRemoteThumbnail(
        from url: URL,
        headers: [String: String],
        directory: URL,
        using session: URLSession
    ) async throws -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PlaylistOfflineStoreError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw PlaylistOfflineStoreError.invalidHTTPStatus(response.statusCode)
        }

        let fileExtension = PlaylistMimeTypeDetector.preferredFileExtension(
            url: url,
            mimeType: response.value(forHTTPHeaderField: "Content-Type"),
            leadingData: Data(data.prefix(4096)),
            fallback: "jpg"
        )
        let relativePath = "thumbnail.\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try data.write(to: destinationURL, options: .atomic)
        return relativePath
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PlaylistOfflineStoreError.thumbnailGenerationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PlaylistOfflineStoreError.thumbnailGenerationFailed
        }
    }
}

private enum PlaylistStoredMediaFileSystem {
    static func directorySize(at url: URL) throws -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }

        if total == 0,
           let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == true {
            total = Int64(values.fileSize ?? 0)
        }

        return total
    }
}

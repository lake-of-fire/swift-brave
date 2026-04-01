import Foundation

public actor PlaylistLibrary {
    private let mediaStreamer: PlaylistMediaStreamer
    private let offlineStore: PlaylistOfflineMediaStore

    public init(
        mediaStreamer: PlaylistMediaStreamer = PlaylistMediaStreamer(),
        offlineStore: PlaylistOfflineMediaStore = PlaylistOfflineMediaStore()
    ) {
        self.mediaStreamer = mediaStreamer
        self.offlineStore = offlineStore
    }

    public func download(
        _ item: PlaylistInfo,
        requestContext: PlaylistMediaRequestContext = .init(),
        storageScope: PlaylistOfflineStorageScope,
        retentionPolicy: PlaylistRetentionPolicy? = nil,
        thumbnail: PlaylistThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> PlaylistStoredMedia {
        let resolvedMedia = try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
        return try await offlineStore.download(
            resolvedMedia,
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
    }

    public func enqueueDownload(
        _ item: PlaylistInfo,
        requestContext: PlaylistMediaRequestContext = .init(),
        storageScope: PlaylistOfflineStorageScope,
        retentionPolicy: PlaylistRetentionPolicy? = nil,
        thumbnail: PlaylistThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> PlaylistDownloadRecord {
        let resolvedMedia = try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
        return try await offlineStore.enqueueDownload(
            resolvedMedia,
            storageScope: storageScope,
            retentionPolicy: retentionPolicy,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
    }

    public func waitForDownload(id: String) async throws -> PlaylistStoredMedia {
        try await offlineStore.waitForDownload(id: id)
    }

    public func downloadEvents(id: String? = nil) async -> AsyncStream<PlaylistDownloadEvent> {
        await offlineStore.downloadEvents(id: id)
    }

    public func restorePendingDownloads(
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> [PlaylistDownloadRecord] {
        try await offlineStore.restorePendingDownloads(onProgress: onProgress)
    }

    public func isDownloading(id: String) async throws -> Bool {
        try await offlineStore.isDownloading(id: id)
    }

    public func cancelDownload(id: String) async throws -> PlaylistDownloadRecord? {
        try await offlineStore.cancelDownload(id: id)
    }

    public func retryDownload(
        id: String,
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> PlaylistDownloadRecord {
        try await offlineStore.retryDownload(id: id, onProgress: onProgress)
    }

    public func downloadRecord(for item: PlaylistInfo) async throws -> PlaylistDownloadRecord? {
        try await offlineStore.downloadRecord(for: item)
    }

    public func currentDownloadRecord(id: String) async throws -> PlaylistDownloadRecord? {
        try await offlineStore.currentDownloadRecord(id: id)
    }

    public func allDownloadRecords(
        states: Set<PlaylistDownloadState>? = nil
    ) async throws -> [PlaylistDownloadRecord] {
        try await offlineStore.allDownloadRecords(states: states)
    }

    public func storedMedia(for item: PlaylistInfo) async throws -> PlaylistStoredMedia? {
        try await offlineStore.storedMedia(for: item)
    }

    public func storedMedia(forPageURL pageURL: URL) async throws -> [PlaylistStoredMedia] {
        try await offlineStore.storedMedia(forPageURL: pageURL)
    }

    public func bestStoredMedia(forPageURL pageURL: URL) async throws -> PlaylistStoredMedia? {
        try await offlineStore.bestStoredMedia(forPageURL: pageURL)
    }

    public func storedMedia(id: String) async throws -> PlaylistStoredMedia? {
        try await offlineStore.storedMedia(id: id)
    }

    public func ensureThumbnail(id: String) async throws -> PlaylistStoredMedia? {
        try await offlineStore.ensureThumbnail(id: id)
    }

    public func allStoredMedia(scope: PlaylistOfflineStorageScope? = nil) async throws -> [PlaylistStoredMedia] {
        try await offlineStore.allStoredMedia(scope: scope)
    }

    @discardableResult
    public func updateStorageScope(
        _ storageScope: PlaylistOfflineStorageScope,
        for id: String
    ) async throws -> PlaylistStoredMedia {
        try await offlineStore.updateStorageScope(storageScope, for: id)
    }

    @discardableResult
    public func updateRetentionPolicy(
        _ retentionPolicy: PlaylistRetentionPolicy,
        for id: String
    ) async throws -> PlaylistDownloadRecord {
        try await offlineStore.updateRetentionPolicy(retentionPolicy, for: id)
    }

    public func deleteStoredMedia(id: String) async throws {
        try await offlineStore.deleteStoredMedia(id: id)
    }

    public func deleteAllStoredMedia(scope: PlaylistOfflineStorageScope? = nil) async throws {
        try await offlineStore.deleteAllStoredMedia(scope: scope)
    }

    public func purgeTransientMedia() async throws {
        try await offlineStore.purgeTransientMedia()
    }

    public func deleteTransientMedia(forPageURL pageURL: URL) async throws {
        try await offlineStore.deleteTransientMedia(forPageURL: pageURL)
    }

    public func purgeTransientMedia(exceptPageURLs pageURLs: [URL]) async throws {
        try await offlineStore.purgeTransientMedia(exceptPageURLs: pageURLs)
    }

    public func handlePageDidChange(from oldPageURL: URL?, to newPageURL: URL?) async throws {
        try await offlineStore.handlePageDidChange(from: oldPageURL, to: newPageURL)
    }

    public func handleSessionDidEnd() async throws {
        try await offlineStore.handleSessionDidEnd()
    }

    public func enforceTransientStoragePolicy() async throws {
        try await offlineStore.enforceTransientStoragePolicy()
    }
}

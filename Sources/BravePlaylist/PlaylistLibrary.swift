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
        thumbnail: PlaylistThumbnailRequest = .automatic(),
        onProgress: @escaping @Sendable (PlaylistDownloadProgress) -> Void = { _ in }
    ) async throws -> PlaylistStoredMedia {
        let resolvedMedia = try await mediaStreamer.resolveMedia(item, requestContext: requestContext)
        return try await offlineStore.download(
            resolvedMedia,
            storageScope: storageScope,
            thumbnail: thumbnail,
            onProgress: onProgress
        )
    }

    public func storedMedia(for item: PlaylistInfo) async throws -> PlaylistStoredMedia? {
        try await offlineStore.storedMedia(for: item)
    }

    public func storedMedia(forPageURL pageURL: URL) async throws -> [PlaylistStoredMedia] {
        try await offlineStore.storedMedia(forPageURL: pageURL)
    }

    public func storedMedia(id: String) async throws -> PlaylistStoredMedia? {
        try await offlineStore.storedMedia(id: id)
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

    public func deleteStoredMedia(id: String) async throws {
        try await offlineStore.deleteStoredMedia(id: id)
    }

    public func deleteAllStoredMedia(scope: PlaylistOfflineStorageScope? = nil) async throws {
        try await offlineStore.deleteAllStoredMedia(scope: scope)
    }

    public func purgeTransientMedia() async throws {
        try await offlineStore.purgeTransientMedia()
    }
}

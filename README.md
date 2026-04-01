# SwiftBrave

Swift Package for a trimmed Brave-derived adblock and media-capture stack.

## BravePlaylist

`BravePlaylist` is the storage-free/webview-neutral extraction layer plus a hidden offline media store.

It currently provides:

- playlist detector/swizzler scripts derived from Brave
- message decoding and candidate selection
- direct URL vs hidden-webview fallback media resolution
- hidden offline media downloads for file and HLS media
- persistent vs transient storage scopes
- explicit stored-media states for queued/downloading/stored/failed/cancelled + scope
- retention policies for persistent, manual transient, page-bound, and session-bound media
- persisted in-progress download records
- explicit download control APIs for query/cancel/retry
- async download event streams for state/progress observation
- relaunch restore for queued/downloading items
- resumable direct-file downloads when a partial file is available
- transient quota/eviction policy
- stored-media lookup by item or page URL, including a preferred page-level result
- eager or lazy local thumbnail storage

It intentionally does **not** include Brave playlist UI, folders, CoreData models, toasts, or any user-visible file exposure.

### Core types

- `PlaylistWebScripts`
- `PlaylistWebMessageDecoder`
- `PlaylistCandidateSelector`
- `PlaylistMediaStreamer`
- `PlaylistOfflineMediaStore`
- `PlaylistLibrary`

### Storage model

Offline media is stored only under app-managed roots:

- persistent: Application Support
- transient: Caches

The package marks these roots as excluded from backup by default and does not expose a user-facing share/export API.

### Download model

There are two layers:

1. `PlaylistMediaStreamer`
   Resolves a `PlaylistInfo` into a playable/downloadable `PlaylistResolvedMedia`.

2. `PlaylistOfflineMediaStore`
   Stores resolved media, keeps per-item metadata, tracks download state, restores unfinished downloads on launch, and manages hidden files.

`PlaylistLibrary` composes both layers for app code that wants a single façade.

### Download control model

The store/library also expose:

- `isDownloading(id:)`
- `cancelDownload(id:)`
- `retryDownload(id:)`
- `downloadEvents(id:)`

This is the intended minimal control surface for Manabi/LakeOfFire before any playlist UI exists.

### Retention and state model

`PlaylistDownloadRecord` and `PlaylistStoredMedia` both expose:

- `storedMediaState`
- `storageScope`
- `retentionPolicy`

Use them as follows:

- `storageScope: .transient` + `retentionPolicy: .untilPageChange`
  Download the full file for current-page playback/transcription and drop it after the page changes.
- `storageScope: .transient` + `retentionPolicy: .untilSessionEnds`
  Keep the full file until app/session cleanup.
- `storageScope: .transient` + `retentionPolicy: .manualTransient`
  Keep the file in hidden transient storage until your own cleanup policy removes it.
- `storageScope: .persistent` + `retentionPolicy: .persistent`
  User explicitly chose offline save.

You can later promote or demote retention with `updateRetentionPolicy(...)` without building UI concepts into this package.

### Thumbnail model

`PlaylistThumbnailRequest` supports:

- `.automatic()`
  Eager for media-derived thumbnails, lazy when a separate remote thumbnail URL would require extra network work.
- `.lazy(...)`
  Defer thumbnail generation/fetch until `ensureThumbnail(id:)`.
- `.none`
  Skip thumbnail work entirely.

This keeps media download latency separate from thumbnail fetch latency when the thumbnail is optional.

### Recommended integration for LakeOfFire / Manabi

1. Detect candidates from the visible webview with `PlaylistWebScripts` and `PlaylistWebMessageDecoder`.
2. Pick the preferred candidate with `PlaylistCandidateSelector`.
3. When the user wants playback/transcription/download behavior, call `PlaylistLibrary.enqueueDownload(...)` or `PlaylistLibrary.download(...)`.
4. Use `.transient` plus `.untilPageChange` or `.untilSessionEnds` when the media is only needed for the current page/session.
5. Use `.persistent` when the user explicitly chooses offline save.
6. On app launch, call `PlaylistLibrary.restorePendingDownloads()` to restart queued/downloading items.
7. On navigation changes, use `PlaylistLibrary.deleteTransientMedia(forPageURL:)` or `PlaylistLibrary.purgeTransientMedia(exceptPageURLs:)`.
8. When a transient item should be kept, call `PlaylistLibrary.updateRetentionPolicy(.persistent, for: id)` or `PlaylistLibrary.updateStorageScope(.persistent, for: id)`.
9. When UI needs artwork later, call `PlaylistLibrary.ensureThumbnail(id:)` instead of forcing thumbnail work into the initial download path.
10. When the page changes, call `PlaylistLibrary.handlePageDidChange(from:to:)`.
11. When the app/session ends, call `PlaylistLibrary.handleSessionDidEnd()`.

### APIs you will likely use next in Manabi

```swift
let library = PlaylistLibrary(
    mediaStreamer: PlaylistMediaStreamer(
        urlSession: .shared,
        webLoaderFactory: yourHiddenWebLoaderFactory
    ),
    offlineStore: PlaylistOfflineMediaStore()
)

let record = try await library.enqueueDownload(
    candidate,
    requestContext: requestContext,
    storageScope: .transient,
    retentionPolicy: .untilPageChange,
    thumbnail: .automatic()
)

let stored = try await library.waitForDownload(id: record.id)
let existing = try await library.bestStoredMedia(forPageURL: pageURL)
let thumbReady = try await library.ensureThumbnail(id: stored.id)
let isDownloading = try await library.isDownloading(id: record.id)
let events = await library.downloadEvents(id: record.id)

try await library.restorePendingDownloads()
try await library.handlePageDidChange(from: previousPageURL, to: pageURL)
try await library.purgeTransientMedia(exceptPageURLs: [pageURL])
try await library.updateRetentionPolicy(.persistent, for: stored.id)
```

### Notes

- File downloads use a direct request path.
- HLS downloads use `AVAssetDownloadURLSession`.
- Relaunch restore currently re-enqueues unfinished downloads from persisted metadata. For direct file downloads, the downloader resumes from `media.partial` when that file exists; otherwise it restarts cleanly.
- DRM/Widevine/FairPlay media remains unsupported.
- Subtitle extraction is intentionally out of scope here.

- Run `../brave-core/make-spm /path/to/swift-brave` to regenerate locally.
- CI release: use the `release-binary` workflow to build a zip + checksum for the
  `BraveAdblockCore.xcframework` binary target.

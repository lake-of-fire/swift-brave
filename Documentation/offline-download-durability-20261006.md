# Offline download durability fixes

## Scope and integration

This draft changes only `Sources/WebMedia/WebMediaOfflineStore.swift` in SwiftBrave's WebMedia package. The media coordinator and SwiftUIDownloads are untouched.

Base: published `lake-of-fire/swift-brave` main, `84f2ba37df3992db73f62b99a3389cee886cbce5`. The supplied review points to a newer local Reader checkout. Its exact SwiftBrave revision has not been provided and the published Reader v3-hotfix `.gitmodules` does not list SwiftBrave. **Do not replace the local file wholesale or assume this draft is already integrated with that checkout.** Apply/reconcile this draft with the actual media branch before selecting a Reader dependency pin.

## Changes

1. Native HLS work uses a fresh operation per invocation. One serial queue owns registration, cancellation, delegate callbacks, file completion and exactly-once continuation completion. A cancellation latch survives cancellation before registration; callbacks must match their session/task.
2. File resumption requires a saved strong ETag, request fingerprint, final response URL and compatible representation length. Requests use identity encoding and `If-Range`. A 206 response must match that identity and describe the complete expected tail; received length is checked before completion. Unvalidated legacy partials restart, and a mismatched response invalidates resume identity without appending. Resume metadata stores a hash of request headers, never their plaintext values.
3. The completed result is formed before the atomic downloaded metadata write. Subsequent transient cache maintenance is best-effort and cannot route an already committed download through destructive failure handling.
4. Metadata read/decode failures propagate while preserving the directory. They no longer imply permission to delete a persistent or transient download.
5. Scope/retention updates share a durable transition intent containing both target scope and exact retention policy. Intent is atomically written before the move; reads recover from either location and clear intent only after destination metadata commits. Conflicting destination copies are preserved and reported. Retry relocation uses the same primitive. Active downloads reject retention/scope mutation until their operation finishes, rather than moving files out from under a live writer.

## Verification intentionally not run

At the user's request, no build, typecheck, lint, tests, simulator run or runtime verification was performed. This is an implementation draft, not a qualification or release claim.

The owner should reconcile the correct local base, then cover:

- HLS cancellation before registration, during creation, during progress and racing success/error; duplicate and old callbacks; reuse of one public downloader for overlapping invocations.
- Full 200, valid 206, ignored range returning 200, changed/missing/weak ETag, changed redirect URL, encoded response, malformed/multipart Content-Range, short/long body, 416, cancellation and restart at each sidecar/truncate/write boundary.
- A committed persistent/transient download surviving permission/I/O failures during optional cleanup, while waiters receive success once.
- Metadata locked by data protection, permission failures, invalid JSON and unavailable directories, with original bytes preserved and errors surfaced.
- All scope/retention transitions interrupted before/after intent write, move and final metadata write; exact `.untilPageChange` / `.untilSessionEnds` / `.manualTransient` recovery; conflicting destination copies; active-writer rejection and retry after completion.

Safe behavior changes: servers without a usable strong validator restart downloads rather than range-resume; invalid range attempts fail without corrupting the prefix and the next explicit retry starts fresh. Metadata enumeration may throw instead of silently discarding an unreadable item. Cache cleanup failures may leave extra transient files until a later cleanup attempt. Ambiguous duplicate move destinations require explicit recovery rather than automatic deletion.

## Generator and upstream investigation (October 6)

The published generator is in `lake-of-fire/brave-core`, not `swift-brave-core`: `make-spm` calls `spm/make_spm.py` (blob `33d7fd5a779b62069d835c698289e2de144f9c4c`). It clears destination entries except `.git`/`.gitignore`, copies templates and adblock sources, and applies `spm/patches/*.patch`. Published master and `codex/reader-hotfix-integration` currently lack a WebMedia Swift template; their five patches concern adblock. `swift-brave/Scripts/sync_web_media_sources.py` copies three Brave JavaScript files and rewrites existing Swift overlays, rather than supplying the offline-store implementation. Therefore this output-side patch is not yet a durable generator-side reconciliation. Locate/publish the actual local overlay first. Do not run the generator over unpreserved newer media work.

Brave upstream [#38461](https://github.com/brave/brave-core/pull/38461), merged July 29 (`aa85c139bb84ab0431c4e7490734a97f1da84ad9`), adds pending item/UUID ownership and startup cancellation in PlaylistManager. Adapt that ownership idea rather than blindly cherry-picking its CoreData/Playlist integration. The inspected October 6 upstream implementation does not establish complete post-probe/pre-start cancellation fencing for this custom checked-continuation HLS wrapper.

Upstream [#35862](https://github.com/brave/brave-core/pull/35862) addresses stale bookmarks/missing cached files and [#38650](https://github.com/brave/brave-core/pull/38650) adds LRU reclamation. Neither supplies WebMedia's representation-validated partial-file appending or persistent/transient retention transaction model. A wholesale Brave update is not a demonstrated fix for these custom-layer issues. Preserve upstream license/provenance notices if copying code. This investigation was read-only; no execution qualification was added.

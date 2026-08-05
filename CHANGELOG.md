## 1.1.0

- `HuggingFaceDownloader`:
  - **Rate limits (HTTP 429) and transient unavailability (503) are now
    retried** instead of thrown. The Hub rate-limits by client address, so
    anything sharing one — CI runners, an office NAT — meets 429 on perfectly
    ordinary usage, where the answer is to wait rather than to fail.
    - `maxRetries` (default 5; 0 disables), `retryInitialDelay` (default 1s,
      doubled per attempt) and `maxRetryDelay` (default 30s) configure it.
    - A response's `Retry-After` is honoured over the backoff when it names a
      delay in seconds, capped at `maxRetryDelay` so a server cannot stall the
      client indefinitely.
    - Only those two statuses retry: a 404 or a 401 describes the request, and
      repeating it would only be slower.
  - Added `endpoint`, defaulting to `$HF_ENDPOINT` and then
    `https://huggingface.co` — the same variable `huggingface_hub` reads, so a
    mirror or proxy already configured for those tools is picked up here too.
  - Added `downloadFile`: fetches a **single** file from a repository, over the
    same path `downloadSnapshot` uses (resume, cache store, progress, auth).
    A repository is often a rack of alternatives — one model published at a
    dozen quantizations — where a full snapshot would fetch tens of gigabytes
    to obtain one file.
    - The destination is either an explicit `localFile`, or `remoteFile`'s path
      resolved under `localDir`; a remote path that escapes `localDir`
      (absolute, or climbing out with `..`) is an `ArgumentError` rather than a
      write outside the directory.
  - Added `listFiles`: the repository's `rfilename` entries, sorted, with the
    same extension filtering `downloadSnapshot` applies. Lets a caller show what
    a repository offers before choosing, and explain a failed download without
    guessing at its contents.

## 1.0.3

- Cache store:
  - Generalized the download cache into a `DownloadCacheStore` interface
    (with a `DownloadCacheKey`), responsible for placing files at the download
    destination (`fetchTo`) and persisting downloaded files (`store`).
  - Added `LocalDirectoryDownloadCacheStore`, a filesystem-directory
    implementation that, when `useLinks` is enabled, places files at the
    destination as symbolic links to the cached version (`supportsLinks`).
  - `HuggingFaceDownloader` accepts a `cacheStore`; the existing
    `localDownloadCacheDirectory` / `localDownloadCacheMinFileLength` /
    `localDownloadCacheUseLink` parameters are a convenience that builds a
    `LocalDirectoryDownloadCacheStore` (ignored when `cacheStore` is provided).

- `HuggingFaceDownloader`:
  - Added `localDownloadCacheUseLink` option: serve cached files as symbolic
    links to the cached version instead of copying them (avoids duplicating
    large files on disk). Defaults to `false`.
    - On a fresh download, the file is moved into the cache and the local path
      is linked to the cached version.
    - On a cache hit, the local path is linked to the cached file.
  - When copying from the cache, any existing link at the destination is removed
    first, so the copy does not write through the link into the cached file.
  - The streaming download no longer writes through a stale symbolic link at the
    destination (the link is dropped before a fresh write).
  - Caching now also works when the server does not report a `Content-Length`
    (chunked responses): the downloaded file size is used to validate and size
    the cache entry.

- Tests:
  - Added `download_cache_store_test.dart` covering
    `LocalDirectoryDownloadCacheStore` (copy/link `store` and `fetchTo`,
    minimum length, unknown size, stale-link handling).
  - Added tests for `localDownloadCacheUseLink`
    (`huggingface_downloader_test.dart`):
    - Links file from local cache instead of copying.
    - Copies (not links) from cache by default.
    - Linking replaces an existing local file.
    - Fresh download moves the file to the cache and links it.
    - Copying from cache removes a stale link at the destination.
    - Uses an explicitly provided `cacheStore`.

## 1.0.2

- `HuggingFaceDownloader`:
  - Added support for local download cache with configurable cache directory and minimum file length.
  - `downloadSnapshot`:
    - Checks local cache before downloading; copies from cache if valid.
    - Stores downloaded files in cache if they meet size criteria.
  - Added private methods:
    - `_resolveLocalDownloadCacheFile`: resolves cache file path based on repo, revision, and filename.
    - `_copyFileFromDownloadCache`: copies file from cache if size matches.
    - `_storeInDownloadCache`: stores file in cache if size matches and above minimum.
  - Added `localDownloadCacheDirectory` and `localDownloadCacheMinFileLength` fields.
  - Added constant `defaultLocalDownloadCacheMinFileLength` (128 KB).

- Tests (`huggingface_downloader_test.dart`):
  - Added tests for local download cache functionality:
    - Copies file from local cache if available.
    - Does not use cache if cached file size differs.
    - Does not create cache for files smaller than minimum length.
    - Cache persists across downloader instance recreations.
    - Verified default cache minimum length is 128 KB.

## 1.0.1

- `HuggingFaceDownloader`:
  - Updated file download logic to normalize remote file paths using `path.posix.normalize`.
  - Added checks to reject absolute remote file paths (both POSIX and Windows style).
  - Ensured local file paths are within the target directory using `path.isWithin` to prevent directory traversal.
  - Constructed local file paths safely using `path.joinAll` and normalized them with `path.normalize`.

- Dependencies:
  - Added `path` package dependency (^1.9.1) for path manipulation utilities.

## 1.0.0

- Initial version.

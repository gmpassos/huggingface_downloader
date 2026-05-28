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

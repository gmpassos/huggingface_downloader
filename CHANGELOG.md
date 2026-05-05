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

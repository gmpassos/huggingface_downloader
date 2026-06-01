import 'dart:io';

import 'package:path/path.dart' as path;

/// Identifies a single cached download entry within a [DownloadCacheStore].
class DownloadCacheKey {
  /// The Hugging Face repository id (e.g. `org/model`).
  final String repoId;

  /// The repository revision/branch (e.g. `main`).
  final String revision;

  /// The remote file path within the repository (e.g. `config.json`).
  final String remoteFile;

  const DownloadCacheKey({
    required this.repoId,
    required this.revision,
    required this.remoteFile,
  });

  @override
  String toString() => 'DownloadCacheKey[$repoId@$revision:$remoteFile]';
}

/// A pluggable cache for downloaded files.
///
/// Implementations are responsible for placing files at the download
/// destination ([fetchTo]) and for persisting downloaded files into the cache
/// ([store]). When an implementation [supportsLinks], it may place the file at
/// the destination as a link to the cached version (and convert a freshly
/// downloaded file into such a link) instead of duplicating its bytes.
abstract class DownloadCacheStore {
  /// Whether this store places files at the destination as links to the cached
  /// version instead of independent copies.
  bool get supportsLinks;

  /// Tries to serve a cached entry for [key] into [destination].
  ///
  /// [totalBytes] is the expected file size, or a negative value when the size
  /// is unknown up-front. Returns `true` when [destination] was populated from
  /// the cache, `false` when there was no usable cache entry (in which case the
  /// caller is expected to download the file).
  Future<bool> fetchTo({
    required DownloadCacheKey key,
    required File destination,
    required int totalBytes,
  });

  /// Stores [downloadedFile] into the cache for [key].
  ///
  /// [totalBytes] is the expected file size, or a negative value when the size
  /// is unknown (the downloaded file size is then trusted). Returns `true` when
  /// the file was cached. When [supportsLinks] is enabled, [downloadedFile] may
  /// be moved into the cache and replaced with a link to the cached version.
  Future<bool> store({
    required DownloadCacheKey key,
    required File downloadedFile,
    required int totalBytes,
  });
}

/// A [DownloadCacheStore] backed by a local filesystem directory.
///
/// Cached files are stored as flat `*.cached` files named after the
/// [DownloadCacheKey]. When [useLinks] is enabled, the store places files at the
/// download destination as symbolic links to the cached version, avoiding
/// duplicating large files on disk.
class LocalDirectoryDownloadCacheStore implements DownloadCacheStore {
  /// Default minimum file length (128 KB) to be eligible for caching.
  static const int defaultMinFileLength = 1024 * 128;

  /// The directory holding the cached files.
  final Directory directory;

  /// Minimum file length (in bytes) to be eligible for caching.
  final int minFileLength;

  /// Whether to place files at the destination as symbolic links to the cached
  /// version instead of independent copies.
  final bool useLinks;

  LocalDirectoryDownloadCacheStore({
    required this.directory,
    this.minFileLength = defaultMinFileLength,
    this.useLinks = false,
  });

  @override
  bool get supportsLinks => useLinks;

  /// Resolves the cache file for [key], or `null` when the (known) [totalBytes]
  /// is below [minFileLength].
  File? _resolveCacheFile(DownloadCacheKey key, int totalBytes) {
    // Skip only when the size is known up-front and below the minimum. When the
    // size is unknown (`totalBytes < 0`) the decision is deferred to [store],
    // which uses the downloaded size.
    if (totalBytes >= 0 && totalBytes < minFileLength) return null;

    var cacheFileName = '${key.repoId}--${key.revision}--${key.remoteFile}'
        .replaceAll(RegExp(r'[^\w-]'), '_');

    cacheFileName += '.cached';

    return File(path.join(directory.path, cacheFileName));
  }

  @override
  Future<bool> fetchTo({
    required DownloadCacheKey key,
    required File destination,
    required int totalBytes,
  }) async {
    final cacheFile = _resolveCacheFile(key, totalBytes);
    if (cacheFile == null) return false;

    final cacheFileLng = (await cacheFile.exists())
        ? await cacheFile.length()
        : 0;

    // Only serve from cache when the cached size matches the expected size.
    if (cacheFileLng != totalBytes) return false;

    final existingType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );

    if (useLinks) {
      // Remove any existing file/link at the target path before linking.
      if (existingType == FileSystemEntityType.link) {
        await Link(destination.path).delete();
      } else if (existingType != FileSystemEntityType.notFound) {
        await destination.delete();
      }

      await Link(destination.path).create(cacheFile.absolute.path);
    } else {
      // Remove any existing link at the target path so the copy does not write
      // through the link into the cached file.
      if (existingType == FileSystemEntityType.link) {
        await Link(destination.path).delete();
      }

      await cacheFile.copy(destination.path);
    }

    return true;
  }

  @override
  Future<bool> store({
    required DownloadCacheKey key,
    required File downloadedFile,
    required int totalBytes,
  }) async {
    final downloadedLng = await downloadedFile.length();

    // When the size is known, ensure the download completed. Otherwise
    // (`totalBytes < 0`) trust the downloaded file size.
    if (totalBytes >= 0 && downloadedLng != totalBytes) return false;

    if (downloadedLng < minFileLength) return false;

    final cacheFile = _resolveCacheFile(key, totalBytes);
    if (cacheFile == null) return false;

    final cacheFileLng = (await cacheFile.exists())
        ? await cacheFile.length()
        : 0;

    final cacheHasFile = downloadedLng == cacheFileLng;

    if (cacheHasFile && !useLinks) return false;

    await cacheFile.parent.create(recursive: true);

    if (useLinks) {
      if (cacheHasFile) {
        // Cache already holds the file; just replace the local copy with a link.
        await downloadedFile.delete();
      } else {
        // Move the downloaded file into the cache.
        await _moveFile(downloadedFile, cacheFile.path);
      }

      // Link the local path to the cached version.
      await Link(downloadedFile.path).create(cacheFile.absolute.path);
    } else {
      await downloadedFile.copy(cacheFile.path);
    }

    return true;
  }

  Future<void> _moveFile(File source, String destinationPath) async {
    try {
      await source.rename(destinationPath);
    } on FileSystemException {
      // `rename` fails across file systems; fall back to copy + delete.
      await source.copy(destinationPath);
      await source.delete();
    }
  }
}

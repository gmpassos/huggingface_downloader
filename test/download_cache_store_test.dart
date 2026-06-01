import 'dart:io';

import 'package:huggingface_downloader/huggingface_downloader.dart';
import 'package:test/test.dart';

void main() {
  group('LocalDirectoryDownloadCacheStore', () {
    late Directory cacheDir;
    late Directory workDir;

    const key = DownloadCacheKey(
      repoId: 'org/model',
      revision: 'main',
      remoteFile: 'config.json',
    );

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('tmp_cache_store_');
      workDir = await Directory.systemTemp.createTemp('tmp_cache_work_');
    });

    tearDown(() async {
      for (final d in [cacheDir, workDir]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });

    List<int> bytesOf(int n) => List<int>.generate(n, (i) => i % 256);

    Future<List<File>> cacheFiles() =>
        cacheDir.list().where((e) => e is File).cast<File>().toList();

    test('supportsLinks reflects useLinks', () {
      expect(
        LocalDirectoryDownloadCacheStore(directory: cacheDir).supportsLinks,
        isFalse,
      );
      expect(
        LocalDirectoryDownloadCacheStore(
          directory: cacheDir,
          useLinks: true,
        ).supportsLinks,
        isTrue,
      );
    });

    test('default minimum file length is 128 KB', () {
      expect(
        LocalDirectoryDownloadCacheStore.defaultMinFileLength,
        equals(1024 * 128),
      );
    });

    test('store copies the file into the cache (copy mode)', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final data = bytesOf(2048);
      final local = File('${workDir.path}/config.json');
      await local.writeAsBytes(data, flush: true);

      final stored = await store.store(
        key: key,
        downloadedFile: local,
        totalBytes: data.length,
      );

      expect(stored, isTrue);
      // In copy mode the local file stays an independent regular file.
      expect(await FileSystemEntity.isLink(local.path), isFalse);
      expect(await local.readAsBytes(), equals(data));

      final files = await cacheFiles();
      expect(files, hasLength(1));
      expect(await files.first.readAsBytes(), equals(data));
    });

    test('store rejects files smaller than the minimum length', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 4096,
      );

      final data = bytesOf(100);
      final local = File('${workDir.path}/config.json');
      await local.writeAsBytes(data, flush: true);

      final stored = await store.store(
        key: key,
        downloadedFile: local,
        totalBytes: data.length,
      );

      expect(stored, isFalse);
      expect(await cacheFiles(), isEmpty);
    });

    test('store rejects incomplete downloads when size is known', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final data = bytesOf(2048);
      final local = File('${workDir.path}/config.json');
      await local.writeAsBytes(data, flush: true);

      final stored = await store.store(
        key: key,
        downloadedFile: local,
        totalBytes: data.length + 10, // expected larger than actual
      );

      expect(stored, isFalse);
      expect(await cacheFiles(), isEmpty);
    });

    test('store trusts the downloaded length when size is unknown', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final data = bytesOf(2048);
      final local = File('${workDir.path}/config.json');
      await local.writeAsBytes(data, flush: true);

      final stored = await store.store(
        key: key,
        downloadedFile: local,
        totalBytes: -1,
      );

      expect(stored, isTrue);
      final files = await cacheFiles();
      expect(files, hasLength(1));
      expect(await files.first.length(), equals(data.length));
    });

    test('fetchTo copies from cache to the destination (copy mode)', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final data = bytesOf(2048);
      final seed = File('${workDir.path}/seed.json');
      await seed.writeAsBytes(data, flush: true);
      await store.store(
        key: key,
        downloadedFile: seed,
        totalBytes: data.length,
      );

      final dest = File('${workDir.path}/config.json');
      final served = await store.fetchTo(
        key: key,
        destination: dest,
        totalBytes: data.length,
      );

      expect(served, isTrue);
      expect(await FileSystemEntity.isLink(dest.path), isFalse);
      expect(await dest.readAsBytes(), equals(data));
    });

    test('fetchTo returns false on missing entry or size mismatch', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final dest = File('${workDir.path}/config.json');

      // Missing entry.
      expect(
        await store.fetchTo(key: key, destination: dest, totalBytes: 2048),
        isFalse,
      );

      final data = bytesOf(2048);
      final seed = File('${workDir.path}/seed.json');
      await seed.writeAsBytes(data, flush: true);
      await store.store(
        key: key,
        downloadedFile: seed,
        totalBytes: data.length,
      );

      // Size mismatch.
      expect(
        await store.fetchTo(key: key, destination: dest, totalBytes: 4096),
        isFalse,
      );
      // Unknown size cannot be validated against the cache.
      expect(
        await store.fetchTo(key: key, destination: dest, totalBytes: -1),
        isFalse,
      );
      expect(await dest.exists(), isFalse);
    });

    test('fetchTo replaces a stale link at the destination (copy mode)', () async {
      final store = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      );

      final data = bytesOf(2048);
      final seed = File('${workDir.path}/seed.json');
      await seed.writeAsBytes(data, flush: true);
      await store.store(
        key: key,
        downloadedFile: seed,
        totalBytes: data.length,
      );

      // Destination is a dangling link left over from a previous link-mode run.
      final dest = File('${workDir.path}/config.json');
      final dangling = '${workDir.path}/missing.bin';
      await Link(dest.path).create(dangling);

      final served = await store.fetchTo(
        key: key,
        destination: dest,
        totalBytes: data.length,
      );

      expect(served, isTrue);
      expect(await FileSystemEntity.isLink(dest.path), isFalse);
      expect(await dest.readAsBytes(), equals(data));
      // The copy must not be written through the link to its (missing) target.
      expect(await File(dangling).exists(), isFalse);
    });

    test(
      'store (link mode) moves the file to the cache and links it',
      () async {
        final store = LocalDirectoryDownloadCacheStore(
          directory: cacheDir,
          minFileLength: 0,
          useLinks: true,
        );

        final data = bytesOf(2048);
        final local = File('${workDir.path}/config.json');
        await local.writeAsBytes(data, flush: true);

        final stored = await store.store(
          key: key,
          downloadedFile: local,
          totalBytes: data.length,
        );

        expect(stored, isTrue);
        expect(await FileSystemEntity.isLink(local.path), isTrue);

        final target = await Link(local.path).target();
        expect(await File(target).exists(), isTrue);
        expect(await File(local.path).readAsBytes(), equals(data));

        final files = await cacheFiles();
        expect(files, hasLength(1));
        expect(await files.first.readAsBytes(), equals(data));
      },
    );

    test('store (link mode) links to an existing cache entry', () async {
      final data = bytesOf(2048);

      // Pre-populate the cache via copy mode.
      final seed = File('${workDir.path}/seed.json');
      await seed.writeAsBytes(data, flush: true);
      await LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
      ).store(key: key, downloadedFile: seed, totalBytes: data.length);

      final linkStore = LocalDirectoryDownloadCacheStore(
        directory: cacheDir,
        minFileLength: 0,
        useLinks: true,
      );

      final local = File('${workDir.path}/config.json');
      await local.writeAsBytes(data, flush: true);

      final stored = await linkStore.store(
        key: key,
        downloadedFile: local,
        totalBytes: data.length,
      );

      expect(stored, isTrue);
      expect(await FileSystemEntity.isLink(local.path), isTrue);
      expect(await File(local.path).readAsBytes(), equals(data));
      // The cache still holds a single entry.
      expect(await cacheFiles(), hasLength(1));
    });

    test(
      'fetchTo (link mode) links destination over an existing file',
      () async {
        final data = bytesOf(2048);

        final seed = File('${workDir.path}/seed.json');
        await seed.writeAsBytes(data, flush: true);
        await LocalDirectoryDownloadCacheStore(
          directory: cacheDir,
          minFileLength: 0,
        ).store(key: key, downloadedFile: seed, totalBytes: data.length);

        final linkStore = LocalDirectoryDownloadCacheStore(
          directory: cacheDir,
          minFileLength: 0,
          useLinks: true,
        );

        // A stale regular file already exists at the destination.
        final dest = File('${workDir.path}/config.json');
        await dest.writeAsBytes(bytesOf(16), flush: true);

        final served = await linkStore.fetchTo(
          key: key,
          destination: dest,
          totalBytes: data.length,
        );

        expect(served, isTrue);
        expect(await FileSystemEntity.isLink(dest.path), isTrue);
        expect(await File(dest.path).readAsBytes(), equals(data));
      },
    );
  });
}

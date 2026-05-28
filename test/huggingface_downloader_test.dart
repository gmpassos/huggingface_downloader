import 'dart:io';

import 'package:huggingface_downloader/huggingface_downloader.dart';
import 'package:test/test.dart';

void main() {
  group('HuggingFaceDownloader integration', () {
    const repoId = 'fxmarty/really-tiny-falcon-testing';

    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'tmp_hf_downloader_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads tiny public repository', () async {
      final downloader = HuggingFaceDownloader();

      await downloader.downloadSnapshot(repoId: repoId, localDir: tempDir);

      downloader.close();

      final files = await _listAllFiles(tempDir);

      expect(files, isNotEmpty);
      expect(files.any((e) => e.endsWith('config.json')), isTrue);
    });

    test('downloads only allowed extensions', () async {
      final downloader = HuggingFaceDownloader();

      await downloader.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        allowExtensions: ['.json'],
      );

      downloader.close();

      final files = await _listAllFiles(tempDir);

      expect(files, isNotEmpty);

      for (final file in files) {
        expect(file.endsWith('.json'), isTrue);
      }
    });

    test('excludes unwanted extensions', () async {
      final downloader = HuggingFaceDownloader();

      await downloader.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        excludeExtensions: ['.onnx'],
      );

      downloader.close();

      final files = await _listAllFiles(tempDir);

      for (final file in files) {
        expect(file.endsWith('.onnx'), isFalse);
      }
    });

    test('reports progress callback', () async {
      final downloader = HuggingFaceDownloader();

      int progressCalls = 0;

      await downloader.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        progress: (file, received, total) {
          progressCalls++;
        },
      );

      downloader.close();

      expect(progressCalls, greaterThan(0));
    });

    test('resumes partial download', () async {
      final downloader1 = HuggingFaceDownloader();

      await downloader1.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        allowExtensions: ['.json'],
      );

      downloader1.close();

      final config = File('${tempDir.path}/config.json');

      expect(await config.exists(), isTrue);

      final bytes = await config.readAsBytes();

      final partial = bytes.sublist(0, bytes.length ~/ 2);

      print('** partial: ${partial.length} / ${bytes.length}');

      await config.writeAsBytes(partial, flush: true);

      expect(await config.length(), equals(partial.length));

      final partialSize = await config.length();

      expect(partialSize, lessThan(bytes.length));

      final downloader2 = HuggingFaceDownloader();

      await downloader2.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        allowExtensions: ['.json'],
      );

      downloader2.close();

      final finalSize = await config.length();

      expect(finalSize, equals(bytes.length));
    });

    test('overwriteExisting forces full redownload', () async {
      final downloader1 = HuggingFaceDownloader();

      await downloader1.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        allowExtensions: ['.json'],
      );

      downloader1.close();

      final config = File('${tempDir.path}/config.json');

      expect(await config.exists(), isTrue);

      final originalBytes = await config.readAsBytes();
      final originalSize = originalBytes.length;

      // corrupt file intentionally
      await config.writeAsString('CORRUPTED_FILE', flush: true);

      final corruptedSize = await config.length();

      expect(corruptedSize, isNot(originalSize));
      expect(corruptedSize, lessThan(originalSize));

      final downloader2 = HuggingFaceDownloader();

      await downloader2.downloadSnapshot(
        repoId: repoId,
        localDir: tempDir,
        allowExtensions: ['.json'],
        overwriteExisting: true,
      );

      downloader2.close();

      final finalBytes = await config.readAsBytes();
      final finalSize = finalBytes.length;

      expect(finalSize, equals(originalSize));
      expect(finalBytes, equals(originalBytes));
    });

    test('copies file from local download cache', () async {
      final cacheDir = await Directory.systemTemp.createTemp(
        'tmp_hf_cache_test_',
      );

      try {
        final downloader1 = HuggingFaceDownloader(
          localDownloadCacheDirectory: cacheDir,
          localDownloadCacheMinFileLength: 0,
        );

        await downloader1.downloadSnapshot(
          repoId: repoId,
          localDir: tempDir,
          allowExtensions: ['.json'],
        );

        downloader1.close();

        final config1 = File('${tempDir.path}/config.json');

        expect(await config1.exists(), isTrue);

        final originalBytes = await config1.readAsBytes();

        // remove downloaded file
        await config1.delete();

        expect(await config1.exists(), isFalse);

        final downloader2 = HuggingFaceDownloader(
          localDownloadCacheDirectory: cacheDir,
          localDownloadCacheMinFileLength: 0,
        );

        await downloader2.downloadSnapshot(
          repoId: repoId,
          localDir: tempDir,
          allowExtensions: ['.json'],
        );

        downloader2.close();

        final config2 = File('${tempDir.path}/config.json');

        expect(await config2.exists(), isTrue);

        final cachedBytes = await config2.readAsBytes();

        expect(cachedBytes, equals(originalBytes));

        final cacheFiles = await cacheDir.list().toList();

        expect(cacheFiles.whereType<File>(), isNotEmpty);
      } finally {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      }
    });

    test('does not use cache when cached file size differs', () async {
      final cacheDir = await Directory.systemTemp.createTemp(
        'tmp_hf_cache_corrupted_',
      );

      try {
        final downloader1 = HuggingFaceDownloader(
          localDownloadCacheDirectory: cacheDir,
          localDownloadCacheMinFileLength: 0,
        );

        await downloader1.downloadSnapshot(
          repoId: repoId,
          localDir: tempDir,
          allowExtensions: ['.json'],
        );

        downloader1.close();

        final cacheFiles = await cacheDir
            .list()
            .where((e) => e is File)
            .cast<File>()
            .toList();

        expect(cacheFiles, isNotEmpty);

        final cacheFile = cacheFiles.first;

        // corrupt cache file
        await cacheFile.writeAsString('BROKEN_CACHE', flush: true);

        final config = File('${tempDir.path}/config.json');

        await config.delete();

        final downloader2 = HuggingFaceDownloader(
          localDownloadCacheDirectory: cacheDir,
          localDownloadCacheMinFileLength: 0,
        );

        await downloader2.downloadSnapshot(
          repoId: repoId,
          localDir: tempDir,
          allowExtensions: ['.json'],
        );

        downloader2.close();

        expect(await config.exists(), isTrue);
        expect(await config.length(), greaterThan('BROKEN_CACHE'.length));
      } finally {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      }
    });

    test(
      'does not create cache for files smaller than minimum length',
      () async {
        final cacheDir = await Directory.systemTemp.createTemp(
          'tmp_hf_cache_min_size_',
        );

        try {
          final downloader = HuggingFaceDownloader(
            localDownloadCacheDirectory: cacheDir,
            localDownloadCacheMinFileLength: 1024 * 1024 * 1024,
          );

          await downloader.downloadSnapshot(
            repoId: repoId,
            localDir: tempDir,
            allowExtensions: ['.json'],
          );

          downloader.close();

          final cacheFiles = await cacheDir.list().toList();

          expect(cacheFiles, isEmpty);
        } finally {
          if (await cacheDir.exists()) {
            await cacheDir.delete(recursive: true);
          }
        }
      },
    );

    test('cache survives downloader instance recreation', () async {
      final cacheDir = await Directory.systemTemp.createTemp(
        'tmp_hf_cache_persist_',
      );

      late List<int> originalBytes;

      try {
        {
          final dir1 = await Directory.systemTemp.createTemp('tmp_hf_dl1_');

          final downloader = HuggingFaceDownloader(
            localDownloadCacheDirectory: cacheDir,
            localDownloadCacheMinFileLength: 0,
          );

          await downloader.downloadSnapshot(
            repoId: repoId,
            localDir: dir1,
            allowExtensions: ['.json'],
          );

          downloader.close();

          originalBytes = await File('${dir1.path}/config.json').readAsBytes();

          await dir1.delete(recursive: true);
        }

        {
          final dir2 = await Directory.systemTemp.createTemp('tmp_hf_dl2_');

          final downloader = HuggingFaceDownloader(
            localDownloadCacheDirectory: cacheDir,
            localDownloadCacheMinFileLength: 0,
          );

          await downloader.downloadSnapshot(
            repoId: repoId,
            localDir: dir2,
            allowExtensions: ['.json'],
          );

          downloader.close();

          final bytes = await File('${dir2.path}/config.json').readAsBytes();

          expect(bytes, equals(originalBytes));

          await dir2.delete(recursive: true);
        }
      } finally {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      }
    });

    test('default cache minimum length is 1MB', () {
      expect(
        HuggingFaceDownloader.defaultLocalDownloadCacheMinFileLength,
        equals(1024 * 128),
      );
    });
  });
}

Future<List<String>> _listAllFiles(Directory dir) async {
  final out = <String>[];

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) {
      out.add(entity.path.replaceAll('\\', '/').split('/').last);
    }
  }

  return out;
}

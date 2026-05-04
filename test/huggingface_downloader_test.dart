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

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

typedef ProgressCallback =
    void Function(String fileName, int receivedBytes, int totalBytes);

class HuggingFaceDownloader {
  final HttpClient _http = HttpClient();
  String? _token;

  HuggingFaceDownloader({String? token}) {
    _token = token;
  }

  Future<List<File>> downloadSnapshot({
    required String repoId,
    required Directory localDir,
    String revision = 'main',
    ProgressCallback? progress,
    bool includeReadme = false,
    bool overwriteExisting = false,
    List<String>? allowExtensions,
    List<String>? excludeExtensions,
  }) async {
    await localDir.create(recursive: true);

    final manifest = await _fetchManifest(repoId);
    final siblings = manifest['siblings'] as List<dynamic>? ?? [];

    final files = siblings
        .map((e) => e['rfilename'] as String)
        .where(
          (f) => _shouldDownload(
            f,
            includeReadme: includeReadme,
            allowExtensions: allowExtensions,
            excludeExtensions: excludeExtensions,
          ),
        )
        .toList();

    print('Files selected for download: ${files.length}');
    for (final f in files) {
      print('  $f');
    }
    print('');

    final downloadedFiles = <File>[];

    for (final filePath in files) {
      var filePathNormalized = path.posix.normalize(filePath);

      // Reject absolute paths from remote manifest
      if (path.posix.isAbsolute(filePathNormalized) ||
          path.windows.isAbsolute(filePathNormalized)) {
        print(
          '** Ignoring absolute remote file path: $filePath -> $filePathNormalized',
        );
        continue;
      }

      var filePathNormalizedParts = path.posix.split(filePathNormalized);

      var localFilePath = path.normalize(
        path.joinAll([localDir.path, ...filePathNormalizedParts]),
      );

      // Invalid file path, ignore it:
      if (!path.isWithin(localDir.path, localFilePath)) {
        print(
          '** Ignoring invalid local file path: $filePath -> $localFilePath',
        );
        continue;
      }

      final localFile = File(localFilePath);

      await _downloadFile(
        repoId: repoId,
        revision: revision,
        remoteFile: filePath,
        localFile: localFile,
        overwriteExisting: overwriteExisting,
        progress: progress,
      );

      downloadedFiles.add(localFile);
      stdout.writeln();
    }

    return downloadedFiles;
  }

  Future<Map<String, dynamic>> _fetchManifest(String repoId) async {
    final uri = Uri.parse('https://huggingface.co/api/models/$repoId');

    final req = await _http.getUrl(uri);

    if (_token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }

    final res = await req.close();

    if (res.statusCode != 200) {
      throw HttpException('Failed to fetch model manifest: ${res.statusCode}');
    }

    final txt = await utf8.decodeStream(res);
    return jsonDecode(txt);
  }

  bool _shouldDownload(
    String file, {
    required bool includeReadme,
    List<String>? allowExtensions,
    List<String>? excludeExtensions,
  }) {
    final lower = file.toLowerCase();

    if (!includeReadme && lower == 'readme.md') {
      return false;
    }

    if (excludeExtensions != null) {
      for (final ext in excludeExtensions) {
        if (lower.endsWith(ext.toLowerCase())) {
          return false;
        }
      }
    }

    if (allowExtensions != null && allowExtensions.isNotEmpty) {
      for (final ext in allowExtensions) {
        if (lower.endsWith(ext.toLowerCase())) {
          return true;
        }
      }
      return false;
    }

    return true;
  }

  Future<void> _downloadFile({
    required String repoId,
    required String revision,
    required String remoteFile,
    required File localFile,
    required bool overwriteExisting,
    ProgressCallback? progress,
  }) async {
    await localFile.parent.create(recursive: true);

    int existingBytes = 0;

    if (await localFile.exists()) {
      if (overwriteExisting) {
        await localFile.delete();
      } else {
        existingBytes = await localFile.length();
      }
    }

    final encodedPath = remoteFile
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');

    final uri = Uri.parse(
      'https://huggingface.co/$repoId/resolve/$revision/$encodedPath',
    );

    final req = await _http.getUrl(uri);

    if (_token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }

    if (existingBytes > 0) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }

    final res = await req.close();

    // local file is already complete
    if (res.statusCode == 416) {
      progress?.call(remoteFile, existingBytes, existingBytes);
      return;
    }

    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('Failed to download $remoteFile : ${res.statusCode}');
    }

    final totalBytes = res.contentLength > 0
        ? res.contentLength + (res.statusCode == 206 ? existingBytes : 0)
        : -1;

    final sink = localFile.openWrite(
      mode: res.statusCode == 206 ? FileMode.append : FileMode.write,
    );

    int received = res.statusCode == 206 ? existingBytes : 0;

    await for (final chunk in res) {
      sink.add(chunk);
      received += chunk.length;
      progress?.call(remoteFile, received, totalBytes);
    }

    await sink.flush();
    await sink.close();
  }

  void close() {
    _http.close(force: true);
  }
}

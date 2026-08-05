import 'dart:convert';
import 'dart:io';

import 'package:huggingface_downloader/huggingface_downloader.dart';
import 'package:test/test.dart';

/// A stand-in Hub that answers the first [failures] requests to each path with
/// [failureStatus], then serves normally. Lets the rate-limit handling be
/// tested without depending on being rate-limited.
class _StubHub {
  final int failures;
  final int failureStatus;

  /// Value for the `Retry-After` header on a failure response, or null to omit
  /// it (leaving the client to its own backoff).
  final String? retryAfter;

  late final HttpServer _server;

  /// Requests received per path, failures included.
  final Map<String, int> hits = {};

  _StubHub({this.failures = 0, this.failureStatus = 429, this.retryAfter});

  String get endpoint => 'http://127.0.0.1:${_server.port}';

  static const fileBody = 'hello from the stub hub';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  void _handle(HttpRequest req) {
    final path = req.uri.path;
    final seen = hits[path] = (hits[path] ?? 0) + 1;

    if (seen <= failures) {
      req.response.statusCode = failureStatus;
      if (retryAfter != null) {
        req.response.headers.set(HttpHeaders.retryAfterHeader, retryAfter!);
      }
      req.response.write('rate limited');
      req.response.close();
      return;
    }

    if (path.startsWith('/api/models/')) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'siblings': [
            {'rfilename': 'config.json'},
            {'rfilename': 'README.md'},
          ],
        }),
      );
      req.response.close();
      return;
    }

    // A resolve URL: serve the body, honouring a Range request so the resume
    // path is exercised against something that behaves like the real thing.
    final bytes = utf8.encode(fileBody);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    var from = 0;

    if (range != null && range.startsWith('bytes=')) {
      from = int.tryParse(range.substring(6).split('-').first) ?? 0;
      if (from >= bytes.length) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.partialContent;
    }

    req.response.add(bytes.sublist(from));
    req.response.close();
  }
}

void main() {
  group('rate-limit handling', () {
    late _StubHub hub;

    tearDown(() => hub.stop());

    /// Retries are configured tiny so the tests measure behaviour, not patience.
    HuggingFaceDownloader downloaderFor(
      _StubHub hub, {
      int maxRetries = 5,
      Duration? initial,
    }) => HuggingFaceDownloader(
      endpoint: hub.endpoint,
      maxRetries: maxRetries,
      retryInitialDelay: initial ?? const Duration(milliseconds: 10),
      maxRetryDelay: const Duration(milliseconds: 50),
    );

    test('a manifest request retries past 429 and then succeeds', () async {
      hub = _StubHub(failures: 3);
      await hub.start();

      final downloader = downloaderFor(hub);
      addTearDown(downloader.close);

      final files = await downloader.listFiles('owner/repo');

      expect(files, ['README.md', 'config.json']);
      // Three refusals plus the one that worked.
      expect(hub.hits['/api/models/owner/repo'], 4);
    });

    test('a file download retries past 429 and then succeeds', () async {
      hub = _StubHub(failures: 2);
      await hub.start();

      final downloader = downloaderFor(hub);
      addTearDown(downloader.close);

      final dir = await Directory.systemTemp.createTemp('tmp_hf_retry_');
      addTearDown(() => dir.delete(recursive: true));

      final file = await downloader.downloadFile(
        repoId: 'owner/repo',
        remoteFile: 'config.json',
        localDir: dir,
      );

      expect(await file.readAsString(), _StubHub.fileBody);
      expect(hub.hits['/owner/repo/resolve/main/config.json'], 3);
    });

    test('503 is retried too', () async {
      hub = _StubHub(failures: 2, failureStatus: HttpStatus.serviceUnavailable);
      await hub.start();

      final downloader = downloaderFor(hub);
      addTearDown(downloader.close);

      expect(await downloader.listFiles('owner/repo'), isNotEmpty);
      expect(hub.hits['/api/models/owner/repo'], 3);
    });

    test('giving up after maxRetries reports the status', () async {
      hub = _StubHub(failures: 99);
      await hub.start();

      final downloader = downloaderFor(hub, maxRetries: 2);
      addTearDown(downloader.close);

      await expectLater(
        downloader.listFiles('owner/repo'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('429'),
          ),
        ),
      );

      // The first attempt plus exactly two retries — not an unbounded loop.
      expect(hub.hits['/api/models/owner/repo'], 3);
    });

    test('maxRetries: 0 fails on the first refusal', () async {
      hub = _StubHub(failures: 1);
      await hub.start();

      final downloader = downloaderFor(hub, maxRetries: 0);
      addTearDown(downloader.close);

      await expectLater(
        downloader.listFiles('owner/repo'),
        throwsA(isA<HttpException>()),
      );
      expect(hub.hits['/api/models/owner/repo'], 1);
    });

    test('a non-retriable status is terminal, not repeated', () async {
      hub = _StubHub(failures: 0);
      await hub.start();

      final downloader = downloaderFor(hub);
      addTearDown(downloader.close);

      final dir = await Directory.systemTemp.createTemp('tmp_hf_terminal_');
      addTearDown(() => dir.delete(recursive: true));

      // A local file longer than the body makes the resume range start past
      // the end, so the stub answers 416 — a status the client must treat as
      // final ("already complete") rather than retry.
      await File(
        '${dir.path}/config.json',
      ).writeAsString('x' * (_StubHub.fileBody.length + 10));

      await downloader.downloadFile(
        repoId: 'owner/repo',
        remoteFile: 'config.json',
        localDir: dir,
      );

      expect(hub.hits['/owner/repo/resolve/main/config.json'], 1);
    });

    test('Retry-After is honoured over the backoff', () async {
      hub = _StubHub(failures: 1, retryAfter: '1');
      await hub.start();

      // A backoff far longer than the server's ask; if `Retry-After` were
      // ignored the elapsed time would be 10s, not ~1s.
      final downloader = HuggingFaceDownloader(
        endpoint: hub.endpoint,
        maxRetries: 3,
        retryInitialDelay: const Duration(seconds: 10),
        maxRetryDelay: const Duration(seconds: 30),
      );
      addTearDown(downloader.close);

      final sw = Stopwatch()..start();
      await downloader.listFiles('owner/repo');
      sw.stop();

      expect(sw.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a Retry-After longer than maxRetryDelay is capped', () async {
      hub = _StubHub(failures: 1, retryAfter: '3600');
      await hub.start();

      final downloader = HuggingFaceDownloader(
        endpoint: hub.endpoint,
        maxRetries: 3,
        retryInitialDelay: const Duration(milliseconds: 10),
        maxRetryDelay: const Duration(milliseconds: 200),
      );
      addTearDown(downloader.close);

      final sw = Stopwatch()..start();
      await downloader.listFiles('owner/repo');
      sw.stop();

      // An hour, capped to 200ms: the server cannot stall the client forever.
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a garbage Retry-After falls back to the backoff', () async {
      hub = _StubHub(failures: 1, retryAfter: 'Wed, 21 Oct 2015 07:28:00 GMT');
      await hub.start();

      final downloader = downloaderFor(hub);
      addTearDown(downloader.close);

      // The HTTP-date form is not parsed; the backoff still gets it through.
      expect(await downloader.listFiles('owner/repo'), isNotEmpty);
      expect(hub.hits['/api/models/owner/repo'], 2);
    });
  });

  group('endpoint', () {
    test('defaults to huggingface.co', () {
      final downloader = HuggingFaceDownloader();
      addTearDown(downloader.close);
      expect(downloader.endpoint, HuggingFaceDownloader.defaultEndpoint);
    });

    test('an explicit endpoint wins, without its trailing slash', () {
      final downloader = HuggingFaceDownloader(
        endpoint: 'https://hf-mirror.example/',
      );
      addTearDown(downloader.close);
      expect(downloader.endpoint, 'https://hf-mirror.example');
    });
  });
}

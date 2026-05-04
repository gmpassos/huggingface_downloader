import 'dart:io';

import 'package:huggingface_downloader/huggingface_downloader.dart';

Future<void> main() async {
  final downloader = HuggingFaceDownloader();

  final repoId = 'HuggingFaceTB/SmolLM-135M-Instruct';
  final outputDir = Directory('./models/test-model');

  print('Downloading: $repoId');
  print('Saving to : ${outputDir.path}');
  print('');

  try {
    await downloader.downloadSnapshot(
      repoId: repoId,
      localDir: outputDir,

      // Recommended for tests: avoid huge junk files
      allowExtensions: ['.json', '.txt', '.model', '.safetensors', '.bin'],
      excludeExtensions: [
        '.onnx',
        '.gguf',
        '.h5',
        '.msgpack',
        '.tflite',
        '.pt',
        '.pth',
        '.ot',
        '.ckpt',
      ],

      progress: (file, received, total) {
        stdout.write('\r${_progress(file, received, total)}');
      },
    );

    print('\n\nDownload completed.');
  } catch (e) {
    print('\n\nError: $e');
  } finally {
    downloader.close();
  }
}

String _progress(String file, int received, int total) {
  if (total <= 0) {
    return '$file -> ${_fmt(received)}';
  }

  final pct = (received / total * 100).toStringAsFixed(1);

  return '$file -> $pct% (${_fmt(received)} / ${_fmt(total)})';
}

String _fmt(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];

  double size = bytes.toDouble();
  int i = 0;

  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }

  return '${size.toStringAsFixed(2)} ${units[i]}';
}

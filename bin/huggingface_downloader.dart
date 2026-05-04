import 'dart:io';

import 'package:huggingface_downloader/huggingface_downloader.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    _showUsage();
    exit(1);
  }

  final repoId = args[0];
  final outputDir = args[1];

  String? token;
  List<String>? allowExtensions;
  List<String>? excludeExtensions;
  bool llmOnly = false;
  bool overwriteExisting = false;

  for (int i = 2; i < args.length; i++) {
    final arg = args[i];

    if (arg.startsWith('--token=')) {
      token = arg.substring('--token='.length);
    } else if (arg.startsWith('--ext=')) {
      allowExtensions = arg
          .substring('--ext='.length)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (arg.startsWith('--exclude=')) {
      excludeExtensions = arg
          .substring('--exclude='.length)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (arg == '--llm-only') {
      llmOnly = true;
    } else if (arg == '--overwrite') {
      overwriteExisting = true;
    }
  }

  if (llmOnly) {
    allowExtensions = ['.json', '.txt', '.model', '.safetensors', '.bin'];

    excludeExtensions = [
      '.onnx',
      '.gguf',
      '.h5',
      '.msgpack',
      '.tflite',
      '.pt',
      '.pth',
      '.ot',
      '.ckpt',
    ];
  }

  print('');
  print('HuggingFace Downloader');
  print('----------------------');
  print('Repository : $repoId');
  print('Output Dir : $outputDir');

  if (llmOnly) print('Mode       : LLM ONLY');
  if (overwriteExisting) print('Overwrite  : YES');

  if (allowExtensions != null) {
    print('Allow Ext  : ${allowExtensions.join(", ")}');
  }

  if (excludeExtensions != null) {
    print('Exclude Ext: ${excludeExtensions.join(", ")}');
  }

  print('');

  final downloader = HuggingFaceDownloader(token: token);

  try {
    final files = await downloader.downloadSnapshot(
      repoId: repoId,
      localDir: Directory(outputDir),
      allowExtensions: allowExtensions,
      excludeExtensions: excludeExtensions,
      overwriteExisting: overwriteExisting,
      progress: (file, received, total) {
        stdout.write('\r${_progressLine(file, received, total)}');
      },
    );

    print('\nDownload completed successfully.\n');

    print('Downloaded files (${files.length}):');
    print('----------------------');

    for (final file in files) {
      print(file.path);
    }
  } catch (e) {
    print('\nERROR: $e');
    exit(2);
  } finally {
    downloader.close();
  }
}

String _progressLine(String file, int received, int total) {
  if (total <= 0) {
    return '$file -> ${_formatBytes(received)}';
  }

  final pct = (received / total * 100).toStringAsFixed(1);

  return '$file -> $pct% (${_formatBytes(received)} / ${_formatBytes(total)})';
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];

  double size = bytes.toDouble();
  int unit = 0;

  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }

  return '${size.toStringAsFixed(2)} ${units[unit]}';
}

void _showUsage() {
  print('''
Usage:
  dart run bin/huggingface_downloader.dart <repoId> <outputDir> [options]

Options:
  --token=hf_xxx
  --ext=.json,.safetensors
  --exclude=.onnx,.gguf,.pt
  --llm-only
  --overwrite

Examples:

  dart run bin/huggingface_downloader.dart HuggingFaceTB/SmolLM2-135M-Instruct ./models/smollm2 --llm-only

  dart run bin/huggingface_downloader.dart Qwen/Qwen2-0.5B ./models/qwen --exclude=.onnx,.gguf

  dart run bin/huggingface_downloader.dart meta-llama/Llama-3.2-1B ./models/llama --token=hf_xxx --llm-only --overwrite
''');
}

# huggingface_downloader

[![pub package](https://img.shields.io/pub/v/huggingface_downloader.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/huggingface_downloader)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/huggingface_downloader?logo=git&logoColor=white)](https://github.com/gmpassos/huggingface_downloader/releases)
[![Last Commit](https://img.shields.io/github/last-commit/gmpassos/huggingface_downloader?logo=github&logoColor=white)](https://github.com/gmpassos/huggingface_downloader/commits/master)
[![License](https://img.shields.io/github/license/gmpassos/huggingface_downloader?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/huggingface_downloader/blob/master/LICENSE)

`huggingface_downloader` is a native Dart utility for **downloading complete model snapshots directly from Hugging Face
Hub**.

It provides a lightweight implementation similar in spirit to Python's `huggingface_hub.snapshot_download()`, allowing
Dart applications, AI runtimes, and CLI tools to fetch Hugging Face repositories without external Python dependencies.

Ideal for:

* 🤖 downloading LLM repositories
* 🧠 fetching tokenizer/config/model artifacts
* ⚙️ automation pipelines
* 🧪 CI model fixture downloads
* 📦 building local inference environments
* 🔄 resumable large file downloads

---

## Features

* 📥 Download complete Hugging Face repository snapshots
* 📂 Preserve nested directory structure
* 🔁 Resume interrupted downloads automatically
* ♻️ Optional full overwrite/redownload mode
* 🔐 Support gated/private repositories via HF token
* 🎯 Inclusion filters (`--ext`)
* 🚫 Exclusion filters (`--exclude`)
* 🤖 Built-in `--llm-only` mode for common LLM artifacts
* 📄 Returns downloaded file list programmatically
* 💻 CLI utility included
* 🧩 Native dependency-free Dart implementation using `HttpClient`

---

# CLI Usage

Activate globally:

```bash
dart pub global activate huggingface_downloader
````

Run:

```bash
huggingface_downloader <repoId> <outputDir> [options]
```

---

## Arguments

* `<repoId>` → Hugging Face repository id
* `<outputDir>` → local directory where files will be downloaded

---

## Options

* `--token=hf_xxx` → Hugging Face access token for private/gated models
* `--ext=.json,.safetensors` → download only selected extensions
* `--exclude=.onnx,.gguf,.pt` → exclude unwanted artifact types
* `--llm-only` → keep only common LLM files
* `--overwrite` → force full redownload even if files already exist
* `-h`, `--help` → show help message

---

## CLI Examples

Download SmolLM2:

```bash
huggingface_downloader HuggingFaceTB/SmolLM2-135M-Instruct ./models/smollm2 --llm-only
```

Force overwrite existing local files:

```bash
huggingface_downloader HuggingFaceTB/SmolLM2-135M-Instruct ./models/smollm2 --llm-only --overwrite
```

Download Qwen excluding ONNX/GGUF:

```bash
huggingface_downloader Qwen/Qwen2-0.5B ./models/qwen2 --exclude=.onnx,.gguf
```

Download private/gated repository:

```bash
huggingface_downloader meta-llama/Llama-3.2-1B-Instruct ./models/llama --token=hf_xxxxxxxxx --llm-only
```

---

## Example CLI Output

```txt
HuggingFace Downloader
----------------------
Repository : HuggingFaceTB/SmolLM2-135M-Instruct
Output Dir : ./models/smollm2
Mode       : LLM ONLY

Files selected for download: 6
  config.json
  tokenizer.json
  tokenizer_config.json
  generation_config.json
  special_tokens_map.json
  model.safetensors

model.safetensors -> 100.0% (542.13 MB / 542.13 MB)

Download completed successfully.

Downloaded files (6):
----------------------
models/smollm2/config.json
models/smollm2/tokenizer.json
models/smollm2/tokenizer_config.json
models/smollm2/generation_config.json
models/smollm2/special_tokens_map.json
models/smollm2/model.safetensors
```

---

# Programmatic Usage

`huggingface_downloader` can be embedded directly into Dart scripts, model preparation tools, or local inference
pipelines.

```dart
import 'dart:io';
import 'package:huggingface_downloader/huggingface_downloader.dart';

Future<void> main() async {
  final downloader = HuggingFaceDownloader();

  final files = await downloader.downloadSnapshot(
    repoId: 'HuggingFaceTB/SmolLM2-135M-Instruct',
    localDir: Directory('./models/smollm2'),
    excludeExtensions: ['.onnx', '.gguf'],
    overwriteExisting: false,
    progress: (file, received, total) {
      print('$file -> $received / $total');
    },
  );

  for (final file in files) {
    print('Downloaded: ${file.path}');
  }

  downloader.close();
}
```

---

## LLM Only Mode

`--llm-only` is a convenience mode designed for the most common local inference workflow.

Automatically includes:

* `.json`
* `.txt`
* `.model`
* `.safetensors`
* `.bin`

Automatically excludes:

* `.onnx`
* `.gguf`
* `.h5`
* `.msgpack`
* `.tflite`
* `.pt`
* `.pth`
* `.ot`
* `.ckpt`

This avoids downloading unrelated framework artifacts commonly present in Hugging Face repositories.

---

## How It Works

1. Fetch repository manifest from Hugging Face Hub API
2. Read repository file list (`siblings`)
3. Apply include/exclude filters
4. Resolve each file through Hugging Face `resolve` endpoints
5. Resume or overwrite existing files as requested
6. Stream files directly to disk
7. Return the final downloaded file list

---

## Why This Package

Python has `huggingface_hub.snapshot_download()`.

Dart had no native equivalent.

`huggingface_downloader` fills that gap with a simple automation-friendly downloader suitable for:

* Dart AI runtimes
* local LLM preparation
* CI artifact fetching
* reproducible model bootstrapping
* CLI tooling

---

## Test Repository

For automated tests and CI validation, a tiny public repository works very well:

```txt
fxmarty/really-tiny-falcon-testing
```

---

## Issues & Feature Requests

Please report issues or request features via the
[issue tracker][tracker].

[tracker]: https://github.com/gmpassos/huggingface_downloader/issues

---

## Author

Graciliano M. Passos: [gmpassos@GitHub][github]

[github]: https://github.com/gmpassos

---

## License

Dart free & open-source - [BSD 3-Clause License](https://github.com/dart-lang/stagehand/blob/master/LICENSE).

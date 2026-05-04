# huggingface_downloader

[![pub package](https://img.shields.io/pub/v/huggingface_downloader.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/huggingface_downloader)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/huggingface_downloader?logo=git&logoColor=white)](https://github.com/gmpassos/huggingface_downloader/releases)
[![Last Commit](https://img.shields.io/github/last-commit/gmpassos/huggingface_downloader?logo=github&logoColor=white)](https://github.com/gmpassos/huggingface_downloader/commits/master)
[![License](https://img.shields.io/github/license/gmpassos/huggingface_downloader?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/huggingface_downloader/blob/master/LICENSE)

`huggingface_downloader` is a Dart utility for **downloading complete model snapshots from Hugging Face Hub**.

It provides a lightweight native implementation similar in spirit to Python's `huggingface_hub.snapshot_download()`, allowing Dart applications and CLI tools to fetch model repositories directly from Hugging Face without external dependencies.

The package supports both **programmatic usage** and a **command line downloader**, making it ideal for:

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
* 🔐 Support gated/private repositories via HF token
* 🎯 Allow inclusion filters (`--ext`)
* 🚫 Allow exclusion filters (`--exclude`)
* 🤖 Built-in `--llm-only` mode for common model artifacts
* 🧪 Tiny public test repository support for unit/integration tests
* 💻 CLI utility included
* 🧩 Native Dart implementation using `HttpClient`

---

## Usage

### CLI

Activate globally:

```bash
dart pub global activate huggingface_downloader
```

Run:

```bash
huggingface_downloader <repoId> <outputDir> [options]
```

---

### Arguments

* `<repoId>` – Hugging Face repository id
* `<outputDir>` – Local directory where files will be downloaded

---

### Options

* `--token=hf_xxx` – Hugging Face access token for private/gated models
* `--ext=.json,.safetensors` – Download only selected extensions
* `--exclude=.onnx,.gguf,.pt` – Exclude unwanted artifact types
* `--llm-only` – Keep only common LLM files (`json`, `txt`, `model`, `safetensors`, `bin`)
* `-h`, `--help` – Show help message

---

## Examples

Download SmolLM2 135M Instruct:

```bash
huggingface_downloader HuggingFaceTB/SmolLM2-135M-Instruct ./models/smollm2-135m --llm-only
```

Download Qwen2 excluding ONNX/GGUF:

```bash
huggingface_downloader Qwen/Qwen2-0.5B ./models/qwen2 --exclude=.onnx,.gguf
```

Download private/gated repository:

```bash
huggingface_downloader meta-llama/Llama-3.2-1B-Instruct ./models/llama --token=hf_xxxxxxxxx --llm-only
```

Download a tiny public repo for testing:

```bash
huggingface_downloader fxmarty/really-tiny-falcon-testing ./test_models/tiny --llm-only
```

---

## Example Output

```txt
HuggingFace Downloader
----------------------
Repository : HuggingFaceTB/SmolLM2-135M-Instruct
Output Dir : ./models/smollm2-135m
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
```

---

## Programmatic Usage

`huggingface_downloader` can be embedded directly into Dart tools, scripts, or model preparation pipelines.

```dart
import 'dart:io';
import 'package:huggingface_downloader/huggingface_downloader.dart';

Future<void> main() async {
  final downloader = HuggingFaceDownloader();

  await downloader.downloadSnapshot(
    repoId: 'HuggingFaceTB/SmolLM2-135M-Instruct',
    localDir: Directory('./models/smollm2'),
    excludeExtensions: ['.onnx', '.gguf'],
    progress: (file, received, total) {
      print('$file -> $received / $total');
    },
  );

  downloader.close();
}
```

---

## LLM Only Mode

The `--llm-only` convenience mode is designed for the most common local inference workflow.

It automatically includes:

* `.json`
* `.txt`
* `.model`
* `.safetensors`
* `.bin`

and excludes:

* `.onnx`
* `.gguf`
* `.h5`
* `.msgpack`
* `.tflite`
* `.pt`
* `.pth`
* `.ot`
* `.ckpt`

This avoids downloading unrelated framework artifacts often present in Hugging Face repositories.

---

## Tiny Test Repository

For automated tests and CI validation, the package recommends using:

```txt
fxmarty/really-tiny-falcon-testing
```

This repository is intentionally very small and downloads quickly while still exercising the full Hugging Face snapshot logic.

---

## How It Works

1. Fetches repository manifest from Hugging Face Hub API
2. Reads repository file list (`siblings`)
3. Applies inclusion/exclusion filters
4. Resolves each file through Hugging Face `resolve` endpoints
5. Streams files to disk with resumable range requests
6. Preserves repository folder structure locally

---

## Why This Package

Python has `huggingface_hub.snapshot_download()`.

Dart previously had no native equivalent.

`huggingface_downloader` fills that gap with a simple, dependency-free, automation-friendly implementation suitable for:

* local LLM preparation
* Dart AI runtimes
* CLI tooling
* reproducible CI downloads

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

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
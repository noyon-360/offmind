# Offmind – project guide

Offmind is a Flutter app: an **offline, on-device AI voice chatbot**. After a one-time model download, everything (language model, speech-to-text, text-to-speech) runs on the phone with no internet.

Owner: Noyon. Package/bundle ID: `com.nsn.offmind`. Display name: Offmind.
Planning doc (plan, package research, references): https://claude.ai/artifact/GdnsSMr91sdAbALB2WqLLt

---

## 1. Status (as of 22 Nov 2026)

| Area | State |
|---|---|
| App code (chat UI, setup/download screen, voice in/out) | Written, compiles |
| Runs on iPhone 18 Pro simulator (iOS 27.2) | Yes – welcome/setup screen shows, engine starts |
| Runs on Android emulator (Pixel 9, arm64) | Built and launched; not visually checked |
| Model download (Qwen3-0.6B, ~328 MB) | Started in the simulator, very slow (~1%/min on the dev network); never finished |
| Chat replies, mic input, spoken output | **NOT tested yet** (blocked on the model download) |
| Bangla | Not supported/tested. English only |
| 3D avatar | Not started (later phase) |

Testing: Noyon runs and tests the app himself on his own simulator/emulator/phone. Claude should not launch simulators or drive the IDE for testing unless asked. Do not describe the untested items as working until Noyon has confirmed them.

---

## 2. Architecture

```
Mic (16 kHz mono PCM) -> STT (Whisper tiny) -> LLM (Qwen3-0.6B) -> TTS (system voice) -> Speaker
```

- **LLM**: `flutter_edge_ai` + `flutter_edge_ai_litertlm` (LiteRT-LM engine), model file `.litertlm`.
- **STT**: `flutter_edge_ai_speech` (`LiteRtSttBackend`, `LiteRtSpeechModels.whisperTiny.f32`).
- **Mic capture**: `record` package, PCM 16-bit, 16 kHz, mono.
- **TTS**: `flutter_tts` (the phone's built-in voice, offline if the voice is installed).
- **State**: a single `ChatController` (ChangeNotifier) used by `ChatPage`.

### File map

| File | Purpose |
|---|---|
| `lib/main.dart` | App entry. Calls `FlutterEdgeAi.initialize(...)`, builds the Material 3 dark UI: setup card, chat list, input bar with mic/send. |
| `lib/chat_controller.dart` | App state: `Phase` (checking / needsModel / downloading / ready / error), messages, send flow, mic toggle, sentence-by-sentence TTS. |
| `lib/services/llm_service.dart` | Model URL, install with progress, load, new chat, streaming reply, `stripThinking()`. |
| `lib/services/voice_service.dart` | Mic recording, Whisper transcription, STT install/load, TTS queue. |
| `test/widget_test.dart` | Unit test for `stripThinking`. |
| `android/app/build.gradle.kts` | `minSdk = 30`, `abiFilters` arm64-v8a only. |
| `android/app/src/main/AndroidManifest.xml` | INTERNET, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, TTS_SERVICE query. |
| `ios/Runner/Info.plist` | `NSMicrophoneUsageDescription`. iOS deployment target is 15.0. |

---

## 3. Dependencies (resolved versions)

- `flutter_edge_ai` 2.7.1
- `flutter_edge_ai_litertlm` 1.21.0
- `flutter_edge_ai_speech` 0.6.2 (declared as `any` in pubspec; consider pinning)
- `flutter_tts` 4.2.5
- `record` 6.2.1
- `permission_handler` 12.0.3 (currently unused; `record` asks for mic permission itself. Remove or use it.)

Notes:
- `flutter_gemma` is **discontinued**; `flutter_edge_ai` is its replacement. Do not add `flutter_gemma`.
- The LiteRT native library is downloaded from GitHub at build time, so the first build needs internet and is slow.

---

## 4. Models

| Model | Size | Notes |
|---|---|---|
| Qwen3-0.6B `Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm` | ~328 MiB | Apache-2.0, no Hugging Face login seen. URL in `kModelUrl`. Used as `ModelType.qwen3`, `ModelFileType.litertlm`. |
| Whisper tiny (f32) | ~150 MB (estimate, unchecked) | Downloaded from the in-app "Enable voice input" button. |
| Gemma 3 1B int4 `.litertlm` | 529 MB | Better quality, but gated: needs a Hugging Face login and Gemma license acceptance. |

- Qwen3 may emit reasoning in think tags. The app appends `/no_think` to each user message and removes think blocks with `stripThinking()`.
- Whisper reads a fixed 30 s window. `voice_service.dart` truncates longer audio.
- Models are NOT bundled in the app. They download on first launch (about 0.7-1 GB total with voice).

---

## 5. How to run

```
flutter pub get
flutter run -d <device>        # Android emulator or iOS simulator
```

- Android: needs an arm64 emulator or device, API 30+. Apple Silicon Macs can use arm64 emulators (AVDs on this Mac: Pixel_9, Pixel_Rootable).
- iOS: simulator is CPU only. The project uses Swift Package Manager; `flutter_tts` does not support it, so Flutter falls back to CocoaPods for that plugin (a warning is printed, build works).
- First Android build is slow because it downloads native libraries.
- After changing `pubspec.yaml` or native config, do a full stop and re-run (hot reload/restart is not enough).

---

## 6. API notes (flutter_edge_ai 2.7.x)

Used and confirmed to compile:
- `FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()], sttBackends: [LiteRtSttBackend()])`
- `FlutterEdgeAi.installModel(modelType:, fileType:).fromNetwork(url).withProgress(cb).install()`
- `FlutterEdgeAi.getActiveModel(maxTokens:)` – throws `NoActiveModelError` if nothing is installed
- `model.createChat()` – **deprecated since 2.6.0** (removal planned for 3.0.0); `chat.addQueryChunk(Message.text(...))`; `chat.generateChatResponseAsync()` yielding `TextResponse` with `.token`
- `FlutterEdgeAi.installStt().fromCatalog(LiteRtSpeechModels.whisperTiny.f32).install()`, `getActiveStt()`, `transcribe(pcm)`

Kept `dynamic` on purpose: the model/chat/STT objects in `llm_service.dart` and `voice_service.dart` (concrete class names are internal and may change). The return type of `transcribe` is unverified; the code handles a `String` or an object with `.text`.

Other package features worth knowing (from the docs, not yet used): `installModelFromCatalog(...)`, `FlutterEdgeAi.catalog`, `installModel(...).fromHuggingFace(repo)`, `ResponseFormat.jsonSchema`, `MessageTranscriptCodec` (save/load conversations), `VoiceSession` in `flutter_edge_ai_speech` (STT -> LLM -> TTS push-to-talk loop with barge-in), TTS backends (Matcha, Qwen3-TTS).

---

## 6b. Known issues and gotchas

1. Model download is very slow on the dev network. The progress callback may report a value of 100 at the start and then drop to real progress; the app treats values above 1 as percentages.
2. If the model download is interrupted, restart the app and tap Download again.
3. `llm_service.dart` still has an unused import (`flutter_edge_ai_litertlm`) and an HTML-in-doc-comment lint; harmless. Remove the import and reword the doc comment.
4. `flutter_tts` and `record_android` print a Kotlin Gradle Plugin warning (future Flutter versions may fail to build with them). Watch for plugin updates.
5. No fallback if the speech catalog install fails: text chat still works, the mic stays disabled.
6. Mic and TTS on emulators/simulators depend on host audio; real-device testing is still required.
7. The user must be able to use the app with no internet at all; the first-launch download is the only online step. Plan for sideloading or bundling the model (see roadmap) for rural/low-bandwidth users.

---

## 7. Roadmap

**Phase A – finish and verify the MVP**
1. (Noyon) Let the model download finish (or sideload it), then test text chat on the iPhone simulator and the Android emulator.
2. (Noyon) Enable voice, test the mic -> Whisper -> reply -> spoken answer loop.
3. (Noyon) Test on a real arm64 Android phone with 6 GB RAM or more; check speed, heat, battery.
4. Fix errors found, remove the lint issues, pin `flutter_edge_ai_speech`.

**Phase B – make it robust**
- "Import model from file" (sideload) and a resume-able download; show download size and a Wi-Fi warning.
- Persist conversations (`MessageTranscriptCodec` or local storage).
- Handle low-memory and model-load failures with clear messages.
- Replace the deprecated `createChat` when the replacement API is confirmed.
- Try the `VoiceSession` loop in `flutter_edge_ai_speech` with barge-in (interrupt the bot by speaking).
- Offer model choices (Gemma 3 1B for quality, Qwen3-0.6B for small size).

**Phase C – language and quality**
- Test Bangla speech-to-text, replies and text-to-speech before promising it (not mentioned in the speech packages' docs). Fall back to English-only if it fails.
- Try an on-device TTS from `flutter_edge_ai_speech` (Matcha/Qwen3-TTS) for a more natural voice than the system voice.

**Phase D – 3D avatar (later)**
- Rigged GLB/VRM character rendered through a WebView with Three.js (+ three-vrm) or Unity as a Library.
- Start with mouth movement from audio amplitude, then viseme lip-sync, idle animation and blinking.

**Phase E – release**
- Final app ID and name check (Play Store/App Store, domain, handles), icons, store listing.
- App size: app itself about 50-100 MB (estimate); models download separately. Consider Play Asset Delivery if users cannot download on first launch.

---

## 8. References

- flutter_edge_ai: https://pub.dev/packages/flutter_edge_ai
- flutter_edge_ai_litertlm: https://pub.dev/packages/flutter_edge_ai_litertlm
- flutter_edge_ai_speech: https://pub.dev/packages/flutter_edge_ai_speech
- flutter_edge_ai changelog: https://pub.dev/packages/flutter_edge_ai/changelog
- flutter_tts: https://pub.dev/packages/flutter_tts
- record: https://pub.dev/packages/record
- Qwen3-0.6B (LiteRT): https://huggingface.co/litert-community/Qwen3-0.6B
- Gemma 3 1B (LiteRT, gated): https://huggingface.co/litert-community/Gemma3-1B-IT
- Alternatives for offline speech: https://pub.dev/packages/sherpa_onnx

---

## 9. Working notes for future updates

- Keep the voice/LLM code behind `LlmService` and `VoiceService` so packages can be swapped without touching the UI.
- When a package API changes, check the package changelog first (`flutter_edge_ai` changes often; versions 2.5 to 2.7 changed install and chat APIs).
- Update the Status table in section 1 whenever something is tested.
- File location: keep this guide at `.claude/CLAUDE.md` (a root `CLAUDE.md` is also read by Claude Code). Remote tools cannot write into `.claude`, so edit the root copy and copy it over with `cp CLAUDE.md .claude/CLAUDE.md`, or edit the `.claude` file directly.

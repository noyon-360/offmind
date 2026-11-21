import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// Small, Apache-2.0 licensed model (~328 MiB, int4). No login needed.
const String kModelUrl =
    'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
    'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm';

/// Removes Qwen3 "<think>...</think>" blocks (also while still streaming).
String stripThinking(String raw) {
  var out = raw.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
  final open = out.indexOf('<think>');
  if (open >= 0) out = out.substring(0, open);
  return out.trimLeft();
}

/// Wraps the on-device LLM (flutter_edge_ai + LiteRT-LM).
class LlmService {
  // Kept dynamic on purpose: the concrete model/chat classes are internal to
  // the package and may be renamed between versions.
  dynamic _model;
  dynamic _chat;

  bool get isLoaded => _chat != null;

  /// Installs the model once. [onProgress] receives 0.0 - 1.0.
  Future<void> install(void Function(double) onProgress) async {
    await FlutterEdgeAi.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    )
        .fromNetwork(kModelUrl)
        .withProgress((percent) {
      final v = (percent as num).toDouble();
      onProgress(v > 1 ? v / 100 : v);
    }).install();
  }

  /// Installs a model from a `.litertlm` file already on the device
  /// (for example one downloaded on a computer and copied over).
  Future<void> installFromFile(String path) async {
    await FlutterEdgeAi.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
  }

  /// Loads the installed model. Throws [NoActiveModelError] if not installed.
  Future<void> load() async {
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: 2048);
    await newChat();
  }

  Future<void> newChat() async {
    // ignore: deprecated_member_use
    _chat = await _model.createChat();
  }

  /// Streams the cumulative reply text for [userText].
  Stream<String> reply(String userText) async* {
    final chat = _chat;
    await chat.addQueryChunk(
      // "/no_think" asks Qwen3 to skip long reasoning for faster answers.
      Message.text(text: '$userText /no_think', isUser: true),
    );
    var raw = '';
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) {
        raw += r.token;
        yield stripThinking(raw);
      }
    }
  }

  Future<void> dispose() async {
    try {
      await _model?.close();
    } catch (_) {}
  }
}

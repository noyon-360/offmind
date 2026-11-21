import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'services/llm_service.dart';
import 'services/voice_service.dart';

enum Phase { checking, needsModel, downloading, ready, error }

class ChatMessage {
  ChatMessage(this.text, {required this.isUser});
  String text;
  final bool isUser;
}

class ChatController extends ChangeNotifier {
  final LlmService llm = LlmService();
  final VoiceService voice = VoiceService();

  Phase phase = Phase.checking;
  double progress = 0;
  bool importing = false;
  String? error;

  final List<ChatMessage> messages = <ChatMessage>[];
  bool generating = false;
  bool recording = false;
  bool transcribing = false;
  bool speakReplies = true;

  bool voiceReady = false;
  bool voiceDownloading = false;
  String? voiceError;

  Future<void> init() async {
    await voice.initTts();
    await _loadModel();
    voiceReady = await voice.loadStt();
    notifyListeners();
  }

  Future<void> _loadModel() async {
    phase = Phase.checking;
    notifyListeners();
    try {
      await llm.load();
      phase = Phase.ready;
    } on NoActiveModelError {
      phase = Phase.needsModel;
    } catch (e) {
      error = '$e';
      phase = Phase.error;
    }
    notifyListeners();
  }

  Future<void> downloadModel() async {
    phase = Phase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await llm.install((p) {
        progress = p.clamp(0.0, 1.0);
        notifyListeners();
      });
      await _loadModel();
    } catch (e) {
      error = '$e';
      phase = Phase.needsModel;
      notifyListeners();
    }
  }

  /// Lets the user pick a `.litertlm` model file already on the device.
  /// Useful when the in-app download is too slow or there is no internet.
  Future<void> importModelFromFile() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      error = 'Could not open the file picker: $e';
      notifyListeners();
      return;
    }
    final path = picked?.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.litertlm')) {
      error = 'Please choose a .litertlm model file.';
      notifyListeners();
      return;
    }
    importing = true;
    phase = Phase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await llm.installFromFile(path);
      await _loadModel();
    } catch (e) {
      error = 'Could not install the model: $e';
      phase = Phase.needsModel;
    }
    importing = false;
    notifyListeners();
  }

  Future<void> downloadVoice() async {
    voiceDownloading = true;
    voiceError = null;
    notifyListeners();
    try {
      await voice.installStt();
      voiceReady = await voice.loadStt();
      if (!voiceReady) voiceError = 'Voice model installed but could not load.';
    } catch (e) {
      voiceError = '$e';
    }
    voiceDownloading = false;
    notifyListeners();
  }

  Future<void> send(String input) async {
    final text = input.trim();
    if (text.isEmpty || generating || phase != Phase.ready) return;
    await voice.stopSpeaking();
    messages.add(ChatMessage(text, isUser: true));
    final reply = ChatMessage('', isUser: false);
    messages.add(reply);
    generating = true;
    notifyListeners();

    var spoken = 0;
    try {
      await for (final partial in llm.reply(text)) {
        reply.text = partial;
        notifyListeners();
        if (speakReplies) {
          // Speak each finished sentence while the model keeps generating.
          final ends = RegExp(r'[.!?।]\s')
              .allMatches(partial)
              .where((m) => m.end > spoken)
              .toList();
          if (ends.isNotEmpty) {
            final end = ends.last.end;
            voice.enqueue(partial.substring(spoken, end));
            spoken = end;
          }
        }
      }
      if (speakReplies && spoken < reply.text.length) {
        voice.enqueue(reply.text.substring(spoken));
      }
      if (reply.text.trim().isEmpty) reply.text = '(no answer)';
    } catch (e) {
      reply.text = 'Something went wrong: $e';
    }
    generating = false;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    if (generating || transcribing || !voiceReady) return;
    if (!recording) {
      await voice.stopSpeaking();
      final ok = await voice.startRecording();
      if (!ok) {
        voiceError = 'Microphone permission is needed for voice input.';
        notifyListeners();
        return;
      }
      voiceError = null;
      recording = true;
      notifyListeners();
    } else {
      recording = false;
      transcribing = true;
      notifyListeners();
      var text = '';
      try {
        text = await voice.stopAndTranscribe();
      } catch (e) {
        voiceError = 'Could not understand audio: $e';
      }
      transcribing = false;
      notifyListeners();
      if (text.isNotEmpty) await send(text);
    }
  }

  void toggleSpeakReplies() {
    speakReplies = !speakReplies;
    if (!speakReplies) voice.stopSpeaking();
    notifyListeners();
  }

  Future<void> newConversation() async {
    if (generating) return;
    await voice.stopSpeaking();
    messages.clear();
    if (phase == Phase.ready) await llm.newChat();
    notifyListeners();
  }

  @override
  void dispose() {
    llm.dispose();
    voice.dispose();
    super.dispose();
  }
}

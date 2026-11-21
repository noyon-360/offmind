import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

/// Offline speech in (Whisper tiny via flutter_edge_ai_speech) and
/// speech out (the phone's built-in text-to-speech voice).
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  final List<int> _pcm = <int>[];
  StreamSubscription<Uint8List>? _sub;
  Future<void> _speakQueue = Future<void>.value();
  dynamic _stt;

  bool get sttLoaded => _stt != null;

  Future<void> initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  /// Downloads the speech-to-text model (once).
  Future<void> installStt() async {
    await FlutterEdgeAi.installStt()
        .fromCatalog(LiteRtSpeechModels.whisperTiny.f32)
        .install();
  }

  Future<bool> loadStt() async {
    try {
      _stt = await FlutterEdgeAi.getActiveStt();
      return true;
    } catch (_) {
      _stt = null;
      return false;
    }
  }

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    _pcm.clear();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));
    _sub = stream.listen(_pcm.addAll);
    return true;
  }

  Future<String> stopAndTranscribe() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    // Whisper reads a 30 s window: 16 kHz * 2 bytes * 30 s.
    const maxBytes = 16000 * 2 * 30;
    var bytes = Uint8List.fromList(_pcm);
    if (bytes.length > maxBytes) bytes = bytes.sublist(0, maxBytes);
    if (bytes.length < 16000) return ''; // under 0.5 s: nothing to transcribe
    final result = await _stt.transcribe(bytes);
    String text;
    if (result is String) {
      text = result;
    } else {
      try {
        text = result.text.toString();
      } catch (_) {
        text = result.toString();
      }
    }
    return text.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
  }

  /// Queues [text] so sentences are spoken one after another.
  void enqueue(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _speakQueue = _speakQueue.then((_) async {
      try {
        await _tts.speak(clean);
      } catch (_) {}
    });
  }

  Future<void> stopSpeaking() async {
    _speakQueue = Future<void>.value();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _recorder.dispose();
    await _tts.stop();
  }
}

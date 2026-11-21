import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_speech/flutter_edge_ai_speech.dart';

import 'chat_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterEdgeAi.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    sttBackends: [LiteRtSttBackend()],
  );
  runApp(const OffmindApp());
}

class OffmindApp extends StatelessWidget {
  const OffmindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offmind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B6CFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatController _c = ChatController();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.init();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _input.text;
    _input.clear();
    _c.send(t);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offmind'),
        actions: [
          IconButton(
            tooltip: _c.speakReplies ? 'Mute spoken replies' : 'Speak replies',
            icon: Icon(_c.speakReplies ? Icons.volume_up : Icons.volume_off),
            onPressed: _c.toggleSpeakReplies,
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _c.newConversation,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _body(scheme)),
            if (_c.phase == Phase.ready) _inputBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    switch (_c.phase) {
      case Phase.checking:
        return const Center(child: CircularProgressIndicator());
      case Phase.needsModel:
      case Phase.downloading:
        return _setupCard(scheme);
      case Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load the model:\n${_c.error}',
                textAlign: TextAlign.center),
          ),
        );
      case Phase.ready:
        return _chatList(scheme);
    }
  }

  Widget _setupCard(ColorScheme scheme) {
    final downloading = _c.phase == Phase.downloading;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_alt, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Welcome to Offmind',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'An AI assistant that runs fully on your phone. Download the '
              'language model once (about 330 MB, Wi-Fi recommended). After '
              'that it works with no internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (downloading) ...[
              LinearProgressIndicator(
                value: !_c.importing && _c.progress > 0 ? _c.progress : null,
              ),
              const SizedBox(height: 8),
              Text(_c.importing
                  ? 'Installing model…'
                  : 'Downloading… ${(_c.progress * 100).toStringAsFixed(0)}%'),
            ] else ...[
              FilledButton.icon(
                onPressed: _c.downloadModel,
                icon: const Icon(Icons.download),
                label: const Text('Download model'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _c.importModelFromFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Import model from file'),
              ),
              const SizedBox(height: 12),
              Text(
                'Slow connection? Download '
                'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm from '
                'huggingface.co/litert-community/Qwen3-0.6B on a computer, '
                'copy it to this device, then tap "Import model from file".',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_c.error != null) ...[
              const SizedBox(height: 16),
              Text(_c.error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chatList(ColorScheme scheme) {
    if (_c.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: scheme.primary, size: 40),
              const SizedBox(height: 12),
              const Text('Offline and private.\nType a message or tap the mic.',
                  textAlign: TextAlign.center),
              if (!_c.voiceReady) ...[
                const SizedBox(height: 20),
                _voiceSetup(),
              ],
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _c.messages.length,
      itemBuilder: (context, i) {
        final m = _c.messages[i];
        final waiting = !m.isUser && m.text.isEmpty && _c.generating;
        return Align(
          alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: m.isUser
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: waiting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SelectableText(m.text),
          ),
        );
      },
    );
  }

  Widget _voiceSetup() {
    if (_c.voiceDownloading) {
      return const Column(
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('Downloading voice model…'),
        ],
      );
    }
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _c.downloadVoice,
          icon: const Icon(Icons.mic),
          label: const Text('Enable voice input (about 150 MB)'),
        ),
        if (_c.voiceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_c.voiceError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Widget _inputBar(ColorScheme scheme) {
    final busy = _c.generating || _c.transcribing;
    final hint = _c.recording
        ? 'Listening… tap the mic to send'
        : _c.transcribing
            ? 'Transcribing…'
            : 'Message Offmind';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: _c.voiceReady ? 'Talk' : 'Voice not enabled',
            style: _c.recording
                ? IconButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            icon: Icon(_c.recording ? Icons.stop : Icons.mic),
            onPressed: _c.voiceReady && !_c.generating && !_c.transcribing
                ? _c.toggleMic
                : (_c.voiceReady ? null : _c.downloadVoice),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_c.recording,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: busy || _c.recording ? null : _submit,
          ),
        ],
      ),
    );
  }
}

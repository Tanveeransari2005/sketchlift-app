// The per-call listen() parameters are deprecated in favour of
// SpeechListenOptions but still supported; kept for readability.
// ignore_for_file: deprecated_member_use
/// Feature 13: voice questions (speech_to_text) + spoken answers (flutter_tts).
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Listens once and completes with the final recognised sentence ('' if none).
  Future<String> listenOnce({required bool hindi}) async {
    if (!await init()) return '';
    final done = Completer<String>();
    var last = '';
    await _stt.listen(
      localeId: hindi ? 'hi_IN' : 'en_IN',
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        last = r.recognizedWords;
        if (r.finalResult && !done.isCompleted) done.complete(last);
      },
    );
    // Safety net if no final result arrives.
    Future.delayed(const Duration(seconds: 15), () {
      if (!done.isCompleted) done.complete(last);
    });
    return done.future;
  }

  Future<void> stopListening() => _stt.stop();

  /// Speaks [text] in Hindi (hi-IN) or Indian English (en-IN).
  Future<void> speak(String text, {required bool hindi}) async {
    await _tts.stop();
    await _tts.setLanguage(hindi ? 'hi-IN' : 'en-IN');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() => _tts.stop();
}

/// Talks to Google Gemini — either directly with the user's own key, or
/// through the free SketchLift proxy (no key needed on the phone).
///
///   own key  → `POST generativelanguage.googleapis.com/v1beta/models/{m}:generateContent`
///              header `x-goog-api-key` = key from Settings (secure storage)
///   proxy    → `POST AppConfig.proxyUrl {"model": m, "body": sameBody}`
///              headers X-App + X-Device-Id; proxy adds the key server-side.
///
/// Both paths return Gemini's raw response JSON, so parsing is shared.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/diagram.dart';
import 'gemini_prompts.dart';

/// Thrown for any AI problem; [userMessage] is safe to show (Hinglish).
class AiException implements Exception {
  final String userMessage;
  final String debug;
  const AiException(this.userMessage, [this.debug = '']);
  @override
  String toString() => 'AiException($userMessage, $debug)';
}

/// The free daily limit (local or proxy) was reached.
class DailyLimitException extends AiException {
  const DailyLimitException()
      : super('Aaj ke free diagrams khatam ho gaye 🙏 Kal phir try karo, ya Settings mein apni Gemini key daalo.\n'
            "Today's free limit is used up. Try again tomorrow, or add your own Gemini key in Settings.");
}

/// How the client should reach Gemini.
class AiConfig {
  final String ownKey; // empty = use proxy
  final String model; // used with own key
  final String proxyUrl;
  final String deviceId;
  const AiConfig({required this.ownKey, required this.model, required this.proxyUrl, required this.deviceId});

  bool get usesOwnKey => ownKey.isNotEmpty;
  bool get isAvailable => usesOwnKey || proxyUrl.isNotEmpty;
}

class GeminiService {
  final AiConfig config;
  final http.Client _http;
  GeminiService(this.config, {http.Client? client}) : _http = client ?? http.Client();

  /// Requests left today according to the proxy (null = unknown).
  int? lastRemaining;

  // ---------------------------------------------------------------------------
  // High-level features
  // ---------------------------------------------------------------------------

  /// Feature 2: understand a (pre-processed) diagram photo.
  Future<DiagramResult> analyzeDiagram(Uint8List jpeg) async {
    final text = await generateText(GeminiPrompts.analyzeBody(jpeg));
    try {
      return DiagramResult.parseModelText(text);
    } on FormatException catch (e) {
      throw AiException('AI ka jawab samajh nahi aaya, dobara try karo.', e.toString());
    }
  }

  /// Feature 11: compare a student's drawing with a reference diagram.
  Future<DrawingCheck> checkDrawing(Uint8List jpeg, DiagramResult reference) async {
    final text = await generateText(GeminiPrompts.checkDrawingBody(jpeg, reference));
    try {
      return DrawingCheck.fromJson(extractJsonObject(text));
    } on FormatException catch (e) {
      throw AiException('AI ka jawab samajh nahi aaya, dobara try karo.', e.toString());
    }
  }

  /// Feature 13: answer a spoken question about the current diagram.
  Future<String> askAboutDiagram(DiagramResult d, String question, {required bool hindi}) async {
    final text = await generateText(GeminiPrompts.askBody(d, question, hindi: hindi));
    return text.replaceAll(RegExp(r'[*_#`]'), '').trim();
  }

  /// One-line explanation for a label the student added by hand.
  Future<(String, String)> explainPart(String title, String part) async {
    final text = await generateText(GeminiPrompts.explainPartBody(title, part));
    final j = extractJsonObject(text);
    return ((j['explain_en'] ?? '').toString(), (j['explain_hi'] ?? '').toString());
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  /// Sends a generateContent [body] and returns the model's text output.
  Future<String> generateText(Map<String, dynamic> body) async {
    final raw = await generateRaw(body);
    return extractText(raw);
  }

  Future<Map<String, dynamic>> generateRaw(Map<String, dynamic> body) async {
    if (!config.isAvailable) {
      throw const AiException('AI setup nahi hai. Settings mein Gemini key daalo.');
    }
    final http.Response res;
    try {
      if (config.usesOwnKey) {
        final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent');
        res = await _http
            .post(uri,
                headers: {'Content-Type': 'application/json', 'x-goog-api-key': config.ownKey},
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 90));
      } else {
        res = await _http
            .post(Uri.parse(config.proxyUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'X-App': AppConfig.proxyAppId,
                  'X-Device-Id': config.deviceId,
                },
                body: jsonEncode({'model': AppConfig.proxyModel, 'body': body}))
            .timeout(const Duration(seconds: 90));
        final rem = int.tryParse(res.headers['x-remaining'] ?? '');
        if (rem != null) lastRemaining = rem;
      }
    } on TimeoutException {
      throw const AiException('Internet slow hai — AI ne time par jawab nahi diya. Dobara try karo.');
    } catch (e) {
      throw AiException('Internet connection check karo aur dobara try karo.', e.toString());
    }
    return handleResponse(res.statusCode, res.body, usesOwnKey: config.usesOwnKey);
  }

  /// Maps HTTP status codes to friendly errors (public for unit tests).
  static Map<String, dynamic> handleResponse(int status, String body, {required bool usesOwnKey}) {
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    if (status == 200 && j != null) return j;
    final errText = (j?['error'] is Map ? j!['error']['message'] : j?['error'])?.toString() ?? body;
    if (status == 429) {
      if (!usesOwnKey && (j?['error'] == 'daily_limit')) throw const DailyLimitException();
      throw AiException(
          usesOwnKey
              ? 'Aapki Gemini key ki free limit abhi khatam hai. Thodi der baad try karo.'
              : 'Server busy hai, 1 minute baad try karo.',
          errText);
    }
    if (status == 400 && errText.toLowerCase().contains('api key')) {
      throw AiException('Gemini key galat lag rahi hai. Settings mein check karo.', errText);
    }
    if (status == 401 || status == 403) {
      throw AiException(
          usesOwnKey ? 'Gemini key galat hai ya allowed nahi. Settings check karo.' : 'Free server ne request mana kar di.',
          errText);
    }
    if (status == 404) {
      throw AiException('AI model nahi mila. Settings → Advanced mein model badlo.', errText);
    }
    if (status == 413) {
      throw AiException('Photo bahut badi hai, chhoti photo try karo.', errText);
    }
    throw AiException('AI se baat nahi ho payi (error $status). Dobara try karo.', errText);
  }

  /// Pulls the concatenated text out of a generateContent response.
  static String extractText(Map<String, dynamic> raw) {
    final cands = raw['candidates'];
    if (cands is! List || cands.isEmpty) {
      final block = raw['promptFeedback']?['blockReason'];
      throw AiException('AI ne is photo par jawab nahi diya${block != null ? ' ($block)' : ''}.');
    }
    final parts = cands.first['content']?['parts'];
    if (parts is! List) throw const AiException('AI ka jawab khaali tha, dobara try karo.');
    final buf = StringBuffer();
    for (final p in parts) {
      // Skip "thought" parts some models return.
      if (p is Map && p['text'] is String && p['thought'] != true) buf.write(p['text']);
    }
    final s = buf.toString();
    if (s.trim().isEmpty) throw const AiException('AI ka jawab khaali tha, dobara try karo.');
    return s;
  }
}

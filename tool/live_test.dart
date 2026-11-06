// Developer tool: runs the REAL image pipeline + REAL Gemini prompt on a photo
// through the SketchLift proxy (or your own key) and prints the parsed result.
//
//   dart run tool/live_test.dart <photo.jpg> [out.json] [check:<drawing.jpg>]
//
// Env: PROXY_URL (default: AppConfig.proxyUrl), DEVICE_ID, or GEMINI_API_KEY to
// call Google directly.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sketchlift/models/diagram.dart';
import 'package:sketchlift/services/gemini_prompts.dart';
import 'package:sketchlift/services/glossary.dart';
import 'package:sketchlift/services/image_pipeline.dart';

const _proxy = 'https://sketchlift-proxy.vercel.app/api/generate';
const _model = 'gemini-3.8-flash';

Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
  final key = Platform.environment['GEMINI_API_KEY'] ?? '';
  final http.Response r;
  if (key.isNotEmpty) {
    r = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
        body: jsonEncode(body));
  } else {
    r = await http.post(Uri.parse(Platform.environment['PROXY_URL'] ?? _proxy),
        headers: {
          'Content-Type': 'application/json',
          'X-App': 'sketchlift',
          'X-Device-Id': Platform.environment['DEVICE_ID'] ?? 'devtest_cli_0001',
        },
        body: jsonEncode({'model': _model, 'body': body}));
  }
  stderr.writeln('HTTP ${r.statusCode}  remaining=${r.headers['x-remaining']}');
  if (r.statusCode != 200) {
    stderr.writeln(r.body);
    exit(1);
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

String _text(Map<String, dynamic> raw) => (raw['candidates'][0]['content']['parts'] as List)
    .where((p) => p['text'] is String && p['thought'] != true)
    .map((p) => p['text'])
    .join();

Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();
  final processed = processPhoto(ProcessRequest(File(args[0]).readAsBytesSync()));
  File('/tmp/processed.png').writeAsBytesSync(processed);
  final jpeg = toUploadJpeg(processed);
  stderr.writeln('pipeline ${sw.elapsedMilliseconds} ms, upload ${jpeg.length ~/ 1024} KB');

  final checkArg = args.where((a) => a.startsWith('check:')).toList();
  if (checkArg.isNotEmpty) {
    final ref = DiagramResult.parseModelText(File(args[1]).readAsStringSync());
    final drawing = toUploadJpeg(processPhoto(ProcessRequest(File(checkArg.first.substring(6)).readAsBytesSync())));
    final raw = await _call(GeminiPrompts.checkDrawingBody(drawing, ref));
    final c = DrawingCheck.fromJson(extractJsonObject(_text(raw)));
    stdout.writeln('score ${c.score}/${c.total}  missing=${c.missing} misplaced=${c.misplaced}\n${c.feedbackEn}\n${c.feedbackHi}');
    return;
  }

  final raw = await _call(GeminiPrompts.analyzeBody(jpeg));
  final text = _text(raw);
  stderr.writeln('model answered in ${sw.elapsedMilliseconds} ms');
  if (args.length > 1) File(args[1]).writeAsStringSync(text);
  final r = DiagramResult.parseModelText(text);
  stdout.writeln('is_diagram=${r.isDiagram} (${r.reason})\n${r.subject}: ${r.title} / ${r.titleHi}  body=${r.bodyBox?.toJson()}');
  for (final p in r.parts) {
    stdout.writeln(' - ${p.name}  [wrote "${p.labelText}" → ${Glossary.fix(p.name, subject: r.subject)}] '
        '@(${p.anchor.x.toStringAsFixed(3)}, ${p.anchor.y.toStringAsFixed(3)}) box=${p.labelBox?.toJson()}\n'
        '     EN: ${p.explainEn}\n     HI: ${p.explainHi}');
  }
}

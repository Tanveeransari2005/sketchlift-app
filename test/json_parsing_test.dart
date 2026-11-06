import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchlift/l10n/strings.dart';
import 'package:sketchlift/models/diagram.dart';
import 'package:sketchlift/services/gemini_service.dart';

void main() {
  group('DiagramResult parsing', () {
    test('parses the recorded real Gemini answer (assets/demo)', () {
      final r = DiagramResult.parseModelText(File('assets/demo/plant_cell_gemini.json').readAsStringSync());
      expect(r.isDiagram, isTrue);
      expect(r.subject, 'Biology');
      expect(r.title, 'Plant Cell');
      expect(r.parts.length, greaterThanOrEqualTo(6));
      expect(r.bodyBox, isNotNull);
      for (final p in r.parts) {
        expect(p.anchor.x, inInclusiveRange(0, 1));
        expect(p.anchor.y, inInclusiveRange(0, 1));
        expect(p.explainEn, isNotEmpty);
        expect(p.explainHi, isNotEmpty);
      }
    });

    test('strips ```json fences and chatter', () {
      const text = 'Sure! Here is the JSON:\n```json\n{"is_diagram": true, "reason": "ok", "subject": "physics",'
          ' "title": "Convex Lens", "parts": [{"name": "Principal axis", "point": {"x": 0.5, "y": 0.5}}], "arrows": []}\n```\nThanks';
      final r = DiagramResult.parseModelText(text);
      expect(r.title, 'Convex Lens');
      expect(r.subject, 'Physics');
      expect(r.parts.single.name, 'Principal axis');
    });

    test('accepts 0-1000 coordinates and box_2d lists', () {
      final r = DiagramResult.fromJson({
        'is_diagram': true,
        'parts': [
          {'name': 'A', 'point': {'x': 250, 'y': 750}, 'label_bbox': [100, 200, 300, 400]},
          {'name': 'B', 'point': [0.1, 0.2]},
        ],
      });
      expect(r.parts[0].anchor.x, closeTo(0.25, 1e-9));
      expect(r.parts[0].anchor.y, closeTo(0.75, 1e-9));
      final b = r.parts[0].labelBox!; // [ymin,xmin,ymax,xmax]/1000
      expect(b.x, closeTo(0.2, 1e-9));
      expect(b.y, closeTo(0.1, 1e-9));
      expect(b.w, closeTo(0.2, 1e-9));
      expect(b.h, closeTo(0.2, 1e-9));
      expect(r.parts[1].anchor.y, closeTo(0.2, 1e-9));
    });

    test('missing fields fall back safely; empty parts are dropped', () {
      final r = DiagramResult.fromJson({
        'is_diagram': 'true',
        'parts': [
          {'name': '', 'label_text': ''},
          {'label_text': 'xylem'},
          'garbage',
        ],
        'arrows': [{'from': 'Root', 'to': 'Leaf'}],
      });
      expect(r.isDiagram, isTrue);
      expect(r.parts.single.name, 'xylem');
      expect(r.parts.single.anchor.x, 0.5);
      expect(r.subject, 'Other');
      expect(r.arrows.single.to, 'Leaf');
    });

    test('not a diagram', () {
      final r = DiagramResult.parseModelText('{"is_diagram": false, "reason": "This is a selfie.", "parts": []}');
      expect(r.isDiagram, isFalse);
      expect(r.reason, contains('selfie'));
    });

    test('round-trips through toJson', () {
      final r = DiagramResult.parseModelText(File('assets/demo/plant_cell_gemini.json').readAsStringSync());
      final again = DiagramResult.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(again.parts.map((p) => p.name), r.parts.map((p) => p.name));
      expect(again.bodyBox!.w, closeTo(r.bodyBox!.w, 1e-9));
    });

    test('invalid text throws FormatException', () {
      expect(() => extractJsonObject('no json here'), throwsFormatException);
      expect(() => extractJsonObject('{"a": "unterminated'), throwsFormatException);
      // Braces inside strings do not confuse the scanner.
      expect(extractJsonObject('x {"a": "}{", "b": 1} y')['b'], 1);
    });
  });

  group('DrawingCheck parsing', () {
    test('clamps score and accepts object lists', () {
      final c = DrawingCheck.fromJson({
        'total': 5,
        'score': 9,
        'found': ['Nucleus', {'name': 'Vacuole'}],
        'missing': ['Cell wall'],
        'misplaced': [],
        'feedback_en': 'Good try!',
        'feedback_hi': 'अच्छी कोशिश!',
      });
      expect(c.score, 5);
      expect(c.found, ['Nucleus', 'Vacuole']);
      expect(c.missing, ['Cell wall']);
    });
  });

  group('Gemini response handling', () {
    test('extracts text and skips thought parts / thoughtSignature', () {
      final raw = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'thinking...', 'thought': true},
                {'text': '{"a":', 'thoughtSignature': 'abc'},
                {'text': '1}'},
              ]
            }
          }
        ]
      };
      expect(GeminiService.extractText(raw), '{"a":1}');
    });

    test('blocked prompt gives a friendly error', () {
      expect(() => GeminiService.extractText({'promptFeedback': {'blockReason': 'SAFETY'}}),
          throwsA(isA<AiException>()));
    });

    test('proxy daily limit → DailyLimitException', () {
      expect(() => GeminiService.handleResponse(429, '{"error":"daily_limit","limit":5}', usesOwnKey: false),
          throwsA(isA<DailyLimitException>()));
    });

    test('own-key 429 is a different, non-limit error', () {
      expect(
          () => GeminiService.handleResponse(429, '{"error":{"message":"quota"}}', usesOwnKey: true),
          throwsA(predicate((e) => e is AiException && e is! DailyLimitException)));
    });

    test('bad key / unknown model / ok', () {
      expect(() => GeminiService.handleResponse(400, '{"error":{"message":"API key not valid"}}', usesOwnKey: true),
          throwsA(isA<AiException>()));
      expect(() => GeminiService.handleResponse(404, '{"error":{"message":"model"}}', usesOwnKey: true),
          throwsA(isA<AiException>()));
      expect(GeminiService.handleResponse(200, '{"candidates": []}', usesOwnKey: false), isA<Map>());
    });
  });

  test('English and Hindi UI strings have the same keys', () {
    expect(Strings.hi.keys.toSet(), Strings.en.keys.toSet());
  });
}

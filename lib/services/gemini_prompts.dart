/// All prompts + JSON schemas sent to Gemini, in one place.
///
/// We use Gemini "structured output" (responseMimeType: application/json +
/// responseSchema) so the model must answer in our exact JSON shape. The
/// parser in models/diagram.dart is still defensive in case a model ignores it.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/diagram.dart';

class GeminiPrompts {
  GeminiPrompts._();

  static Map<String, dynamic> _imagePart(Uint8List jpeg) => {
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(jpeg)}
      };

  static const _rect = {
    'type': 'OBJECT',
    'nullable': true,
    'properties': {
      'x': {'type': 'NUMBER'},
      'y': {'type': 'NUMBER'},
      'w': {'type': 'NUMBER'},
      'h': {'type': 'NUMBER'},
    },
    'required': ['x', 'y', 'w', 'h'],
  };

  /// Response schema for diagram understanding (feature 2).
  static const Map<String, dynamic> diagramSchema = {
    'type': 'OBJECT',
    'properties': {
      'is_diagram': {'type': 'BOOLEAN'},
      'reason': {'type': 'STRING'},
      'subject': {
        'type': 'STRING',
        'enum': ['Biology', 'Physics', 'Chemistry', 'Geography', 'Maths', 'Other']
      },
      'title': {'type': 'STRING'},
      'title_hi': {'type': 'STRING'},
      'body_bbox': _rect,
      'parts': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'name': {'type': 'STRING'},
            'label_text': {'type': 'STRING'},
            'point': {
              'type': 'OBJECT',
              'properties': {
                'x': {'type': 'NUMBER'},
                'y': {'type': 'NUMBER'},
              },
              'required': ['x', 'y'],
            },
            'label_bbox': _rect,
            'explain_en': {'type': 'STRING'},
            'explain_hi': {'type': 'STRING'},
          },
          'required': ['name', 'label_text', 'point', 'explain_en', 'explain_hi'],
        },
      },
      'arrows': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'from': {'type': 'STRING'},
            'to': {'type': 'STRING'},
            'label': {'type': 'STRING'},
          },
          'required': ['from', 'to'],
        },
      },
    },
    'required': ['is_diagram', 'reason', 'subject', 'title', 'title_hi', 'parts', 'arrows'],
  };

  static const String analyzeInstruction = '''
You are an expert Indian school science teacher (NCERT/CBSE classes 6-12).
The image is a student's phone photo of a diagram (from a textbook, a blackboard
or a hand sketch). It has already been cropped and whitened. UNDERSTAND the
diagram and describe it so an app can redraw clean, correctly spelled labels.

Rules:
- is_diagram: true only for an educational diagram whose parts can be labelled
  (cells, organs, flowers, circuits, ray diagrams, apparatus, earth layers, maps,
  cycles...). Selfies, plain text pages, random objects -> false.
- reason: one short sentence explaining the decision.
- title: standard English name (e.g. "Plant Cell"); title_hi: Hindi (Devanagari).
- body_bbox: tight box around the DRAWING ONLY. Exclude handwritten labels and
  label text that sit outside the drawing.
- parts: every labelled part. If the drawing has no labels, list the important
  parts a student must label (max 14). For each part:
  * name: correct standard NCERT spelling in Title case (fix spelling mistakes,
    e.g. "mitocondria" -> "Mitochondria"). If one label is clearly wrong for the
    part it points to, use the correct name.
  * label_text: exactly what is written in the image ("" if nothing).
  * point: a point ON the part itself, inside body_bbox, where a leader line
    should touch it.
  * label_bbox: tight box around the written label TEXT for this part (wherever
    it is, inside or outside the drawing) so the app can erase it; null if the
    part has no written label.
  * explain_en: one simple sentence (max 18 words) for a class 9 student.
  * explain_hi: the same in simple Hindi (Devanagari); common English science
    words may stay in English.
- arrows: for flow / process / cycle diagrams, the direction between parts
  ({from, to, label}); otherwise [].
- Coordinates are normalised: x 0 = left edge, 1 = right edge; y 0 = top,
  1 = bottom of the image.
''';

  /// Body for feature 2 (analyse a diagram photo).
  static Map<String, dynamic> analyzeBody(Uint8List jpeg) => {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': analyzeInstruction},
              _imagePart(jpeg),
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
          'responseSchema': diagramSchema,
        },
      };

  static const Map<String, dynamic> checkSchema = {
    'type': 'OBJECT',
    'properties': {
      'total': {'type': 'INTEGER'},
      'score': {'type': 'INTEGER'},
      'found': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'missing': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'misplaced': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'feedback_en': {'type': 'STRING'},
      'feedback_hi': {'type': 'STRING'},
    },
    'required': ['total', 'score', 'found', 'missing', 'misplaced', 'feedback_en', 'feedback_hi'],
  };

  /// Body for feature 11 ("Meri drawing check karo").
  static Map<String, dynamic> checkDrawingBody(Uint8List jpeg, DiagramResult ref) {
    final parts = ref.parts.map((p) => p.name).toList();
    final prompt = '''
You are a kind Indian school teacher checking a student's own drawing of
"${ref.title}". Reference part list (from a correct diagram): ${jsonEncode(parts)}.
Look at the student's photo and judge, for each reference part, whether it is
drawn AND labelled in roughly the right position.
- total = ${parts.length}; score = number of parts drawn and labelled correctly.
- found: parts done right; missing: parts not drawn or not labelled;
  misplaced: parts labelled but in a clearly wrong place, written as
  "<part> - <short hint>".
- feedback_en / feedback_hi: 2 short encouraging sentences (Hindi in Devanagari)
  that praise one good thing and give the single most useful tip.
If the photo is not a drawing of this diagram, score 0 and say so kindly.''';
    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            _imagePart(jpeg),
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
        'responseSchema': checkSchema,
      },
    };
  }

  /// Body for feature 13 (voice question). Text-only = cheap & fast.
  static Map<String, dynamic> askBody(DiagramResult d, String question, {required bool hindi}) {
    final ctx = d.parts.map((p) => '- ${p.name}: ${p.explainEn}').join('\n');
    final prompt = '''
A school student is looking at a diagram of "${d.title}" (${d.subject}) with
these labelled parts:
$ctx
The student asks: "$question"
Answer in ${hindi ? 'simple Hindi (Devanagari script)' : 'simple English'} in at
most 2 short sentences, suitable for reading aloud. No markdown, no lists.
If the question is not about this diagram, gently say you can only help with it.''';
    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 2048},
    };
  }

  /// Body for explaining a label the student added manually.
  static Map<String, dynamic> explainPartBody(String title, String part) => {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'In a school diagram of "$title", explain the part "$part" in one simple '
                    'sentence (max 18 words) for a class 9 student. Return JSON with explain_en and '
                    'explain_hi (simple Hindi, Devanagari).'
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'explain_en': {'type': 'STRING'},
              'explain_hi': {'type': 'STRING'},
            },
            'required': ['explain_en', 'explain_hi'],
          },
        },
      };
}

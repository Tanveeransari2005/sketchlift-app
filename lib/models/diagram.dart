/// Data model for an "understood" diagram, plus robust JSON parsing.
///
/// Gemini is asked to return a strict JSON schema (see
/// `services/gemini_prompts.dart`). Real model output can still be messy
/// (code fences, 0-1000 coordinates instead of 0-1, missing fields), so every
/// `fromJson` here is defensive: it never throws on a missing optional field
/// and clamps coordinates into the 0..1 range.
library;

import 'dart:convert';
import 'dart:math' as math;

/// A point in normalised image coordinates (0..1 on both axes, origin top-left).
class NPoint {
  final double x;
  final double y;
  const NPoint(this.x, this.y);

  factory NPoint.fromJson(Object? j) {
    if (j is Map) {
      return NPoint(_coord(j['x']), _coord(j['y']));
    }
    if (j is List && j.length >= 2) {
      // Some models answer [y, x] in 0-1000 ("box_2d" style); we ask for
      // {x, y} but accept a 2-list as [x, y].
      return NPoint(_coord(j[0]), _coord(j[1]));
    }
    return const NPoint(0.5, 0.5);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

/// A rectangle in normalised coordinates.
class NRect {
  final double x, y, w, h;
  const NRect(this.x, this.y, this.w, this.h);

  double get right => x + w;
  double get bottom => y + h;
  NPoint get center => NPoint(x + w / 2, y + h / 2);

  static NRect? tryParse(Object? j) {
    if (j is Map) {
      if (j.containsKey('w') || j.containsKey('width')) {
        final x = _coord(j['x']), y = _coord(j['y']);
        final w = _coord(j['w'] ?? j['width']), h = _coord(j['h'] ?? j['height']);
        if (w <= 0 || h <= 0) return null;
        return NRect(x, y, math.min(w, 1 - x), math.min(h, 1 - y));
      }
      if (j.containsKey('x1') || j.containsKey('xmin')) {
        final x1 = _coord(j['x1'] ?? j['xmin']), y1 = _coord(j['y1'] ?? j['ymin']);
        final x2 = _coord(j['x2'] ?? j['xmax']), y2 = _coord(j['y2'] ?? j['ymax']);
        if (x2 <= x1 || y2 <= y1) return null;
        return NRect(x1, y1, x2 - x1, y2 - y1);
      }
    }
    if (j is List && j.length == 4) {
      // Gemini's native "box_2d" convention: [ymin, xmin, ymax, xmax] in 0-1000.
      final v = j.map(_coord).toList();
      if (v[3] <= v[1] || v[2] <= v[0]) return null;
      return NRect(v[1], v[0], v[3] - v[1], v[2] - v[0]);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

/// Converts any numeric-ish value to a 0..1 coordinate.
/// Values in (1, 1000] are treated as Gemini's 0-1000 scale; values in
/// (1, 100] with a '%' string as percentages.
double _coord(Object? v) {
  double d;
  if (v is num) {
    d = v.toDouble();
  } else if (v is String) {
    final s = v.trim();
    final isPct = s.endsWith('%');
    d = double.tryParse(s.replaceAll('%', '')) ?? 0.5;
    if (isPct) d /= 100;
  } else {
    return 0.5;
  }
  if (d.isNaN) return 0.5;
  if (d > 1.0001) d = d / 1000.0; // 0-1000 scale
  return d.clamp(0.0, 1.0);
}

/// One labelled part of the diagram.
class DiagramPart {
  /// Canonical, correctly spelled part name (shown on the clean diagram).
  String name;

  /// What was literally written on the photo (may be misspelled / empty).
  final String labelText;

  /// Where the leader line should point (on the part itself).
  final NPoint anchor;

  /// Box around the old handwritten label inside the photo — we paint it white.
  final NRect? labelBox;

  /// One-line explanations.
  String explainEn;
  String explainHi;

  DiagramPart({
    required this.name,
    this.labelText = '',
    required this.anchor,
    this.labelBox,
    this.explainEn = '',
    this.explainHi = '',
  });

  factory DiagramPart.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? j['label_text'] ?? '').toString().trim();
    return DiagramPart(
      name: name,
      labelText: (j['label_text'] ?? '').toString().trim(),
      anchor: NPoint.fromJson(j['point'] ?? j['label_anchor'] ?? j['anchor']),
      labelBox: NRect.tryParse(j['label_bbox'] ?? j['bbox']),
      explainEn: (j['explain_en'] ?? j['explanation_en'] ?? '').toString().trim(),
      explainHi: (j['explain_hi'] ?? j['explanation_hi'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'label_text': labelText,
        'point': anchor.toJson(),
        if (labelBox != null) 'label_bbox': labelBox!.toJson(),
        'explain_en': explainEn,
        'explain_hi': explainHi,
      };

  String explain(bool hindi) =>
      hindi ? (explainHi.isNotEmpty ? explainHi : explainEn) : (explainEn.isNotEmpty ? explainEn : explainHi);
}

/// A directed relation between two parts (e.g. "Mouth → Oesophagus").
class DiagramArrow {
  final String from;
  final String to;
  final String label;
  const DiagramArrow(this.from, this.to, [this.label = '']);

  factory DiagramArrow.fromJson(Map<String, dynamic> j) => DiagramArrow(
      (j['from'] ?? '').toString(), (j['to'] ?? '').toString(), (j['label'] ?? '').toString());

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'label': label};
}

/// Everything Gemini understood about one photo.
class DiagramResult {
  final bool isDiagram;
  final String reason;
  String subject;
  String title;
  String titleHi;

  /// Box around the drawing itself (labels outside it get erased).
  final NRect? bodyBox;
  final List<DiagramPart> parts;
  final List<DiagramArrow> arrows;

  DiagramResult({
    required this.isDiagram,
    this.reason = '',
    this.subject = 'Other',
    this.title = 'Diagram',
    this.titleHi = '',
    this.bodyBox,
    List<DiagramPart>? parts,
    List<DiagramArrow>? arrows,
  })  : parts = parts ?? [],
        arrows = arrows ?? [];

  factory DiagramResult.fromJson(Map<String, dynamic> j) {
    final isDiag = j['is_diagram'];
    bool isDiagram;
    if (isDiag is bool) {
      isDiagram = isDiag;
    } else if (isDiag is Map) {
      // Accept {"value": true, "reason": "..."} as well.
      isDiagram = isDiag['value'] == true;
    } else {
      isDiagram = isDiag.toString().toLowerCase() == 'true';
    }
    final reason = (j['reason'] ?? (isDiag is Map ? isDiag['reason'] : '') ?? '').toString();
    final parts = <DiagramPart>[];
    for (final p in (j['parts'] as List? ?? const [])) {
      if (p is Map) {
        final part = DiagramPart.fromJson(p.cast<String, dynamic>());
        if (part.name.isNotEmpty) parts.add(part);
      }
    }
    final arrows = <DiagramArrow>[];
    for (final a in (j['arrows'] as List? ?? const [])) {
      if (a is Map) arrows.add(DiagramArrow.fromJson(a.cast<String, dynamic>()));
    }
    return DiagramResult(
      isDiagram: isDiagram,
      reason: reason,
      subject: _subject((j['subject'] ?? 'Other').toString()),
      title: (j['title'] ?? 'Diagram').toString().trim(),
      titleHi: (j['title_hi'] ?? '').toString().trim(),
      bodyBox: NRect.tryParse(j['body_bbox']),
      parts: parts,
      arrows: arrows,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_diagram': isDiagram,
        'reason': reason,
        'subject': subject,
        'title': title,
        'title_hi': titleHi,
        if (bodyBox != null) 'body_bbox': bodyBox!.toJson(),
        'parts': parts.map((p) => p.toJson()).toList(),
        'arrows': arrows.map((a) => a.toJson()).toList(),
      };

  /// Parses raw model text: strips ```json fences and finds the JSON object.
  static DiagramResult parseModelText(String text) =>
      DiagramResult.fromJson(extractJsonObject(text));

  static const subjects = ['Biology', 'Physics', 'Chemistry', 'Geography', 'Maths', 'Other'];

  static String _subject(String s) {
    final l = s.toLowerCase();
    for (final sub in subjects) {
      if (l.contains(sub.toLowerCase())) return sub;
    }
    if (l.contains('science')) return 'Biology';
    return 'Other';
  }
}

/// Finds the first complete JSON object inside [text] (handles code fences
/// and chatter before/after the JSON). Throws [FormatException] if none.
Map<String, dynamic> extractJsonObject(String text) {
  var t = text.trim();
  // Strip markdown fences like ```json ... ```
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
  final m = fence.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  final start = t.indexOf('{');
  if (start < 0) throw const FormatException('No JSON object in model output');
  // Walk braces (respecting strings) to find the matching close brace.
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < t.length; i++) {
    final c = t[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c == r'\') {
        esc = true;
      } else if (c == '"') {
        inStr = false;
      }
      continue;
    }
    if (c == '"') inStr = true;
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        final decoded = jsonDecode(t.substring(start, i + 1));
        if (decoded is Map<String, dynamic>) return decoded;
        throw const FormatException('JSON is not an object');
      }
    }
  }
  throw const FormatException('Unterminated JSON object in model output');
}

/// Result of "Meri drawing check karo".
class DrawingCheck {
  final int score;
  final int total;
  final List<String> found;
  final List<String> missing;
  final List<String> misplaced;
  final String feedbackEn;
  final String feedbackHi;

  const DrawingCheck({
    required this.score,
    required this.total,
    this.found = const [],
    this.missing = const [],
    this.misplaced = const [],
    this.feedbackEn = '',
    this.feedbackHi = '',
  });

  factory DrawingCheck.fromJson(Map<String, dynamic> j) {
    List<String> list(Object? v) =>
        (v is List ? v : const []).map((e) => e is Map ? (e['name'] ?? '').toString() : e.toString()).where((s) => s.isNotEmpty).toList();
    final found = list(j['found']);
    final missing = list(j['missing']);
    final misplaced = list(j['misplaced']);
    final total = (j['total'] as num?)?.toInt() ?? (found.length + missing.length);
    var score = (j['score'] as num?)?.toInt() ?? found.length;
    score = score.clamp(0, total < 0 ? 0 : total);
    return DrawingCheck(
      score: score,
      total: total,
      found: found,
      missing: missing,
      misplaced: misplaced,
      feedbackEn: (j['feedback_en'] ?? '').toString(),
      feedbackHi: (j['feedback_hi'] ?? '').toString(),
    );
  }
}

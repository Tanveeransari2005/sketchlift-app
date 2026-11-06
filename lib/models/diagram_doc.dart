/// A diagram the app is working with: the AI result + the cleaned picture.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'diagram.dart';

class DiagramDoc {
  int? id;
  DiagramResult result;

  /// Cleaned PNG of just the diagram body (old labels erased).
  Uint8List bodyPng;

  /// Which part of the processed photo [bodyPng] covers (normalised), used to
  /// convert the AI's anchor points into body coordinates.
  NRect usedBody;
  String chapter;
  DateTime createdAt;

  DiagramDoc({
    this.id,
    required this.result,
    required this.bodyPng,
    required this.usedBody,
    this.chapter = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get title => result.title;
  String get subject => result.subject;

  /// Anchor of part [i] relative to the body picture (0..1).
  Offset anchorInBody(int i) {
    final a = result.parts[i].anchor;
    return Offset(
      ((a.x - usedBody.x) / usedBody.w).clamp(0.0, 1.0),
      ((a.y - usedBody.y) / usedBody.h).clamp(0.0, 1.0),
    );
  }

  /// Adds a label at [bodyPoint] (0..1 within the body picture).
  void addPart(String name, Offset bodyPoint) {
    result.parts.add(DiagramPart(
      name: name,
      anchor: NPoint(usedBody.x + bodyPoint.dx * usedBody.w, usedBody.y + bodyPoint.dy * usedBody.h),
    ));
  }

  /// JSON stored in the database (the PNG is stored as a file).
  String encodeMeta() => jsonEncode({'result': result.toJson(), 'used_body': usedBody.toJson()});

  static (DiagramResult, NRect) decodeMeta(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return (
      DiagramResult.fromJson((j['result'] as Map).cast<String, dynamic>()),
      NRect.tryParse(j['used_body']) ?? const NRect(0, 0, 1, 1),
    );
  }
}

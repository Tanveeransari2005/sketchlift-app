/// End-to-end: photo → cleaned picture → Gemini → spell-fix → DiagramDoc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/diagram.dart';
import '../models/diagram_doc.dart';
import 'gemini_service.dart';
import 'glossary.dart';
import 'image_pipeline.dart';

/// The photo did not look like a diagram (feature 2: "Ye diagram nahi lag raha").
class NotADiagramException implements Exception {
  final String reason;
  const NotADiagramException(this.reason);
}

class DiagramPipeline {
  DiagramPipeline._();

  /// Step 1: clean the photo (isolate). [corners] = tl,tr,br,bl normalised.
  static Future<Uint8List> clean(Uint8List raw, {List<double>? corners, bool bw = false}) =>
      compute(processPhoto, ProcessRequest(raw, corners: corners, blackAndWhite: bw));

  /// Steps 2-4: ask Gemini, fix spellings, erase old labels, build the doc.
  static Future<DiagramDoc> understand(GeminiService ai, Uint8List processedPng) async {
    final jpeg = await compute(toUploadJpeg, processedPng);
    final result = await ai.analyzeDiagram(jpeg);
    return finish(result, processedPng);
  }

  /// Shared tail used by the real path and the offline demo.
  static Future<DiagramDoc> finish(DiagramResult result, Uint8List processedPng) async {
    if (!result.isDiagram || result.parts.isEmpty) {
      throw NotADiagramException(result.reason);
    }
    applyGlossary(result);
    final body = result.bodyBox;
    // Erase every old handwritten label (ones outside the body are cropped too).
    final boxes = [for (final p in result.parts) if (p.labelBox != null) p.labelBox!];
    final cleaned = await compute(cleanBody, CleanBodyRequest(processedPng, body, boxes));
    return DiagramDoc(result: result, bodyPng: cleaned.png, usedBody: cleaned.usedBody);
  }

  /// Feature 3: snap every label to the closest glossary term.
  static void applyGlossary(DiagramResult r) {
    for (final p in r.parts) {
      p.name = Glossary.fix(p.name.isNotEmpty ? p.name : p.labelText, subject: r.subject);
    }
  }

  /// Offline demo: a bundled photo + a recorded Gemini answer, so the app can
  /// be shown without internet or quota. Runs the REAL image pipeline.
  static Future<DiagramDoc> demo() async {
    final raw = (await rootBundle.load('assets/demo/plant_cell_photo.jpg')).buffer.asUint8List();
    final json = await rootBundle.loadString('assets/demo/plant_cell_gemini.json');
    final processed = await clean(raw);
    final result = DiagramResult.parseModelText(json);
    return finish(result, processed);
  }
}

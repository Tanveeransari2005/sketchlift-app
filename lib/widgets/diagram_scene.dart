/// Draws a clean diagram: the cleaned picture + crisp vector labels.
///
/// The same [DiagramScene] is used for the on-screen view (CustomPainter) and
/// for exporting PNG/PDF (PictureRecorder), so what you see is what you print.
/// Labels are real text drawn by Flutter (not pixels), so they stay sharp when
/// you zoom.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/diagram_doc.dart';
import '../services/label_layout.dart';
import '../theme.dart';

enum DiagramMode { labelled, practice }

class DiagramScene {
  DiagramScene._(this.doc, this.mode, this.layout, this.texts, this.numberTexts);

  final DiagramDoc doc;
  final DiagramMode mode;
  final LayoutResult layout;
  final List<TextPainter?> texts; // null in practice mode
  final List<TextPainter> numberTexts;

  // Sizes are in "canvas units"; the view scales the whole canvas to fit.
  static const double bodyLongSide = 760;
  static const double fontSize = 26;
  static const double badgeR = 18;
  static const double maxTextWidth = 280;
  static const double practiceBoxWidth = 190;

  Size get size => layout.canvasSize;

  /// Measures every label and runs the placement engine.
  static DiagramScene build(DiagramDoc doc, Size imageSize, DiagramMode mode) {
    final s = bodyLongSide / math.max(imageSize.width, imageSize.height);
    final bodySize = Size(imageSize.width * s, imageSize.height * s);
    final parts = doc.result.parts;
    final texts = <TextPainter?>[];
    final sizes = <Size>[];
    final anchors = <Offset>[];
    for (var i = 0; i < parts.length; i++) {
      anchors.add(doc.anchorInBody(i));
      if (mode == DiagramMode.labelled) {
        final tp = TextPainter(
          text: TextSpan(text: parts[i].name, style: labelStyle),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: maxTextWidth);
        texts.add(tp);
        sizes.add(Size(badgeR * 2 + 8 + tp.width + 8, math.max(badgeR * 2 + 4, tp.height + 8)));
      } else {
        texts.add(null);
        sizes.add(const Size(badgeR * 2 + 8 + practiceBoxWidth, badgeR * 2 + 8));
      }
    }
    final layout = LabelLayout.compute(bodySize: bodySize, anchors: anchors, labelSizes: sizes);
    final numbers = [
      for (final p in layout.placements)
        TextPainter(
          text: TextSpan(text: '${p.number}', style: numberStyle),
          textDirection: TextDirection.ltr,
        )..layout()
    ];
    return DiagramScene._(doc, mode, layout, texts, numbers);
  }

  static const labelStyle = TextStyle(
      fontFamily: 'Poppins', fontFamilyFallback: ['Roboto'], fontSize: fontSize, fontWeight: FontWeight.w500, color: Color(0xFF1F2340), height: 1.15);
  static const numberStyle =
      TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white);

  /// Paints at canvas-unit scale (caller applies any extra scaling).
  void paint(Canvas canvas, ui.Image? image, {int? selected, bool background = true}) {
    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    }
    final body = layout.bodyRect;
    if (image != null) {
      paintImage(canvas: canvas, rect: body, image: image, filterQuality: FilterQuality.high, fit: BoxFit.fill);
    }
    final line = Paint()
      ..color = Brand.ink.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = Brand.ink;

    // Leader lines first (under the labels).
    for (final p in layout.placements) {
      final end = p.attach;
      // A short horizontal "elbow" next to the label looks tidier than a
      // single diagonal line, like textbook diagrams.
      final elbowX = p.side == LabelSide.left ? end.dx + 14 : end.dx - 14;
      final path = Path()
        ..moveTo(p.anchor.dx, p.anchor.dy)
        ..lineTo(elbowX, end.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, line..color = (p.index == selected ? Brand.green : Brand.ink.withValues(alpha: 0.85)));
      canvas.drawCircle(p.anchor, 3.6, dot);
      canvas.drawCircle(p.anchor, 1.6, Paint()..color = Colors.white);
    }

    for (var k = 0; k < layout.placements.length; k++) {
      final p = layout.placements[k];
      final r = p.rect;
      final isSel = p.index == selected;
      if (isSel) {
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(10)),
            Paint()..color = Brand.green.withValues(alpha: 0.14));
      }
      // Badge sits on the side facing the diagram so numbers line up.
      final badgeCenter = p.side == LabelSide.left
          ? Offset(r.right - badgeR, r.center.dy)
          : Offset(r.left + badgeR, r.center.dy);
      canvas.drawCircle(badgeCenter, badgeR, Paint()..color = isSel ? Brand.green : Brand.indigo);
      final nt = numberTexts[k];
      nt.paint(canvas, badgeCenter - Offset(nt.width / 2, nt.height / 2));

      final textLeft = p.side == LabelSide.left ? r.left : r.left + badgeR * 2 + 8;
      final textRight = p.side == LabelSide.left ? r.right - badgeR * 2 - 8 : r.right;
      if (mode == DiagramMode.labelled) {
        final tp = texts[p.index]!;
        final x = p.side == LabelSide.left ? textRight - tp.width - 2 : textLeft + 2;
        tp.paint(canvas, Offset(x, r.center.dy - tp.height / 2));
      } else {
        final box = Rect.fromLTRB(textLeft, r.top + 3, textRight - 2, r.bottom - 3);
        canvas.drawRRect(
            RRect.fromRectAndRadius(box, const Radius.circular(6)),
            Paint()
              ..color = Brand.ink.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3);
      }
    }
  }

  /// Which label (part index) is at [pt] (canvas units), if any.
  int? hitTest(Offset pt) {
    for (final p in layout.placements) {
      if (p.rect.inflate(6).contains(pt)) return p.index;
    }
    var best = -1;
    var bestD = 22.0;
    for (final p in layout.placements) {
      final d = (p.anchor - pt).distance;
      if (d < bestD) {
        bestD = d;
        best = p.index;
      }
    }
    return best >= 0 ? best : null;
  }

  /// Converts a canvas point to a 0..1 point in the body (for "add label").
  Offset? toBody(Offset pt) {
    final b = layout.bodyRect;
    if (!b.contains(pt)) return null;
    return Offset((pt.dx - b.left) / b.width, (pt.dy - b.top) / b.height);
  }

  /// Renders to PNG at [pixelRatio] with an optional title band on top.
  Future<ui.Image> toImage(ui.Image image, {double pixelRatio = 2.5, String? title}) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final titleH = title == null ? 0.0 : 64.0;
    final total = Size(size.width, size.height + titleH);
    c.scale(pixelRatio);
    c.drawRect(Offset.zero & total, Paint()..color = Colors.white);
    if (title != null) {
      final tp = TextPainter(
        text: TextSpan(
            text: title,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w600, color: Brand.ink)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: total.width - 40);
      tp.paint(c, Offset((total.width - tp.width) / 2, 18));
      c.translate(0, titleH);
    }
    paint(c, image, background: false);
    final pic = rec.endRecording();
    return pic.toImage((total.width * pixelRatio).ceil(), (total.height * pixelRatio).ceil());
  }
}

/// CustomPainter wrapper used by the on-screen view.
class DiagramPainter extends CustomPainter {
  DiagramPainter(this.scene, this.image, {this.selected});
  final DiagramScene scene;
  final ui.Image? image;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / scene.size.width;
    canvas.save();
    canvas.scale(s);
    scene.paint(canvas, image, selected: selected);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DiagramPainter old) =>
      old.scene != scene || old.image != image || old.selected != selected;
}

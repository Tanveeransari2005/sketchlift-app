import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchlift/services/label_layout.dart';

/// Checks every rule the placement engine promises.
void expectValidLayout(LayoutResult r, int n) {
  expect(r.placements.length, n);
  final canvas = Offset.zero & r.canvasSize;
  for (final p in r.placements) {
    // 1. labels never cover the diagram body
    expect(p.rect.overlaps(r.bodyRect), isFalse, reason: 'label ${p.index} overlaps the body');
    // 2. labels stay on the canvas
    expect(canvas.inflate(0.001).contains(p.rect.topLeft) && canvas.inflate(0.001).contains(p.rect.bottomRight), isTrue,
        reason: 'label ${p.index} is off-canvas: ${p.rect} vs $canvas');
    // 3. anchor is on the body
    expect(r.bodyRect.inflate(0.001).contains(p.anchor), isTrue);
  }
  // 4. no two labels overlap
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final a = r.placements[i].rect, b = r.placements[j].rect;
      expect(a.overlaps(b), isFalse, reason: 'labels $i and $j overlap: $a $b');
    }
  }
  // 5. numbers are a permutation of 1..n
  expect(r.placements.map((p) => p.number).toSet(), {for (var i = 1; i <= n; i++) i});
}

void main() {
  group('clockwise numbering', () {
    test('starts at 12 o\'clock and goes clockwise', () {
      final anchors = [
        const Offset(0.2, 0.5), // 9 o'clock  -> 4
        const Offset(0.5, 0.1), // 12 o'clock -> 1
        const Offset(0.5, 0.9), // 6 o'clock  -> 3
        const Offset(0.9, 0.5), // 3 o'clock  -> 2
      ];
      expect(LabelLayout.clockwiseNumbers(anchors), [4, 1, 3, 2]);
    });

    test('empty input', () {
      expect(LabelLayout.clockwiseNumbers(const []), isEmpty);
    });
  });

  group('placement', () {
    test('plant-cell-like layout is valid', () {
      final anchors = [
        const Offset(0.40, 0.48), const Offset(0.52, 0.51), const Offset(0.38, 0.63),
        const Offset(0.52, 0.70), const Offset(0.61, 0.28), const Offset(0.63, 0.48), const Offset(0.67, 0.62),
      ];
      final sizes = List.generate(anchors.length, (i) => Size(90 + 12.0 * i, 30));
      final r = LabelLayout.compute(bodySize: const Size(500, 400), anchors: anchors, labelSizes: sizes);
      expectValidLayout(r, anchors.length);
    });

    test('many labels clustered at one point still do not overlap', () {
      final anchors = List.generate(14, (i) => const Offset(0.5, 0.5));
      final sizes = List.generate(14, (_) => const Size(140, 32));
      final r = LabelLayout.compute(bodySize: const Size(300, 200), anchors: anchors, labelSizes: sizes);
      expectValidLayout(r, 14);
      // Canvas grew taller than the body to fit the columns.
      expect(r.canvasSize.height, greaterThan(200));
    });

    test('random layouts are always valid (property test)', () {
      final rnd = math.Random(42);
      for (var t = 0; t < 200; t++) {
        final n = 1 + rnd.nextInt(16);
        final anchors = List.generate(n, (_) => Offset(rnd.nextDouble(), rnd.nextDouble()));
        final sizes = List.generate(n, (_) => Size(40 + rnd.nextDouble() * 200, 24 + rnd.nextDouble() * 30));
        final body = Size(150 + rnd.nextDouble() * 600, 150 + rnd.nextDouble() * 600);
        final r = LabelLayout.compute(bodySize: body, anchors: anchors, labelSizes: sizes);
        expectValidLayout(r, n);
      }
    });

    test('labels on a side keep the vertical order of their anchors', () {
      final anchors = [const Offset(0.9, 0.1), const Offset(0.9, 0.5), const Offset(0.9, 0.9), const Offset(0.1, 0.5)];
      final sizes = List.generate(4, (_) => const Size(100, 30));
      final r = LabelLayout.compute(bodySize: const Size(400, 400), anchors: anchors, labelSizes: sizes);
      final right = r.placements.where((p) => p.side == LabelSide.right).toList()
        ..sort((a, b) => a.anchor.dy.compareTo(b.anchor.dy));
      for (var i = 1; i < right.length; i++) {
        expect(right[i].rect.top, greaterThan(right[i - 1].rect.top));
      }
    });

    test('labels stay near their anchors when there is room', () {
      final anchors = [const Offset(0.95, 0.2), const Offset(0.95, 0.8)];
      final sizes = List.generate(2, (_) => const Size(100, 30));
      final r = LabelLayout.compute(bodySize: const Size(400, 400), anchors: anchors, labelSizes: sizes);
      for (final p in r.placements) {
        expect((p.rect.center.dy - p.anchor.dy).abs(), lessThan(1.0));
      }
    });

    test('sides are balanced', () {
      final anchors = List.generate(8, (i) => Offset(0.9, 0.1 + i * 0.1)); // all on the right
      final sizes = List.generate(8, (_) => const Size(100, 30));
      final r = LabelLayout.compute(bodySize: const Size(400, 400), anchors: anchors, labelSizes: sizes);
      final left = r.placements.where((p) => p.side == LabelSide.left).length;
      expect((left - (8 - left)).abs(), lessThanOrEqualTo(1));
    });
  });
}

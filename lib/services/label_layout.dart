/// Label placement engine.
///
/// Problem: given the diagram body (a picture) and N anchor points on it, put
/// N text labels AROUND the picture so that
///   * no label covers the diagram body,
///   * no two labels overlap,
///   * each label stays close to the height of the part it names, and
///   * leader lines rarely cross (labels on one side keep their anchors' order).
///
/// Approach — "two columns + 1-D sweep" (a greedy method, O(n log n)):
///   1. Number the parts clockwise starting at 12 o'clock around the body
///      centre (exam style: 1 at the top, then going right / down).
///   2. Put every label in the LEFT or RIGHT column, depending on which half of
///      the body its anchor lies in. If one side gets much more crowded, the
///      anchors closest to the vertical centre line move to the other side.
///   3. In each column, every label "wants" to sit vertically centred on its
///      anchor. Sort by that wish, then sweep top→bottom pushing each label down
///      just enough to clear the one above (forward pass). If the column now
///      overflows the bottom, sweep bottom→top pulling labels up (backward pass)
///      and finally clamp to the top. Order never changes → no crossings among
///      neighbours, and every label stays as close to its wish as possible.
///   4. The canvas grows to fit: margins are as wide as the widest label of each
///      column, and the height is max(body, tallest column). So there is never
///      overflow and nothing is clipped.
///
/// Pure Dart (only dart:ui geometry types) so it is unit-tested in
/// test/label_layout_test.dart.
library;

import 'dart:math' as math;
import 'dart:ui';

enum LabelSide { left, right }

class LabelPlacement {
  /// Index into the input lists.
  final int index;

  /// Clockwise number shown in the badge (1-based).
  final int number;
  final LabelSide side;

  /// Where the label box is drawn (canvas coordinates).
  final Rect rect;

  /// Where the leader line starts (on the diagram, canvas coordinates).
  final Offset anchor;

  const LabelPlacement({
    required this.index,
    required this.number,
    required this.side,
    required this.rect,
    required this.anchor,
  });

  /// Point on the label edge facing the diagram — where the leader line ends.
  Offset get attach =>
      side == LabelSide.left ? Offset(rect.right, rect.center.dy) : Offset(rect.left, rect.center.dy);
}

class LayoutResult {
  final Size canvasSize;
  final Rect bodyRect;
  final List<LabelPlacement> placements; // in input order

  const LayoutResult(this.canvasSize, this.bodyRect, this.placements);

  /// Placements sorted by their clockwise number.
  List<LabelPlacement> get byNumber => [...placements]..sort((a, b) => a.number.compareTo(b.number));
}

class LabelLayout {
  LabelLayout._();

  /// Clockwise order of [anchors] (normalised 0..1 points inside the body),
  /// starting at 12 o'clock. Returns, for each input index, its 1-based number.
  static List<int> clockwiseNumbers(List<Offset> anchors) {
    if (anchors.isEmpty) return const [];
    final c = _centroidOfBox(anchors);
    final idx = List<int>.generate(anchors.length, (i) => i);
    double angle(Offset p) {
      // atan2(dx, -dy): 0 at 12 o'clock, increasing clockwise (y points down).
      // +15° so a part sitting just left of "12" still counts as number 1.
      final a = math.atan2(p.dx - c.dx, -(p.dy - c.dy)) + math.pi / 12;
      return a < 0 ? a + 2 * math.pi : (a >= 2 * math.pi ? a - 2 * math.pi : a);
    }

    idx.sort((a, b) {
      final d = angle(anchors[a]).compareTo(angle(anchors[b]));
      return d != 0 ? d : anchors[a].dy.compareTo(anchors[b].dy);
    });
    final numbers = List<int>.filled(anchors.length, 0);
    for (var k = 0; k < idx.length; k++) {
      numbers[idx[k]] = k + 1;
    }
    return numbers;
  }

  /// Computes the full layout.
  ///
  /// [bodySize]   size the diagram picture is drawn at.
  /// [anchors]    normalised (0..1) anchor points relative to the body.
  /// [labelSizes] measured size of each label box (badge + text).
  /// [gap]        horizontal space between body and label column (leader room).
  /// [spacing]    minimum vertical space between two labels.
  /// [padding]    outer canvas padding.
  static LayoutResult compute({
    required Size bodySize,
    required List<Offset> anchors,
    required List<Size> labelSizes,
    double gap = 36,
    double spacing = 8,
    double padding = 16,
  }) {
    assert(anchors.length == labelSizes.length);
    final n = anchors.length;
    final numbers = clockwiseNumbers(anchors);

    // ---- 1. side assignment -------------------------------------------------
    final c = n == 0 ? const Offset(0.5, 0.5) : _centroidOfBox(anchors);
    final sides = List<LabelSide>.generate(
        n, (i) => anchors[i].dx < c.dx ? LabelSide.left : LabelSide.right);
    _balanceSides(sides, anchors, c.dx);

    // ---- 2. canvas geometry -------------------------------------------------
    double colWidth(LabelSide s) {
      var w = 0.0;
      for (var i = 0; i < n; i++) {
        if (sides[i] == s) w = math.max(w, labelSizes[i].width);
      }
      return w;
    }

    double colHeight(LabelSide s) {
      var h = 0.0;
      var count = 0;
      for (var i = 0; i < n; i++) {
        if (sides[i] == s) {
          h += labelSizes[i].height;
          count++;
        }
      }
      return h + math.max(0, count - 1) * spacing;
    }

    final leftW = colWidth(LabelSide.left);
    final rightW = colWidth(LabelSide.right);
    final leftMargin = padding + (leftW > 0 ? leftW + gap : 0);
    final rightMargin = padding + (rightW > 0 ? rightW + gap : 0);
    final contentH = math.max(bodySize.height, math.max(colHeight(LabelSide.left), colHeight(LabelSide.right)));
    final canvas = Size(leftMargin + bodySize.width + rightMargin, contentH + 2 * padding);
    final body = Rect.fromLTWH(leftMargin, padding + (contentH - bodySize.height) / 2, bodySize.width, bodySize.height);

    Offset toCanvas(Offset p) =>
        Offset(body.left + p.dx.clamp(0.0, 1.0) * body.width, body.top + p.dy.clamp(0.0, 1.0) * body.height);

    // ---- 3. 1-D sweep per column -------------------------------------------
    final tops = List<double>.filled(n, 0);
    for (final side in LabelSide.values) {
      final members = [for (var i = 0; i < n; i++) if (sides[i] == side) i];
      if (members.isEmpty) continue;
      final wish = {for (final i in members) i: toCanvas(anchors[i]).dy - labelSizes[i].height / 2};
      members.sort((a, b) {
        final d = wish[a]!.compareTo(wish[b]!);
        return d != 0 ? d : numbers[a].compareTo(numbers[b]);
      });
      final minTop = padding;
      final maxBottom = canvas.height - padding;
      // Forward pass: push down to clear the previous label.
      var cursor = minTop;
      for (final i in members) {
        final y = math.max(wish[i]!, cursor);
        tops[i] = y;
        cursor = y + labelSizes[i].height + spacing;
      }
      // Backward pass: pull up if we fell off the bottom.
      var limit = maxBottom;
      for (final i in members.reversed) {
        final y = math.min(tops[i], limit - labelSizes[i].height);
        tops[i] = y;
        limit = y - spacing;
      }
      // Final clamp to the top (only matters if the column is exactly full).
      cursor = minTop;
      for (final i in members) {
        tops[i] = math.max(tops[i], cursor);
        cursor = tops[i] + labelSizes[i].height + spacing;
      }
    }

    // ---- 4. build placements ------------------------------------------------
    final placements = <LabelPlacement>[];
    for (var i = 0; i < n; i++) {
      final s = labelSizes[i];
      final left = sides[i] == LabelSide.left
          ? body.left - gap - s.width // right-aligned against the body
          : body.right + gap;
      placements.add(LabelPlacement(
        index: i,
        number: numbers[i],
        side: sides[i],
        rect: Rect.fromLTWH(left, tops[i], s.width, s.height),
        anchor: toCanvas(anchors[i]),
      ));
    }
    return LayoutResult(canvas, body, placements);
  }

  /// If one side has 2+ more labels than the other, move the anchors closest
  /// to the vertical centre line across (they are the cheapest to move).
  static void _balanceSides(List<LabelSide> sides, List<Offset> anchors, double cx) {
    int count(LabelSide s) => sides.where((e) => e == s).length;
    while ((count(LabelSide.left) - count(LabelSide.right)).abs() > 1) {
      final from = count(LabelSide.left) > count(LabelSide.right) ? LabelSide.left : LabelSide.right;
      final to = from == LabelSide.left ? LabelSide.right : LabelSide.left;
      var best = -1;
      var bestDist = double.infinity;
      for (var i = 0; i < sides.length; i++) {
        if (sides[i] != from) continue;
        final d = (anchors[i].dx - cx).abs();
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      if (best < 0) break;
      sides[best] = to;
    }
  }

  /// Centre of the bounding box of the points (more stable than the mean when
  /// many parts cluster on one side).
  static Offset _centroidOfBox(List<Offset> pts) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    // Blend with the body centre so a single cluster still splits sensibly.
    return Offset(((minX + maxX) / 2 + 0.5) / 2, ((minY + maxY) / 2 + 0.5) / 2);
  }
}

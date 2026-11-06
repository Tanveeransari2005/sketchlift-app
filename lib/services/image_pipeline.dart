/// Image clean-up pipeline (pure Dart, runs in a background isolate).
///
/// Steps for a phone photo of a diagram:
///   1. decode + fix EXIF rotation + downscale (long side 1600 px)
///   2. perspective crop to the 4 page corners chosen by the user / scanner
///   3. "whitening": estimate the paper background with a downscaled max-filter
///      + blur, then divide each pixel by it. Shadows and the yellow cast of a
///      tube-light / bulb are part of the background, so dividing removes them
///      and the paper becomes pure white while ink stays dark.
///   4. levels + gamma to make strokes crisp; optional black & white mode
///      (threshold on the normalised image = adaptive threshold)
///   5. sharpen (3x3 unsharp kernel)
///
/// After Gemini has located things, [cleanBody] whitens the old handwritten
/// labels and crops to the diagram body so our neat vector labels can go
/// around it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/diagram.dart';

/// Input for [processPhoto]; plain data so it can cross isolate boundaries.
class ProcessRequest {
  final Uint8List bytes;

  /// Optional 4 corners (normalised): tl, tr, br, bl as [x0,y0,x1,y1,...].
  final List<double>? corners;
  final bool blackAndWhite;
  final int maxSide;

  const ProcessRequest(this.bytes, {this.corners, this.blackAndWhite = false, this.maxSide = 1600});
}

/// Full clean-up; returns PNG bytes. Top-level so `compute()` can call it.
Uint8List processPhoto(ProcessRequest req) {
  var image = img.decodeImage(req.bytes);
  if (image == null) throw const FormatException('Could not read this image');
  image = img.bakeOrientation(image);
  image = _limitSize(image, req.maxSide);
  if (req.corners != null && req.corners!.length == 8) {
    image = perspectiveCrop(image, req.corners!);
  }
  image = whiten(image, blackAndWhite: req.blackAndWhite);
  image = img.convolution(image, filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0]);
  return Uint8List.fromList(img.encodePng(image, level: 4));
}

/// JPEG for upload to Gemini (smaller = faster + cheaper).
Uint8List toUploadJpeg(Uint8List pngOrJpeg) {
  var image = img.decodeImage(pngOrJpeg)!;
  image = _limitSize(image, 1280);
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

img.Image _limitSize(img.Image image, int maxSide) {
  final long = math.max(image.width, image.height);
  if (long <= maxSide) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
}

/// Warps the quadrilateral [c] (normalised tl,tr,br,bl) to a flat rectangle.
img.Image perspectiveCrop(img.Image src, List<double> c) {
  img.Point p(int i) => img.Point(c[i * 2] * (src.width - 1), c[i * 2 + 1] * (src.height - 1));
  final tl = p(0), tr = p(1), br = p(2), bl = p(3);
  double dist(img.Point a, img.Point b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  final w = math.max(dist(tl, tr), dist(bl, br)).round().clamp(32, 4000);
  final h = math.max(dist(tl, bl), dist(tr, br)).round().clamp(32, 4000);
  final out = img.Image(width: w, height: h, numChannels: 3);
  return img.copyRectify(src,
      topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br,
      interpolation: img.Interpolation.linear, toImage: out);
}

/// Shadow / yellow-light removal by background division (see file header).
img.Image whiten(img.Image src, {bool blackAndWhite = false, bool removeRuledLines = true}) {
  final w = src.width, h = src.height;
  final rgb = src.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);

  // --- background estimate on a small copy ---
  const scale = 16;
  final sw = math.max(4, w ~/ scale), sh = math.max(4, h ~/ scale);
  var small = img.copyResize(src.convert(numChannels: 3), width: sw, height: sh, interpolation: img.Interpolation.average);
  // Max filter (dilation) removes thin dark strokes; repeat to cover thick ones.
  for (var k = 0; k < 3; k++) {
    small = _maxFilter3(small);
  }
  small = img.gaussianBlur(small, radius: 2);
  final bg = img.copyResize(small, width: w, height: h, interpolation: img.Interpolation.linear)
      .getBytes(order: img.ChannelOrder.rgb);

  // --- divide + levels ---
  final out = Uint8List(w * h * 3);
  const black = 0.25, white = 0.88, gamma = 1.25;
  // Lookup table: v (ratio pixel/background, 0..2 in 1/256 steps) -> output.
  final lut = Float64List(513);
  for (var k = 0; k <= 512; k++) {
    var v = k / 256.0;
    v = ((v - black) / (white - black)).clamp(0.0, 1.0);
    lut[k] = math.pow(v, gamma).toDouble();
  }
  for (var i = 0; i < w * h; i++) {
    final o = i * 3;
    final bgLum = (bg[o] + bg[o + 1] + bg[o + 2]) / 3;
    if (bgLum < 90) {
      // Not paper (table, mug, deep shadow): dividing would explode colours,
      // so keep the original pixel. The body crop removes it later anyway.
      out[o] = rgb[o];
      out[o + 1] = rgb[o + 1];
      out[o + 2] = rgb[o + 2];
      continue;
    }
    final r = lut[math.min(512, (rgb[o] * 256) ~/ math.max(bg[o], 40))];
    final g = lut[math.min(512, (rgb[o + 1] * 256) ~/ math.max(bg[o + 1], 40))];
    final b = lut[math.min(512, (rgb[o + 2] * 256) ~/ math.max(bg[o + 2], 40))];
    final lum = (r + g + b) / 3;
    // Notebook ruled lines are light blue / pink: clearly tinted and not dark.
    final ruled = removeRuledLines && lum > 0.42 && ((b - r) > 0.10 || (r - b) > 0.18 && (r - g) > 0.12);
    if (blackAndWhite) {
      final bw = (lum < 0.72 && !ruled) ? 0 : 255;
      out[o] = out[o + 1] = out[o + 2] = bw;
    } else if (lum > 0.86 || ruled) {
      // Near-white -> pure white (kills leftover tint / paper texture).
      out[o] = out[o + 1] = out[o + 2] = 255;
    } else {
      // Keep (slightly calmed) colour in real ink — NCERT diagrams are often
      // coloured; division would otherwise over-saturate it.
      out[o] = ((lum + (r - lum) * 0.6) * 255).round().clamp(0, 255);
      out[o + 1] = ((lum + (g - lum) * 0.6) * 255).round().clamp(0, 255);
      out[o + 2] = ((lum + (b - lum) * 0.6) * 255).round().clamp(0, 255);
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
}

img.Image _maxFilter3(img.Image src) {
  final w = src.width, h = src.height;
  final s = src.getBytes(order: img.ChannelOrder.rgb);
  final d = Uint8List(s.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var m = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (var dx = -1; dx <= 1; dx++) {
            final xx = (x + dx).clamp(0, w - 1);
            final v = s[(yy * w + xx) * 3 + c];
            if (v > m) m = v;
          }
        }
        d[(y * w + x) * 3 + c] = m;
      }
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: d.buffer, numChannels: 3);
}

/// Input for [cleanBody].
class CleanBodyRequest {
  final Uint8List processedPng;
  final NRect? body;
  final List<NRect> labelBoxes;
  const CleanBodyRequest(this.processedPng, this.body, this.labelBoxes);
}

/// Output of [cleanBody]: PNG of just the diagram body + the body rect used
/// (normalised in the processed image) so anchors can be re-mapped.
class CleanBodyResult {
  final Uint8List png;
  final NRect usedBody;
  const CleanBodyResult(this.png, this.usedBody);
}

/// Whitens old handwritten labels and crops to the body box.
CleanBodyResult cleanBody(CleanBodyRequest r) {
  final image = img.decodeImage(r.processedPng)!.convert(numChannels: 3);
  final w = image.width, h = image.height;
  // Erase handwritten labels (see [eraseTextInBox]).
  for (final b in r.labelBoxes) {
    eraseTextInBox(image, b);
  }
  // Crop to the body (+3% padding). Labels outside disappear with the crop.
  var body = r.body ?? const NRect(0, 0, 1, 1);
  const pad = 0.03;
  final bx = math.max(0.0, body.x - pad), by = math.max(0.0, body.y - pad);
  final br = math.min(1.0, body.right + pad), bb = math.min(1.0, body.bottom + pad);
  body = NRect(bx, by, br - bx, bb - by);
  final cropped = img.copyCrop(image,
      x: (bx * w).round(), y: (by * h).round(),
      width: math.max(8, ((br - bx) * w).round()), height: math.max(8, ((bb - by) * h).round()));
  // Paint the padding ring white: only the exact body stays, so fragments of
  // labels / arrows that sat just outside the drawing disappear.
  if (r.body != null) {
    final white = img.ColorRgb8(255, 255, 255);
    final ix0 = ((r.body!.x - bx) * w).round(), iy0 = ((r.body!.y - by) * h).round();
    final ix1 = ((r.body!.right - bx) * w).round(), iy1 = ((r.body!.bottom - by) * h).round();
    final cw = cropped.width, chh = cropped.height;
    if (iy0 > 0) img.fillRect(cropped, x1: 0, y1: 0, x2: cw - 1, y2: iy0 - 1, color: white);
    if (iy1 < chh) img.fillRect(cropped, x1: 0, y1: iy1, x2: cw - 1, y2: chh - 1, color: white);
    if (ix0 > 0) img.fillRect(cropped, x1: 0, y1: 0, x2: ix0 - 1, y2: chh - 1, color: white);
    if (ix1 < cw) img.fillRect(cropped, x1: ix1, y1: 0, x2: cw - 1, y2: chh - 1, color: white);
  }
  return CleanBodyResult(Uint8List.fromList(img.encodePng(cropped, level: 4)), body);
}

/// Erases handwritten label text in [box] (normalised, from Gemini).
///
/// Two passes, because Gemini's boxes are approximate:
///   1. the box itself (+0.6% padding) is painted white — reliable;
///   2. around it, in a grown box, we flood-fill blobs of dark ink:
///      * a blob that touches the edge of the grown box continues outside it →
///        part of the drawing (cell wall, outline…) → keep it;
///      * a blob that lies completely inside → a stray letter → erase it.
/// Trade-off: when a label is written ON TOP of the drawing, pass 1 also
/// whitens that bit of the drawing (a small gap in a line).
void eraseTextInBox(img.Image image, NRect box, {int darkThreshold = 170}) {
  final w = image.width, h = image.height;
  // Pass 1: the core box.
  img.fillRect(image,
      x1: ((box.x - 0.006) * w).floor().clamp(0, w - 1),
      y1: ((box.y - 0.006) * h).floor().clamp(0, h - 1),
      x2: ((box.right + 0.006) * w).ceil().clamp(0, w - 1),
      y2: ((box.bottom + 0.006) * h).ceil().clamp(0, h - 1),
      color: img.ColorRgb8(255, 255, 255));
  // Pass 2: stray letters around it.
  final gx = math.max(box.w * 0.5, 0.02), gy = math.max(box.h * 0.5, 0.015);
  final x0 = ((box.x - gx) * w).floor().clamp(0, w - 1);
  final y0 = ((box.y - gy) * h).floor().clamp(0, h - 1);
  final x1 = ((box.right + gx) * w).ceil().clamp(0, w - 1);
  final y1 = ((box.bottom + gy) * h).ceil().clamp(0, h - 1);
  final rw = x1 - x0 + 1, rh = y1 - y0 + 1;
  if (rw < 3 || rh < 3) return;

  final dark = Uint8List(rw * rh);
  for (var y = 0; y < rh; y++) {
    for (var x = 0; x < rw; x++) {
      final p = image.getPixel(x0 + x, y0 + y);
      if ((p.r + p.g + p.b) / 3 < darkThreshold) dark[y * rw + x] = 1;
    }
  }
  final seen = Uint8List(rw * rh);
  final stack = <int>[];
  final comp = <int>[];
  final white = img.ColorRgb8(255, 255, 255);
  for (var start = 0; start < rw * rh; start++) {
    if (dark[start] == 0 || seen[start] == 1) continue;
    comp.clear();
    var touchesEdge = false;
    stack.add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      comp.add(i);
      final x = i % rw, y = i ~/ rw;
      if (x == 0 || y == 0 || x == rw - 1 || y == rh - 1) touchesEdge = true;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= rw || ny >= rh) continue;
          final j = ny * rw + nx;
          if (dark[j] == 1 && seen[j] == 0) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
    }
    if (!touchesEdge) {
      for (final i in comp) {
        final x = x0 + i % rw, y = y0 + i ~/ rw;
        // Erase the pixel and its anti-aliased halo.
        img.fillRect(image, x1: math.max(0, x - 1), y1: math.max(0, y - 1),
            x2: math.min(w - 1, x + 1), y2: math.min(h - 1, y + 1), color: white);
      }
    }
  }
}

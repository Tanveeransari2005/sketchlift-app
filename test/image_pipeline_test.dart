import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sketchlift/models/diagram.dart';
import 'package:sketchlift/services/image_pipeline.dart';

double lum(img.Image im, int x, int y) {
  final p = im.getPixel(x, y);
  return (p.r + p.g + p.b) / 3;
}

void main() {
  test('whiten() removes a yellow shadowy background but keeps ink', () {
    // Yellowish paper with a dark gradient shadow on the right + a black line.
    final im = img.Image(width: 200, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 200; x++) {
        final shade = 1.0 - 0.45 * (x / 200); // shadow towards the right
        im.setPixelRgb(x, y, (235 * shade).round(), (220 * shade).round(), (170 * shade).round());
      }
    }
    img.drawLine(im, x1: 10, y1: 60, x2: 190, y2: 60, color: img.ColorRgb8(40, 40, 40), thickness: 3);
    final out = whiten(im);
    // Paper is white on both the bright and the shadowed side.
    expect(lum(out, 20, 20), greaterThan(245));
    expect(lum(out, 180, 20), greaterThan(245));
    final p = out.getPixel(180, 100);
    expect(p.b, greaterThan(240)); // yellow cast gone
    // Ink stays dark (also inside the shadow).
    expect(lum(out, 20, 60), lessThan(90));
    expect(lum(out, 180, 60), lessThan(120));
  });

  test('eraseTextInBox erases letters but keeps a line crossing the box', () {
    final im = img.Image(width: 200, height: 200);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    // A long "cell wall" line crossing the label box.
    img.drawLine(im, x1: 0, y1: 100, x2: 199, y2: 100, color: img.ColorRgb8(0, 0, 0), thickness: 2);
    // Small "letters" fully inside the box.
    img.fillRect(im, x1: 80, y1: 80, x2: 86, y2: 92, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(im, x1: 92, y1: 80, x2: 95, y2: 92, color: img.ColorRgb8(0, 0, 0));
    // Gemini's box covers only the first letter; the second (outside it) is
    // still removed by the flood-fill pass.
    eraseTextInBox(im, const NRect(0.39, 0.39, 0.06, 0.08));
    expect(lum(im, 83, 85), 255); // letter erased
    expect(lum(im, 93, 85), 255);
    expect(lum(im, 120, 100), lessThan(50)); // line kept outside the core box
    expect(lum(im, 10, 100), lessThan(50));
  });

  test('full pipeline on the demo photo: process + clean body', () {
    final raw = File('assets/demo/plant_cell_photo.jpg').readAsBytesSync();
    final processed = processPhoto(ProcessRequest(raw));
    final decoded = img.decodePng(processed)!;
    expect(decoded.width, 1408);
    final res = cleanBody(CleanBodyRequest(processed, const NRect(0.28, 0.23, 0.44, 0.63), const [NRect(0.46, 0.47, 0.1, 0.08)]));
    final body = img.decodePng(res.png)!;
    expect(body.width, lessThan(decoded.width));
    expect(res.usedBody.x, closeTo(0.25, 0.001)); // 3% padding
  });

  test('perspective crop produces a rectangle of the expected size', () {
    final im = img.Image(width: 400, height: 300);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    final out = perspectiveCrop(im, const [0.1, 0.1, 0.9, 0.15, 0.85, 0.9, 0.12, 0.85]);
    expect(out.width, inInclusiveRange(300, 330));
    expect(out.height, inInclusiveRange(200, 240));
  });
}

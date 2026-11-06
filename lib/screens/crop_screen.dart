/// Manual 4-corner crop (fallback when the ML Kit scanner is unavailable).
///
/// The user drags 4 handles onto the page/diagram corners; the pipeline then
/// warps that quadrilateral into a flat rectangle (perspective correction =
/// "deskew").
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';

class CropResult {
  final List<double> corners; // tl, tr, br, bl (normalised x,y pairs)
  final bool blackAndWhite;
  const CropResult(this.corners, this.blackAndWhite);
}

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  // Start slightly inset so handles are easy to grab.
  final List<Offset> _pts = const [Offset(0.06, 0.06), Offset(0.94, 0.06), Offset(0.94, 0.94), Offset(0.06, 0.94)].toList();
  late bool _bw = AppScope.read(context).blackAndWhite;
  Size? _imgSize;

  @override
  void initState() {
    super.initState();
    final provider = MemoryImage(widget.bytes);
    provider.resolve(const ImageConfiguration()).addListener(ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imgSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
    }));
  }

  bool get _isFull =>
      _pts[0] == const Offset(0, 0) && _pts[1] == const Offset(1, 0) && _pts[2] == const Offset(1, 1) && _pts[3] == const Offset(0, 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('crop_title')), actions: [
        IconButton(
          tooltip: 'Full image',
          icon: const Icon(Icons.fullscreen_rounded),
          onPressed: () => setState(() {
            _pts
              ..[0] = const Offset(0, 0)
              ..[1] = const Offset(1, 0)
              ..[2] = const Offset(1, 1)
              ..[3] = const Offset(0, 1);
          }),
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(context.tr('crop_hint'), style: TextStyle(color: Brand.ink.withValues(alpha: 0.7))),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _imgSize == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  // Fit the image into the available box.
                  final s = (c.maxWidth - 32) / _imgSize!.width < (c.maxHeight - 32) / _imgSize!.height
                      ? (c.maxWidth - 32) / _imgSize!.width
                      : (c.maxHeight - 32) / _imgSize!.height;
                  final w = _imgSize!.width * s, h = _imgSize!.height * s;
                  return Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(child: Image.memory(widget.bytes, fit: BoxFit.fill)),
                        Positioned.fill(child: CustomPaint(painter: _QuadPainter(_pts))),
                        for (var i = 0; i < 4; i++)
                          Positioned(
                            left: _pts[i].dx * w - 22,
                            top: _pts[i].dy * h - 22,
                            child: GestureDetector(
                              onPanUpdate: (d) => setState(() {
                                _pts[i] = Offset(
                                  (_pts[i].dx + d.delta.dx / w).clamp(0.0, 1.0),
                                  (_pts[i].dy + d.delta.dy / h).clamp(0.0, 1.0),
                                );
                              }),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Brand.green, width: 4),
                                    boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  );
                }),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              FilterChip(
                label: Text(context.tr('bw_mode')),
                selected: _bw,
                onSelected: (v) => setState(() => _bw = v),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(context.tr('continue')),
                onPressed: () => Navigator.pop(
                  context,
                  CropResult(
                      _isFull ? const [] : [for (final p in _pts) ...[p.dx, p.dy]], _bw),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.pts);
  final List<Offset> pts;
  @override
  void paint(Canvas canvas, Size size) {
    final p = [for (final o in pts) Offset(o.dx * size.width, o.dy * size.height)];
    final quad = Path()..addPolygon(p, true);
    // Dim outside the selection.
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), quad);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawPath(
        quad,
        Paint()
          ..color = Brand.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}

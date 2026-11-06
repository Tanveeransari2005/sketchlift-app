/// Interactive, zoomable view of a [DiagramDoc].
///
/// * pinch-zoom / pan via InteractiveViewer (labels are vector text → no blur)
/// * tap a label (or its dot) → [onTapPart]
/// * in "add" mode, tap on the picture → [onTapBody] with a 0..1 point
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/diagram_doc.dart';
import 'diagram_scene.dart';

class DiagramView extends StatefulWidget {
  const DiagramView({
    super.key,
    required this.doc,
    required this.mode,
    required this.version,
    this.selected,
    this.onTapPart,
    this.onTapBody,
    this.addMode = false,
  });

  final DiagramDoc doc;
  final DiagramMode mode;

  /// Bump this whenever the doc's parts change so the layout is recomputed.
  final int version;
  final int? selected;
  final ValueChanged<int>? onTapPart;
  final ValueChanged<Offset>? onTapBody;
  final bool addMode;

  @override
  State<DiagramView> createState() => _DiagramViewState();
}

class _DiagramViewState extends State<DiagramView> {
  ui.Image? _image;
  DiagramScene? _scene;
  final _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(DiagramView old) {
    super.didUpdateWidget(old);
    if (old.doc.bodyPng != widget.doc.bodyPng) {
      _decode();
    } else if (old.version != widget.version || old.mode != widget.mode) {
      _rebuildScene();
    }
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.doc.bodyPng);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    _image = frame.image;
    _rebuildScene();
  }

  void _rebuildScene() {
    if (_image == null) return;
    setState(() {
      _scene = DiagramScene.build(
          widget.doc, Size(_image!.width.toDouble(), _image!.height.toDouble()), widget.mode);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (scene == null) return const AspectRatio(aspectRatio: 1.4, child: Center(child: CircularProgressIndicator()));
    return AspectRatio(
      aspectRatio: scene.size.width / scene.size.height,
      child: LayoutBuilder(builder: (context, c) {
        final scale = c.maxWidth / scene.size.width;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 6,
            child: GestureDetector(
              onTapUp: (d) {
                final p = d.localPosition / scale; // → canvas units
                if (widget.addMode) {
                  final b = scene.toBody(p);
                  if (b != null) widget.onTapBody?.call(b);
                  return;
                }
                final hit = scene.hitTest(p);
                if (hit != null) widget.onTapPart?.call(hit);
              },
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxWidth * scene.size.height / scene.size.width),
                painter: DiagramPainter(scene, _image, selected: widget.selected),
              ),
            ),
          ),
        );
      }),
    );
  }
}

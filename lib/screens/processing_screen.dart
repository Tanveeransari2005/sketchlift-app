/// Runs the pipeline with a friendly animated progress screen.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/diagram_doc.dart';
import '../services/diagram_pipeline.dart';
import '../services/gemini_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key, this.raw, this.corners, this.blackAndWhite = false, this.demo = false});
  final Uint8List? raw;
  final List<double>? corners;
  final bool blackAndWhite;
  final bool demo;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> with SingleTickerProviderStateMixin {
  int _step = 0; // 0 = cleaning, 1 = understanding
  Uint8List? _cleaned;
  String? _error;
  String? _notDiagram;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final app = AppScope.read(context);
    setState(() {
      _error = null;
      _notDiagram = null;
      _step = 0;
    });
    try {
      DiagramDoc doc;
      if (widget.demo) {
        doc = await DiagramPipeline.demo();
      } else {
        _cleaned ??= await DiagramPipeline.clean(widget.raw!,
            corners: (widget.corners?.length == 8) ? widget.corners : null, bw: widget.blackAndWhite);
        if (!mounted) return;
        setState(() => _step = 1);
        if (!app.canScan) throw const DailyLimitException();
        doc = await DiagramPipeline.understand(app.ai, _cleaned!);
        await app.recordScan();
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: ResultScreen(doc: doc, isNew: true)),
        ),
      );
    } on NotADiagramException catch (e) {
      // A real (successful) AI call still counts.
      await app.recordScan();
      setState(() => _notDiagram = e.reason);
    } on AiException catch (e) {
      setState(() => _error = e.userMessage);
    } catch (e) {
      setState(() => _error = 'Kuch gadbad ho gayi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _notDiagram != null
              ? _message(Icons.image_not_supported_outlined, Brand.coral, 'Ye diagram nahi lag raha 🤔',
                  '${context.tr('not_diagram')}.\n$_notDiagram')
              : _error != null
                  ? _message(Icons.wifi_off_rounded, Brand.indigo, 'Oops!', _error!, retry: true)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      ScaleTransition(
                        scale: Tween(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                        child: Hero(tag: 'logo', child: Image.asset('assets/branding/logo.png', height: 120)),
                      ),
                      const SizedBox(height: 28),
                      _stepRow(0, context.tr('processing')),
                      _stepRow(1, context.tr('understanding')),
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(),
                    ]),
        ),
      ),
    );
  }

  Widget _stepRow(int i, String text) {
    final done = _step > i;
    final active = _step == i;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: done
              ? const Icon(Icons.check_circle_rounded, color: Brand.green, key: ValueKey('d'))
              : Icon(active ? Icons.autorenew_rounded : Icons.circle_outlined,
                  color: active ? Brand.indigo : Colors.black26, key: ValueKey('a$active')),
        ),
        const SizedBox(width: 10),
        Text(text, style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.w400, fontSize: 16)),
      ]),
    );
  }

  Widget _message(IconData icon, Color color, String title, String body, {bool retry = false}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(radius: 44, backgroundColor: color.withValues(alpha: 0.13), child: Icon(icon, size: 44, color: color)),
      const SizedBox(height: 18),
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(body, textAlign: TextAlign.center, style: TextStyle(color: Brand.ink.withValues(alpha: 0.75))),
      const SizedBox(height: 24),
      Wrap(spacing: 12, children: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('retake'))),
        if (retry) FilledButton(onPressed: _run, child: const Text('Retry')),
      ]),
    ]);
  }
}

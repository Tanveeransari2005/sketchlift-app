/// Feature 11: "Meri drawing check karo".
///
/// 1. pick the reference diagram from the Library (its JSON = answer key)
/// 2. photograph your own drawing (cleaned by the same pipeline)
/// 3. Gemini compares → score / missing / misplaced + encouraging feedback.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../models/diagram.dart';
import '../models/diagram_doc.dart';
import '../services/diagram_pipeline.dart';
import '../services/gemini_service.dart';
import '../services/image_pipeline.dart';
import '../services/library_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'library_screen.dart';

class CheckDrawingScreen extends StatefulWidget {
  const CheckDrawingScreen({super.key});
  @override
  State<CheckDrawingScreen> createState() => _CheckDrawingScreenState();
}

class _CheckDrawingScreenState extends State<CheckDrawingScreen> {
  DiagramDoc? _ref;
  DrawingCheck? _result;
  bool _busy = false;
  String? _error;
  late bool _hindi = AppScope.read(context).hindi;

  Future<void> _pickRef() async {
    final ids = await Navigator.push<List<int>>(
        context, MaterialPageRoute(builder: (_) => DiagramPickerScreen(title: context.tr('pick_reference'))));
    if (ids == null || ids.isEmpty) return;
    final d = await (await LibraryDb.open()).load(ids.first);
    if (mounted) setState(() => _ref = d);
  }

  Future<void> _check(ImageSource src) async {
    final app = AppScope.read(context);
    final x = await ImagePicker().pickImage(source: src, imageQuality: 92, maxWidth: 2200);
    if (x == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if (!app.canScan) throw const DailyLimitException();
      final cleaned = await DiagramPipeline.clean(await x.readAsBytes());
      final res = await app.ai.checkDrawing(toUploadJpeg(cleaned), _ref!.result);
      await app.recordScan();
      setState(() => _result = res);
    } on AiException catch (e) {
      setState(() => _error = e.userMessage);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('check_drawing'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ActionTile(
          icon: Icons.menu_book_rounded,
          title: _ref?.title ?? context.tr('pick_reference'),
          subtitle: _ref == null ? null : '${_ref!.result.parts.length} parts',
          onTap: _pickRef,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _ref == null || _busy ? null : () => _check(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded),
              label: Text(context.tr('photo_drawing')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
              onPressed: _ref == null || _busy ? null : () => _check(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded)),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Brand.coral))),
        if (r != null) ...[
          const SizedBox(height: 18),
          _ScoreRing(score: r.score, total: r.total),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('💬 Feedback', style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(
                      onPressed: () => setState(() => _hindi = !_hindi),
                      child: Text(_hindi ? context.tr('read_english') : context.tr('read_hindi'))),
                ]),
                Text(_hindi && r.feedbackHi.isNotEmpty ? r.feedbackHi : r.feedbackEn, style: const TextStyle(height: 1.4)),
              ]),
            ),
          ),
          _list('✅ ${context.tr('found')}', r.found, Brand.green),
          _list('❌ ${context.tr('missing')}', r.missing, Brand.coral),
          _list('↔️ ${context.tr('misplaced')}', r.misplaced, Brand.indigo),
          const SizedBox(height: 10),
          const VerifyNote(),
        ],
      ]),
    );
  }

  Widget _list(String title, List<String> items, Color c) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in items) Chip(label: Text(i), backgroundColor: c.withValues(alpha: 0.12), side: BorderSide.none),
        ]),
      ]),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.total});
  final int score, total;
  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : score / total;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: f),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => SizedBox(
          width: 150,
          height: 150,
          child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(
                value: v, strokeWidth: 12, backgroundColor: Brand.greenSoft, color: f >= 0.6 ? Brand.green : Brand.sun),
            Center(
              child: Text('$score / $total', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The clean diagram: view, edit labels, practice mode, explanations, voice
/// questions, save to library and export.
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/diagram.dart';
import '../models/diagram_doc.dart';
import '../services/export_service.dart';
import '../services/gemini_service.dart';
import '../services/glossary.dart';
import '../services/label_layout.dart';
import '../services/library_db.dart';
import '../services/voice_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/diagram_scene.dart';
import '../widgets/diagram_view.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.doc, this.isNew = false, this.startInPractice = false});
  final DiagramDoc doc;
  final bool isNew;
  final bool startInPractice;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late DiagramMode _mode = widget.startInPractice ? DiagramMode.practice : DiagramMode.labelled;
  int _version = 0;
  int? _selected;
  bool _addMode = false;
  bool _showKey = false;
  late bool _hindi = AppScope.read(context).hindi;
  bool _dirty = false;
  bool _busy = false;
  String? _voiceAnswer;

  DiagramDoc get doc => widget.doc;

  @override
  void initState() {
    super.initState();
    _dirty = widget.isNew;
  }

  void _changed() => setState(() {
        _version++;
        _dirty = true;
      });

  // ---- label editing (feature 5) ---------------------------------------------
  Future<void> _editPart(int i) async {
    final part = doc.result.parts[i];
    final ctrl = TextEditingController(text: part.name);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.tr('edit'), style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: context.tr('label_name'))),
          const SizedBox(height: 14),
          Row(children: [
            TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                icon: const Icon(Icons.delete_outline, color: Brand.coral),
                label: Text(context.tr('delete'), style: const TextStyle(color: Brand.coral))),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(context.tr('save'))),
          ]),
        ]),
      ),
    );
    if (action == 'delete') {
      doc.result.parts.removeAt(i);
      _selected = null;
      _changed();
    } else if (action == 'save' && ctrl.text.trim().isNotEmpty) {
      part.name = ctrl.text.trim(); // user's text wins — no auto-correct on manual edits
      _changed();
    }
  }

  Future<void> _addAt(Offset bodyPoint) async {
    final ai = AppScope.read(context).ai; // read before any await
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('add_label')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: context.tr('label_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(context.tr('save'))),
        ],
      ),
    );
    setState(() => _addMode = false);
    if (name == null || name.trim().isEmpty) return;
    final fixed = Glossary.fix(name, subject: doc.subject);
    doc.addPart(fixed, bodyPoint);
    final idx = doc.result.parts.length - 1;
    _selected = idx;
    _changed();
    // Best-effort one-line explanation from AI (doesn't block editing).
    try {
      final (en, hi) = await ai.explainPart(doc.title, fixed);
      if (!mounted || idx >= doc.result.parts.length) return;
      doc.result.parts[idx]
        ..explainEn = en
        ..explainHi = hi;
      setState(() {});
    } catch (_) {}
  }

  // ---- voice (feature 13) ---------------------------------------------------
  Future<void> _voiceAsk() async {
    final voice = VoiceService.instance;
    final hindi = _hindi;
    showSnack(context, context.tr('listening'));
    final q = await voice.listenOnce(hindi: hindi);
    if (!mounted) return;
    if (q.trim().isEmpty) {
      showSnack(context, 'Kuch sunai nahi diya — dobara bolo.');
      return;
    }
    setState(() {
      _busy = true;
      _voiceAnswer = '❓ $q\n…';
    });
    try {
      final ans = await AppScope.read(context).ai.askAboutDiagram(doc.result, q, hindi: hindi);
      if (!mounted) return;
      setState(() => _voiceAnswer = '❓ $q\n💬 $ans');
      await voice.speak(ans, hindi: hindi);
    } on AiException catch (e) {
      if (mounted) setState(() => _voiceAnswer = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- save (feature 9) -----------------------------------------------------
  Future<void> _save() async {
    final titleCtrl = TextEditingController(text: doc.title);
    final chapterCtrl = TextEditingController(text: doc.chapter);
    var subject = doc.subject;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(context.tr('save')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleCtrl, decoration: InputDecoration(labelText: context.tr('title'))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: DiagramResult.subjects.contains(subject) ? subject : 'Other',
              decoration: InputDecoration(labelText: context.tr('subject')),
              items: [for (final s in DiagramResult.subjects) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setD(() => subject = v ?? subject),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: chapterCtrl,
                decoration: InputDecoration(labelText: context.tr('chapter'), hintText: 'e.g. The Fundamental Unit of Life')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    doc.result.title = titleCtrl.text.trim().isEmpty ? doc.title : titleCtrl.text.trim();
    doc.result.subject = subject;
    doc.chapter = chapterCtrl.text;
    final db = await LibraryDb.open();
    await db.save(doc);
    if (!mounted) return;
    setState(() => _dirty = false);
    showSnack(context, '✅ ${context.tr('saved')}');
  }

  // ---- export (feature 8) ---------------------------------------------------
  Future<void> _export() async {
    final app = AppScope.read(context);
    final header = PdfHeader(name: app.studentName, className: app.className, school: app.schoolName);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.download_rounded), title: Text(context.tr('download_png')), onTap: () => Navigator.pop(ctx, 'png')),
          ListTile(leading: const Icon(Icons.share_rounded), title: Text(context.tr('share_png')), onTap: () => Navigator.pop(ctx, 'share_png')),
          ListTile(leading: const Icon(Icons.print_rounded), title: Text(context.tr('print_pdf')), onTap: () => Navigator.pop(ctx, 'print')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: Text(context.tr('share_pdf')), onTap: () => Navigator.pop(ctx, 'share_pdf')),
        ]),
      ),
    );
    if (choice == null) return;
    setState(() => _busy = true);
    try {
      switch (choice) {
        case 'png':
          await ExportService.saveToGallery(await ExportService.renderPng(doc, _mode), doc.title);
          if (mounted) showSnack(context, '✅ Saved to gallery');
        case 'share_png':
          await ExportService.shareBytes(await ExportService.renderPng(doc, _mode),
              ExportService.fileName(doc.title, 'png'), 'image/png', text: doc.title);
        case 'print':
          await ExportService.printPdf(await ExportService.diagramPdf(doc, _mode, header), doc.title);
        case 'share_pdf':
          await ExportService.shareBytes(await ExportService.diagramPdf(doc, _mode, header),
              ExportService.fileName(doc.title, 'pdf'), 'application/pdf', text: doc.title);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = doc.result.parts;
    final sel = (_selected != null && _selected! < parts.length) ? parts[_selected!] : null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Save karna hai?'),
            content: const Text('Diagram abhi Library mein save nahi hua.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('save'))),
            ],
          ),
        );
        if (!context.mounted) return;
        if (leave == true) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        } else {
          _save();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_hindi && doc.result.titleHi.isNotEmpty ? doc.result.titleHi : doc.title),
          actions: [
            IconButton(tooltip: context.tr('save'), onPressed: _save, icon: Icon(_dirty ? Icons.save_outlined : Icons.check_circle_outline)),
            IconButton(tooltip: context.tr('export'), onPressed: _export, icon: const Icon(Icons.ios_share_rounded)),
          ],
        ),
        floatingActionButton: _mode == DiagramMode.labelled
            ? FloatingActionButton.extended(
                heroTag: 'add',
                backgroundColor: _addMode ? Brand.coral : Brand.indigo,
                foregroundColor: Colors.white,
                onPressed: () => setState(() => _addMode = !_addMode),
                icon: Icon(_addMode ? Icons.close : Icons.add_rounded),
                label: Text(_addMode ? context.tr('cancel') : context.tr('add_label')),
              )
            : null,
        body: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            Row(children: [
              Expanded(
                child: SegmentedButton<DiagramMode>(
                  segments: [
                    ButtonSegment(value: DiagramMode.labelled, label: Text(context.tr('labelled')), icon: const Icon(Icons.label_outline)),
                    ButtonSegment(value: DiagramMode.practice, label: Text(context.tr('practice')), icon: const Icon(Icons.edit_outlined)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _addMode = false;
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (_addMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('👆 ${context.tr('add_label_hint')}',
                    style: const TextStyle(color: Brand.indigo, fontWeight: FontWeight.w600)),
              ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Brand.ink.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: DiagramView(
                doc: doc,
                mode: _mode,
                version: _version,
                selected: _selected,
                addMode: _addMode,
                onTapPart: (i) => setState(() => _selected = i),
                onTapBody: _addAt,
              ),
            ),
            const SizedBox(height: 12),
            if (_mode == DiagramMode.practice) ...[
              SwitchListTile(
                value: _showKey,
                onChanged: (v) => setState(() => _showKey = v),
                title: Text(context.tr('answer_key')),
                contentPadding: EdgeInsets.zero,
              ),
              if (_showKey) _AnswerKey(doc: doc, version: _version),
            ] else ...[
              _ExplainCard(
                part: sel,
                hindi: _hindi,
                onToggleLang: () => setState(() => _hindi = !_hindi),
                onEdit: sel == null ? null : () => _editPart(_selected!),
                onSpeak: sel == null ? null : () => VoiceService.instance.speak(
                    '${sel.name}. ${sel.explain(_hindi)}', hindi: _hindi),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _voiceAsk,
                icon: const Icon(Icons.mic_rounded),
                label: Text(context.tr('ask_voice')),
              ),
              if (_voiceAnswer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_voiceAnswer!))),
                ),
            ],
            if (doc.result.arrows.isNotEmpty) ...[
              SectionTitle(context.tr('flow')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in doc.result.arrows)
                  Chip(label: Text('${a.from} → ${a.to}${a.label.isNotEmpty ? ' (${a.label})' : ''}')),
              ]),
            ],
            const SizedBox(height: 14),
            const VerifyNote(),
          ]),
          if (_busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}

class _ExplainCard extends StatelessWidget {
  const _ExplainCard({required this.part, required this.hindi, required this.onToggleLang, this.onEdit, this.onSpeak});
  final DiagramPart? part;
  final bool hindi;
  final VoidCallback onToggleLang;
  final VoidCallback? onEdit;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(part?.name ?? context.tr('tap_label'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: part == null ? 14 : 17)),
              ),
              TextButton(
                onPressed: onToggleLang,
                child: Text(hindi ? context.tr('read_english') : context.tr('read_hindi')),
              ),
            ]),
            if (part != null) ...[
              const SizedBox(height: 4),
              Text(part!.explain(hindi).isEmpty ? '—' : part!.explain(hindi),
                  style: const TextStyle(fontSize: 15, height: 1.4)),
              if (part!.labelText.isNotEmpty && part!.labelText.toLowerCase() != part!.name.toLowerCase())
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Photo mein likha tha: "${part!.labelText}"',
                      style: TextStyle(fontSize: 12.5, color: Brand.ink.withValues(alpha: 0.6))),
                ),
              Row(children: [
                IconButton(onPressed: onSpeak, icon: const Icon(Icons.volume_up_rounded), tooltip: 'Suno'),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded), tooltip: context.tr('edit')),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Numbered answer list for practice mode (same numbering as the diagram).
class _AnswerKey extends StatelessWidget {
  const _AnswerKey({required this.doc, required this.version});
  final DiagramDoc doc;
  final int version;

  @override
  Widget build(BuildContext context) {
    // Numbering is the clockwise order computed by the layout engine.
    final anchors = [for (var i = 0; i < doc.result.parts.length; i++) doc.anchorInBody(i)];
    final numbers = LabelLayout.clockwiseNumbers(anchors);
    final order = List.generate(anchors.length, (i) => i)..sort((a, b) => numbers[a].compareTo(numbers[b]));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(spacing: 16, runSpacing: 6, children: [
          for (final i in order)
            Text('${numbers[i]}. ${doc.result.parts[i].name}', style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

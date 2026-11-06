/// Teacher tab: worksheet builder (10), classes dashboard (14), bulk mode (15).
library;

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../l10n/strings.dart';
import '../models/diagram_doc.dart';
import '../services/export_service.dart';
import '../services/library_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bulk_screen.dart';
import 'library_screen.dart';
import 'plans_screen.dart';

class TeacherScreen extends StatelessWidget {
  const TeacherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Text(context.tr('teacher_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        ActionTile(
          icon: Icons.assignment_outlined,
          title: context.tr('worksheet'),
          subtitle: context.tr('worksheet_sub'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorksheetScreen())),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.dashboard_outlined,
          color: Brand.indigo,
          title: context.tr('dashboard'),
          subtitle: context.tr('dashboard_sub'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.local_printshop_outlined,
          color: Brand.coral,
          title: context.tr('bulk'),
          subtitle: context.tr('bulk_sub'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkScreen())),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFFE0A100),
          title: context.tr('plans'),
          subtitle: 'Student • Teacher • School',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
        ),
      ]),
    );
  }
}

/// Feature 10: pick ≤4 saved diagrams → A4 worksheet + answer key.
class WorksheetScreen extends StatefulWidget {
  const WorksheetScreen({super.key});
  @override
  State<WorksheetScreen> createState() => _WorksheetScreenState();
}

class _WorksheetScreenState extends State<WorksheetScreen> {
  final List<DiagramDoc> _docs = [];
  List<ClassRow> _classes = [];
  int? _classId;
  final _title = TextEditingController(text: 'Diagram Worksheet');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LibraryDb.open().then((db) => db.classes()).then((c) {
      if (mounted) setState(() => _classes = c);
    });
  }

  Future<void> _pick() async {
    final ids = await Navigator.push<List<int>>(
        context,
        MaterialPageRoute(
            builder: (_) => DiagramPickerScreen(title: context.tr('select_diagrams'), max: AppConfig.maxWorksheetDiagrams)));
    if (ids == null) return;
    final db = await LibraryDb.open();
    final docs = <DiagramDoc>[];
    for (final id in ids) {
      final d = await db.load(id);
      if (d != null) docs.add(d);
    }
    setState(() => _docs
      ..clear()
      ..addAll(docs));
  }

  Future<void> _make({required bool share}) async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final pdf = await ExportService.worksheetPdf(
          _docs, PdfHeader(name: app.studentName, school: app.schoolName, className: app.className),
          title: _title.text.trim().isEmpty ? 'Diagram Worksheet' : _title.text.trim());
      await (await LibraryDb.open()).addWorksheet(_classId, _title.text.trim(), [for (final d in _docs) d.id!]);
      if (share) {
        await ExportService.shareBytes(pdf, ExportService.fileName(_title.text, 'pdf'), 'application/pdf',
            text: '${_title.text} — ${AppConfig.appName}');
      } else {
        await ExportService.printPdf(pdf, _title.text);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('worksheet'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, decoration: InputDecoration(labelText: context.tr('title'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _classId,
          decoration: InputDecoration(labelText: context.tr('class_section')),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (final c in _classes) DropdownMenuItem(value: c.id, child: Text(c.label)),
          ],
          onChanged: (v) => setState(() => _classId = v),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text('${context.tr('select_diagrams')} (${_docs.length}/${AppConfig.maxWorksheetDiagrams})'),
        ),
        const SizedBox(height: 8),
        for (final d in _docs)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(d.bodyPng, width: 48, height: 48, fit: BoxFit.cover)),
              title: Text(d.title),
              subtitle: Text('${d.result.parts.length} labels'),
            ),
          ),
        const SizedBox(height: 18),
        if (_busy) const LinearProgressIndicator(),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
                onPressed: _docs.isEmpty || _busy ? null : () => _make(share: false),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Print')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
                onPressed: _docs.isEmpty || _busy ? null : () => _make(share: true),
                icon: const Icon(Icons.share_rounded),
                label: const Text('WhatsApp / Share')),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Brand.indigoSoft, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            '🔗 Web link (students open without an account) — coming soon. '
            'It needs online storage (Firebase/Supabase); for now the PDF is shared directly.',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}

/// Feature 14: local dashboard — classes/sections + monthly worksheet history.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<ClassRow> _classes = [];
  List<WorksheetRow> _sheets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await LibraryDb.open();
    final c = await db.classes();
    final w = await db.worksheets();
    if (mounted) {
      setState(() {
        _classes = c;
        _sheets = w;
      });
    }
  }

  Future<void> _addClass() async {
    final name = TextEditingController(), section = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('add_class')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Class (e.g. 9)')),
          const SizedBox(height: 8),
          TextField(controller: section, decoration: const InputDecoration(labelText: 'Section (e.g. B)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('save'))),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await (await LibraryDb.open()).addClass(name.text, section.text);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool thisMonth(DateTime d) => d.year == now.year && d.month == now.month;
    // Monthly counts for the last 6 months (simple bar chart).
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    final counts = [
      for (final m in months) _sheets.where((s) => s.createdAt.year == m.year && s.createdAt.month == m.month).length
    ];
    final maxC = counts.fold<int>(1, (a, b) => b > a ? b : a);
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('dashboard'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _addClass, icon: const Icon(Icons.add), label: Text(context.tr('add_class'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Worksheets: ${_sheets.where((s) => thisMonth(s.createdAt)).length} ${context.tr('this_month')}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 14),
              SizedBox(
                height: 120,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < months.length; i++)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('${counts[i]}', style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: counts[i] / maxC),
                          duration: const Duration(milliseconds: 600),
                          builder: (_, v, _) => Container(
                            height: 6 + 80 * v,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                                color: i == months.length - 1 ? Brand.green : Brand.indigo.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(monthNames[months[i].month - 1], style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        SectionTitle(context.tr('class_section').toUpperCase()),
        if (_classes.isEmpty) const Text('—'),
        for (final c in _classes)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Brand.greenSoft, child: Icon(Icons.groups_rounded, color: Brand.green)),
              title: Text(c.label),
              subtitle: Text(
                  '${_sheets.where((s) => s.classId == c.id && thisMonth(s.createdAt)).length} ${context.tr('this_month')} • '
                  '${_sheets.where((s) => s.classId == c.id).length} total'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await (await LibraryDb.open()).deleteClass(c.id);
                  _load();
                },
              ),
            ),
          ),
        const SectionTitle('HISTORY'),
        for (final s in _sheets.take(30))
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text(s.title.isEmpty ? 'Worksheet' : s.title),
            subtitle: Text(
                '${s.createdAt.day}/${s.createdAt.month}/${s.createdAt.year} • ${s.diagramIds.length} diagram(s)'
                '${s.classId == null ? '' : ' • ${_classes.where((c) => c.id == s.classId).map((c) => c.label).join()}'}'),
          ),
      ]),
    );
  }
}

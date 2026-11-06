/// Library tab: Subject → Chapter folders + search (feature 9).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/diagram.dart';
import '../services/library_db.dart';
import '../theme.dart';
import 'result_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  String? _subject;
  List<SavedDiagramRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final db = await LibraryDb.open();
    final rows = await db.list(query: _query, subject: _subject);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _open(SavedDiagramRow r) async {
    final db = await LibraryDb.open();
    final doc = await db.load(r.id);
    if (doc == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(doc: doc)));
    reload();
  }

  Future<void> _delete(SavedDiagramRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${context.tr('delete')} "${r.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await (await LibraryDb.open()).delete(r.id);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    // Group: subject → chapter → diagrams (rows are already newest first).
    final groups = <String, Map<String, List<SavedDiagramRow>>>{};
    for (final r in _rows) {
      groups.putIfAbsent(r.subject, () => {}).putIfAbsent(r.chapter, () => []).add(r);
    }
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('search')),
            onChanged: (v) {
              _query = v;
              reload();
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final s in [null, ...DiagramResult.subjects])
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(s ?? context.tr('all')),
                  selected: _subject == s,
                  onSelected: (_) {
                    _subject = s;
                    reload();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Image.asset('assets/branding/mascot.png', height: 140),
                        const SizedBox(height: 12),
                        Text(context.tr('library_empty')),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: reload,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                        for (final subject in groups.keys) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                            child: Row(children: [
                              const Icon(Icons.folder_rounded, color: Brand.green),
                              const SizedBox(width: 8),
                              Text(subject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                            ]),
                          ),
                          for (final chapter in groups[subject]!.keys)
                            Card(
                              margin: const EdgeInsets.only(top: 8),
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                shape: const Border(),
                                leading: const Icon(Icons.menu_book_rounded, color: Brand.indigo),
                                title: Text(chapter, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${groups[subject]![chapter]!.length} diagram(s)'),
                                children: [
                                  for (final r in groups[subject]![chapter]!)
                                    ListTile(
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(File(r.imagePath),
                                            width: 52, height: 52, fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => const Icon(Icons.image)),
                                      ),
                                      title: Text(r.title),
                                      subtitle: Text('${r.createdAt.day}/${r.createdAt.month}/${r.createdAt.year}'),
                                      onTap: () => _open(r),
                                      trailing: IconButton(
                                          icon: const Icon(Icons.delete_outline), onPressed: () => _delete(r)),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ]),
                    ),
        ),
      ]),
    );
  }
}

/// Reusable multi-select picker over the library (worksheet, practice, check).
class DiagramPickerScreen extends StatefulWidget {
  const DiagramPickerScreen({super.key, required this.title, this.max = 1});
  final String title;
  final int max;
  @override
  State<DiagramPickerScreen> createState() => _DiagramPickerScreenState();
}

class _DiagramPickerScreenState extends State<DiagramPickerScreen> {
  List<SavedDiagramRow> _rows = [];
  final List<int> _picked = [];

  @override
  void initState() {
    super.initState();
    LibraryDb.open().then((db) => db.list()).then((r) {
      if (mounted) setState(() => _rows = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (widget.max > 1)
          TextButton(
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, List<int>.from(_picked)),
            child: Text('${context.tr('done')} (${_picked.length}/${widget.max})'),
          ),
      ]),
      body: _rows.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.tr('library_empty'))))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final r in _rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: CheckboxListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      value: _picked.contains(r.id),
                      secondary: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(r.imagePath),
                            width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image)),
                      ),
                      title: Text(r.title),
                      subtitle: Text('${r.subject} • ${r.chapter}'),
                      onChanged: (v) {
                        if (widget.max == 1) {
                          Navigator.pop(context, [r.id]);
                          return;
                        }
                        setState(() {
                          if (v == true && _picked.length < widget.max) {
                            _picked.add(r.id);
                          } else {
                            _picked.remove(r.id);
                          }
                        });
                      },
                    ),
                  ),
                ),
            ]),
    );
  }
}

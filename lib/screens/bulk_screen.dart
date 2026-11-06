/// Feature 15: print-shop bulk mode — many photos → one combined PDF.
///
/// Photos are processed one after another (sequential = gentle on the free
/// AI quota and on low-end phones). Failures are listed, the rest still go
/// into the PDF. Each photo counts as one scan for the daily limit.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../models/diagram_doc.dart';
import '../services/diagram_pipeline.dart';
import '../services/export_service.dart';
import '../services/gemini_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _Item {
  final XFile file;
  String status = 'waiting';
  DiagramDoc? doc;
  _Item(this.file);
}

class BulkScreen extends StatefulWidget {
  const BulkScreen({super.key});
  @override
  State<BulkScreen> createState() => _BulkScreenState();
}

class _BulkScreenState extends State<BulkScreen> {
  final List<_Item> _items = [];
  bool _running = false;

  Future<void> _pick() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 92, maxWidth: 2200, limit: 30);
    setState(() => _items.addAll(files.map(_Item.new)));
  }

  Future<void> _run() async {
    final app = AppScope.read(context);
    setState(() => _running = true);
    for (final it in _items.where((i) => i.doc == null)) {
      if (!app.canScan) {
        setState(() => it.status = 'daily limit');
        continue;
      }
      try {
        setState(() => it.status = 'cleaning…');
        final cleaned = await DiagramPipeline.clean(await it.file.readAsBytes(), bw: app.blackAndWhite);
        setState(() => it.status = 'AI…');
        it.doc = await DiagramPipeline.understand(app.ai, cleaned);
        await app.recordScan();
        setState(() => it.status = '✓ ${it.doc!.title}');
      } on NotADiagramException {
        await app.recordScan();
        setState(() => it.status = 'not a diagram');
      } on AiException catch (e) {
        setState(() => it.status = e is DailyLimitException ? 'daily limit' : 'failed');
      } catch (e) {
        setState(() => it.status = 'failed');
      }
    }
    setState(() => _running = false);
  }

  Future<void> _pdf({required bool share}) async {
    final app = AppScope.read(context);
    final docs = [for (final i in _items) if (i.doc != null) i.doc!];
    if (docs.isEmpty) return;
    try {
      final pdf = await ExportService.batchPdf(
          docs, PdfHeader(name: app.studentName, className: app.className, school: app.schoolName));
      if (share) {
        await ExportService.shareBytes(pdf, ExportService.fileName('bulk', 'pdf'), 'application/pdf');
      } else {
        await ExportService.printPdf(pdf, 'Diagrams');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _items.where((i) => i.doc != null).length;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('bulk'))),
      body: Column(children: [
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: FilledButton.icon(
                      onPressed: _pick, icon: const Icon(Icons.photo_library_rounded), label: Text(context.tr('pick_photos'))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor: it.doc != null ? Brand.greenSoft : Brand.indigoSoft, child: Text('${i + 1}')),
                        title: Text(it.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(it.status),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (_running) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Row(children: [
                IconButton.filledTonal(onPressed: _running ? null : _pick, icon: const Icon(Icons.add_photo_alternate_outlined)),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _running || _items.isEmpty ? null : _run,
                    child: Text('${context.tr('processing_n')} (${_items.length})'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: done == 0 || _running ? null : () => _pdf(share: false),
                        icon: const Icon(Icons.print_rounded),
                        label: Text('Print ($done)'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: done == 0 || _running ? null : () => _pdf(share: true),
                        icon: const Icon(Icons.share_rounded),
                        label: Text('PDF ($done)'))),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

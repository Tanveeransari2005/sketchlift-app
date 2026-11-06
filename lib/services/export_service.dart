/// Feature 8 & 10 & 15: PNG / A4 PDF export, printing and sharing.
///
/// PDFs are built with the `pdf` package. The diagram itself is embedded as a
/// high-resolution PNG rendered by [DiagramScene] (same drawing as on screen),
/// and all PDF text uses the bundled Poppins font.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../models/diagram_doc.dart';
import '../widgets/diagram_scene.dart';

/// Text printed in every PDF header.
class PdfHeader {
  final String name, className, school;
  const PdfHeader({this.name = '', this.className = '', this.school = ''});
}

class ExportService {
  ExportService._();

  /// Decodes PNG bytes into a ui.Image.
  static Future<ui.Image> decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    return (await codec.getNextFrame()).image;
  }

  /// Renders [doc] in [mode] to PNG bytes (with title band).
  static Future<Uint8List> renderPng(DiagramDoc doc, DiagramMode mode, {double pixelRatio = 2.5}) async {
    final image = await decode(doc.bodyPng);
    final scene = DiagramScene.build(doc, ui.Size(image.width.toDouble(), image.height.toDouble()), mode);
    final out = await scene.toImage(image, pixelRatio: pixelRatio, title: doc.title);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// Saves a PNG into the phone gallery (Pictures/SketchLift).
  static Future<void> saveToGallery(Uint8List png, String name) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    await Gal.putImageBytes(png, name: _safe(name), album: AppConfig.appName);
  }

  /// Writes bytes to a temp file and opens the Android share sheet.
  static Future<void> shareBytes(Uint8List bytes, String fileName, String mime, {String? text}) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], text: text));
  }

  static Future<void> printPdf(Uint8List pdf, String name) =>
      Printing.layoutPdf(onLayout: (_) async => pdf, name: name);

  // ---------------------------------------------------------------------------
  // PDF builders
  // ---------------------------------------------------------------------------

  static Future<pw.ThemeData> _theme() async {
    final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
    return pw.ThemeData.withFont(base: reg, bold: bold);
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  static pw.Widget _header(PdfHeader h, String title, {bool blanks = false}) {
    final style = const pw.TextStyle(fontSize: 10, color: PdfColors.grey800);
    String v(String s) => s.isEmpty ? '______________' : s;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(AppConfig.appName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.green700)),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Name: ${blanks ? '______________' : v(h.name)}', style: style),
        pw.Text('Class: ${blanks ? '________' : v(h.className)}', style: style),
        pw.Text('Date: ${_date(DateTime.now())}', style: style),
      ]),
      if (h.school.isNotEmpty) pw.Text(h.school, style: style),
      pw.Divider(color: PdfColors.grey400),
    ]);
  }

  static pw.Widget _verifyNote() => pw.Text('AI-generated — ek baar verify kar lo (please verify once).',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600));

  static pw.Widget _answerKey(DiagramDoc doc, DiagramScene scene) {
    final rows = scene.layout.byNumber;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Answer key — ${doc.title}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Wrap(spacing: 18, runSpacing: 4, children: [
        for (final r in rows)
          pw.Text('${r.number}. ${doc.result.parts[r.index].name}', style: const pw.TextStyle(fontSize: 10)),
      ]),
    ]);
  }

  static Future<(pw.MemoryImage, DiagramScene)> _diagramImage(DiagramDoc doc, DiagramMode mode) async {
    final image = await decode(doc.bodyPng);
    final scene = DiagramScene.build(doc, ui.Size(image.width.toDouble(), image.height.toDouble()), mode);
    final out = await scene.toImage(image, pixelRatio: 2.2);
    final bytes = (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return (pw.MemoryImage(bytes), scene);
  }

  /// Single diagram → A4 PDF. Practice mode adds the answer key on page 2.
  static Future<Uint8List> diagramPdf(DiagramDoc doc, DiagramMode mode, PdfHeader header) async {
    final pdf = pw.Document(theme: await _theme(), title: doc.title, author: header.name);
    final (img, scene) = await _diagramImage(doc, mode);
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(children: [
        _header(header, mode == DiagramMode.practice ? '${doc.title} — Practice' : doc.title),
        pw.SizedBox(height: 12),
        pw.Expanded(child: pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))),
        if (mode == DiagramMode.labelled) ...[
          pw.SizedBox(height: 8),
          for (final r in scene.layout.byNumber)
            if (doc.result.parts[r.index].explainEn.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text('${r.number}. ${doc.result.parts[r.index].name}: ${doc.result.parts[r.index].explainEn}',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
        ],
        pw.SizedBox(height: 6),
        _verifyNote(),
      ]),
    ));
    if (mode == DiagramMode.practice) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _header(header, 'Answer key'),
          _answerKey(doc, scene),
        ]),
      ));
    }
    return pdf.save();
  }

  /// Feature 10: up to 4 diagrams as a blank worksheet + answer-key page.
  static Future<Uint8List> worksheetPdf(List<DiagramDoc> docs, PdfHeader teacher, {String title = 'Diagram Worksheet'}) async {
    final pdf = pw.Document(theme: await _theme(), title: title, author: teacher.name);
    final rendered = <(pw.MemoryImage, DiagramScene)>[];
    for (final d in docs) {
      rendered.add(await _diagramImage(d, DiagramMode.practice));
    }
    // 1 diagram per page if 1, else 2 per page.
    final perPage = docs.length == 1 ? 1 : 2;
    for (var i = 0; i < docs.length; i += perPage) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(children: [
          _header(PdfHeader(school: teacher.school), title, blanks: true),
          for (var k = i; k < i + perPage && k < docs.length; k++) ...[
            pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('Q${k + 1}. Label the diagram: ${docs[k].title}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 4),
            pw.Expanded(child: pw.Center(child: pw.Image(rendered[k].$1, fit: pw.BoxFit.contain))),
            pw.SizedBox(height: 8),
          ],
        ]),
      ));
    }
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _header(teacher, 'Answer key — $title'),
        for (var k = 0; k < docs.length; k++) ...[
          pw.Text('Q${k + 1}.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          _answerKey(docs[k], rendered[k].$2),
          pw.SizedBox(height: 12),
        ],
        pw.Spacer(),
        _verifyNote(),
      ]),
    ));
    return pdf.save();
  }

  /// Feature 15: many processed diagrams → one PDF, one per page.
  static Future<Uint8List> batchPdf(List<DiagramDoc> docs, PdfHeader header) async {
    final pdf = pw.Document(theme: await _theme(), title: 'Diagrams', author: header.name);
    for (final d in docs) {
      final (img, _) = await _diagramImage(d, DiagramMode.labelled);
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(children: [
          _header(header, d.title),
          pw.Expanded(child: pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))),
          _verifyNote(),
        ]),
      ));
    }
    return pdf.save();
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  static String fileName(String title, String ext) =>
      '${_safe(AppConfig.appName)}_${_safe(title)}_${DateTime.now().millisecondsSinceEpoch}.$ext';
}

/// Feature 10 (future): a no-account web link for worksheets needs hosting.
///
/// TODO(backend): implement with Firebase Storage / Supabase Storage — upload
/// the PDF, return a public URL, and show it with a QR code. Until then the
/// app shares the PDF file directly through the WhatsApp share sheet.
abstract class WorksheetLinkPublisher {
  /// Uploads [pdf] and returns a public link students can open without login.
  Future<Uri> publish(Uint8List pdf, {required String title});
}

class NotConfiguredLinkPublisher implements WorksheetLinkPublisher {
  const NotConfiguredLinkPublisher();
  @override
  Future<Uri> publish(Uint8List pdf, {required String title}) =>
      throw UnimplementedError('Web links need a backend (Firebase/Supabase) — not set up yet.');
}

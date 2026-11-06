// Renders real app screens to PNG for the README / portfolio.
//
//   flutter test --update-goldens test/screenshots_test.dart
//
// Output: test/goldens/*.png  (copied to docs/screenshots/ for the README).
// Uses the real image pipeline + the recorded real Gemini answer (offline).
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sketchlift/models/diagram.dart';
import 'package:sketchlift/models/diagram_doc.dart';
import 'package:sketchlift/screens/onboarding_screen.dart';
import 'package:sketchlift/screens/photosynthesis_screen.dart';
import 'package:sketchlift/screens/plans_screen.dart';
import 'package:sketchlift/screens/result_screen.dart';
import 'package:sketchlift/screens/scan_screen.dart';
import 'package:sketchlift/services/diagram_pipeline.dart';
import 'package:sketchlift/services/export_service.dart';
import 'package:sketchlift/services/image_pipeline.dart';
import 'package:sketchlift/state/app_state.dart';
import 'package:sketchlift/theme.dart';
import 'package:sketchlift/widgets/diagram_scene.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Poppins', [
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final mf = '$flutterRoot/bin/cache/artifacts/material_fonts';
  // Roboto = Android's system font (fallback for ₂, → …).
  await load('Roboto', ['$mf/Roboto-Regular.ttf', '$mf/Roboto-Medium.ttf', '$mf/Roboto-Bold.ttf']);
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
  // Devanagari fallback for Hindi text (if the machine has Noto).
  for (final p in ['/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf']) {
    if (File(p).existsSync()) await load('Poppins', [p]);
  }
}

Future<DiagramDoc> _demoDoc() async {
  final raw = File('assets/demo/plant_cell_photo.jpg').readAsBytesSync();
  final processed = processPhoto(ProcessRequest(raw));
  final result = DiagramResult.parseModelText(File('assets/demo/plant_cell_gemini.json').readAsStringSync());
  DiagramPipeline.applyGlossary(result);
  final boxes = [for (final p in result.parts) if (p.labelBox != null) p.labelBox!];
  final cleaned = cleanBody(CleanBodyRequest(processed, result.bodyBox, boxes));
  return DiagramDoc(result: result, bodyPng: cleaned.png, usedBody: cleaned.usedBody);
}

Widget _app(AppState s, Widget child) => AppScope(
      state: s,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: child),
    );

void main() {
  late AppState state;
  late DiagramDoc doc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    SharedPreferences.setMockInitialValues({'onboarded': true});
    state = await AppState.load();
    doc = await _demoDoc();
  });

  Future<void> shoot(WidgetTester tester, String name, Widget w,
      {Future<void> Function()? warm, Future<void> Function()? after}) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(state, w));
      // Let images decode (real async work), then settle animations.
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (warm != null) await warm();
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    if (after != null) await after();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('01 onboarding', (t) async => shoot(t, '01_onboarding', const OnboardingScreen()));
  testWidgets('02 scan home', (t) async => shoot(t, '02_scan', const Scaffold(body: ScanScreen())));
  testWidgets('03 result labelled', (t) async {
    await shoot(t, '03_result_labelled', ResultScreen(doc: doc), warm: () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
  });
  testWidgets('04 result tapped label', (t) async {
    await shoot(t, '04_result_explain', ResultScreen(doc: doc), warm: () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }, after: () async {
      // Tap label #1 using the scene's own geometry.
      final view = find.byType(CustomPaint).evaluate().where((e) => (e.widget as CustomPaint).painter is DiagramPainter).first;
      final box = view.renderObject as RenderBox;
      final painter = (view.widget as CustomPaint).painter as DiagramPainter;
      final scale = box.size.width / painter.scene.size.width;
      final first = painter.scene.layout.byNumber.first;
      await t.tapAt(box.localToGlobal(first.rect.center * scale));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    });
  });
  testWidgets('05 practice', (t) async {
    await shoot(t, '05_practice', ResultScreen(doc: doc, startInPractice: true), warm: () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
  });
  testWidgets('06 photosynthesis', (t) async {
    await shoot(t, '06_photosynthesis', const PhotosynthesisScreen());
  });
  testWidgets('07 plans', (t) async => shoot(t, '07_plans', const PlansScreen()));

  test('08 before/after export PNG', () async {
    // Clean PNG export exactly as "Save PNG" produces it.
    final image = await ExportService.decode(doc.bodyPng);
    final scene = DiagramScene.build(doc, Size(image.width.toDouble(), image.height.toDouble()), DiagramMode.labelled);
    final out = await scene.toImage(image, pixelRatio: 2, title: doc.title);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    Directory('test/goldens').createSync(recursive: true);
    File('test/goldens/08_export_labelled.png').writeAsBytesSync(png!.buffer.asUint8List());
    final scene2 = DiagramScene.build(doc, Size(image.width.toDouble(), image.height.toDouble()), DiagramMode.practice);
    final out2 = await scene2.toImage(image, pixelRatio: 2, title: '${doc.title} — Practice');
    File('test/goldens/09_export_practice.png')
        .writeAsBytesSync((await out2.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    // PDF too (A4, header, answer key).
    final pdf = await ExportService.diagramPdf(doc, DiagramMode.practice, const PdfHeader(name: 'Tanveer Ansari', className: '9-B'));
    File('test/goldens/10_practice.pdf').writeAsBytesSync(pdf);
    expect(pdf.length, greaterThan(1000));
  });
}

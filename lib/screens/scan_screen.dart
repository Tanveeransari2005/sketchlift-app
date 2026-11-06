/// Scan tab: camera / gallery / smart scan / demo → crop → process → result.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../app_config.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'crop_screen.dart';
import 'plans_screen.dart';
import 'processing_screen.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final app = AppScope.read(context);
    if (!app.canScan) return _limitReached(context);
    final x = await ImagePicker().pickImage(source: source, imageQuality: 95, maxWidth: 2400);
    if (x == null || !context.mounted) return;
    final bytes = await x.readAsBytes();
    if (!context.mounted) return;
    // Manual 4-corner crop (works on every phone).
    final crop = await Navigator.push<CropResult>(
        context, MaterialPageRoute(builder: (_) => CropScreen(bytes: bytes)));
    if (crop == null || !context.mounted) return;
    _process(context, bytes, crop.corners, crop.blackAndWhite);
  }

  /// ML Kit document scanner: auto edge detection + crop (Google Play services).
  Future<void> _smartScan(BuildContext context) async {
    final app = AppScope.read(context);
    if (!app.canScan) return _limitReached(context);
    try {
      final scanner = DocumentScanner(
          options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        mode: ScannerMode.filter,
        pageLimit: 1,
        isGalleryImport: true,
      ));
      final res = await scanner.scanDocument();
      await scanner.close();
      final path = res.images?.isNotEmpty == true ? res.images!.first : null;
      if (path == null || !context.mounted) return;
      final bytes = await File(path).readAsBytes();
      if (!context.mounted) return;
      _process(context, bytes, null, app.blackAndWhite);
    } catch (e) {
      if (!context.mounted) return;
      // Scanner not available (no Play services) → fall back to manual crop.
      showSnack(context, 'Smart scan not available on this phone — using manual crop.');
      _pick(context, ImageSource.camera);
    }
  }

  void _process(BuildContext context, Uint8List bytes, List<double>? corners, bool bw) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProcessingScreen(raw: bytes, corners: corners, blackAndWhite: bw)));
  }

  void _limitReached(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aaj ki limit poori 🙏'),
        content: Text('Free plan: ${AppScope.read(context).dailyLimit} diagrams/day.\n'
            'Kal phir aao, ya Settings mein apni Gemini key daalo (unlimited).'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen()));
              },
              child: const Text('Plans')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(children: [
            Hero(tag: 'logo', child: Image.asset('assets/branding/logo.png', height: 40)),
            const SizedBox(width: 10),
            Text(AppConfig.appName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            _QuotaChip(app: app),
          ]),
          const SizedBox(height: 20),
          // Hero card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Brand.green, Color(0xFF3FB98A)]),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('scan_hero'),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(context.tr('scan_sub'), style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                ]),
              ),
              Image.asset('assets/branding/mascot.png', height: 110),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: BigAction(
                    icon: Icons.photo_camera_rounded,
                    label: context.tr('camera'),
                    color: Brand.indigo,
                    onTap: () => _pick(context, ImageSource.camera))),
            const SizedBox(width: 14),
            Expanded(
                child: BigAction(
                    icon: Icons.photo_library_rounded,
                    label: context.tr('gallery'),
                    color: Brand.coral,
                    onTap: () => _pick(context, ImageSource.gallery))),
          ]),
          const SizedBox(height: 14),
          ActionTile(
            icon: Icons.crop_free_rounded,
            title: context.tr('smart_scan'),
            subtitle: 'Google ML Kit document scanner',
            onTap: () => _smartScan(context),
          ),
          const SizedBox(height: 10),
          ActionTile(
            icon: Icons.play_circle_outline_rounded,
            title: context.tr('try_demo'),
            subtitle: 'Plant cell sketch → clean diagram',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ProcessingScreen(demo: true))),
          ),
          const SizedBox(height: 18),
          const VerifyNote(),
        ],
      ),
    );
  }
}

class _QuotaChip extends StatelessWidget {
  const _QuotaChip({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final text = app.unlimited ? '∞' : '${app.scansLeft}/${app.dailyLimit}';
    return Tooltip(
      message: app.unlimited ? context.tr('unlimited') : context.tr('left_today'),
      child: Chip(
        avatar: const Icon(Icons.bolt_rounded, size: 18, color: Brand.green),
        label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Brand.greenSoft,
        side: BorderSide.none,
      ),
    );
  }
}

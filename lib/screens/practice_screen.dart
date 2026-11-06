/// Practice tab: practice sheets, "Meri drawing check karo", animated diagram.
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/library_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'check_drawing_screen.dart';
import 'library_screen.dart';
import 'photosynthesis_screen.dart';
import 'result_screen.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  Future<void> _practiceSheet(BuildContext context) async {
    final ids = await Navigator.push<List<int>>(
        context, MaterialPageRoute(builder: (_) => DiagramPickerScreen(title: context.tr('practice_sheet'))));
    if (ids == null || ids.isEmpty || !context.mounted) return;
    final doc = await (await LibraryDb.open()).load(ids.first);
    if (doc == null || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(doc: doc, startInPractice: true)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Text(context.tr('practice_title'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        ActionTile(
          icon: Icons.quiz_outlined,
          title: context.tr('practice_sheet'),
          subtitle: context.tr('practice_sheet_sub'),
          onTap: () => _practiceSheet(context),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.fact_check_outlined,
          color: Brand.indigo,
          title: context.tr('check_drawing'),
          subtitle: context.tr('check_drawing_sub'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckDrawingScreen())),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.wb_sunny_outlined,
          color: const Color(0xFFE0A100),
          title: context.tr('animated'),
          subtitle: context.tr('animated_sub'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotosynthesisScreen())),
        ),
      ]),
    );
  }
}

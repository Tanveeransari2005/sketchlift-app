/// Bottom navigation: Scan · Library · Practice · Teacher · Settings.
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'library_screen.dart';
import 'practice_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'teacher_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;

  // Library reloads whenever it becomes visible (simple + reliable).
  final _libraryKey = GlobalKey<LibraryScreenState>();

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ScanScreen(),
      LibraryScreen(key: _libraryKey),
      const PracticeScreen(),
      const TeacherScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.document_scanner_outlined),
              selectedIcon: const Icon(Icons.document_scanner),
              label: context.tr('nav_scan')),
          NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: context.tr('nav_library')),
          NavigationDestination(
              icon: const Icon(Icons.edit_note_outlined),
              selectedIcon: const Icon(Icons.edit_note),
              label: context.tr('nav_practice')),
          NavigationDestination(
              icon: const Icon(Icons.school_outlined),
              selectedIcon: const Icon(Icons.school),
              label: context.tr('nav_teacher')),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: context.tr('nav_settings')),
        ],
      ),
    );
  }
}

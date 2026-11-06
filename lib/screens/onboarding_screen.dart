/// 3-screen animated onboarding (shown once).
library;

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _page = PageController();
  int _index = 0;
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _page.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pages = [
      (Icons.photo_camera_rounded, Brand.indigo, 'onb1_t', 'onb1_b'),
      (Icons.auto_awesome_rounded, Brand.green, 'onb2_t', 'onb2_b'),
      (Icons.print_rounded, Brand.coral, 'onb3_t', 'onb3_b'),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              Image.asset('assets/branding/logo.png', height: 34),
              const SizedBox(width: 8),
              Text(AppConfig.appName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              // Language toggle right on the first screen.
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('EN')),
                  ButtonSegment(value: true, label: Text('हिं')),
                ],
                selected: {app.hindi},
                showSelectedIcon: false,
                onSelectionChanged: (s) => app.setHindi(s.first),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final (icon, color, t, b) = pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedBuilder(
                      animation: _bob,
                      builder: (_, child) =>
                          Transform.translate(offset: Offset(0, -10 * Curves.easeInOut.transform(_bob.value)), child: child),
                      child: i == 0
                          ? Image.asset('assets/branding/mascot.png', height: 220)
                          : Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: Icon(icon, size: 96, color: color),
                            ),
                    ),
                    const SizedBox(height: 36),
                    Text(context.tr(t),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(context.tr(b),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Brand.ink.withValues(alpha: 0.7))),
                    if (i == 0) ...[
                      const SizedBox(height: 16),
                      Text(AppConfig.tagline,
                          style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.all(4),
                width: i == _index ? 26 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? Brand.green : Brand.green.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(children: [
              TextButton(onPressed: app.setOnboarded, child: Text(context.tr('skip'))),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (_index < pages.length - 1) {
                    _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
                  } else {
                    app.setOnboarded();
                  }
                },
                child: Text(context.tr(_index < pages.length - 1 ? 'next' : 'start')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

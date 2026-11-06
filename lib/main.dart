/// SketchLift — messy diagram photo → clean, labelled, print-ready diagram.
///
/// Entry point: loads settings, then shows onboarding (first run) or the
/// bottom-navigation home shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  final state = await AppState.load();
  runApp(SketchLiftApp(state: state));
}

class SketchLiftApp extends StatelessWidget {
  const SketchLiftApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: state,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: state.onboarded ? const HomeShell() : const OnboardingScreen(),
          ),
        ),
      ),
    );
  }
}

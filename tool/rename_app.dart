// Renames the app's DISPLAY name everywhere in one go.
//
//   dart run tool/rename_app.dart "NewName"
//
// Updates: lib/app_config.dart (AppConfig.appName), the Android launcher label,
// the pubspec description and README.md. (The package id
// com.tanveer.sketchlift is NOT changed — changing it makes a "different app"
// on Android, so do that only before the first public release.)
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || args.first.trim().isEmpty) {
    stderr.writeln('Usage: dart run tool/rename_app.dart "NewName"');
    exit(64);
  }
  final newName = args.first.trim();
  final config = File('lib/app_config.dart');
  final m = RegExp(r"static const String appName = '([^']*)';").firstMatch(config.readAsStringSync());
  if (m == null) {
    stderr.writeln('Could not find AppConfig.appName');
    exit(1);
  }
  final old = m.group(1)!;
  void replaceIn(String path, String from, String to) {
    final f = File(path);
    if (!f.existsSync()) return;
    final s = f.readAsStringSync();
    if (s.contains(from)) {
      f.writeAsStringSync(s.replaceAll(from, to));
      stdout.writeln('updated $path');
    }
  }

  replaceIn('lib/app_config.dart', "appName = '$old'", "appName = '$newName'");
  replaceIn('android/app/src/main/AndroidManifest.xml', 'android:label="$old"', 'android:label="$newName"');
  replaceIn('pubspec.yaml', 'description: "$old', 'description: "$newName');
  replaceIn('README.md', old, newName);
  stdout.writeln('Renamed "$old" → "$newName". Regenerate the wordmark (assets/branding/logo_wordmark.png) if needed.');
}

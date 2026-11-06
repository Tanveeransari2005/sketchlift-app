/// ---------------------------------------------------------------------------
/// App-wide configuration — THE ONE PLACE to change the app's name & defaults.
/// ---------------------------------------------------------------------------
///
/// Final name: SketchLift (chosen Nov 2026). If it ever changes again,
/// everything the user sees reads the name from [AppConfig.appName].
/// To rename the app everywhere (Dart + Android launcher label + README), run:
///
///   dart run tool/rename_app.dart "NewName"
///
/// Values marked "dart-define" can be overridden at build time without editing
/// code, e.g.:
///
///   flutter build apk --release \
///     --dart-define=PROXY_URL=https://sketchlift-proxy.vercel.app/api/generate \
///     --dart-define=GEMINI_API_KEY=xxxx   # dev only, never commit a key
library;

class AppConfig {
  AppConfig._();

  /// Display name of the app (swap with tool/rename_app.dart).
  static const String appName = 'SketchLift';

  /// Short tagline shown on the splash / onboarding.
  static const String tagline = 'Ganda sketch → saaf diagram';

  /// URL of the free-tier proxy (source in /proxy, deployed on Vercel). When
  /// this is non-empty and the user has NOT entered their own key, all Gemini
  /// calls go through the proxy, so friends can use the app without a key.
  /// Contract: `POST {"model": m, "body": generateContentBody}` with headers
  /// `X-App: sketchlift` and `X-Device-Id: per-install-id`; 429 = daily limit.
  static const String proxyUrl = String.fromEnvironment('PROXY_URL',
      defaultValue: 'https://sketchlift-proxy.vercel.app/api/generate');

  /// Value of the X-App header the proxy expects.
  static const String proxyAppId = 'sketchlift';

  /// Model requested through the proxy (must be in the proxy's allow-list).
  static const String proxyModel =
      String.fromEnvironment('PROXY_MODEL', defaultValue: 'gemini-3.8-flash');

  /// Optional developer key injected at build time (never commit a real key).
  /// A key typed in Settings always wins over this.
  static const String devGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Default model when the user brings their OWN key (newest GA "Flash"
  /// model at the time of writing, Nov 2026).
  /// Users can change it in Settings → Advanced if Google renames models.
  static const String defaultModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');

  /// Free plan: how many new diagram scans per day (local counter).
  static const int freeDailyScans = 5;

  /// Max diagrams a teacher can combine in one worksheet.
  static const int maxWorksheetDiagrams = 4;

  /// Developer / portfolio link shown in Settings → About.
  static const String developer = 'Tanveer Ansari';
}

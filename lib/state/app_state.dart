/// App-wide state: settings, language, AI config and the daily free counter.
///
/// Simple `ChangeNotifier` + `InheritedNotifier` (no extra state library), so
/// any widget can call `AppScope.of(context)` and rebuild when settings change.
library;

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../services/gemini_service.dart';

class AppState extends ChangeNotifier {
  AppState(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _kKey = 'gemini_api_key';

  String _ownKey = '';

  /// Loads settings (and the API key from encrypted storage).
  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    final s = AppState(prefs, secure);
    try {
      s._ownKey = await secure.read(key: _kKey) ?? '';
    } catch (_) {
      s._ownKey = ''; // keystore problems should never crash the app
    }
    if (s.deviceId.isEmpty) {
      await prefs.setString('device_id', _newDeviceId());
    }
    return s;
  }

  /// Random 32-char id, generated once per install (for the proxy's limit).
  static String _newDeviceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ---- simple getters / setters --------------------------------------------
  String get deviceId => _prefs.getString('device_id') ?? '';
  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  bool get hindi => _prefs.getBool('hindi') ?? false;
  String get studentName => _prefs.getString('student_name') ?? '';
  String get className => _prefs.getString('class_name') ?? '';
  String get schoolName => _prefs.getString('school_name') ?? '';
  String get model => _prefs.getString('model') ?? AppConfig.defaultModel;
  int get dailyLimit => _prefs.getInt('daily_limit') ?? AppConfig.freeDailyScans;
  bool get blackAndWhite => _prefs.getBool('bw') ?? false;

  /// Key typed in Settings, else the optional --dart-define dev key.
  String get ownKey => _ownKey.isNotEmpty ? _ownKey : AppConfig.devGeminiKey;
  bool get hasOwnKey => ownKey.isNotEmpty;
  bool get hasKeyInSettings => _ownKey.isNotEmpty;

  Future<void> _set(Future<bool> f) async {
    await f;
    notifyListeners();
  }

  Future<void> setOnboarded() => _set(_prefs.setBool('onboarded', true));
  Future<void> setHindi(bool v) => _set(_prefs.setBool('hindi', v));
  Future<void> setStudentName(String v) => _set(_prefs.setString('student_name', v.trim()));
  Future<void> setClassName(String v) => _set(_prefs.setString('class_name', v.trim()));
  Future<void> setSchoolName(String v) => _set(_prefs.setString('school_name', v.trim()));
  Future<void> setModel(String v) =>
      _set(v.trim().isEmpty ? _prefs.remove('model') : _prefs.setString('model', v.trim()));
  Future<void> setDailyLimit(int v) => _set(_prefs.setInt('daily_limit', v.clamp(1, 100)));
  Future<void> setBlackAndWhite(bool v) => _set(_prefs.setBool('bw', v));

  Future<void> setOwnKey(String key) async {
    _ownKey = key.trim();
    if (_ownKey.isEmpty) {
      await _secure.delete(key: _kKey);
    } else {
      await _secure.write(key: _kKey, value: _ownKey);
    }
    notifyListeners();
  }

  /// Gemini client configured for the current settings.
  GeminiService get ai => GeminiService(AiConfig(
        ownKey: ownKey,
        model: model,
        proxyUrl: AppConfig.proxyUrl,
        deviceId: deviceId,
      ));

  // ---- daily free counter (feature 16) --------------------------------------
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// Scans used today (resets automatically on a new day).
  int get scansToday => _prefs.getString('usage_day') == _today() ? (_prefs.getInt('usage_count') ?? 0) : 0;

  /// Own key = unlimited (the user pays with their own Google quota).
  bool get unlimited => hasOwnKey;
  int get scansLeft => unlimited ? 999 : max(0, dailyLimit - scansToday);
  bool get canScan => unlimited || scansLeft > 0;

  Future<void> recordScan() async {
    await _prefs.setString('usage_day', _today());
    await _prefs.setInt('usage_count', scansToday + 1);
    notifyListeners();
  }

  /// Teacher "classes" list is small; stored as simple prefs (see LibraryDb
  /// for worksheet history).
}

/// Makes [AppState] available to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}

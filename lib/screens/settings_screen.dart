/// Settings: language, PDF header details, AI connection (free server or own
/// Gemini key in encrypted storage), daily limit, plans, about.
library;

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'plans_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState app = AppScope.read(context);
  late final _name = TextEditingController(text: app.studentName);
  late final _class = TextEditingController(text: app.className);
  late final _school = TextEditingController(text: app.schoolName);
  final _key = TextEditingController();
  late final _model = TextEditingController(text: app.model);
  bool _showKey = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Text(context.tr('settings_title'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        SectionTitle(context.tr('language').toUpperCase()),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('English')),
            ButtonSegment(value: true, label: Text('हिंदी')),
          ],
          selected: {app.hindi},
          onSelectionChanged: (s) => app.setHindi(s.first),
        ),
        SectionTitle(context.tr('student_details').toUpperCase()),
        TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('student_name')), onChanged: app.setStudentName),
        const SizedBox(height: 10),
        TextField(controller: _class, decoration: InputDecoration(labelText: context.tr('class_name')), onChanged: app.setClassName),
        const SizedBox(height: 10),
        TextField(controller: _school, decoration: InputDecoration(labelText: context.tr('school_name')), onChanged: app.setSchoolName),
        const SizedBox(height: 4),
        Text('Tip: PDF header ke liye English letters use karo.',
            style: TextStyle(fontSize: 12, color: Brand.ink.withValues(alpha: 0.55))),
        SectionTitle(context.tr('ai_section').toUpperCase()),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(app.hasOwnKey ? Icons.key_rounded : Icons.cloud_done_rounded, color: Brand.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(app.hasOwnKey ? context.tr('own_key') : context.tr('free_server'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                app.hasOwnKey
                    ? '${context.tr('key_saved')} • ${context.tr('unlimited')}'
                    : '${app.scansLeft}/${app.dailyLimit} ${context.tr('left_today')}',
                style: TextStyle(color: Brand.ink.withValues(alpha: 0.65)),
              ),
              const Divider(height: 24),
              Text(context.tr('own_key'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Free key: aistudio.google.com → Get API key. Key sirf is phone mein encrypted save hoti hai.',
                  style: TextStyle(fontSize: 12.5, color: Brand.ink.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              TextField(
                controller: _key,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  hintText: app.hasKeyInSettings ? '•••••••••• (saved)' : context.tr('own_key_hint'),
                  suffixIcon: IconButton(
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (app.hasKeyInSettings)
                  TextButton(
                    onPressed: () async {
                      await app.setOwnKey('');
                      if (context.mounted) showSnack(context, 'Key removed — using free server');
                    },
                    child: Text(context.tr('remove_key')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    if (_key.text.trim().length < 20) {
                      showSnack(context, 'Ye key sahi nahi lag rahi');
                      return;
                    }
                    await app.setOwnKey(_key.text);
                    _key.clear();
                    if (context.mounted) showSnack(context, '✅ ${context.tr('key_saved')}');
                  },
                  child: Text(context.tr('save')),
                ),
              ]),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                title: const Text('Advanced', style: TextStyle(fontSize: 14)),
                children: [
                  TextField(
                    controller: _model,
                    decoration: InputDecoration(labelText: context.tr('model'), helperText: 'Default: ${AppConfig.defaultModel}'),
                    onSubmitted: app.setModel,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(context.tr('daily_limit'))),
                    IconButton(onPressed: () => app.setDailyLimit(app.dailyLimit - 1), icon: const Icon(Icons.remove_circle_outline)),
                    Text('${app.dailyLimit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(onPressed: () => app.setDailyLimit(app.dailyLimit + 1), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  Text('Free server ki apni limit bhi hai (${AppConfig.freeDailyScans}/day per phone).',
                      style: TextStyle(fontSize: 12, color: Brand.ink.withValues(alpha: 0.55))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${context.tr('bw_mode')} (default)'),
                    value: app.blackAndWhite,
                    onChanged: app.setBlackAndWhite,
                  ),
                ],
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        ActionTile(
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFFE0A100),
          title: context.tr('plans'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen())),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.info_outline_rounded,
          color: Brand.indigo,
          title: context.tr('about'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: AppConfig.appName,
            applicationVersion: '1.0.0',
            applicationIcon: Image.asset('assets/branding/logo.png', width: 48),
            applicationLegalese: '${AppConfig.tagline}\nMade by ${AppConfig.developer} • MIT licence\nAI: Google Gemini',
          ),
        ),
        const SizedBox(height: 18),
        Center(child: Image.asset('assets/branding/logo_wordmark.png', height: 36)),
      ]),
    );
  }
}

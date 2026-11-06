/// Small shared widgets.
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme.dart';

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// "Ek baar verify kar lo" — shown on every AI output.
class VerifyNote extends StatelessWidget {
  const VerifyNote({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Brand.sun.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF8A6100)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Ek baar verify kar lo • ${context.tr('verify_note')}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B4B00))),
        ),
      ]),
    );
  }
}

/// Large square-ish action button used on the Scan tab.
class BigAction extends StatelessWidget {
  const BigAction({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(children: [
            CircleAvatar(
                radius: 28, backgroundColor: color.withValues(alpha: 0.14), child: Icon(icon, color: color, size: 30)),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

/// List row card with icon, title, subtitle and chevron.
class ActionTile extends StatelessWidget {
  const ActionTile(
      {super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.color = Brand.green, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.13), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: Brand.ink.withValues(alpha: 0.6))),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

/// Section title.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.6, color: Brand.ink.withValues(alpha: 0.6))),
      );
}

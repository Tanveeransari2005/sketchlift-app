/// Feature 16: plans (UI only — no payment integration yet).
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class Plan {
  final String name, price, note;
  final List<String> perks;
  final Color color;
  final bool current;
  const Plan(this.name, this.price, this.note, this.perks, this.color, {this.current = false});
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final plans = [
      Plan('Free', '₹0', '${app.dailyLimit} diagrams / day', const ['Clean labelled diagram', 'Practice sheet + answer key', 'PDF / PNG / WhatsApp share'],
          Brand.green, current: true),
      const Plan('Student', '₹49 / month', 'or ₹299 / year', ['Unlimited diagrams', 'Check my drawing', 'Voice ask in Hindi/English'], Brand.indigo),
      const Plan('Teacher', '₹199 / month', 'Unlimited worksheets', ['4-diagram worksheets + answer keys', 'Class & section history', 'Bulk PDF'], Brand.coral),
      const Plan('School / Coaching', '₹5,000 – 15,000 / year', 'Licence for all teachers', ['Bulk print-shop mode', 'Shared worksheet library', 'Priority support'], Color(0xFFE0A100)),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('plans'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final p in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.current ? p.color : Colors.transparent, width: 2),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 6, backgroundColor: p.color),
                  const SizedBox(width: 8),
                  Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (p.current) Chip(label: const Text('Current'), backgroundColor: Brand.greenSoft, side: BorderSide.none),
                ]),
                const SizedBox(height: 6),
                Text(p.price, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.color)),
                Text(p.note, style: TextStyle(color: Brand.ink.withValues(alpha: 0.6))),
                const SizedBox(height: 10),
                for (final perk in p.perks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: p.color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(perk)),
                    ]),
                  ),
                if (!p.current) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => showSnack(context, '${context.tr('coming_soon')} 🚀'),
                      child: Text(context.tr('coming_soon')),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        Text('Payments are not live yet — nothing will be charged.',
            textAlign: TextAlign.center, style: TextStyle(color: Brand.ink.withValues(alpha: 0.55), fontSize: 12)),
      ]),
    );
  }
}

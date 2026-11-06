/// Feature 12: interactive animated diagram — Photosynthesis.
///
/// * light-intensity slider → more sunlight rays and more O₂ bubbles per second
/// * labelled: Sunlight, Leaf (chlorophyll), CO₂, Water, O₂, Glucose
/// * "Play steps" walks through the process one step at a time (EN/HI captions)
///
/// Built with a CustomPainter + a Ticker driving a tiny particle system.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';

class PhotoStep {
  final String en, hi;
  final String focus; // which element glows
  const PhotoStep(this.focus, this.en, this.hi);
}

const photoSteps = [
  PhotoStep('sun', 'Sunlight falls on the leaf. Chlorophyll absorbs the light energy.',
      'सूरज की रोशनी पत्ती पर पड़ती है। क्लोरोफ़िल प्रकाश ऊर्जा सोख लेता है।'),
  PhotoStep('water', 'Water (H₂O) travels up from the roots through the xylem to the leaf.',
      'पानी (H₂O) जड़ों से ज़ाइलम के रास्ते पत्ती तक पहुँचता है।'),
  PhotoStep('co2', 'Carbon dioxide (CO₂) from air enters the leaf through tiny pores called stomata.',
      'हवा की कार्बन डाइऑक्साइड (CO₂) स्टोमेटा नाम के छोटे छिद्रों से पत्ती में जाती है।'),
  PhotoStep('glucose', 'In the chloroplasts, light energy joins CO₂ and water to make glucose (food).',
      'क्लोरोप्लास्ट में प्रकाश ऊर्जा से CO₂ और पानी मिलकर ग्लूकोज़ (भोजन) बनाते हैं।'),
  PhotoStep('o2', 'Oxygen (O₂) is released as bubbles. More light → more bubbles!',
      'ऑक्सीजन (O₂) बुलबुलों के रूप में निकलती है। ज़्यादा रोशनी → ज़्यादा बुलबुले!'),
];

class _Particle {
  Offset pos;
  final Offset vel;
  double age = 0;
  final double life;
  final String kind; // o2 | co2 | water
  _Particle(this.pos, this.vel, this.life, this.kind);
}

class PhotosynthesisScreen extends StatefulWidget {
  const PhotosynthesisScreen({super.key});
  @override
  State<PhotosynthesisScreen> createState() => _PhotosynthesisScreenState();
}

class _PhotosynthesisScreenState extends State<PhotosynthesisScreen> with SingleTickerProviderStateMixin {
  double _light = 0.6;
  int? _step; // null = free play
  bool _playing = false;
  late bool _hindi = AppScope.read(context).hindi;
  final List<_Particle> _particles = [];
  final _rnd = math.Random(7);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _o2Acc = 0, _co2Acc = 0, _waterAcc = 0, _stepClock = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Advances the simulation. Coordinates are in a 0..1 "scene" space.
  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _time += dt;
    // Emission rates: O₂ grows strongly with light (that's the lesson!).
    _o2Acc += dt * (0.3 + 7 * _light * _light);
    _co2Acc += dt * (0.6 + 1.6 * _light);
    _waterAcc += dt * (0.6 + 1.4 * _light);
    while (_o2Acc >= 1) {
      _o2Acc -= 1;
      _particles.add(_Particle(Offset(0.48 + _rnd.nextDouble() * 0.16, 0.40 + _rnd.nextDouble() * 0.08),
          Offset((_rnd.nextDouble() - 0.5) * 0.04, -0.11 - _rnd.nextDouble() * 0.06), 3.2, 'o2'));
    }
    while (_co2Acc >= 1) {
      _co2Acc -= 1;
      _particles.add(_Particle(Offset(1.02, 0.42 + _rnd.nextDouble() * 0.2),
          Offset(-0.14 - _rnd.nextDouble() * 0.04, (_rnd.nextDouble() - 0.5) * 0.02), 2.6, 'co2'));
    }
    while (_waterAcc >= 1) {
      _waterAcc -= 1;
      _particles.add(_Particle(Offset(0.495 + _rnd.nextDouble() * 0.01, 1.0), const Offset(0, -0.16), 2.3, 'water'));
    }
    for (final p in _particles) {
      p.age += dt;
      p.pos += p.vel * dt;
    }
    _particles.removeWhere((p) => p.age > p.life);
    if (_playing) {
      _stepClock += dt;
      if (_stepClock > 3.2) {
        _stepClock = 0;
        final next = (_step ?? -1) + 1;
        if (next >= photoSteps.length) {
          _playing = false;
          _step = null;
        } else {
          _step = next;
        }
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final step = _step == null ? null : photoSteps[_step!];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('animated')), actions: [
        TextButton(
            onPressed: () => setState(() => _hindi = !_hindi),
            child: Text(_hindi ? 'EN' : 'हिं', style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 0.95,
            child: CustomPaint(painter: _PhotoPainter(_particles, _light, _time, step?.focus)),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(_step),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Text(
              step == null
                  ? (_hindi
                      ? 'स्लाइडर से धूप बढ़ाओ और O₂ के बुलबुले गिनो। "स्टेप चलाओ" दबाकर पूरी प्रक्रिया देखो।'
                      : 'Move the slider to change sunlight and count the O₂ bubbles. Press "Play steps" to see the whole process.')
                  : '${context.tr('step')} ${_step! + 1}/${photoSteps.length}: ${_hindi ? step.hi : step.en}',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.wb_sunny_rounded, color: Color(0xFFE0A100)),
          const SizedBox(width: 6),
          Text(context.tr('light')),
          Expanded(
            child: Slider(value: _light, onChanged: (v) => setState(() => _light = v)),
          ),
          Text('${(_light * 100).round()}%'),
        ]),
        Text(
          'O₂: ~${(0.3 + 7 * _light * _light).toStringAsFixed(1)} bubbles/sec',
          style: TextStyle(color: Brand.ink.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => setState(() {
            _playing = true;
            _step = 0;
            _stepClock = 0;
          }),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.tr('play')),
        ),
        const SizedBox(height: 8),
        Text('6CO₂ + 6H₂O  —(sunlight, chlorophyll)→  C₆H₁₂O₆ + 6O₂',
            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: Brand.ink.withValues(alpha: 0.8))),
      ]),
    );
  }
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.particles, this.light, this.time, this.focus);
  final List<_Particle> particles;
  final double light, time;
  final String? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset at(double x, double y) => Offset(x * w, y * h);

    // Sky gets brighter with light.
    final sky = Color.lerp(const Color(0xFFB9C7E6), const Color(0xFFBFE8FF), light)!;
    canvas.drawRect(Offset.zero & size,
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [sky, const Color(0xFFF2FBEF)]).createShader(Offset.zero & size));
    // Ground
    canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), Paint()..color = const Color(0xFFCBA77A));

    // Sun + rays
    final sun = at(0.15, 0.13);
    final glow = focus == 'sun' ? 1.0 : 0.0;
    for (var i = 0; i < 5; i++) {
      final t = (time * 0.6 + i / 5) % 1.0;
      final start = Offset.lerp(sun, at(0.5, 0.45), 0.15)!;
      final p = Offset.lerp(start, at(0.48, 0.42), t)!;
      canvas.drawLine(
          sun,
          Offset.lerp(sun, at(0.48 + (i - 2) * 0.04, 0.44), 1)!,
          Paint()
            ..color = const Color(0xFFFFC94A).withValues(alpha: 0.18 + 0.5 * light)
            ..strokeWidth = 2 + 4 * light);
      canvas.drawCircle(p, 3 + 3 * light, Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.4 + 0.6 * light));
    }
    canvas.drawCircle(sun, w * (0.07 + 0.02 * light) + glow * 6, Paint()..color = const Color(0xFFFFC94A));

    // Stem
    canvas.drawLine(at(0.5, 0.86), at(0.5, 0.55),
        Paint()
          ..color = const Color(0xFF3E8E41)
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round);
    // Leaf (bezier shape) with veins
    final leaf = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..quadraticBezierTo(w * 0.42, h * 0.26, w * 0.74, h * 0.34)
      ..quadraticBezierTo(w * 0.66, h * 0.60, w * 0.30, h * 0.52)
      ..close();
    final leafGlow = focus == 'glucose';
    canvas.drawPath(leaf, Paint()..color = Color.lerp(const Color(0xFF4CAF50), const Color(0xFF2E9E57), light)!);
    if (leafGlow) {
      canvas.drawPath(leaf, Paint()
        ..color = const Color(0xFFFFF59D).withValues(alpha: 0.35 + 0.25 * math.sin(time * 6))
        ..style = PaintingStyle.fill);
    }
    canvas.drawLine(at(0.31, 0.52), at(0.72, 0.35), Paint()..color = const Color(0xFF1B5E20)..strokeWidth = 2);
    for (var i = 1; i < 5; i++) {
      final b = Offset.lerp(at(0.31, 0.52), at(0.72, 0.35), i / 5)!;
      canvas.drawLine(b, b + Offset(w * 0.03, -h * 0.06), Paint()..color = const Color(0xFF1B5E20).withValues(alpha: 0.7)..strokeWidth = 1.4);
      canvas.drawLine(b, b + Offset(w * 0.05, h * 0.03), Paint()..color = const Color(0xFF1B5E20).withValues(alpha: 0.7)..strokeWidth = 1.4);
    }

    // Particles
    for (final p in particles) {
      final fade = (1 - p.age / p.life).clamp(0.0, 1.0);
      final o = at(p.pos.dx, p.pos.dy);
      switch (p.kind) {
        case 'o2':
          final hl = focus == 'o2';
          canvas.drawCircle(o, hl ? 7 : 5.5, Paint()..color = Colors.white.withValues(alpha: 0.85 * fade));
          canvas.drawCircle(o, hl ? 7 : 5.5, Paint()
            ..color = const Color(0xFF4FC3F7).withValues(alpha: fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
        case 'co2':
          final hl = focus == 'co2';
          canvas.drawCircle(o, hl ? 6 : 4.5, Paint()..color = const Color(0xFF8D8D8D).withValues(alpha: fade));
          canvas.drawCircle(o + const Offset(-6, 0), hl ? 4 : 3, Paint()..color = const Color(0xFFE57373).withValues(alpha: fade));
          canvas.drawCircle(o + const Offset(6, 0), hl ? 4 : 3, Paint()..color = const Color(0xFFE57373).withValues(alpha: fade));
        case 'water':
          final hl = focus == 'water';
          canvas.drawCircle(o, hl ? 5.5 : 4, Paint()..color = const Color(0xFF1E88E5).withValues(alpha: 0.9 * fade));
      }
    }

    // Labels with leader lines
    void label(String text, Offset anchor, Offset pos, String key) {
      final hl = focus == key;
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hl ? Colors.white : Brand.ink)),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = Rect.fromCenter(center: pos, width: tp.width + 16, height: tp.height + 8);
      canvas.drawLine(anchor, pos, Paint()..color = Brand.ink.withValues(alpha: 0.6)..strokeWidth = 1.2);
      canvas.drawCircle(anchor, 3, Paint()..color = Brand.ink);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)),
          Paint()..color = hl ? Brand.green : Colors.white.withValues(alpha: 0.92));
      tp.paint(canvas, r.topLeft + const Offset(8, 4));
    }

    label('Sunlight', at(0.24, 0.2), at(0.36, 0.08), 'sun');
    label('O₂ (oxygen)', at(0.56, 0.24), at(0.78, 0.14), 'o2');
    label('CO₂', at(0.86, 0.48), at(0.86, 0.62), 'co2');
    label('Leaf (chlorophyll)', at(0.40, 0.46), at(0.24, 0.66), 'glucose');
    label('Glucose', at(0.60, 0.42), at(0.80, 0.30), 'glucose');
    label('Water (H₂O)', at(0.5, 0.76), at(0.28, 0.80), 'water');
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => true;
}

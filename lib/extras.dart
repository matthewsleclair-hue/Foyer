import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';

// ───────────────────────── the two small buttons on the home screen ─────────────────────────

class HomeSideButtons extends StatelessWidget {
  const HomeSideButtons({super.key, required this.onFireplace, required this.onGoodnight});
  final VoidCallback onFireplace;
  final VoidCallback onGoodnight;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _RoundButton(
              icon: Icons.local_fire_department_rounded,
              tooltip: 'Fireplace',
              color: const Color(0xFFFFB454),
              onSelect: onFireplace),
          const SizedBox(height: 18),
          _RoundButton(
              icon: Icons.nightlight_round,
              tooltip: 'Goodnight',
              color: const Color(0xFFB8C4FF),
              onSelect: onGoodnight),
        ]),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon, required this.tooltip, required this.color, required this.onSelect});
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => FocusButton(
        onSelect: onSelect,
        scale: 1.0,
        builder: (_, f) => Semantics(
          label: tooltip,
          button: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: f ? Colors.white : Colors.white.withAlpha(30),
              border: Border.all(color: Colors.white.withAlpha(f ? 255 : 70), width: f ? 3 : 1.5),
            ),
            child: Icon(icon, size: 42, color: f ? Colors.black : color),
          ),
        ),
      );
}

// ───────────────────────── fireplace ─────────────────────────

/// A calm, animated fireplace drawn in code (no video file, so Foyer stays small).
class FireplaceScreen extends StatefulWidget {
  const FireplaceScreen({super.key});
  @override
  State<FireplaceScreen> createState() => _FireplaceScreenState();
}

class _FireplaceScreenState extends State<FireplaceScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(seconds: 120))..repeat();
  bool _hint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent &&
                (e.logicalKey == LogicalKeyboardKey.select ||
                    e.logicalKey == LogicalKeyboardKey.enter ||
                    e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _FirePainter(_t), isComplex: true, willChange: true),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: AnimatedOpacity(
                opacity: _hint ? 0.8 : 0,
                duration: const Duration(milliseconds: 600),
                child: const Text('Press Back to leave',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, color: Colors.white70)),
              ),
            ),
          ]),
        ),
      );
}

class _FirePainter extends CustomPainter {
  _FirePainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static final Random _r = Random(7);
  // fixed random look for each flame tongue and each ember
  static final List<List<double>> _tongues = List.generate(
      9, (i) => [_r.nextDouble() * 6.28, 0.7 + _r.nextDouble() * 0.9, 0.8 + _r.nextDouble() * 0.5]);
  static final List<List<double>> _embers = List.generate(
      36, (i) => [_r.nextDouble(), _r.nextDouble(), 0.4 + _r.nextDouble() * 0.9, _r.nextDouble() * 2 - 1]);

  @override
  void paint(Canvas canvas, Size size) {
    final s = t.value * 120.0; // seconds
    final w = size.width, h = size.height;

    // the room: dark and warm
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF060302), Color(0xFF120804)])
              .createShader(Offset.zero & size));

    // flicker: a few sine waves added together
    final flick = 0.82 +
        0.10 * sin(s * 7.1) +
        0.05 * sin(s * 13.7 + 1.3) +
        0.04 * sin(s * 3.3 + 0.4);

    final cx = w / 2;
    final baseY = h * 0.80;
    final fw = w * 0.30; // fire width

    // light spilling into the room
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
                  center: Alignment(0, 0.55),
                  radius: 0.95,
                  colors: [
                    const Color(0xFFFF8A3D).withAlpha((120 * flick).round()),
                    const Color(0xFFB8391A).withAlpha((50 * flick).round()),
                    Colors.transparent
                  ],
                  stops: const [0, 0.45, 1])
              .createShader(Offset.zero & size));

    // the fireplace opening
    final opening = RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(cx, h * 0.60), width: w * 0.46, height: h * 0.52),
        topLeft: Radius.circular(w * 0.23),
        topRight: Radius.circular(w * 0.23));
    final surround = RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(cx, h * 0.585), width: w * 0.54, height: h * 0.60),
        topLeft: Radius.circular(w * 0.27),
        topRight: Radius.circular(w * 0.27));
    canvas.drawRRect(surround, Paint()..color = const Color(0xFF1B1411));
    canvas.drawRRect(
        surround,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF2A1E18));
    canvas.drawRRect(opening, Paint()..color = const Color(0xFF050202));

    canvas.save();
    canvas.clipRRect(opening);

    // glow on the back wall of the opening
    canvas.drawRect(
        opening.outerRect,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(0, 0.9),
                  radius: 1.0,
                  colors: [
                    const Color(0xFFFF9B3D).withAlpha((200 * flick).round()),
                    const Color(0xFF7A1F0E).withAlpha((90 * flick).round()),
                    Colors.transparent
                  ],
                  stops: const [0, 0.5, 1])
              .createShader(opening.outerRect));

    // logs
    final logPaint = Paint()..color = const Color(0xFF2B1608);
    final logLight = Paint()..color = const Color(0xFF4A2812);
    for (final dir in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(cx, baseY + h * 0.02);
      canvas.rotate(dir * 0.10);
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: fw * 1.25, height: h * 0.05),
          Radius.circular(h * 0.025));
      canvas.drawRRect(rr, logPaint);
      canvas.drawRRect(rr.deflate(h * 0.008), logLight..color = const Color(0xFF3A1E0C));
      canvas.restore();
    }

    // flame tongues, drawn back to front, glowing where they overlap
    final glow = Paint()..blendMode = BlendMode.plus;
    for (var layer = 0; layer < 3; layer++) {
      final scale = [1.0, 0.72, 0.42][layer];
      final colors = [
        [const Color(0xFFD9381E), const Color(0x00D9381E)],
        [const Color(0xFFFF9A2E), const Color(0x00FF9A2E)],
        [const Color(0xFFFFE9A8), const Color(0x00FFE9A8)],
      ][layer];
      for (var i = 0; i < _tongues.length; i++) {
        final tg = _tongues[i];
        final pos = (i / (_tongues.length - 1)) * 2 - 1; // -1 .. 1
        final sway = sin(s * (1.6 + tg[1]) + tg[0]) * fw * 0.06 +
            sin(s * (3.1 + tg[2]) + tg[0] * 2) * fw * 0.03;
        final x = cx + pos * fw * 0.46 + sway;
        final bump = 1 - pos.abs() * 0.55; // tallest in the middle
        final hgt = h * 0.36 * bump * scale * (0.78 + 0.22 * sin(s * (2.4 + tg[1] * 2) + tg[0]) +
            0.08 * flick);
        final wid = fw * 0.20 * (0.9 + 0.1 * tg[2]) * (0.5 + 0.5 * scale);
        final top = Offset(x + sway * 1.6, baseY - hgt);
        final path = Path()
          ..moveTo(x - wid, baseY)
          ..cubicTo(x - wid * 1.1, baseY - hgt * 0.35, x - wid * 0.2, baseY - hgt * 0.6, top.dx, top.dy)
          ..cubicTo(x + wid * 0.3, baseY - hgt * 0.6, x + wid * 1.1, baseY - hgt * 0.35, x + wid, baseY)
          ..close();
        glow.shader = LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [colors[0].withAlpha(210), colors[1]])
            .createShader(Rect.fromLTWH(x - wid, top.dy, wid * 2, baseY - top.dy));
        canvas.drawPath(path, glow);
      }
    }
    // glowing coals
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, baseY + h * 0.012), width: fw * 1.1, height: h * 0.05),
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFFFFC45E).withAlpha((230 * flick).round()),
            const Color(0xFFB8391A).withAlpha(0)
          ]).createShader(Rect.fromCenter(
              center: Offset(cx, baseY + h * 0.012), width: fw * 1.1, height: h * 0.05)));
    canvas.restore();

    // embers drifting up and out
    final ember = Paint()..blendMode = BlendMode.plus;
    for (final e in _embers) {
      final life = ((s * 0.09 * e[2] + e[0]) % 1.0);
      final x = cx + (e[1] * 2 - 1) * fw * 0.35 + e[3] * life * fw * 0.5 + sin(s * 2 + e[0] * 9) * 12;
      final y = baseY - life * h * 0.52;
      final a = (sin(life * pi) * 220).clamp(0, 255).round();
      ember.color = Color.fromARGB(a, 255, lerpDouble(190, 110, life)!.round(), 60);
      canvas.drawCircle(Offset(x, y), 2.2 + e[2] * 1.6 * (1 - life), ember);
    }

    // hearth stone
    canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), Paint()..color = const Color(0xFF0C0706));
    canvas.drawRect(
        Rect.fromLTWH(0, h * 0.86, w, h * 0.14),
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(0, -1),
                  radius: 0.8,
                  colors: [const Color(0xFFFF8A3D).withAlpha((70 * flick).round()), Colors.transparent])
              .createShader(Rect.fromLTWH(0, h * 0.86, w, h * 0.14)));
  }

  @override
  bool shouldRepaint(covariant _FirePainter old) => false;
}

// ───────────────────────── goodnight ─────────────────────────

/// Closes the other apps, then goes to a dark screen with a dim clock. Any key wakes it.
Future<void> startGoodnight(BuildContext context) async {
  try {
    await kChannel.invokeMethod<int>('closeAllApps');
  } catch (_) {}
  if (!context.mounted) return;
  await Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 900),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => const GoodnightScreen(),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class GoodnightScreen extends StatefulWidget {
  const GoodnightScreen({super.key});
  @override
  State<GoodnightScreen> createState() => _GoodnightScreenState();
}

class _GoodnightScreenState extends State<GoodnightScreen> {
  Timer? _tick;
  bool _greeting = true;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _greeting = false);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _time(bool h24) {
    final m = _now.minute.toString().padLeft(2, '0');
    if (h24) return '${_now.hour.toString().padLeft(2, '0')}:$m';
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cfg = SettingsScope.of(context);
    // the clock drifts a little each minute so no pixel stays lit all night
    final dx = sin(_now.minute * 0.7) * 0.5, dy = cos(_now.minute * 0.9) * 0.4;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(children: [
          Align(
            alignment: Alignment(dx, dy),
            child: AnimatedOpacity(
              opacity: _greeting ? 0 : 1,
              duration: const Duration(seconds: 2),
              child: Text(_time(cfg.clock24),
                  style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF2C2118))),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0),
            child: AnimatedOpacity(
              opacity: _greeting ? 1 : 0,
              duration: const Duration(seconds: 2),
              child: Text('Goodnight, ${cfg.name}',
                  style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.w300, color: Color(0xFFB7A48F))),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
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

/// A wood fire: flames, glowing logs, sparks and light flickering on brick, simulated live by a
/// shader (shaders/fire.frag), with a crackling loop for sound. No video file.
/// Up and Down change the sound; OK or Back leaves.
class FireplaceScreen extends StatefulWidget {
  const FireplaceScreen({super.key});
  @override
  State<FireplaceScreen> createState() => _FireplaceScreenState();
}

/// Crackle loudness for each step of [Settings.fireVolume] (0 = silent).
const List<double> kFireVolumes = [0.0, 0.2, 0.42, 0.7, 1.0];

class _FireplaceScreenState extends State<FireplaceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(seconds: 120))..repeat();
  final Stopwatch _clock = Stopwatch()..start();
  ui.FragmentShader? _shader;
  bool _hint = true;
  Timer? _hintTimer;
  bool _volShown = false;
  Timer? _volTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _hint = false);
    });
    _loadShader();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sound());
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/fire.frag');
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // shader missing or not supported on this box: the drawn fire below is used instead
    }
  }

  int get _vol => SettingsScope.read(context).fireVolume.clamp(0, kFireVolumes.length - 1).toInt();

  void _sound([double? volume]) {
    kChannel.invokeMethod('fireSound', {'volume': volume ?? kFireVolumes[_vol]}).catchError((_) => null);
  }

  void _changeVolume(int by) {
    final s = SettingsScope.read(context);
    final v = (_vol + by).clamp(0, kFireVolumes.length - 1).toInt();
    if (v != s.fireVolume) s.change(() => s.fireVolume = v);
    _sound();
    _volTimer?.cancel();
    setState(() => _volShown = true);
    _volTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _volShown = false);
    });
  }

  // the TV side stops the crackle whenever Foyer leaves the screen; pick it up again on return
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sound();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sound(0); // fades out
    _hintTimer?.cancel();
    _volTimer?.cancel();
    _t.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perf = SettingsScope.of(context).perfMode;
    final vol = _vol;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowUp) {
            _changeVolume(1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            _changeVolume(-1);
            return KeyEventResult.handled;
          }
          if (e is KeyDownEvent &&
              (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA)) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(fit: StackFit.expand, children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _shader != null
                    // drawn small and scaled up: fire is soft anyway, and it stays smooth
                    ? _ShaderFirePainter(_t, _shader!, _clock, perf ? const Size(480, 270) : const Size(800, 450))
                    : _FirePainter(_t),
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: AnimatedOpacity(
              opacity: _hint ? 0.8 : 0,
              duration: const Duration(milliseconds: 600),
              child: const Text('▲ ▼ change the crackle   ·   Back to leave',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 24, color: Colors.white70)),
            ),
          ),
          Positioned(
            right: 60,
            top: 50,
            child: AnimatedOpacity(
              opacity: _volShown ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Glass(
                radius: 30,
                liquid: false,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(vol == 0 ? Icons.volume_off_rounded : Icons.local_fire_department_rounded,
                      size: 30, color: const Color(0xFFFFB454)),
                  const SizedBox(width: 14),
                  for (var i = 1; i < kFireVolumes.length; i++)
                    Container(
                      width: 14,
                      height: 10.0 + i * 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          color: i <= vol ? const Color(0xFFFFB454) : Colors.white24,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  const SizedBox(width: 14),
                  Text(vol == 0 ? 'Silent' : 'Crackle', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Runs the fire shader at a small size and stretches it over the screen.
class _ShaderFirePainter extends CustomPainter {
  _ShaderFirePainter(Listenable tick, this.shader, this.clock, this.small) : super(repaint: tick);
  final ui.FragmentShader shader;
  final Stopwatch clock;
  final Size small;

  @override
  void paint(Canvas canvas, Size size) {
    // wrap the clock so the maths stays precise on long evenings (one tiny skip every 15 minutes)
    final seconds = (clock.elapsedMilliseconds % 900000) / 1000.0;
    shader
      ..setFloat(0, small.width)
      ..setFloat(1, small.height)
      ..setFloat(2, seconds);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Offset.zero & small, Paint()..shader = shader);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(small.width.round(), small.height.round());
    picture.dispose();
    canvas.drawImageRect(image, Offset.zero & small, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    image.dispose();
  }

  @override
  bool shouldRepaint(covariant _ShaderFirePainter old) => old.shader != shader || old.small != small;
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

// ───────────────────────── sleep timer ─────────────────────────

/// When the TV goes to sleep (ms since 1970), 0 = off. Kept by the native side.
final ValueNotifier<int> kSleepAt = ValueNotifier(0);

Future<void> refreshSleep() async {
  try {
    kSleepAt.value = (await kChannel.invokeMethod<int>('sleepStatus')) ?? 0;
  } catch (_) {}
}

Future<void> setSleep(int minutes) async {
  try {
    kSleepAt.value = (await kChannel.invokeMethod<int>('sleepTimer', {'minutes': minutes})) ?? 0;
  } catch (_) {}
}

String sleepLeft(int at) {
  final m = ((at - DateTime.now().millisecondsSinceEpoch) / 60000).ceil();
  if (m <= 1) return '1 min';
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// The moon button: goodnight now, or a sleep timer.
Future<void> goodnightMenu(BuildContext context) async {
  await refreshSleep();
  if (!context.mounted) return;
  final on = kSleepAt.value > DateTime.now().millisecondsSinceEpoch;
  showMenu2(context, on ? 'Sleep in ${sleepLeft(kSleepAt.value)}' : 'Goodnight', [
    MenuChoice('Goodnight now', () => startGoodnight(context)),
    MenuChoice(on ? 'Change the sleep timer…' : 'Sleep timer…', () => _sleepChoices(context)),
    if (on) MenuChoice('Turn off the sleep timer', () => setSleep(0)),
    MenuChoice('Cancel', () {}),
  ]);
}

void _sleepChoices(BuildContext context) => showMenu2(context, 'Turn the TV off in', [
      MenuChoice('Keeps playing until then. A minute before, a note lets you keep watching.', null),
      for (final m in const [15, 30, 45, 60, 90, 120])
        MenuChoice(m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '${m / 60} hours'.replaceAll('.0', '')),
            () => setSleep(m)),
      MenuChoice('Cancel', () {}),
    ]);

/// Small "Sleep in 42 min" pill on the home screen while a timer runs.
class SleepPill extends StatefulWidget {
  const SleepPill({super.key});
  @override
  State<SleepPill> createState() => _SleepPillState();
}

class _SleepPillState extends State<SleepPill> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    refreshSleep();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => refreshSleep());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: kSleepAt,
        builder: (_, at, __) {
          if (at <= DateTime.now().millisecondsSinceEpoch) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Glass(
              radius: 40,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bedtime_rounded, size: 28, color: Color(0xFFB8C4FF)),
                const SizedBox(width: 10),
                Text(sleepLeft(at), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        },
      );
}

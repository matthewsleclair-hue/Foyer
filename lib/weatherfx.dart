// Weather on the background: light rain, snow or fog drawn over the wallpaper when
// that's the weather outside (idea from couch-tv's ambient weather, MIT).
// Every particle's position is worked out from the time, so nothing is stored per
// frame and it stays light on a TV box.
import 'dart:math';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'screens.dart';

enum FxKind { none, rain, storm, snow, fog }

/// Open-Meteo weather code -> effect.
FxKind fxFor(int code) {
  if (code == 45 || code == 48) return FxKind.fog;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return FxKind.snow;
  if (code >= 95) return FxKind.storm;
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return FxKind.rain;
  return FxKind.none;
}

class WeatherFx extends StatefulWidget {
  const WeatherFx({super.key, required this.kind, this.light = false});
  final FxKind kind;

  /// Performance mode: fewer drops and flakes.
  final bool light;
  @override
  State<WeatherFx> createState() => _WeatherFxState();
}

class _WeatherFxState extends State<WeatherFx> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void initState() {
    super.initState();
    if (widget.kind != FxKind.none) _c.repeat();
  }

  @override
  void didUpdateWidget(WeatherFx old) {
    super.didUpdateWidget(old);
    if (widget.kind == FxKind.none) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == FxKind.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FxPainter(widget.kind, _c, widget.light),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.kind, this.anim, this.light) : super(repaint: anim);
  final FxKind kind;
  final Animation<double> anim;
  final bool light;

  // fixed random numbers per particle, made once
  static final List<List<double>> _seeds = () {
    final r = Random(7);
    return List.generate(260, (_) => List.generate(5, (_) => r.nextDouble()));
  }();

  double get _t => anim.value * 60; // seconds into the minute

  @override
  void paint(Canvas canvas, Size size) {
    if (kind == FxKind.rain) _rain(canvas, size, light ? 70 : 150, 1.0);
    if (kind == FxKind.storm) {
      _rain(canvas, size, light ? 100 : 220, 1.3);
      _flash(canvas, size);
    }
    if (kind == FxKind.snow) _snow(canvas, size, light ? 60 : 130);
    if (kind == FxKind.fog) _fog(canvas, size);
  }

  void _rain(Canvas canvas, Size size, int n, double hard) {
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const slant = 0.18; // drops lean a little with the wind
    for (var i = 0; i < n; i++) {
      final s = _seeds[i];
      final depth = 0.4 + s[2] * 0.6; // far drops are slower, thinner and fainter
      final speed = (900 + s[3] * 700) * depth * hard; // px per second
      final len = (28 + s[4] * 34) * depth * hard;
      final travel = size.height + len + 200;
      final y = (s[1] * travel + _t * speed) % travel - len - 100;
      final x = (s[0] * (size.width + 300) + y * slant) % (size.width + 300) - 150;
      p
        ..strokeWidth = 1.2 + depth * 1.4
        ..color = Color.fromRGBO(210, 225, 255, 0.10 + depth * 0.22);
      canvas.drawLine(Offset(x, y), Offset(x + len * slant, y + len), p);
    }
  }

  void _flash(Canvas canvas, Size size) {
    // a soft flash now and then (about every 17 seconds, two quick pulses)
    final t = _t % 17;
    double a = 0;
    if (t < 0.25) a = (0.25 - t) / 0.25 * 0.16;
    if (t > 0.45 && t < 0.8) a = (0.8 - t) / 0.35 * 0.10;
    if (a > 0) canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(220, 230, 255, a));
  }

  void _snow(Canvas canvas, Size size, int n) {
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final s = _seeds[i];
      final depth = 0.35 + s[2] * 0.65;
      final speed = (40 + s[3] * 60) * depth; // gentle
      final r = 1.6 + depth * 4.2;
      final travel = size.height + 40;
      final y = (s[1] * travel + _t * speed) % travel - 20;
      final sway = sin(_t * (0.4 + s[4] * 0.6) + s[0] * 20) * 26 * depth;
      final x = (s[0] * size.width + sway + _t * 8 * depth) % size.width;
      p.color = Color.fromRGBO(255, 255, 255, 0.25 + depth * 0.5);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  void _fog(Canvas canvas, Size size) {
    // a few wide, soft bands of mist drifting slowly across the lower half
    for (var i = 0; i < 6; i++) {
      final s = _seeds[i];
      final w = size.width * (0.7 + s[0] * 0.6);
      final h = size.height * (0.16 + s[1] * 0.14);
      final dir = i.isEven ? 1 : -1;
      final cx = ((s[2] * (size.width + w)) + dir * _t * (6 + s[3] * 10)) % (size.width + w) - w / 2;
      final cy = size.height * (0.45 + s[4] * 0.45);
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
      final p = Paint()
        ..shader = RadialGradient(colors: [
          Color.fromRGBO(225, 230, 235, 0.16 + s[1] * 0.08),
          const Color.fromRGBO(225, 230, 235, 0),
        ]).createShader(rect);
      canvas.drawOval(rect, p);
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => old.kind != kind || old.light != light;
}

// ───────────────────────── settings page ─────────────────────────

class WeatherFxScreen extends StatelessWidget {
  const WeatherFxScreen({super.key});

  void _preview(BuildContext context, FxKind k) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, __, ___) => Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent) Navigator.of(ctx).pop();
            return KeyEventResult.handled;
          },
          child: Stack(fit: StackFit.expand, children: [
            const Wallpaper(tint: kDefaultTint),
            WeatherFx(kind: k, light: SettingsScope.read(ctx).perfMode),
            const Align(
              alignment: Alignment(0, 0.9),
              child: Text('Preview. Press any button to go back.',
                  style: TextStyle(fontSize: 24, color: Colors.white60)),
            ),
          ]),
        ),
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'Weather on the background',
      subtitle: 'When it\'s raining, snowing or foggy outside, the home screen shows it too: light rain, '
          'falling snow or drifting mist over your background. It uses the weather place you set.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(autofocus: true, label: 'On', selected: s.weatherFx, onSelect: () => s.change(() => s.weatherFx = true)),
            Opt(label: 'Off', selected: !s.weatherFx, onSelect: () => s.change(() => s.weatherFx = false)),
          ]),
          if (s.weatherCity.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text('Set a place under Home screen → Weather first.',
                  style: TextStyle(fontSize: 24, color: Color(0xFFFFD43B))),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 34, bottom: 14),
            child: Text('See what it looks like', style: TextStyle(fontSize: 28, color: Colors.white70)),
          ),
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(label: 'Rain', selected: false, onSelect: () => _preview(context, FxKind.rain)),
            Opt(label: 'Thunderstorm', selected: false, onSelect: () => _preview(context, FxKind.storm)),
            Opt(label: 'Snow', selected: false, onSelect: () => _preview(context, FxKind.snow)),
            Opt(label: 'Fog', selected: false, onSelect: () => _preview(context, FxKind.fog)),
          ]),
        ]),
      ),
    );
  }
}

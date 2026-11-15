// Seasonal home screen: Valentine's Day, St. Patrick's Day, Easter, Halloween, Christmas and
// New Year each get their own colours, gently moving particles and a greeting for the week
// around the day. Christmas also strings coloured lights along the top of the screen.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'screens.dart';

enum Season { none, halloween, christmas, newYear, easter, valentines, stPatricks }

class SeasonLook {
  const SeasonLook(this.name, this.greeting, this.tint, this.icon, this.iconColor);
  final String name;
  final String greeting;
  final Color tint;
  final IconData icon;
  final Color iconColor;
}

const Map<Season, SeasonLook> kSeasonLooks = {
  Season.valentines: SeasonLook('Valentine\'s Day', 'Happy Valentine\'s Day', Color(0xFFE64980),
      Icons.favorite_rounded, Color(0xFFFF8FAB)),
  Season.stPatricks: SeasonLook('St. Patrick\'s Day', 'Happy St. Patrick\'s Day', Color(0xFF2B8A3E),
      Icons.eco_rounded, Color(0xFF8CE99A)),
  Season.easter: SeasonLook('Easter', 'Happy Easter', Color(0xFF9775FA),
      Icons.egg_rounded, Color(0xFFFCC2D7)),
  Season.halloween: SeasonLook('Halloween', 'Happy Halloween', Color(0xFFE8590C),
      Icons.nights_stay_rounded, Color(0xFFFF922B)),
  Season.christmas: SeasonLook('Christmas', 'Merry Christmas', Color(0xFFC92A2A),
      Icons.ac_unit_rounded, Color(0xFFE7F5FF)),
  Season.newYear: SeasonLook('New Year', 'Happy New Year', Color(0xFFF08C00),
      Icons.celebration_rounded, Color(0xFFFFD43B)),
};

/// Easter Sunday (Gregorian), by the Anonymous Gregorian algorithm.
DateTime easterSunday(int y) {
  final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4;
  final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3, h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31, day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(y, month, day);
}

bool _between(DateTime d, DateTime from, DateTime to) {
  final x = DateTime(d.year, d.month, d.day);
  return !x.isBefore(from) && !x.isAfter(to);
}

/// The week around each day:
///   Valentine's Day Feb 8–14, St. Patrick's Day Mar 11–17, Halloween Oct 25–31,
///   Christmas Dec 19–26, New Year Dec 27–Jan 2, Easter from Palm Sunday to Easter Monday.
Season seasonFor(DateTime d) {
  final y = d.year;
  if (_between(d, DateTime(y, 2, 8), DateTime(y, 2, 14))) return Season.valentines;
  if (_between(d, DateTime(y, 3, 11), DateTime(y, 3, 17))) return Season.stPatricks;
  if (_between(d, DateTime(y, 10, 25), DateTime(y, 10, 31))) return Season.halloween;
  if (_between(d, DateTime(y, 12, 19), DateTime(y, 12, 26))) return Season.christmas;
  if (_between(d, DateTime(y, 12, 27), DateTime(y, 12, 31)) || _between(d, DateTime(y, 1, 1), DateTime(y, 1, 2))) {
    return Season.newYear;
  }
  final e = easterSunday(y);
  if (_between(d, e.subtract(const Duration(days: 7)), e.add(const Duration(days: 1)))) return Season.easter;
  return Season.none;
}

/// Set from Settings > Appearance > Seasonal themes to try a look any day. Not saved.
final ValueNotifier<Season?> kSeasonPreview = ValueNotifier(null);

Season activeSeason(Settings s) =>
    kSeasonPreview.value ?? (s.seasonal ? seasonFor(DateTime.now()) : Season.none);

String _fmt(DateTime d) =>
    shortDate(d);

String _range(DateTime a, DateTime b) =>
    kLang == 'fr' ? 'Du ${_fmt(a)} au ${_fmt(b)}' : '${_fmt(a)} to ${_fmt(b)}';

/// "Easter: Mar 21 to Mar 29" for the settings page.
String seasonDates(Season s, int year) {
  switch (s) {
    case Season.halloween:
      return _range(DateTime(year, 10, 25), DateTime(year, 10, 31));
    case Season.christmas:
      return _range(DateTime(year, 12, 19), DateTime(year, 12, 26));
    case Season.newYear:
      return _range(DateTime(year, 12, 27), DateTime(year + 1, 1, 2));
    case Season.easter:
      final e = easterSunday(year);
      return _range(e.subtract(const Duration(days: 7)), e.add(const Duration(days: 1)));
    case Season.valentines:
      return _range(DateTime(year, 2, 8), DateTime(year, 2, 14));
    case Season.stPatricks:
      return _range(DateTime(year, 3, 11), DateTime(year, 3, 17));
    case Season.none:
      return '';
  }
}

// ───────────────────────── greeting ─────────────────────────

/// "Happy Halloween" etc., and on Dec 31 a countdown to midnight.
class SeasonGreeting extends StatefulWidget {
  const SeasonGreeting({super.key, required this.season, required this.fallback});
  final Season season;
  final String fallback;
  @override
  State<SeasonGreeting> createState() => _SeasonGreetingState();
}

class _SeasonGreetingState extends State<SeasonGreeting> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _text() {
    final look = kSeasonLooks[widget.season];
    if (look == null) return widget.fallback;
    final now = DateTime.now();
    if (widget.season == Season.newYear && now.month == 12 && now.day == 31) {
      final left = DateTime(now.year + 1).difference(now);
      final h = left.inHours, m = left.inMinutes % 60;
      final to = kLang == 'fr' ? 'avant' : 'to';
      return h > 0 ? '$h h $m min $to ${now.year + 1}' : '$m min $to ${now.year + 1}';
    }
    return look.greeting;
  }

  @override
  Widget build(BuildContext context) {
    final look = kSeasonLooks[widget.season];
    const style = TextStyle(fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: 0.2);
    if (look == null) return Text(widget.fallback, style: style);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(look.icon, size: 32, color: look.iconColor),
      const SizedBox(width: 14),
      Text(_text(), style: style),
    ]);
  }
}

// ───────────────────────── falling things ─────────────────────────

/// Gently falling particles over the wallpaper: leaves and bats, snow, confetti, petals.
/// Positions come from the clock, so nothing is stored per frame.
class SeasonLayer extends StatefulWidget {
  const SeasonLayer({super.key, required this.season, this.light = false});
  final Season season;
  final bool light; // Performance mode: fewer particles
  @override
  State<SeasonLayer> createState() => _SeasonLayerState();
}

class _SeasonLayerState extends State<SeasonLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(minutes: 10))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.season == Season.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SeasonPainter(widget.season, _c, widget.light ? 18 : 42),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _P {
  _P(Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = r.nextDouble(),
        speed = 0.5 + r.nextDouble(),
        sway = r.nextDouble() * 2 * pi,
        spin = (r.nextDouble() - 0.5) * 4,
        hue = r.nextInt(5);
  final double x, y, size, speed, sway, spin;
  final int hue;
}

class _SeasonPainter extends CustomPainter {
  _SeasonPainter(this.season, this.anim, int count)
      : parts = List.generate(count, (i) => _P(Random(i * 7919 + season.index))),
        super(repaint: anim);
  final Season season;
  final Animation<double> anim;
  final List<_P> parts;

  static const _leaf = [Color(0xFFE8590C), Color(0xFFF08C00), Color(0xFFC2410C), Color(0xFF8B4513), Color(0xFFFFA94D)];
  static const _confetti = [Color(0xFFFFD43B), Color(0xFFE9ECEF), Color(0xFFFF6B6B), Color(0xFF74C0FC), Color(0xFFB197FC)];
  static const _petal = [Color(0xFFFCC2D7), Color(0xFFFFEC99), Color(0xFFD0BFFF), Color(0xFFB2F2BB), Color(0xFFA5D8FF)];
  static const _hearts = [Color(0xFFFF6B8B), Color(0xFFE64980), Color(0xFFFFA8C5), Color(0xFFFF8787), Color(0xFFFFFFFF)];
  static const _greens = [Color(0xFF51CF66), Color(0xFF2F9E44), Color(0xFF8CE99A), Color(0xFF37B24D), Color(0xFF69DB7C)];
  static const _bulbs = [Color(0xFFFF4D4D), Color(0xFF51CF66), Color(0xFF4DABF7), Color(0xFFFFD43B), Color(0xFFFF922B), Color(0xFFDA77F2)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 600; // seconds within the 10-minute loop
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      switch (season) {
        case Season.valentines:
          _heart(canvas, size, p, t, paint, _hearts[p.hue]);
        case Season.stPatricks:
          if (i % 9 == 0) {
            _sparkle(canvas, size, p, t, paint); // a little gold
          } else {
            _shamrock(canvas, size, p, t, paint, _greens[p.hue]);
          }
        case Season.christmas:
          _snow(canvas, size, p, t, paint);
        case Season.halloween:
          if (i % 7 == 0) {
            _bat(canvas, size, p, t, paint);
          } else {
            _flake(canvas, size, p, t, paint, _leaf[p.hue], fall: 38, w: 16, h: 9);
          }
        case Season.newYear:
          if (i % 6 == 0) {
            _sparkle(canvas, size, p, t, paint);
          } else {
            _flake(canvas, size, p, t, paint, _confetti[p.hue], fall: 55, w: 10, h: 5, rect: true);
          }
        case Season.easter:
          _flake(canvas, size, p, t, paint, _petal[p.hue], fall: 30, w: 14, h: 9);
        case Season.none:
          break;
      }
    }
    // Christmas: a string of coloured lights along the top, drawn over the snow
    if (season == Season.christmas) _lights(canvas, size, t, paint);
  }

  /// Hearts float up slowly, swaying and gently turning.
  void _heart(Canvas c, Size s, _P p, double t, Paint paint, Color col) {
    final h = s.height + 80;
    final y = s.height + 40 - ((p.y * h + t * 26 * p.speed) % h);
    final x = p.x * s.width + sin(t * 0.5 * p.speed + p.sway) * 34;
    final k = 9 + p.size * 14;
    final path = Path()
      ..moveTo(0, k * 0.35)
      ..cubicTo(-k * 1.3, -k * 0.45, -k * 0.55, -k * 1.25, 0, -k * 0.5)
      ..cubicTo(k * 0.55, -k * 1.25, k * 1.3, -k * 0.45, 0, k * 0.35)
      ..close();
    c.save();
    c.translate(x, y);
    c.rotate(sin(t * 0.8 + p.sway) * 0.25);
    paint.color = col.withAlpha((150 + p.size * 90).round());
    c.drawPath(path, paint);
    c.restore();
  }

  /// Shamrocks drift down, turning: three heart-shaped leaves and a little stem.
  void _shamrock(Canvas c, Size s, _P p, double t, Paint paint, Color col) {
    final o = _fall(s, p, t, 34, 38);
    final k = 6 + p.size * 9;
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(t * p.spin * 0.4 + p.sway);
    paint.color = col.withAlpha(215);
    for (var leaf = 0; leaf < 3; leaf++) {
      c.save();
      c.rotate(leaf * 2 * pi / 3);
      final path = Path()
        ..moveTo(0, 0)
        ..cubicTo(-k * 1.1, -k * 0.6, -k * 0.75, -k * 1.9, 0, -k * 1.25)
        ..cubicTo(k * 0.75, -k * 1.9, k * 1.1, -k * 0.6, 0, 0)
        ..close();
      c.drawPath(path, paint);
      c.restore();
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, k * 0.22)
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset.zero, Offset(k * 0.35, k * 1.5), paint);
    paint.style = PaintingStyle.fill;
    c.restore();
  }

  /// Christmas lights: a dark wire that swags across the top of the screen, with coloured
  /// bulbs hanging from it that glow and twinkle softly, each at its own pace.
  void _lights(Canvas c, Size s, double t, Paint paint) {
    // kept to a thin band at the very top, above the date on the photo scenes
    const swags = 4, dip = 16.0, top = 2.0, perSwag = 9;
    final w = s.width / swags;
    final wire = Path()..moveTo(0, top);
    for (var i = 0; i < swags; i++) {
      wire.quadraticBezierTo(w * i + w / 2, top + dip * 2, w * (i + 1), top);
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xCC1E2B1E);
    c.drawPath(wire, paint);
    paint.style = PaintingStyle.fill;
    var n = 0;
    for (var i = 0; i < swags; i++) {
      for (var j = 1; j < perSwag; j++) {
        final u = j / perSwag;
        // point and slope on this swag's curve
        final x = w * i + w * u;
        final y = top + dip * 4 * u * (1 - u);
        final slope = dip * 4 * (1 - 2 * u) / w;
        final col = _bulbs[n % _bulbs.length];
        final glow = 0.55 + 0.45 * sin(t * (1.1 + (n % 5) * 0.23) + n * 1.7);
        c.save();
        c.translate(x, y);
        c.rotate(atan(slope));
        // the soft glow around the bulb
        paint
          ..color = col.withAlpha((glow * 120).round())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
        c.drawCircle(const Offset(0, 20), 21, paint);
        paint.maskFilter = null;
        // the cap, then the bulb itself
        paint.color = const Color(0xFF2B2F2B);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-5, 0, 10, 8), const Radius.circular(2)), paint);
        paint.color = Color.lerp(col.withAlpha(255), Colors.white, 0.12 * glow)!.withAlpha((170 + glow * 85).round());
        c.drawOval(const Rect.fromLTWH(-8.5, 6, 17, 28), paint);
        // a little shine
        paint.color = Colors.white.withAlpha((90 * glow).round());
        c.drawOval(const Rect.fromLTWH(-4.5, 10, 4.5, 9), paint);
        c.restore();
        n++;
      }
    }
  }

  Offset _fall(Size s, _P p, double t, double pxPerSec, double swayPx) {
    final h = s.height + 80;
    final y = ((p.y * h + t * pxPerSec * p.speed) % h) - 40;
    final x = p.x * s.width + sin(t * 0.6 * p.speed + p.sway) * swayPx;
    return Offset(x, y);
  }

  void _snow(Canvas c, Size s, _P p, double t, Paint paint) {
    final o = _fall(s, p, t, 42, 26);
    final r = 2.5 + p.size * 5;
    paint
      ..color = Colors.white.withAlpha((110 + p.size * 120).round())
      ..maskFilter = p.size > 0.7 ? const MaskFilter.blur(BlurStyle.normal, 2) : null;
    c.drawCircle(o, r, paint);
    paint.maskFilter = null;
  }

  void _flake(Canvas c, Size s, _P p, double t, Paint paint, Color col,
      {required double fall, required double w, required double h, bool rect = false}) {
    final o = _fall(s, p, t, fall, 40);
    final scale = 0.7 + p.size * 0.8;
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(t * p.spin * 0.5 + p.sway);
    // a little flip, like a leaf or paper turning over
    c.scale(1, 0.35 + 0.65 * cos(t * 1.3 * p.speed + p.sway).abs());
    paint.color = col.withAlpha(200);
    final r = Rect.fromCenter(center: Offset.zero, width: w * scale, height: h * scale);
    if (rect) {
      c.drawRect(r, paint);
    } else {
      c.drawOval(r, paint);
    }
    c.restore();
  }

  void _bat(Canvas c, Size s, _P p, double t, Paint paint) {
    // bats cross the screen sideways, slowly, with flapping wings
    final w = s.width + 200;
    final x = ((p.x * w + t * 70 * p.speed) % w) - 100;
    final y = s.height * (0.08 + p.y * 0.4) + sin(t * 1.4 + p.sway) * 24;
    final flap = 0.45 + 0.55 * sin(t * 9 * p.speed + p.sway).abs();
    final k = 0.8 + p.size * 0.6;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-12 * k, -14 * k * flap, -30 * k, -6 * k * flap)
      ..quadraticBezierTo(-22 * k, -1 * k, -18 * k, 4 * k)
      ..quadraticBezierTo(-10 * k, 0, 0, 6 * k)
      ..quadraticBezierTo(10 * k, 0, 18 * k, 4 * k)
      ..quadraticBezierTo(22 * k, -1 * k, 30 * k, -6 * k * flap)
      ..quadraticBezierTo(12 * k, -14 * k * flap, 0, 0)
      ..close();
    paint.color = const Color(0xE0120A1A);
    c.save();
    c.translate(x, y);
    c.drawPath(path, paint);
    c.restore();
  }

  void _sparkle(Canvas c, Size s, _P p, double t, Paint paint) {
    // twinkling stars that fade in and out where they stand
    final a = (sin(t * 2.2 * p.speed + p.sway) + 1) / 2;
    if (a < 0.15) return;
    final o = Offset(p.x * s.width, p.y * s.height * 0.75);
    final r = (6 + p.size * 10) * a;
    paint.color = const Color(0xFFFFE066).withAlpha((a * 220).round());
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
      ..close();
    c.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SeasonPainter old) => old.season != season || old.parts.length != parts.length;
}

// ───────────────────────── settings ─────────────────────────

class SeasonsScreen extends StatefulWidget {
  const SeasonsScreen({super.key});
  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final year = DateTime.now().year;
    final today = seasonFor(DateTime.now());
    final preview = kSeasonPreview.value;
    Widget opt(String label, bool selected, VoidCallback onSelect, {bool first = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 16),
          child: Opt(label: label, selected: selected, onSelect: onSelect, autofocus: first, color: color),
        );
    return SettingsPage(
      title: 'Seasonal themes',
      subtitle: 'For the week around each holiday, the home screen gets its own colours, a greeting '
          'and gently moving hearts, shamrocks, petals, leaves and bats, snow with Christmas lights, or confetti.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(children: [
            opt('On', s.seasonal, () => s.change(() => s.seasonal = true), first: true),
            opt('Off', !s.seasonal, () => s.change(() => s.seasonal = false)),
          ]),
          const SizedBox(height: 24),
          for (final e in kSeasonLooks.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('${e.value.name}: ${seasonDates(e.key, year)}${today == e.key ? '   (now)' : ''}',
                  style: const TextStyle(fontSize: 26, color: Colors.white70)),
            ),
          const SizedBox(height: 30),
          const Text('Try one now', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Pick one, then go back to the home screen. It lasts until Foyer restarts.',
              style: TextStyle(fontSize: 24, color: Colors.white54)),
          const SizedBox(height: 18),
          Wrap(children: [
            for (final e in kSeasonLooks.entries)
              opt(e.value.name, preview == e.key, () => setState(() => kSeasonPreview.value = e.key),
                  color: e.value.tint),
            opt('Today\'s', preview == null, () => setState(() => kSeasonPreview.value = null)),
          ]),
        ]),
      ),
    );
  }
}

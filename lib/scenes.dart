// Scenic home backgrounds: painted landscapes that take turns, with a big glass clock that sits
// *behind* the front of the scenery (peaks and ridges overlap the bottom of the digits).
// Two kinds: photos (in scenes/, with the scenery in front of the clock cut out of the photo),
// and painted scenes drawn by Foyer from the recipes below.
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'weather.dart';

/// A photo scene: the photo, the clock's place, and the strip of scenery that goes in front of it.
class PhotoScene {
  const PhotoScene(this.name, this.top, {this.frontTop});
  final String name;

  /// Where the top of the clock goes (on the 1920 x 1080 screen).
  final double top;

  /// Where the cut-out strip (scenes/<key>-front.webp, 420 tall) goes; null = nothing in front.
  final double? frontTop;
}

const Map<String, PhotoScene> kPhotoScenes = {
  'meadow': PhotoScene('Misty meadow', 330, frontTop: 310),
  'matterhorn': PhotoScene('Matterhorn', 200),
  'volcano': PhotoScene('Volcano at dusk', 420, frontTop: 400),
  'starlake': PhotoScene('Starry lake', 170, frontTop: 150),
  'mistforest': PhotoScene('Misty forest', 150, frontTop: 130),
};

/// The scenes that take turns: the photos.
const List<String> kSceneTurns = ['meadow', 'matterhorn', 'volcano', 'starlake', 'mistforest'];

/// Every scene, photos first, then the painted ones.
const List<String> kSceneOrder = [...kSceneTurns, 'night', 'golden', 'waterline', 'fog', 'dawn'];

String sceneName(String k) => kPhotoScenes[k]?.name ?? '${kScenes[k]?['name'] ?? ''}';

/// Scene recipes: layers painted back to front. Layers marked 'front' are drawn over the clock.
/// (Generated from the design file; the same numbers drove the previews.)
const Map<String, Map<String, dynamic>> kScenes = {
  'night': {
    'name': 'Night',
    'clock': '#F4F1FF',
    'layers': [
      {'t': 'sky', 'stops': [[0, '#0B1026'], [0.38, '#2A2550'], [0.62, '#7A4A78'], [0.78, '#E09A8C'], [1, '#F3C9A0']], 'h': 720},
      {'t': 'stars', 'count': 150, 'seed': 3, 'maxY': 430, 'alpha': 0.9},
      {'t': 'orb', 'x': 1500, 'y': 170, 'r': 240, 'color': '#C9D4FF', 'alpha': 0.22},
      {'t': 'disc', 'x': 1500, 'y': 170, 'r': 34, 'color': '#F2F4FF'},
      {'t': 'ridge', 'seed': 11, 'base': 640, 'amp': 150, 'freq': 0.0016, 'oct': 4, 'top': '#4B3F6B', 'bottom': '#2B2646'},
      {'t': 'ridge', 'seed': 23, 'base': 690, 'amp': 120, 'freq': 0.0022, 'oct': 4, 'top': '#2E2A4C', 'bottom': '#1A1830', 'peak': [1010, 235, 560, 1.6], 'front': true},
      {'t': 'mist', 'y': 600, 'h': 170, 'color': '#C9A8C8', 'alpha': 0.22, 'front': true},
      {'t': 'ridge', 'seed': 37, 'base': 760, 'amp': 70, 'freq': 0.003, 'oct': 3, 'top': '#141627', 'bottom': '#0C0D18', 'trees': [46, 22], 'front': true},
      {'t': 'water', 'y': 800, 'top': '#3B3358', 'bottom': '#0A0B16', 'glow': '#F0B79A', 'glowAlpha': 0.35, 'seed': 5, 'front': true},
      {'t': 'ridge', 'seed': 51, 'base': 1010, 'amp': 150, 'freq': 0.0011, 'oct': 3, 'top': '#090A12', 'bottom': '#05060B', 'trees': [70, 30], 'edge': [0.0, 0.3, 0.72, 1.0], 'front': true},
    ],
  },
  'golden': {
    'name': 'Golden hour',
    'clock': '#FFF6E6',
    'layers': [
      {'t': 'sky', 'stops': [[0, '#31506E'], [0.35, '#7E8C8E'], [0.6, '#E0B274'], [0.82, '#F6C67A'], [1, '#F9DDA6']], 'h': 760},
      {'t': 'orb', 'x': 600, 'y': 560, 'r': 520, 'color': '#FFE2A0', 'alpha': 0.55},
      {'t': 'ridge', 'seed': 5, 'base': 700, 'amp': 60, 'freq': 0.0018, 'oct': 3, 'top': '#B98C63', 'bottom': '#8E6B4F'},
      {'t': 'ridge', 'seed': 9, 'base': 760, 'amp': 40, 'freq': 0.003, 'oct': 4, 'top': '#A8683A', 'bottom': '#5E3A26', 'peak': [960, 315, 700, 2.0], 'snow': ['#F9DFB4', 0.22], 'front': true},
      {'t': 'mist', 'y': 640, 'h': 190, 'color': '#F7CF8C', 'alpha': 0.3, 'front': true},
      {'t': 'ridge', 'seed': 17, 'base': 830, 'amp': 80, 'freq': 0.0024, 'oct': 4, 'top': '#4C4A2A', 'bottom': '#2B2C18', 'trees': [30, 16], 'front': true},
      {'t': 'mist', 'y': 800, 'h': 130, 'color': '#E9B870', 'alpha': 0.18, 'front': true},
      {'t': 'ridge', 'seed': 29, 'base': 950, 'amp': 110, 'freq': 0.0016, 'oct': 4, 'top': '#23281A', 'bottom': '#10130C', 'trees': [54, 24], 'front': true},
    ],
  },
  'waterline': {
    'name': 'Waterline',
    'clock': '#FFFFFF',
    'layers': [
      {'t': 'sky', 'stops': [[0, '#3F7FC4'], [0.5, '#8FBDE6'], [1, '#DCEBF5']], 'h': 620},
      {'t': 'orb', 'x': 380, 'y': 150, 'r': 420, 'color': '#FFFFFF', 'alpha': 0.35},
      {'t': 'ridge', 'seed': 61, 'base': 600, 'amp': 210, 'freq': 0.0021, 'oct': 5, 'top': '#8FA3BC', 'bottom': '#5D7391', 'snow': ['#FFFFFF', 0.42]},
      {'t': 'ridge', 'seed': 73, 'base': 640, 'amp': 230, 'freq': 0.0027, 'oct': 5, 'top': '#6F8296', 'bottom': '#3F5568', 'snow': ['#F4F8FF', 0.36], 'front': true},
      {'t': 'ridge', 'seed': 81, 'base': 680, 'amp': 90, 'freq': 0.003, 'oct': 4, 'top': '#3E7A46', 'bottom': '#235030', 'trees': [22, 14], 'front': true},
      {'t': 'water', 'y': 690, 'top': '#3FA7B5', 'bottom': '#0B3F52', 'glow': '#DFF7F4', 'glowAlpha': 0.3, 'seed': 9, 'front': true},
      {'t': 'ridge', 'seed': 93, 'base': 1060, 'amp': 90, 'freq': 0.0015, 'oct': 3, 'top': '#0F4A55', 'bottom': '#062B36', 'edge': [0.0, 0.26, 0.76, 1.0], 'front': true},
    ],
  },
  'fog': {
    'name': 'Fog',
    'clock': '#24332F',
    'dark': true,
    'layers': [
      {'t': 'sky', 'stops': [[0, '#8FA3A6'], [0.55, '#B9C6C4'], [1, '#D5DDD8']], 'h': 700},
      {'t': 'ridge', 'seed': 101, 'base': 560, 'amp': 120, 'freq': 0.0014, 'oct': 4, 'top': '#9FB0AE', 'bottom': '#B4C2BE'},
      {'t': 'mist', 'y': 470, 'h': 220, 'color': '#DCE4E0', 'alpha': 0.55},
      {'t': 'ridge', 'seed': 113, 'base': 650, 'amp': 130, 'freq': 0.0019, 'oct': 4, 'top': '#748C88', 'bottom': '#93A6A1', 'trees': [18, 12], 'front': true},
      {'t': 'mist', 'y': 590, 'h': 200, 'color': '#D3DDD8', 'alpha': 0.6, 'front': true},
      {'t': 'ridge', 'seed': 127, 'base': 760, 'amp': 130, 'freq': 0.0022, 'oct': 4, 'top': '#4C6A64', 'bottom': '#6E8882', 'trees': [30, 15], 'front': true},
      {'t': 'mist', 'y': 720, 'h': 200, 'color': '#C5D2CC', 'alpha': 0.55, 'front': true},
      {'t': 'ridge', 'seed': 139, 'base': 900, 'amp': 140, 'freq': 0.0018, 'oct': 4, 'top': '#2A4640', 'bottom': '#3E5B54', 'trees': [46, 20], 'front': true},
      {'t': 'mist', 'y': 880, 'h': 170, 'color': '#AEBFB8', 'alpha': 0.4, 'front': true},
      {'t': 'ridge', 'seed': 151, 'base': 1040, 'amp': 120, 'freq': 0.0015, 'oct': 3, 'top': '#14261F', 'bottom': '#0C1814', 'trees': [64, 26], 'front': true},
    ],
  },
  'dawn': {
    'name': 'Dawn',
    'clock': '#FFF3E8',
    'layers': [
      {'t': 'sky', 'stops': [[0, '#5E6F96'], [0.35, '#B58F9C'], [0.62, '#F1AE86'], [0.85, '#FBD3A0'], [1, '#FDE6C4']], 'h': 700},
      {'t': 'orb', 'x': 1560, 'y': 600, 'r': 460, 'color': '#FFE9B8', 'alpha': 0.6},
      {'t': 'disc', 'x': 1560, 'y': 600, 'r': 46, 'color': '#FFF6DC'},
      {'t': 'ridge', 'seed': 201, 'base': 620, 'amp': 110, 'freq': 0.0015, 'oct': 4, 'top': '#B08C8F', 'bottom': '#C7A092'},
      {'t': 'mist', 'y': 520, 'h': 200, 'color': '#FBD9B4', 'alpha': 0.4},
      {'t': 'ridge', 'seed': 213, 'base': 700, 'amp': 120, 'freq': 0.002, 'oct': 4, 'top': '#7C7480', 'bottom': '#9A8684', 'front': true},
      {'t': 'mist', 'y': 640, 'h': 180, 'color': '#F6CDA6', 'alpha': 0.42, 'front': true},
      {'t': 'ridge', 'seed': 227, 'base': 800, 'amp': 110, 'freq': 0.0024, 'oct': 4, 'top': '#4A5560', 'bottom': '#5F6468', 'trees': [24, 14], 'front': true},
      {'t': 'mist', 'y': 760, 'h': 170, 'color': '#E8BC98', 'alpha': 0.36, 'front': true},
      {'t': 'ridge', 'seed': 239, 'base': 920, 'amp': 120, 'freq': 0.0018, 'oct': 4, 'top': '#263238', 'bottom': '#30393C', 'trees': [44, 20], 'front': true},
      {'t': 'ridge', 'seed': 251, 'base': 1050, 'amp': 110, 'freq': 0.0014, 'oct': 3, 'top': '#10181B', 'bottom': '#0A1012', 'trees': [62, 26], 'front': true},
    ],
  },
};

// ───────────────────────── the painter ─────────────────────────

const double _w = 1920, _h = 1080;

double _fract(double v) => v - v.floorToDouble();
double _h1(double n) => _fract(sin(n * 127.1 + 311.7) * 43758.5453);

double _noise1(double x) {
  final i = x.floorToDouble(), f = x - i, u = f * f * (3 - 2 * f);
  return _h1(i) * (1 - u) + _h1(i + 1) * u;
}

double _fbm1(double x, int oct) {
  var a = 0.5, s = 0.0, n = 0.0;
  for (var i = 0; i < oct; i++) {
    s += a * _noise1(x);
    n += a;
    x = x * 2.03 + 17.3;
    a *= 0.5;
  }
  return s / n;
}

Color _c(Object? hex, [double opacity = 1]) {
  final v = int.parse('$hex'.substring(1), radix: 16);
  return Color(0xFF000000 | v).withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}

double _d(Object? v) => (v as num).toDouble();

List<Offset> _ridgePoints(Map<String, dynamic> l) {
  final base = _d(l['base']), amp = _d(l['amp']), freq = _d(l['freq']), seed = _d(l['seed']);
  final oct = (l['oct'] as num).toInt();
  final peak = l['peak'] as List?, edge = l['edge'] as List?, trees = l['trees'] as List?;
  final pts = <Offset>[];
  for (var x = 0.0; x <= _w; x += 4) {
    var y = base - amp * _fbm1(x * freq + seed * 13.7, oct);
    if (peak != null) {
      final d = max(0.0, 1 - (x - _d(peak[0])).abs() / _d(peak[2]));
      y -= _d(peak[1]) * pow(d, _d(peak[3])) * (0.9 + 0.2 * _fbm1(x * 0.01 + seed, 3));
    }
    if (edge != null) {
      // a foreground ridge that dips in the middle: tall at the sides, low in the centre
      final a = _d(edge[0]), b = _d(edge[1]), c = _d(edge[2]), d = _d(edge[3]);
      final t = x / _w;
      var k = 1.0;
      if (t > a && t < b) {
        k = 1 - (t - a) / (b - a);
      } else if (t >= b && t <= c) {
        k = 0;
      } else if (t > c && t < d) {
        k = (t - c) / (d - c);
      }
      k = k * k * (3 - 2 * k);
      y += (1 - k) * amp * 0.9;
    }
    if (trees != null) {
      final t = x / _d(trees[1]), k = t.floorToDouble(), ph = t - k;
      final tri = 1 - (2 * ph - 1).abs();
      y -= pow(tri, 1.3) * _d(trees[0]) * (0.45 + 0.55 * _h1(k + seed * 7.3));
    }
    pts.add(Offset(x, y));
  }
  return pts;
}

void _drawLayer(Canvas canvas, Map<String, dynamic> l) {
  final paint = Paint()..isAntiAlias = true;
  switch (l['t'] as String) {
    case 'sky':
      final stops = l['stops'] as List;
      paint.shader = ui.Gradient.linear(
          Offset.zero, Offset(0, _d(l['h'])), [for (final s in stops) _c((s as List)[1])], [for (final s in stops) _d((s as List)[0])]);
      canvas.drawRect(const Rect.fromLTWH(0, 0, _w, _h), paint);
    case 'stars':
      final seed = _d(l['seed']), maxY = _d(l['maxY']), alpha = _d(l['alpha']);
      final count = (l['count'] as num).toInt();
      for (var i = 0; i < count; i++) {
        final x = _h1(i * 3.1 + seed) * _w, y = _h1(i * 7.7 + seed + 50) * maxY, r = 0.6 + _h1(i * 1.3 + 9) * 1.5;
        paint.color = Colors.white.withAlpha((255 * alpha * (0.3 + 0.7 * _h1(i * 5.3 + 2)) * (1 - y / maxY * 0.7)).round().clamp(0, 255).toInt());
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    case 'orb':
      final o = Offset(_d(l['x']), _d(l['y'])), r = _d(l['r']);
      paint.shader = ui.Gradient.radial(o, r, [_c(l['color'], _d(l['alpha'])), _c(l['color'], 0)]);
      canvas.drawRect(Rect.fromCircle(center: o, radius: r), paint);
    case 'disc':
      paint.color = _c(l['color']);
      canvas.drawCircle(Offset(_d(l['x']), _d(l['y'])), _d(l['r']), paint);
    case 'mist':
      final y = _d(l['y']), h = _d(l['h']);
      paint.shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + h),
          [_c(l['color'], 0), _c(l['color'], _d(l['alpha'])), _c(l['color'], 0)], const [0, 0.5, 1]);
      canvas.drawRect(Rect.fromLTWH(0, y, _w, h), paint);
    case 'water':
      final y = _d(l['y']), seed = _d(l['seed']), ga = _d(l['glowAlpha']);
      paint.shader = ui.Gradient.linear(Offset(0, y), const Offset(0, _h), [_c(l['top']), _c(l['bottom'])]);
      canvas.drawRect(Rect.fromLTRB(0, y, _w, _h), paint);
      // light lying on the water near the far shore, and thin ripples
      paint.shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + 150), [_c(l['glow'], ga), _c(l['glow'], 0)]);
      canvas.drawRect(Rect.fromLTWH(0, y, _w, 150), paint);
      paint.shader = null;
      for (var i = 0; i < 70; i++) {
        final ry = y + 6 + pow(_h1(i * 2.3 + seed), 1.6) * (_h - y - 20);
        final rw = 40 + _h1(i * 4.1 + seed) * 260, rx = _h1(i * 9.7 + seed) * (_w + 200) - 100;
        paint.color = _c(l['glow'], ga * 0.35 * (1 - (ry - y) / (_h - y)));
        canvas.drawRect(Rect.fromLTWH(rx, ry, rw, 1.5), paint);
      }
    case 'ridge':
      final pts = _ridgePoints(l);
      var top = _h, bottom = 0.0;
      for (final p in pts) {
        top = min(top, p.dy);
        bottom = max(bottom, p.dy);
      }
      paint.shader = ui.Gradient.linear(Offset(0, top), Offset(0, min(_h, top + 420)), [_c(l['top']), _c(l['bottom'])]);
      final path = Path()..moveTo(0, _h);
      for (final p in pts) {
        path.lineTo(p.dx, p.dy);
      }
      path
        ..lineTo(_w, _h)
        ..close();
      canvas.drawPath(path, paint);
      final snow = l['snow'] as List?;
      if (snow != null) {
        // snow from the summits down to a ragged line
        final seed = _d(l['seed']);
        final line = top + (bottom - top) * _d(snow[1]);
        paint
          ..shader = null
          ..color = _c(snow[0], 0.92);
        var run = <Offset>[];
        void flush() {
          if (run.length > 1) {
            final sp = Path()..moveTo(run.first.dx, run.first.dy);
            for (final p in run) {
              sp.lineTo(p.dx, p.dy);
            }
            for (var i = run.length - 1; i >= 0; i--) {
              final p = run[i];
              sp.lineTo(p.dx, p.dy + (line - p.dy) * (0.25 + 0.75 * _fbm1(p.dx * 0.035 + seed * 3.1, 2)));
            }
            sp.close();
            canvas.drawPath(sp, paint);
          }
          run = <Offset>[];
        }

        for (final p in pts) {
          if (p.dy < line) {
            run.add(p);
          } else {
            flush();
          }
        }
        flush();
      }
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.front);
  final String scene;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final layers = (kScenes[scene]?['layers'] as List?) ?? const [];
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);
    for (final l in layers) {
      final m = l as Map<String, dynamic>;
      if ((m['front'] == true) == front) _drawLayer(canvas, m);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.scene != scene || old.front != front;
}

// ───────────────────────── the widget ─────────────────────────

/// Which scene suits right now. With a weather place set, it follows the real sunrise and
/// sunset there (dawn, morning mist, midday, golden hour, night); without one, the clock.
String sceneForNow() {
  final sun = kSun;
  final now = DateTime.now();
  if (sun == null) return sceneForHour(now.hour);
  // sunrise/sunset are today's; move them onto today's date in case the app ran past midnight
  DateTime today(DateTime t) => DateTime(now.year, now.month, now.day, t.hour, t.minute);
  final rise = today(sun.rise), set = today(sun.set);
  if (now.isBefore(rise.subtract(const Duration(minutes: 45)))) return 'starlake';
  if (now.isBefore(rise.add(const Duration(minutes: 90)))) return 'meadow';
  if (now.isBefore(DateTime(now.year, now.month, now.day, 11))) return 'mistforest';
  if (now.isBefore(set.subtract(const Duration(minutes: 100)))) return 'matterhorn';
  if (now.isBefore(set.add(const Duration(minutes: 40)))) return 'volcano';
  return 'starlake';
}

/// Which scene suits the hour (when the sunrise and sunset aren't known).
String sceneForHour(int h) {
  if (h >= 5 && h < 8) return 'meadow';
  if (h >= 8 && h < 11) return 'mistforest';
  if (h >= 11 && h < 16) return 'matterhorn';
  if (h >= 16 && h < 20) return 'volcano';
  return 'starlake';
}

/// One scene, or all of them taking turns every 20 seconds.
///   which: '' = take turns, 'auto' = match the time of day, or a scene's key.
class SceneView extends StatefulWidget {
  const SceneView({super.key, this.which = '', this.clock = true, this.thumb = false});
  final String which;
  final bool clock;

  /// A small preview (decodes photos smaller).
  final bool thumb;
  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> {
  int _i = 0;
  Timer? _turn;

  @override
  void initState() {
    super.initState();
    // start on the scene that suits the hour, then take turns
    _i = max(0, kSceneTurns.indexOf(sceneForNow()));
    _turn = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && (widget.which.isEmpty || widget.which == 'auto')) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _turn?.cancel();
    super.dispose();
  }

  String get _name {
    if (widget.which == 'auto') return sceneForNow();
    if (kScenes.containsKey(widget.which) || kPhotoScenes.containsKey(widget.which)) return widget.which;
    return kSceneTurns[_i % kSceneTurns.length];
  }

  @override
  Widget build(BuildContext context) {
    final name = _name;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1800),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
      child: kPhotoScenes.containsKey(name)
          ? _PhotoStack(key: ValueKey(name), name: name, clock: widget.clock, thumb: widget.thumb)
          : _SceneStack(key: ValueKey(name), name: name, clock: widget.clock),
    );
  }
}

class _SceneStack extends StatelessWidget {
  const _SceneStack({super.key, required this.name, required this.clock});
  final String name;
  final bool clock;

  @override
  Widget build(BuildContext context) {
    final sc = kScenes[name]!;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: CustomPaint(painter: _ScenePainter(name, false))),
      if (clock) _SceneClock(color: _c(sc['clock']), dark: sc['dark'] == true),
      // drawn over the clock: this is what puts the digits behind the scenery
      RepaintBoundary(child: CustomPaint(painter: _ScenePainter(name, true))),
    ]);
  }
}

class _PhotoStack extends StatelessWidget {
  const _PhotoStack({super.key, required this.name, required this.clock, required this.thumb});
  final String name;
  final bool clock;
  final bool thumb;

  @override
  Widget build(BuildContext context) {
    final sc = kPhotoScenes[name]!;
    final ft = sc.frontTop;
    return Stack(fit: StackFit.expand, children: [
      Image.asset('scenes/$name.jpg',
          fit: BoxFit.cover, cacheWidth: thumb ? 480 : null, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black)),
      if (clock) _PhotoClock(top: sc.top),
      // the scenery in front of the clock, cut from the same photo
      if (clock && ft != null)
        Positioned(
          left: 0,
          top: ft,
          width: 1920,
          height: 420,
          child: Image.asset('scenes/$name-front.webp',
              fit: BoxFit.fill, cacheWidth: thumb ? 480 : null, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
    ]);
  }
}

/// The date and big clock on a photo scene, placed so the skyline overlaps the digits
/// just like the previews (Plus Jakarta Sans Bold, 400 px).
class _PhotoClock extends StatefulWidget {
  const _PhotoClock({required this.top});
  final double top;
  @override
  State<_PhotoClock> createState() => _PhotoClockState();
}

class _PhotoClockState extends State<_PhotoClock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _now = DateTime.now();
    if (mounted) setState(() {});
    _t = Timer(Duration(seconds: 61 - _now.second), _tick);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h24 = SettingsScope.of(context).clock24;
    final m = _now.minute.toString().padLeft(2, '0');
    final time = h24 ? '${_now.hour.toString().padLeft(2, '0')}:$m' : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m';
    final date = longDate(_now);
    final top = widget.top;
    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: top - 110,
        child: Text(date,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 44,
                height: 1.0,
                fontWeight: FontWeight.w500,
                color: Color(0xEBFFFFFF),
                shadows: [Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2))])),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: top + 6,
        child: Text(time,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 400,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: Color(0xD7FFFFFF),
                shadows: [Shadow(color: Color(0x46000000), blurRadius: 20, offset: Offset(0, 4))])),
      ),
    ]);
  }
}


/// The date and the big glass clock, centred in the sky.
class _SceneClock extends StatefulWidget {
  const _SceneClock({required this.color, required this.dark});
  final Color color;
  final bool dark;
  @override
  State<_SceneClock> createState() => _SceneClockState();
}

class _SceneClockState extends State<_SceneClock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _now = DateTime.now();
    if (mounted) setState(() {});
    _t = Timer(Duration(seconds: 61 - _now.second), _tick); // one rebuild per minute
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h24 = SettingsScope.of(context).clock24;
    final m = _now.minute.toString().padLeft(2, '0');
    final time = h24 ? '${_now.hour.toString().padLeft(2, '0')}:$m' : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m';
    final date = longDate(_now);
    final c = widget.color;
    final shadow = [
      Shadow(color: widget.dark ? const Color(0x40FFFFFF) : const Color(0x40000000), blurRadius: 30),
    ];
    return Positioned(
      left: 0,
      right: 0,
      top: 136,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(date,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: c.withAlpha(230), shadows: shadow)),
        const SizedBox(height: 26),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          // glass: solid at the top, thinning toward the bottom of the digits
          shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withAlpha(245), c.withAlpha(150)])
              .createShader(r),
          child: Text(time,
              style: TextStyle(
                  fontSize: 400, fontWeight: FontWeight.w200, height: 1.0, letterSpacing: -6, color: c, shadows: shadow)),
        ),
      ]),
    );
  }
}

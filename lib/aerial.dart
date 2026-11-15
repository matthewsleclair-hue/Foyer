// Aerial screensaver (like an Apple TV's): the photo scenes, drifting slowly in and across,
// one after another, with the time in the corner. The scene's name shows when it starts;
// press Down on the remote to see it again (any other button wakes the TV as usual).
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'scenes.dart';

/// Press Down while the aerial screensaver is up: show where it is.
final ValueNotifier<int> kAerialWhere = ValueNotifier(0);

/// What each photo is, for the caption.
const Map<String, String> _where = {
  'meadow': 'Misty meadow at sunrise',
  'matterhorn': 'The Matterhorn, Switzerland',
  'volcano': 'A volcano at dusk',
  'starlake': 'A mountain lake under the stars',
  'mistforest': 'A misty forest in the morning',
  'beach': 'A palm beach at sunset',
  'badlands': 'Rock towers under the Milky Way',
  'lakeland': 'A mountain lake in summer',
};

class AerialView extends StatefulWidget {
  const AerialView({super.key});
  @override
  State<AerialView> createState() => _AerialViewState();
}

class _AerialViewState extends State<AerialView> with TickerProviderStateMixin {
  static const _each = Duration(seconds: 40);
  final _rnd = Random();
  late final List<String> _order = [...kSceneTurns]..shuffle(_rnd);
  int _i = 0;
  late AnimationController _drift = _newDrift();
  AnimationController? _old; // the last scene's, still fading out
  Alignment _from = Alignment.center, _to = Alignment.center;
  double _zFrom = 1.08, _zTo = 1.2;
  bool _caption = true;
  Timer? _next, _hide, _clock;
  DateTime _now = DateTime.now();

  AnimationController _newDrift() => AnimationController(vsync: this, duration: _each)..forward();

  @override
  void initState() {
    super.initState();
    _pickPath();
    _schedule();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));
    kAerialWhere.addListener(_showWhere);
  }

  void _pickPath() {
    // a slow push in (or out) towards one side, different every time
    Alignment side() => Alignment(_rnd.nextDouble() * 1.6 - 0.8, _rnd.nextDouble() * 1.0 - 0.5);
    _from = side();
    _to = side();
    final inward = _rnd.nextBool();
    _zFrom = inward ? 1.06 : 1.24;
    _zTo = inward ? 1.24 : 1.06;
  }

  void _schedule() {
    _caption = true;
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _caption = false);
    });
    _next?.cancel();
    _next = Timer(_each - const Duration(seconds: 2), _advance);
  }

  void _advance() {
    if (!mounted) return;
    _old?.dispose();
    final old = _old = _drift;
    setState(() {
      _i = (_i + 1) % _order.length;
      _pickPath();
      _drift = _newDrift();
    });
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (_old == old) {
        _old = null;
        old.dispose();
      }
    });
    _schedule();
  }

  void _showWhere() {
    if (!mounted) return;
    setState(() => _caption = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _caption = false);
    });
  }

  @override
  void dispose() {
    kAerialWhere.removeListener(_showWhere);
    _next?.cancel();
    _hide?.cancel();
    _clock?.cancel();
    _old?.dispose();
    _old = null;
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final key = _order[_i];
    final m = _now.minute.toString().padLeft(2, '0');
    final time = s.clock24
        ? '${_now.hour.toString().padLeft(2, '0')}:$m'
        : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m';
    const shadow = [Shadow(color: Color(0xAA000000), blurRadius: 24)];
    final drift = _drift;
    final from = _from, to = _to, zf = _zFrom, zt = _zTo;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 2400),
        child: AnimatedBuilder(
          key: ValueKey('$key$_i'),
          animation: drift,
          builder: (_, child) {
            final t = Curves.easeInOutSine.transform(drift.value);
            return Transform.scale(
              scale: zf + (zt - zf) * t,
              alignment: Alignment.lerp(from, to, t)!,
              child: child,
            );
          },
          child: Image.asset('scenes/$key.jpg', fit: BoxFit.cover, width: 1920, height: 1080, gaplessPlayback: true),
        ),
      ),
      // a soft shade at the bottom so the words read on any photo
      const DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
                  stops: [0, 0.22, 0.7, 1]))),
      Positioned(
        top: 56,
        right: 80,
        child: Text(time,
            style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, shadows: shadow)),
      ),
      Positioned(
        left: 80,
        bottom: 64,
        child: AnimatedOpacity(
          opacity: _caption ? 1 : 0,
          duration: const Duration(milliseconds: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_where[key] ?? sceneName(key),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600, shadows: shadow)),
            const SizedBox(height: 6),
            Text(longDate(_now), style: const TextStyle(fontSize: 26, color: Colors.white70, shadows: shadow)),
          ]),
        ),
      ),
    ]);
  }
}

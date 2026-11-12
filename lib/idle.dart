// Smart idle and Screen off (ideas from couch-tv, github.com/Seagey/couch-tv, MIT).
//
// Smart idle: after a long while with nobody pressing anything on the home screen,
// show a dim clock on black that drifts so nothing burns in, black the screen, or turn
// the TV off. And when a show or song stays paused for a while, turn the TV off (with
// a one-minute "still here?" note first). Quiet hours make the waits shorter overnight.
//
// Screen off: the picture goes black while the sound keeps playing.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'screens.dart';

const List<int> kIdleMinutes = [10, 15, 30, 60, 120];
const List<int> kPausedMinutes = [0, 15, 30, 60, 120];

String _mins(int m) => m == 0 ? 'Never' : (m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '${m ~/ 60} hours'));

String idleActionName(String a) =>
    a == 'screenoff' ? 'Screen off' : (a == 'tvoff' ? 'Turn the TV off' : 'Dim clock');

String smartIdleSummary(Settings s) {
  if (!s.idleOn) return 'Off';
  final p = s.pausedMinutes > 0 ? ', paused shows after ${_mins(s.pausedMinutes)}' : '';
  return '${idleActionName(s.idleAction)} after ${_mins(s.idleMinutes)}$p';
}

bool _quietNow() {
  final h = DateTime.now().hour;
  return h >= 23 || h < 6;
}

/// How long the home screen waits before Smart idle steps in.
Duration smartIdleWait(Settings s) {
  var m = s.idleMinutes;
  if (s.quietHours && _quietNow()) m = min(m, 10);
  return Duration(minutes: m);
}

String _idleSig = '';

/// Tells the TV side about the "paused for a while" part (it watches even while another app is in front).
void syncSmartIdle(Settings s) {
  final paused = s.idleOn ? s.pausedMinutes : 0;
  final sig = '$paused/${s.quietHours}';
  if (sig == _idleSig) return;
  _idleSig = sig;
  kChannel.invokeMethod('smartIdle', {'pausedMinutes': paused, 'quiet': s.quietHours}).catchError((Object _) => null);
}

/// Screen off now. Uses the remote helper so it works over any app; without it,
/// a black page inside Foyer does the same while Foyer is in front.
Future<void> screenOffNow(BuildContext context) async {
  var ok = false;
  try {
    ok = (await kChannel.invokeMethod<bool>('screenOff')) ?? false;
  } catch (_) {}
  if (ok || !context.mounted) return;
  await Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (ctx, __, ___) => Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent) Navigator.of(ctx).pop();
          return KeyEventResult.handled;
        },
        child: const _FadingHint(),
      ),
    ),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _FadingHint extends StatefulWidget {
  const _FadingHint();
  @override
  State<_FadingHint> createState() => _FadingHintState();
}

class _FadingHintState extends State<_FadingHint> {
  bool _show = true;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: const Alignment(0, 0.85),
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 1200),
          child: const Text('Screen off. The sound keeps playing.\nPress any button to bring the picture back.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 26, color: Colors.white54)),
        ),
      );
}

/// Smart idle's dim clock: pure black, a small grey clock that slowly drifts so no
/// pixel stays lit in one place. Any button wakes the home screen.
class DimClockView extends StatefulWidget {
  const DimClockView({super.key});
  @override
  State<DimClockView> createState() => _DimClockViewState();
}

class _DimClockViewState extends State<DimClockView> {
  final _rnd = Random();
  Timer? _t;
  DateTime _now = DateTime.now();
  Alignment _at = Alignment.center;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => _move());
  }

  void _move() {
    if (!mounted) return;
    setState(() {
      _now = DateTime.now();
      _at = Alignment(_rnd.nextDouble() * 1.4 - 0.7, _rnd.nextDouble() * 1.2 - 0.6);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final m = _now.minute.toString().padLeft(2, '0');
    final h = s.clock24 ? _now.hour.toString().padLeft(2, '0') : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}';
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return ColoredBox(
      color: Colors.black,
      child: AnimatedAlign(
        alignment: _at,
        duration: const Duration(seconds: 25),
        curve: Curves.easeInOut,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$h:$m',
              style: const TextStyle(fontSize: 150, fontWeight: FontWeight.w200, color: Color(0x66FFFFFF), height: 1)),
          const SizedBox(height: 8),
          Text('${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}',
              style: const TextStyle(fontSize: 30, color: Color(0x4DFFFFFF))),
        ]),
      ),
    );
  }
}

// ───────────────────────── settings page ─────────────────────────

class SmartIdleScreen extends StatelessWidget {
  const SmartIdleScreen({super.key});

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 14),
        child: Text(t, style: const TextStyle(fontSize: 28, color: Colors.white70)),
      );

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'Smart idle',
      subtitle: 'When nobody is watching, Foyer protects the screen and can turn the TV off. '
          'A note shows a minute before the TV turns off: any button keeps it on.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(
                autofocus: true,
                label: 'On',
                selected: s.idleOn,
                onSelect: () => s.change(() => s.idleOn = true)),
            Opt(label: 'Off', selected: !s.idleOn, onSelect: () => s.change(() => s.idleOn = false)),
          ]),
          if (s.idleOn) ...[
            _label('Nothing pressed on the home screen for'),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final m in kIdleMinutes)
                Opt(label: _mins(m), selected: s.idleMinutes == m, onSelect: () => s.change(() => s.idleMinutes = m)),
            ]),
            _label('Then'),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final a in const ['clock', 'screenoff', 'tvoff'])
                Opt(label: idleActionName(a), selected: s.idleAction == a, onSelect: () => s.change(() => s.idleAction = a)),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  s.idleAction == 'screenoff'
                      ? 'The picture goes black. Any button brings it back.'
                      : (s.idleAction == 'tvoff'
                          ? 'The TV turns off, after a one-minute note.'
                          : 'A small, dim clock on black that slowly moves around, so nothing burns into the screen.'),
                  style: const TextStyle(fontSize: 23, color: Colors.white54)),
            ),
            _label('Turn the TV off when a show or song stays paused for'),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final m in kPausedMinutes)
                Opt(
                    label: _mins(m),
                    selected: s.pausedMinutes == m,
                    onSelect: () => s.change(() => s.pausedMinutes = m)),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Works in any app. Game consoles and HDMI inputs are never turned off.',
                  style: TextStyle(fontSize: 23, color: Colors.white54)),
            ),
            _label('Quiet hours'),
            Wrap(spacing: 16, runSpacing: 16, children: [
              Opt(label: 'On', selected: s.quietHours, onSelect: () => s.change(() => s.quietHours = true)),
              Opt(label: 'Off', selected: !s.quietHours, onSelect: () => s.change(() => s.quietHours = false)),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('From 11 pm to 6 am, the waits are shorter: 10 minutes on the home screen, 15 when paused.',
                  style: TextStyle(fontSize: 23, color: Colors.white54)),
            ),
          ],
        ]),
      ),
      actions: [
        PillButton(
            label: 'Preview the dim clock',
            onSelect: () => Navigator.of(context).push(PageRouteBuilder<void>(
                  opaque: true,
                  pageBuilder: (ctx, __, ___) => Focus(
                    autofocus: true,
                    onKeyEvent: (_, e) {
                      if (e is KeyDownEvent) Navigator.of(ctx).pop();
                      return KeyEventResult.handled;
                    },
                    child: const DimClockView(),
                  ),
                ))),
      ],
    );
  }
}

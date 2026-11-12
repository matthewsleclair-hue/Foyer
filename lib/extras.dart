import 'dart:async';
import 'dart:math';
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

/// The flame button opens a fireplace video in the YouTube app, full screen.
/// (Settings > Home screen > Fireplace video changes which one.)
const String kFireplaceVideo = 'https://www.youtube.com/watch?v=XcyX-1J4P1Q';

Future<void> openFireplace(BuildContext context) async {
  final s = SettingsScope.read(context);
  final url = s.fireplaceUrl.trim().isEmpty ? kFireplaceVideo : s.fireplaceUrl.trim();
  bool ok = false;
  try {
    ok = (await kChannel.invokeMethod<bool>('openUrl', {'url': url})) ?? false;
  } catch (_) {}
  if (!ok && context.mounted) {
    showMenu2(context, 'Fireplace', [
      MenuChoice('The fireplace plays in the YouTube app, which doesn\'t seem to be on this TV.', null),
      MenuChoice('OK', () {}),
    ]);
  }
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

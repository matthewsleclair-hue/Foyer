// Small everyday helpers:
//  - No internet: a check every minute; when it's down, an orange button on the home screen
//    says so and offers a fix (reconnect Wi-Fi, Wi-Fi settings, check again).
//  - Open apps: press Back twice on the home screen for big cards of the apps that are open
//    (like an Apple TV): OK opens one, Up swipes it away and closes it.
//  - Battery warnings: the remote or a game controller running low gets a note over
//    whatever is playing; levels also show on the Bluetooth page.
//  - Undo: removing an app from the home screen shows an Undo note for a few seconds.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'i18n.dart';
import 'main.dart';
import 'system.dart';

// ───────────────────────── no internet ─────────────────────────

/// true online, false offline (two failed checks in a row), null not checked yet.
final ValueNotifier<bool?> kOnline = ValueNotifier(null);
Timer? _netTimer;
int _fails = 0;
bool _checking = false;

void startNetWatch() {
  _netTimer ??= Timer.periodic(const Duration(minutes: 1), (_) => checkNetNow());
  checkNetNow();
}

Future<bool> _reachable() async {
  // a plain "are we online" page Google and every phone use; any answer at all is fine
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await c.getUrl(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
        .timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    await res.drain<void>();
    return true;
  } catch (_) {
    try {
      final r = await InternetAddress.lookup('one.one.one.one').timeout(const Duration(seconds: 5));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  } finally {
    c.close(force: true);
  }
}

Future<bool> checkNetNow() async {
  if (_checking) return kOnline.value ?? true;
  _checking = true;
  try {
    final ok = await _reachable();
    if (ok) {
      _fails = 0;
      kOnline.value = true;
    } else if (++_fails >= 2 || kOnline.value == false) {
      kOnline.value = false;
    } else {
      // one miss can be a hiccup: look again soon
      Timer(const Duration(seconds: 10), checkNetNow);
    }
    return ok;
  } finally {
    _checking = false;
  }
}

/// What's wrong, in plain words.
Future<String> _netReason() async {
  if (kIsPc) return 'The PC is not reaching the internet. Check its network cable or Wi-Fi, or restart the modem.';
  final i = await sysCall('info');
  final link = '${i['link'] ?? ''}';
  if (link.isEmpty) return 'The TV isn\'t connected to any network.';
  return link == 'ethernet'
      ? 'The TV is connected by cable, but the internet isn\'t answering. The modem or router may need a restart.'
      : 'The TV is on Wi-Fi, but the internet isn\'t answering. Reconnecting often fixes it; if not, restart the modem or router.';
}

Future<void> netMenu(BuildContext context) async {
  final why = await _netReason();
  if (!context.mounted) return;
  await showMenu2(context, 'No internet', [
    MenuChoice(why, null),
    if (!kIsPc)
      MenuChoice('Reconnect Wi-Fi', () async {
        await adbOut(['cmd wifi set-wifi-enabled disabled', 'sleep 2', 'cmd wifi set-wifi-enabled enabled']);
        _fails = 0;
        Timer(const Duration(seconds: 12), checkNetNow);
      }),
    if (!kIsPc)
      MenuChoice('Wi-Fi settings', () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WifiScreen()));
      }),
    MenuChoice('Check again', () => checkNetNow()),
  ]);
}

// ───────────────────────── recent apps ─────────────────────────

DateTime _lastBack = DateTime(2000);

/// The home screen's Back: twice quickly opens recent apps.
void homeBack(BuildContext context) {
  final now = DateTime.now();
  if (now.difference(_lastBack) < const Duration(milliseconds: 700)) {
    _lastBack = DateTime(2000);
    showRecents(context);
  } else {
    _lastBack = now;
  }
}

/// When each app was closed from the switcher, so it stays gone until it's used again.
final Map<String, DateTime> _closedAt = {};

/// Not apps you'd switch to: Foyer itself, Google's home and setup screens, the assistant.
const _notApps = {
  'com.leclair.leclair_home',
  'com.google.android.apps.tv.launcherx',
  'com.google.android.tvlauncher',
  'com.google.android.tungsten.setupwraith',
  'com.google.android.katniss',
  'com.android.systemui',
  'com.android.tv.settings',
  'com.google.android.tv.remote.service',
  'com.amazon.tv.launcher',
};

/// The TV's own list of recent apps (the one Android keeps), newest first: apps opened from
/// Foyer, Keep watching, Search, the remote's app buttons or the phone. Null when Foyer
/// can't read it (no TV access yet, or on a PC).
Future<List<String>?> _systemRecents() async {
  if (kIsPc) return null;
  final r = await adbOut(['dumpsys activity recents']);
  if (!r.ok || !r.at(0).contains('Recent #')) return null;
  final out = <String>[];
  final now = DateTime.now();
  for (final chunk in r.at(0).split('* Recent #').skip(1)) {
    final m = RegExp(r'realActivity=\{?([A-Za-z0-9_.]+)/').firstMatch(chunk) ??
        RegExp(r'A=\d+:([A-Za-z0-9_.]+)').firstMatch(chunk);
    if (m == null) continue;
    final pkg = m.group(1)!;
    if (_notApps.contains(pkg) || out.contains(pkg)) continue;
    // closed from the switcher, and not used since
    final closed = _closedAt[pkg];
    final idle = int.tryParse(RegExp(r'inactive for (\d+)s').firstMatch(chunk)?.group(1) ?? '');
    if (closed != null && (idle == null || now.subtract(Duration(seconds: idle)).isBefore(closed))) continue;
    out.add(pkg);
  }
  return out;
}

/// Closes an app for real (the TV's force stop), or as well as Android allows.
Future<void> closeAppNow(String pkg) async {
  _closedAt[pkg] = DateTime.now();
  if (!kIsPc) {
    final r = await adbOut(['am force-stop $pkg']);
    if (r.ok) return;
  }
  try {
    await kChannel.invokeMethod<bool>('killApp', {'package': pkg});
  } catch (_) {}
}

/// The app switcher (Back twice on the home screen): big cards of your open apps, like on
/// an Apple TV. OK opens one, Up swipes it away and closes it, Close all closes them all.
Future<void> showRecents(BuildContext context) async {
  final s = SettingsScope.read(context);
  // the TV's own recent apps; Foyer's own list when it can't read those
  final sys = await _systemRecents();
  final want = (sys ?? [for (final p in s.recentApps) if (!_closedAt.containsKey(p)) p]).take(8).toList();
  List<Map> raw = const [];
  if (want.isNotEmpty) {
    try {
      raw = (await kChannel.invokeListMethod<Map>('getApps', {'packages': want})) ?? const [];
    } catch (_) {}
  }
  final byPkg = {for (final m in raw) '${m['package']}': m};
  final apps = [for (final p in want) if (byPkg[p] != null) byPkg[p]!];
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'apps',
    barrierColor: Colors.black.withAlpha(170),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child)),
    pageBuilder: (ctx, _, __) => _Switcher(apps: apps, onGone: (p) => s.change(() => s.recentApps = s.recentApps.where((x) => x != p).toList())),
  );
}

class _Switcher extends StatefulWidget {
  const _Switcher({required this.apps, required this.onGone});
  final List<Map> apps;
  final ValueChanged<String> onGone;
  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  late final List<Map> _apps = [...widget.apps];
  final Set<String> _leaving = {};
  final List<FocusNode> _nodes = [];
  int _at = 0;

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _node(int i) {
    while (_nodes.length <= i) {
      _nodes.add(FocusNode());
    }
    return _nodes[i];
  }

  String _pkg(Map m) => '${m['package']}';

  Future<void> _close(int i) async {
    if (i >= _apps.length) return;
    final m = _apps[i];
    final pkg = _pkg(m);
    if (_leaving.contains(pkg)) return;
    setState(() => _leaving.add(pkg)); // the card flies up and fades
    closeAppNow(pkg);
    widget.onGone(pkg);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() {
      _apps.removeAt(i);
      _leaving.remove(pkg);
      _at = _apps.isEmpty ? 0 : i.clamp(0, _apps.length - 1).toInt();
    });
    if (_apps.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(_at).requestFocus();
    });
  }

  Future<void> _closeAll() async {
    for (final m in [..._apps]) {
      closeAppNow(_pkg(m));
      widget.onGone(_pkg(m));
    }
    setState(() => _leaving.addAll(_apps.map(_pkg)));
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _card(int i) {
    final m = _apps[i];
    final pkg = _pkg(m);
    final gone = _leaving.contains(pkg);
    final img = m['image'] as Uint8List;
    return AnimatedSlide(
      offset: gone ? const Offset(0, -1.2) : Offset.zero,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeIn,
      child: AnimatedOpacity(
        opacity: gone ? 0 : 1,
        duration: const Duration(milliseconds: 240),
        child: Focus(
          skipTraversal: true,
          canRequestFocus: false,
          // Up on a card: swipe it away
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowUp) {
              _close(i);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: FocusButton(
            focusNode: _node(i),
            autofocus: i == _at,
            scale: 1.08,
            onFocusChange: (f) {
              if (f) _at = i;
            },
            onSelect: () {
              Navigator.of(context).pop();
              launchPackage(pkg);
            },
            onLongPress: () => _close(i),
            builder: (_, f) => Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 400,
                height: 225,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: f ? Colors.white : Colors.white24, width: f ? 4 : 1.5),
                  boxShadow: f ? const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 18))] : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: m['wide'] == true
                    ? Image.memory(img, fit: BoxFit.cover)
                    : Container(
                        color: Color((m['color'] as int?) ?? 0xFF333333),
                        padding: const EdgeInsets.all(40),
                        child: Image.memory(img, fit: BoxFit.contain)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 400,
                child: Text('${m['label']}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: f ? Colors.white : Colors.white60)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Open apps', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(_apps.isEmpty ? 'No apps are open.' : 'OK opens  ·  Up closes it  ·  Back goes home',
            style: const TextStyle(fontSize: 24, color: Colors.white60)),
        const SizedBox(height: 60),
        if (_apps.isEmpty)
          PillButton(label: 'OK', autofocus: true, onSelect: () => Navigator.of(context).pop())
        else ...[
          SizedBox(
            height: 300,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < _apps.length; i++)
                  Padding(padding: EdgeInsets.only(left: i == 0 ? 0 : 40), child: _card(i)),
              ]),
            ),
          ),
          const SizedBox(height: 40),
          PillButton(label: _apps.length == 1 ? 'Close it' : 'Close all', onSelect: _closeAll),
        ],
      ]),
    );
  }
}

// ───────────────────────── batteries ─────────────────────────

class Battery {
  Battery(this.name, this.level, this.kind);
  final String name;
  final int level; // 0..100
  final String kind; // remote, controller, headphones, other
}

final ValueNotifier<List<Battery>> kBatteries = ValueNotifier(const []);
final Map<String, (int, DateTime)> _warned = {};
Timer? _batTimer;

void startBatteryWatch() {
  if (kIsPc) return;
  _batTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => checkBatteries());
  Timer(const Duration(minutes: 1), checkBatteries);
}

Future<List<Battery>> checkBatteries({bool warn = true}) async {
  if (kIsPc) return const [];
  List<Map>? raw;
  try {
    raw = await kChannel.invokeListMethod<Map>('batteries');
  } catch (_) {}
  final l = [
    for (final m in raw ?? const <Map>[])
      if (m['level'] is num) Battery('${m['name']}', (m['level'] as num).toInt().clamp(0, 100).toInt(), '${m['kind']}')
  ];
  kBatteries.value = l;
  if (warn) {
    for (final b in l) {
      if (b.level > 15) {
        _warned.remove(b.name);
        continue;
      }
      // once when it gets low, again when it's nearly empty, and at most every 12 hours
      final w = _warned[b.name];
      final again = w == null ||
          (b.level <= 5 && w.$1 > 5) ||
          DateTime.now().difference(w.$2) > const Duration(hours: 12);
      if (!again) continue;
      _warned[b.name] = (b.level, DateTime.now());
      final what = b.kind == 'controller'
          ? 'Controller battery low'
          : (b.kind == 'remote' ? 'Remote battery low' : 'Battery low');
      kChannel.invokeMethod('alert', {
        'emoji': '🔋',
        'event': tr(what),
        'line': '${b.name} · ${b.level}%',
        'color': 'FF9F0A',
        'size': 1,
      }).catchError((_) => null);
    }
  }
  return l;
}

String batteryIcon(int level) => level <= 15 ? '🪫' : '🔋';

// ───────────────────────── undo ─────────────────────────

/// "Removed Netflix · Undo" for a few seconds. OK undoes; anything else lets it go.
Future<void> showUndo(BuildContext context, String message, VoidCallback onUndo) async {
  Timer? t;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'undo',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) {
      t ??= Timer(const Duration(seconds: 6), () {
        if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
      });
      return Align(
        alignment: const Alignment(0, 0.86),
        child: Focus(
          skipTraversal: true,
          canRequestFocus: false,
          // arrows let it go, so moving on feels normal
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent &&
                (e.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    e.logicalKey == LogicalKeyboardKey.arrowRight ||
                    e.logicalKey == LogicalKeyboardKey.arrowUp ||
                    e.logicalKey == LogicalKeyboardKey.arrowDown)) {
              Navigator.of(ctx).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Glass(
            radius: 40,
            padding: const EdgeInsets.fromLTRB(34, 14, 14, 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(message, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
              const SizedBox(width: 22),
              PillButton(
                  label: 'Undo',
                  primary: true,
                  autofocus: true,
                  onSelect: () {
                    Navigator.of(ctx).pop();
                    onUndo();
                  }),
            ]),
          ),
        ),
      );
    },
  );
  t?.cancel();
}

/// Takes an app off the home screen, with Undo.
void removeFromHome(BuildContext context, String pkg, String label) {
  final s = SettingsScope.read(context);
  final before = [...s.pinned];
  s.setPinned(s.pinned.where((p) => p != pkg).toList());
  showUndo(context, tr('Removed {}').replaceFirst('{}', label), () => s.setPinned(before));
}

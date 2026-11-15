// Small everyday helpers:
//  - No internet: a check every minute; when it's down, an orange button on the home screen
//    says so and offers a fix (reconnect Wi-Fi, Wi-Fi settings, check again).
//  - Recent apps: press Back twice on the home screen to jump back to the last few apps.
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

Future<void> showRecents(BuildContext context) async {
  final s = SettingsScope.read(context);
  final want = s.recentApps.take(6).toList();
  List<Map> raw = const [];
  if (want.isNotEmpty) {
    try {
      raw = (await kChannel.invokeListMethod<Map>('getApps', {'packages': want})) ?? const [];
    } catch (_) {}
  }
  // keep the most-recent-first order
  final byPkg = {for (final m in raw) '${m['package']}': m};
  final apps = [for (final p in want) if (byPkg[p] != null) byPkg[p]!];
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'recent',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) => Center(
      child: Glass(
        radius: 40,
        padding: const EdgeInsets.fromLTRB(40, 30, 40, 36),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recent apps', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
          const SizedBox(height: 22),
          if (apps.isEmpty)
            const Text('Apps you open from Foyer show up here.', style: TextStyle(fontSize: 26, color: Colors.white70))
          else
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < apps.length; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 22),
                  child: FocusButton(
                    autofocus: i == 0,
                    onSelect: () {
                      Navigator.of(ctx).pop();
                      launchPackage('${apps[i]['package']}');
                    },
                    builder: (_, f) => Column(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 240,
                        height: 135,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: f ? Colors.white : Colors.white24, width: f ? 4 : 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: apps[i]['wide'] == true
                            ? Image.memory(apps[i]['image'] as Uint8List, fit: BoxFit.cover)
                            : Container(
                                color: Color((apps[i]['color'] as int?) ?? 0xFF333333),
                                padding: const EdgeInsets.all(26),
                                child: Image.memory(apps[i]['image'] as Uint8List, fit: BoxFit.contain)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 240,
                        child: Text('${apps[i]['label']}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 22, color: f ? Colors.white : Colors.white70)),
                      ),
                    ]),
                  ),
                ),
            ]),
        ]),
      ),
    ),
  );
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

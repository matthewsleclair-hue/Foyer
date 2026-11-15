// Settings follow you: every TV and PC linked to Foyer Drop keeps a copy of its settings
// there (apps, people, teams, look, weather, idle, remote buttons; never Plex or other
// sign-ins). A new box, or one reset for someone new, can copy any box in the household:
// right after it's linked to Foyer Drop, or from Settings → Backup and updates.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'screens.dart';
import 'server.dart';

Timer? _soon;
String _sentSig = '';

String get _platform => kIsPc ? 'pc' : 'tv';

/// Settings that belong to this one box and are never copied.
const _thisBoxOnly = ['setupDone', 'serverUrl', 'devMode', 'updateUrl', 'syncOn', 'v'];

/// Called whenever settings are saved: sends the copy a little later, once things settle.
void syncSoon(Settings s, {Duration soon = const Duration(seconds: 20)}) {
  if (!s.syncOn || !s.setupDone || s.serverUrl.isEmpty || s.serverToken.isEmpty) return;
  _soon?.cancel();
  _soon = Timer(soon, () => syncNow(s));
}

Map<String, dynamic> shareableSettings(Settings s) {
  final j = s.toJson(secrets: false);
  for (final k in _thisBoxOnly) {
    j.remove(k);
  }
  if (j['wallMode'] == 'photo') {
    // a photo on this box's storage: the other box won't have it
    j.remove('wallMode');
    j.remove('wallValue');
  }
  return j;
}

/// Sends this box's copy now. Null when fine, or what went wrong.
Future<String?> syncNow(Settings s, {bool force = false}) async {
  if (s.serverUrl.isEmpty || s.serverToken.isEmpty) return 'Link Foyer Drop first.';
  final j = shareableSettings(s);
  final sig = jsonEncode(j);
  if (!force && sig == _sentSig) return null;
  try {
    await DropApi.saveSettings(s.serverUrl, s.serverToken, j, _platform);
    _sentSig = sig;
    return null;
  } catch (e) {
    return '$e';
  }
}

/// The other boxes in the household with a copy, newest first.
Future<List<Map<String, dynamic>>> otherBoxes(Settings s) async {
  if (s.serverUrl.isEmpty || s.serverToken.isEmpty) return const [];
  try {
    final l = await DropApi.settingsCopies(s.serverUrl, s.serverToken);
    return [for (final c in l) if (c['mine'] != true) c];
  } catch (_) {
    return const [];
  }
}

/// Makes this box like another one. Apps only carry over between the same kind of box
/// (a TV's apps aren't a PC's apps); everything else does.
Future<String> copyFromBox(Settings s, Map<String, dynamic> box) async {
  try {
    final r = await DropApi.settingsCopy(s.serverUrl, s.serverToken, '${box['id']}');
    final j = Map<String, dynamic>.from(r['settings'] as Map);
    for (final k in _thisBoxOnly) {
      j.remove(k);
    }
    final same = '${r['platform']}' == _platform;
    if (!same) {
      j.remove('pinned');
      j.remove('remoteKeys');
      j.remove('autoStart');
      j.remove('keepHiddenApps');
      final pr = j['profiles'];
      if (pr is List) {
        j['profiles'] = [
          for (final p in pr)
            if (p is Map) {...Map<String, dynamic>.from(p), 'pinned': s.pinned}
        ];
      }
    }
    s.restore(j);
    final who = '${r['name']}';
    return same
        ? 'This box is now set up like $who. Plex needs to be linked again.'
        : 'Copied from $who: people, teams, look and weather. Apps stay as they are here, since $who is a different kind of box.';
  } catch (e) {
    return 'Could not copy the settings: $e';
  }
}

String boxLabel(Map<String, dynamic> b, {bool name = true}) {
  final kind = b['platform'] == 'pc' ? 'PC' : 'TV';
  final at = b['updated'] is num
      ? DateTime.fromMillisecondsSinceEpoch(((b['updated'] as num) * 1000).round())
      : null;
  final when = at == null ? '' : ' · ${shortDate(at)}';
  return name ? '${b['name']} ($kind)$when' : '$kind$when';
}

/// Right after linking Foyer Drop: "Set up like the living room TV?"
Future<void> offerSettingsCopy(BuildContext context) async {
  final s = SettingsScope.read(context);
  final boxes = await otherBoxes(s);
  if (boxes.isEmpty || !context.mounted) {
    syncSoon(s, soon: const Duration(seconds: 5));
    return;
  }
  String? msg;
  await showMenu2(context, 'Set this up like another TV?', [
    for (final b in boxes.take(5))
      MenuChoice('Copy ${boxLabel(b)}', () async {
        msg = await copyFromBox(s, b);
        if (context.mounted && msg != null) showInfo(context, 'Settings copied', msg!);
      }),
    MenuChoice('Keep this one as it is', () => syncSoon(s, soon: const Duration(seconds: 5))),
  ]);
}

/// Settings → Backup and updates → Settings follow you
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<Map<String, dynamic>>? _boxes;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = SettingsScope.read(context);
    final l = await otherBoxes(s);
    if (mounted) setState(() => _boxes = l);
  }

  Future<void> _copy(Map<String, dynamic> b) async {
    final s = SettingsScope.read(context);
    await showMenu2(context, 'Replace this box\'s settings with ${b['name']}\'s?', [
      MenuChoice('Copy ${b['name']}', () async {
        setState(() => _msg = 'Copying…');
        final m = await copyFromBox(s, b);
        if (mounted) setState(() => _msg = m);
      }),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final linked = s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty;
    final boxes = _boxes;
    return SettingsPage(
      title: 'Settings follow you',
      subtitle:
          'Each TV and PC linked to your Foyer Drop keeps a copy of its settings there: apps, people, teams, look and weather. A new box can copy any of them. Sign-ins like Plex are never copied.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!linked)
            const Text('Link Foyer Drop first (Settings › Home screen › Foyer Drop).',
                style: TextStyle(fontSize: 28, color: Colors.white70))
          else ...[
            SettingRow(
              autofocus: true,
              entry: HubEntry(
                  Icons.cloud_upload_rounded,
                  'Keep a copy on Foyer Drop',
                  s.syncOn ? 'On: saved by itself when something changes' : 'Off',
                  () => s.change(() => s.syncOn = !s.syncOn)),
            ),
            if (s.syncOn)
              SettingRow(
                entry: HubEntry(Icons.sync_rounded, 'Save a copy now', '', () async {
                  setState(() => _msg = 'Saving…');
                  final r = await syncNow(s, force: true);
                  if (mounted) setState(() => _msg = r ?? 'Saved. Your other boxes can copy this one.');
                }),
              ),
            const SizedBox(height: 30),
            const Text('Copy from another box', style: TextStyle(fontSize: 26, color: Colors.white54)),
            const SizedBox(height: 12),
            if (boxes == null)
              const Text('Loading…', style: TextStyle(fontSize: 26, color: Colors.white70))
            else if (boxes.isEmpty)
              const Text('No other TV or PC has saved its settings yet.',
                  style: TextStyle(fontSize: 26, color: Colors.white70))
            else
              for (final b in boxes)
                SettingRow(
                  entry: HubEntry(b['platform'] == 'pc' ? Icons.computer_rounded : Icons.tv_rounded,
                      '${b['name']}', boxLabel(b, name: false), () => _copy(b)),
                ),
          ],
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 26),
            Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70, height: 1.35)),
          ],
        ]),
      ),
    );
  }
}

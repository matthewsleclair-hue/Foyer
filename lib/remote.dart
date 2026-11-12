// Settings > TV tools > Remote buttons: choose what the remote's extra buttons
// open (the Streamer's star button, YouTube, Netflix, or any other button),
// on a press and on a hold. The native side is RemoteKeys.kt.
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';
import 'system.dart';

const Map<int, String> kKnownButtons = {
  313: 'Star button',
  190: 'YouTube button',
  191: 'Netflix button',
};

/// What each known button opens when nobody changed it.
const Map<int, String> _usualApp = {
  190: 'com.google.android.youtube.tv',
  191: 'com.netflix.ninja',
};

String buttonName(int code, [String raw = '']) {
  final k = kKnownButtons[code];
  if (k != null) return k;
  var n = raw.replaceFirst('KEYCODE_', '').replaceAll('_', ' ').toLowerCase();
  if (n.isEmpty || RegExp(r'^\d+$').hasMatch(n)) return 'Button $code';
  n = n[0].toUpperCase() + n.substring(1);
  return '$n button';
}

class RemoteButtonsScreen extends StatefulWidget {
  const RemoteButtonsScreen({super.key});
  @override
  State<RemoteButtonsScreen> createState() => _RemoteButtonsScreenState();
}

class _RemoteButtonsScreenState extends State<RemoteButtonsScreen> {
  Map<String, String> _labels = {};
  bool _helper = true;
  bool _googleHomeOff = false;
  String _msg = '';
  final Map<int, String> _rawNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await fetchInstalledApps();
    Map<String, dynamic> st = {};
    try {
      st = await kChannel.invokeMapMethod<String, dynamic>('remoteKeysStatus') ?? {};
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _labels = {for (final a in apps) a.package: a.label};
      _helper = st['helper'] == true;
      _googleHomeOff = st['googleHomeOff'] == true;
    });
  }

  Future<void> _turnOnHelper() async {
    bool ok = false;
    setState(() => _msg = 'Turning the helper on…');
    // Android blocks helpers for apps it calls "restricted" (any app updated by opening
    // an APK file). Lift that first through the TV's debugging link.
    if (!kIsFireTv) {
      await adbQuick(['appops set com.leclair.leclair_home ACCESS_RESTRICTED_SETTINGS allow']);
    }
    try {
      ok = (await kChannel.invokeMethod<bool>('setHomeKey', {'enabled': true})) ?? false;
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 1));
    await _load();
    if (!mounted) return;
    if (!ok) {
      setState(() => _msg = kIsFireTv
          ? 'Turn on the Home button helper first: Settings › TV tools › Home button.'
          : 'Foyer needs its one-time TV access first: Settings › TV tools › Home button › Make Foyer the home screen.');
    } else if (!_helper) {
      setState(() => _msg = 'Asked the TV to turn the helper on. If nothing changes, restart Foyer.');
    } else {
      setState(() => _msg = '');
    }
  }

  String _describe(String? action, int code, {required bool held}) {
    if (action == null || action.isEmpty) {
      if (held) return 'nothing extra';
      final u = _usualApp[code];
      if (u != null) return '${_labels[u] ?? 'its app'} (normal)';
      if (code == 313) return _googleHomeOff ? 'nothing yet' : 'Google\'s shortcut (normal)';
      return 'normal';
    }
    if (action == 'foyer') return 'Foyer home';
    if (action == 'sleep') return 'Sleep timer (+30 min)';
    return _labels[action] ?? action;
  }

  List<int> _codes(Settings s) {
    final codes = <int>{...kKnownButtons.keys};
    for (final k in s.remoteKeys.keys) {
      final c = int.tryParse(k.replaceAll('L', ''));
      if (c != null) codes.add(c);
    }
    return codes.toList();
  }

  void _set(Settings s, String key, String? value) {
    s.change(() {
      final m = Map<String, String>.from(s.remoteKeys);
      if (value == null) {
        m.remove(key);
      } else {
        m[key] = value;
      }
      s.remoteKeys = m;
    });
  }

  Future<void> _pick(Settings s, int code, {required bool held}) async {
    final key = held ? '${code}L' : '$code';
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => _ActionPicker(
            title: '${buttonName(code, _rawNames[code] ?? '')}: ${held ? 'when held' : 'when pressed'}',
            current: s.remoteKeys[key] ?? '',
            normalLabel: held ? 'Nothing extra' : 'What it normally does')));
    if (r == null) return;
    _set(s, key, r.isEmpty ? null : r);
  }

  void _menu(Settings s, int code) {
    final custom = !kKnownButtons.containsKey(code);
    showMenu2(context, buttonName(code, _rawNames[code] ?? ''), [
      MenuChoice('When pressed…', () => _pick(s, code, held: false)),
      MenuChoice('When held…', () => _pick(s, code, held: true)),
      if (custom || s.remoteKeys.containsKey('$code') || s.remoteKeys.containsKey('${code}L'))
        MenuChoice(custom ? 'Remove this button' : 'Back to normal', () {
          _set(s, '$code', null);
          _set(s, '${code}L', null);
        }),
      MenuChoice('Cancel', () {}),
    ]);
  }

  Future<void> _learn(Settings s) async {
    final r = await showDialog<Map<String, dynamic>>(
        context: context, barrierDismissible: false, builder: (_) => const _LearnDialog());
    if (r == null || !mounted) return;
    if (r['error'] == 'helper') {
      setState(() => _msg = 'Turn on the remote helper first (the row above).');
      return;
    }
    if (r['error'] != null) {
      setState(() => _msg = 'No button was pressed. Try again.');
      return;
    }
    final code = (r['code'] as num).toInt();
    _rawNames[code] = '${r['name'] ?? ''}';
    setState(() => _msg = 'Got the ${buttonName(code, _rawNames[code]!)}. Choose what it does.');
    if (!s.remoteKeys.containsKey('$code') && !kKnownButtons.containsKey(code)) _set(s, '$code', '');
    _menu(s, code);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final codes = _codes(s);
    return SettingsPage(
      title: 'Remote buttons',
      subtitle: 'Choose what the extra buttons on your remote open. Up, down, OK, Back, Home and volume always work as usual.',
      actions: [PillButton(label: 'Add another button', onSelect: () => _learn(s))],
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 18),
              child: SizedBox(width: 1300, child: Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70))),
            ),
          if (!_helper)
            SysRow(
                icon: Icons.settings_remote_rounded,
                title: 'Turn on the remote helper',
                subtitle: 'Lets Foyer hear the extra buttons',
                autofocus: true,
                onSelect: _turnOnHelper),
          for (var i = 0; i < codes.length; i++)
            SysRow(
                icon: codes[i] == 313
                    ? Icons.star_rounded
                    : (codes[i] == 190 || codes[i] == 191 ? Icons.smart_display_rounded : Icons.radio_button_checked_rounded),
                title: buttonName(codes[i], _rawNames[codes[i]] ?? ''),
                subtitle: 'Press: ${_describe(s.remoteKeys['${codes[i]}'], codes[i], held: false)}'
                    '   ·   Hold: ${_describe(s.remoteKeys['${codes[i]}L'], codes[i], held: true)}',
                autofocus: _helper && i == 0,
                onSelect: () => _menu(s, codes[i])),
          if (_googleHomeOff)
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 0, 0),
              child: SizedBox(
                width: 1300,
                child: Text(
                    'Google\'s home is switched off, so Foyer answers the YouTube and Netflix buttons itself.',
                    style: TextStyle(fontSize: 24, color: Colors.white54)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Picks an app (or Foyer home, or normal) for a button.
class _ActionPicker extends StatefulWidget {
  const _ActionPicker({required this.title, required this.current, required this.normalLabel});
  final String title;
  final String current;
  final String normalLabel;
  @override
  State<_ActionPicker> createState() => _ActionPickerState();
}

class _ActionPickerState extends State<_ActionPicker> {
  List<InstalledApp> _apps = [];

  @override
  void initState() {
    super.initState();
    fetchInstalledApps().then((a) {
      a.sort((x, y) => x.label.toLowerCase().compareTo(y.label.toLowerCase()));
      if (mounted) setState(() => _apps = a);
    });
  }

  Widget _row(IconData icon, String title, String value, {bool first = false}) => SysRow(
      icon: icon,
      title: title,
      value: widget.current == value ? '✓' : '',
      chevron: false,
      autofocus: first,
      onSelect: () => Navigator.of(context).pop(value));

  @override
  Widget build(BuildContext context) => SettingsPage(
        title: widget.title,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row(Icons.undo_rounded, widget.normalLabel, '', first: true),
            _row(Icons.home_rounded, 'Foyer home', 'foyer'),
            _row(Icons.bedtime_rounded, 'Sleep timer: 30 more minutes each press', 'sleep'),
            for (final a in _apps) _row(Icons.apps_rounded, a.label, a.package),
          ]),
        ),
      );
}

/// "Press the button on your remote now."
class _LearnDialog extends StatefulWidget {
  const _LearnDialog();
  @override
  State<_LearnDialog> createState() => _LearnDialogState();
}

class _LearnDialogState extends State<_LearnDialog> {
  @override
  void initState() {
    super.initState();
    () async {
      Map<String, dynamic>? r;
      try {
        r = await kChannel.invokeMapMethod<String, dynamic>('learnKey');
      } catch (_) {
        r = {'error': 'helper'};
      }
      if (mounted) Navigator.of(context).pop(r);
    }();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Glass(
            radius: 40,
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.settings_remote_rounded, size: 72),
              const SizedBox(height: 16),
              const Text('Press the button on your remote',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('Any extra button: star, an app button, input…',
                  style: TextStyle(fontSize: 24, color: Colors.white70)),
              const SizedBox(height: 28),
              PillButton(
                  label: 'Cancel',
                  autofocus: true,
                  onSelect: () {
                    kChannel.invokeMethod('cancelLearn').catchError((_) => null);
                    Navigator.of(context).pop();
                  }),
            ]),
          ),
        ),
      );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'online.dart';
import 'update.dart';
import 'weather.dart';

const String kAppPackage = 'com.leclair.leclair_home';

/// Ads, sponsored rows and tracking. Safe to disable and fully reversible.
const List<String> kAdsPkgs = [
  'com.amazon.recess',
  'com.amazon.tv.acr',
  'com.amazon.hybridadidservice',
  'com.amazon.ftvads.deeplinking',
  'com.amazon.sneakpeek',
  'com.amazon.shoptv.client',
  'com.amazon.shoptv.firetv.client',
  'com.amazon.tv.releasenotes',
  'com.amazon.storm.lightning.tutorial',
  'com.amazon.tmm.tutorial',
];

/// Amazon apps many people never open. Reversible.
const List<String> kContentPkgs = [
  'com.amazon.minitv.android.app',
  'com.amazon.imdb.tv.android.app',
  'com.amazon.bueller.photos',
  'com.amazon.bueller.music',
  'com.amazon.gamehub',
  'com.amazon.tv.livetv',
  'com.amazon.tv.support',
  'com.amazon.tv.csapp',
];

const String kAmazonSaver = 'com.amazon.ftv.screensaver';
const String kAmazonHome = 'com.amazon.tv.launcher';

// ───────────────────────── wallpaper ─────────────────────────

class WallPreset {
  const WallPreset(this.name, this.color);
  final String name;
  final Color color;
}

const List<WallPreset> kWallPresets = [
  WallPreset('Midnight', Color(0xFF3B5BDB)),
  WallPreset('Aurora', Color(0xFF12B886)),
  WallPreset('Sunset', Color(0xFFF76707)),
  WallPreset('Violet', Color(0xFF7048E8)),
  WallPreset('Rose', Color(0xFFE64980)),
  WallPreset('Ocean', Color(0xFF1C7ED6)),
  WallPreset('Graphite', Color(0xFF495057)),
];

/// Home-screen wallpaper: follows the focused app by default, or a preset / your photo.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key, required this.tint});
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    if (s.wallMode == 'photo' && s.wallValue.isNotEmpty) {
      return Stack(fit: StackFit.expand, children: [
        Image.file(File(s.wallValue),
            fit: BoxFit.cover,
            cacheWidth: s.perfMode ? 1280 : 1920,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Backdrop(tint: tint)),
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x59000000), Color(0x26000000), Color(0x99000000)],
                    stops: [0, 0.45, 1]))),
      ]);
    }
    if (s.wallMode == 'preset') {
      final i = int.tryParse(s.wallValue) ?? 0;
      return Backdrop(tint: kWallPresets[clampIdx(i, kWallPresets.length - 1)].color);
    }
    return Backdrop(tint: tint);
  }
}

// ───────────────────────── shared bits ─────────────────────────

/// Rounded choice with an optional color dot.
class Opt extends StatelessWidget {
  const Opt(
      {super.key,
      required this.label,
      required this.selected,
      required this.onSelect,
      this.autofocus = false,
      this.color});
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;
  final Color? color;

  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            color: f
                ? Colors.white
                : (selected ? Colors.white.withAlpha(56) : Colors.white.withAlpha(22)),
            border: Border.all(
                color: Colors.white.withAlpha(f ? 255 : (selected ? 170 : 70)),
                width: selected ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (color != null)
              Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.check_rounded, size: 28, color: f ? Colors.black : Colors.white),
              ),
            Text(label,
                style: TextStyle(fontSize: 26, color: f ? Colors.black : Colors.white)),
          ]),
        ),
      );
}

InputDecoration _fieldDeco() => InputDecoration(
      counterText: '',
      filled: true,
      fillColor: Colors.white.withAlpha(24),
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: Colors.white.withAlpha(80))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Colors.white, width: 3)),
    );

/// Standard page chrome for the settings sub-screens.
class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key,
      required this.title,
      this.subtitle,
      required this.child,
      this.actions = const []});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          const Positioned.fill(child: RepaintBoundary(child: Backdrop(tint: kDefaultTint))),
          Padding(
            padding: const EdgeInsets.fromLTRB(140, 80, 140, 60),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 62, fontWeight: FontWeight.w700, letterSpacing: -1)),
              if (subtitle != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                    width: 1300,
                    child: Text(subtitle!,
                        style: const TextStyle(fontSize: 26, color: Colors.white70))),
              ],
              const SizedBox(height: 28),
              Expanded(child: child),
              const SizedBox(height: 20),
              Row(children: [
                PillButton(label: 'Back', onSelect: () => Navigator.of(context).pop()),
                const Spacer(),
                ...actions,
              ]),
            ]),
          ),
        ]),
      );
}

/// Asks for a line of text in a small dialog, so the on-screen keyboard never
/// traps the remote on a normal screen. Returns null if cancelled.
Future<String?> askText(BuildContext context, String title, String initial,
    {String hint = '', int maxLength = 40}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Glass(
          radius: 40,
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            SizedBox(
              width: 820,
              child: TextField(
                controller: c,
                autofocus: true,
                maxLength: maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600),
                decoration: _fieldDeco().copyWith(hintText: hint),
              ),
            ),
            const SizedBox(height: 24),
            Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(label: 'Cancel', onSelect: () => Navigator.of(ctx).pop()),
              const SizedBox(width: 20),
              PillButton(
                  label: 'Done',
                  primary: true,
                  onSelect: () => Navigator.of(ctx).pop(c.text.trim())),
            ]),
          ]),
        ),
      ),
    ),
  );
}

/// Friendly text for on-device ADB failures.
String adbFriendly(Object? error) {
  final e = '$error';
  if (e.contains('refused') || e.contains('ECONNREFUSED')) {
    return 'Could not reach on-device ADB. Turn on ADB debugging in Settings > My Fire TV > Developer options. Some newer Fire OS updates block this for apps; if it still fails, run the command from a computer instead.';
  }
  if (e.contains('imed out') || e.contains('Timeout')) {
    return 'No answer. If a prompt appeared on the TV, choose Always allow, then try again.';
  }
  if (e.contains('EOF') || e.contains('reset')) {
    return 'The stick closed the connection. Check the TV for an "Allow" prompt and choose Always allow, make sure ADB debugging is on, then try again. If it keeps happening, run the command from your computer.';
  }
  return 'ADB problem: $e';
}

/// Runs shell commands through on-device ADB. Returns null on success, or a message.
Future<String?> adbQuick(List<String> cmds, {bool eofOk = false}) async {
  try {
    final res = await kChannel.invokeMapMethod<String, dynamic>('adbRun', {'commands': cmds});
    if (res?['ok'] == true) return null;
    final e = '${res?['error']}';
    if (eofOk && (e.contains('EOF') || e.contains('reset') || e.contains('closed'))) return null;
    return adbFriendly(e);
  } catch (e) {
    return adbFriendly(e);
  }
}

Future<void> showInfo(BuildContext c, String title, String message) =>
    showMenu2(c, title, [MenuChoice(message, null), MenuChoice('OK', () {})]);

Future<void> restartStick(BuildContext context) => showMenu2(context, 'Restart your Fire TV?', [
      MenuChoice('Restart now', () async {
        final err = await adbQuick(['reboot'], eofOk: true);
        if (err != null && context.mounted) showInfo(context, 'Could not restart', err);
      }),
      MenuChoice('Cancel', () {}),
    ]);

Future<void> closeApp(BuildContext context, String pkg, String label) async {
  bool ok = false;
  try {
    ok = (await kChannel.invokeMethod<bool>('killApp', {'package': pkg})) ?? false;
  } catch (_) {}
  if (context.mounted) {
    showInfo(context, ok ? 'Closed' : 'Could not close', ok ? '$label was closed in the background.' : '$label could not be closed.');
  }
}

Future<void> clearAppData(BuildContext context, String pkg, String label) =>
    showMenu2(context, 'Clear $label data?', [
      MenuChoice('This signs you out and resets the app.', null),
      MenuChoice('Clear data', () async {
        final err = await adbQuick(['pm clear $pkg']);
        if (context.mounted) showInfo(context, err == null ? 'Done' : 'Could not clear', err ?? '$label was reset.');
      }),
      MenuChoice('Cancel', () {}),
    ]);

void _push(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

// ───────────────────────── settings hub ─────────────────────────

class SettingsHub extends StatelessWidget {
  const SettingsHub({super.key, required this.onClose, required this.onEdit});
  final VoidCallback onClose;
  final void Function(int step) onEdit; // 0 name/clock, 1 glass, 2 apps, 3 Plex, 4 Home button

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final rows = <_HubItem>[
      _HubItem(Icons.home_rounded, 'Name and clock',
          '${s.name}, ${s.clock24 ? '24-hour' : '12-hour'} clock', () => onEdit(0)),
      _HubItem(Icons.blur_on_rounded, 'Glass style',
          s.liquid ? 'Liquid glass' : 'Simple glass', () => onEdit(1)),
      _HubItem(Icons.apps_rounded, 'Pinned apps',
          '${s.pinned.length} on your home screen', () => onEdit(2)),
      _HubItem(Icons.video_library_rounded, 'Plex',
          s.plexToken.isEmpty ? 'Not linked' : 'Linked to ${s.plexName}', () => onEdit(3)),
      _HubItem(Icons.keyboard_return_rounded, 'Home button',
          'Make the remote\'s Home button open Foyer', () => onEdit(4)),
      _HubItem(
          Icons.wb_sunny_rounded,
          'Weather',
          s.weatherCity.isEmpty
              ? 'Off'
              : '${s.weatherCity}, ${s.weatherF ? 'Fahrenheit' : 'Celsius'}',
          () => _push(context, const WeatherScreen())),
      _HubItem(
          Icons.wallpaper_rounded,
          'Wallpaper',
          s.wallMode == 'photo'
              ? 'Your photo'
              : (s.wallMode == 'preset'
                  ? kWallPresets[clampIdx(int.tryParse(s.wallValue) ?? 0, kWallPresets.length - 1)].name
                  : 'Follows the selected app'),
          () => _push(context, const WallpaperScreen())),
      _HubItem(Icons.bedtime_rounded, 'Screensaver',
          s.ssMinutes == 0 ? 'Off' : 'Starts after ${s.ssMinutes} min idle',
          () => _push(context, const ScreensaverScreen())),
      _HubItem(
          Icons.speed_rounded,
          'Performance mode',
          s.perfMode ? 'On: no blur, lighter animations' : 'Off',
          () => s.change(() => s.perfMode = !s.perfMode)),
      _HubItem(
          Icons.power_settings_new_rounded,
          'Start on boot',
          s.autoStart ? 'On: opens Foyer when the stick starts' : 'Off',
          () => s.change(() => s.autoStart = !s.autoStart)),
      _HubItem(
          Icons.system_update_rounded,
          'Updates',
          kUpdate.value != null
              ? 'Version ${kUpdate.value!.version} is available'
              : (s.updateUrl.isEmpty ? 'Set up an update link' : 'Check for a newer version'),
          () => _push(context, const UpdateScreen())),
      _HubItem(Icons.backup_rounded, 'Backup and restore',
          'Save your settings to a file, or load them back',
          () => _push(context, const BackupScreen())),
      _HubItem(Icons.build_rounded, 'Tune-up',
          'Check your stick, remove ads and bloat, free memory, fix the Home button',
          () => _push(context, const TuneUpScreen())),
      _HubItem(Icons.restart_alt_rounded, 'Restart Fire TV',
          'Reboots the stick (needs ADB debugging on)', () => restartStick(context)),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          const Positioned.fill(child: RepaintBoundary(child: Backdrop(tint: kDefaultTint))),
          Padding(
            padding: const EdgeInsets.fromLTRB(140, 80, 140, 60),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Settings',
                  style: TextStyle(fontSize: 62, fontWeight: FontWeight.w700, letterSpacing: -1)),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (var i = 0; i < rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _HubRow(item: rows[i], autofocus: i == 0),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                PillButton(label: 'Close', onSelect: onClose),
                const Spacer(),
                const Text('Foyer 1.0',
                    style: TextStyle(fontSize: 22, color: Colors.white38)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HubItem {
  _HubItem(this.icon, this.title, this.subtitle, this.onSelect);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
}

class _HubRow extends StatelessWidget {
  const _HubRow({required this.item, this.autofocus = false});
  final _HubItem item;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        onSelect: item.onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 1300,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            color: f ? Colors.white : Colors.white.withAlpha(24),
            border: Border.all(color: Colors.white.withAlpha(f ? 255 : 60), width: 1.5),
          ),
          child: Row(children: [
            Icon(item.icon, size: 44, color: f ? Colors.black : Colors.white),
            const SizedBox(width: 28),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: f ? Colors.black : Colors.white)),
                const SizedBox(height: 4),
                Text(item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 24, color: f ? Colors.black54 : Colors.white70)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 44, color: f ? Colors.black : Colors.white54),
          ]),
        ),
      );
}

// ───────────────────────── weather ─────────────────────────

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final TextEditingController _q = TextEditingController();
  List<GeoPlace> _results = const [];
  String _msg = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _msg = 'Searching…');
    try {
      final r = await WeatherApi.search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _msg = r.isEmpty ? 'No matches. Try a bigger nearby city.' : '';
      });
    } catch (_) {
      if (mounted) setState(() => _msg = 'Could not search. Check the internet connection.');
    }
  }

  void _pick(GeoPlace p) {
    final s = SettingsScope.read(context);
    s.change(() {
      s.weatherCity = p.name;
      s.weatherLat = p.lat;
      s.weatherLon = p.lon;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'Weather',
      subtitle: 'Shows next to your welcome message. Uses Open-Meteo, no account needed.',
      actions: [
        if (s.weatherCity.isNotEmpty)
          PillButton(
              label: 'Turn off',
              onSelect: () {
                s.change(() {
                  s.weatherCity = '';
                  s.weatherLat = null;
                  s.weatherLon = null;
                });
                Navigator.of(context).pop();
              }),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s.weatherCity.isNotEmpty) ...[
            Text('Current: ${s.weatherCity}',
                style: const TextStyle(fontSize: 28, color: Colors.white70)),
            const SizedBox(height: 18),
          ],
          Row(children: [
            PillButton(
                label: _q.text.isEmpty ? 'Search for your city' : 'Search again',
                primary: true,
                autofocus: true,
                onSelect: () async {
                  final v = await askText(context, 'Search for your city', _q.text,
                      hint: 'e.g. Toronto');
                  if (v != null && v.isNotEmpty) {
                    _q.text = v;
                    _search();
                  }
                }),
            const SizedBox(width: 28),
            Opt(
                label: '°C',
                selected: !s.weatherF,
                onSelect: () => s.change(() => s.weatherF = false)),
            const SizedBox(width: 16),
            Opt(
                label: '°F',
                selected: s.weatherF,
                onSelect: () => s.change(() => s.weatherF = true)),
          ]),
          const SizedBox(height: 22),
          if (_msg.isNotEmpty)
            Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70)),
          for (final p in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FocusButton(
                scrollIntoView: true,
                onSelect: () => _pick(p),
                builder: (_, f) => AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 900,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: f ? Colors.white : Colors.white.withAlpha(24),
                    border: Border.all(color: Colors.white.withAlpha(f ? 255 : 60)),
                  ),
                  child: Text(p.label,
                      style: TextStyle(fontSize: 30, color: f ? Colors.black : Colors.white)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── wallpaper ─────────────────────────

class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key});
  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> {
  List<String> _files = const [];
  String _dir = '';
  bool _loading = true;
  bool _perm = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _perm = (await kChannel.invokeMethod<bool>('requestStorage')) ?? false;
    } catch (_) {
      _perm = false;
    }
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('listWallpapers');
      _dir = (m?['dir'] as String?) ?? '';
      _files = ((m?['files'] as List?) ?? const []).cast<String>();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final glow = s.wallMode == 'glow';
    return SettingsPage(
      title: 'Wallpaper',
      subtitle: 'Pick a color style or one of your photos.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(
                autofocus: true,
                label: 'Follow the selected app',
                selected: glow,
                onSelect: () => s.change(() => s.wallMode = 'glow')),
            for (var i = 0; i < kWallPresets.length; i++)
              Opt(
                  label: kWallPresets[i].name,
                  color: kWallPresets[i].color,
                  selected: s.wallMode == 'preset' && s.wallValue == '$i',
                  onSelect: () => s.change(() {
                        s.wallMode = 'preset';
                        s.wallValue = '$i';
                      })),
          ]),
          const SizedBox(height: 36),
          const Text('Your photos', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              _perm
                  ? 'Photos from Pictures, Download and DCIM show up here. You can also copy photos to: $_dir'
                  : 'Storage access was declined, so only photos in this folder show up: $_dir',
              style: const TextStyle(fontSize: 22, color: Colors.white60)),
          const SizedBox(height: 20),
          if (_loading)
            const Text('Looking for photos…', style: TextStyle(fontSize: 26, color: Colors.white70))
          else if (_files.isEmpty)
            const Text('No photos found yet.', style: TextStyle(fontSize: 26, color: Colors.white70))
          else
            Wrap(spacing: 20, runSpacing: 20, children: [
              for (final f in _files)
                FocusButton(
                  scrollIntoView: true,
                  onSelect: () => s.change(() {
                    s.wallMode = 'photo';
                    s.wallValue = f;
                  }),
                  builder: (_, focused) {
                    final sel = s.wallMode == 'photo' && s.wallValue == f;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 256,
                      height: 144,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: focused ? Colors.white : (sel ? Colors.white70 : Colors.white24),
                            width: focused ? 3.5 : 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(fit: StackFit.expand, children: [
                          Image.file(File(f),
                              fit: BoxFit.cover,
                              cacheWidth: 320,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFF1A1D2B))),
                          if (sel)
                            const Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(Icons.check_circle, size: 36, color: Colors.white)),
                        ]),
                      ),
                    );
                  },
                ),
            ]),
        ]),
      ),
    );
  }
}

// ───────────────────────── screensaver ─────────────────────────

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

class _Shot {
  _Shot(this.src, this.net, [this.caption = '']);
  final String src;
  final bool net;
  final String caption;
}

class ScreensaverView extends StatefulWidget {
  const ScreensaverView({super.key, this.weather});
  final WeatherNow? weather;
  @override
  State<ScreensaverView> createState() => _ScreensaverViewState();
}

class _ScreensaverViewState extends State<ScreensaverView> with SingleTickerProviderStateMixin {
  static const _spots = [
    Alignment(-0.7, -0.6),
    Alignment(0.7, -0.5),
    Alignment(0.7, 0.6),
    Alignment(-0.7, 0.55),
  ];
  late final AnimationController _zoom =
      AnimationController(vsync: this, duration: const Duration(seconds: 40));
  Timer? _t;
  DateTime _now = DateTime.now();
  int _ticks = 0;
  int _spot = 0;
  int _photoIdx = 0;
  double _hue = 220;
  List<_Shot> _shots = const [];

  @override
  void initState() {
    super.initState();
    final cfg = SettingsScope.read(context);
    if (!cfg.perfMode) _zoom.repeat(reverse: true);
    if (cfg.ssSource != 'colors') _loadShots(cfg.ssSource);
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      _ticks++;
      setState(() {
        _now = DateTime.now();
        _hue = (_hue + 25) % 360;
        if (_ticks % 3 == 0) _spot = (_spot + 1) % _spots.length; // drift to avoid burn-in
        if (_ticks % 2 == 0 && _shots.isNotEmpty) _photoIdx = (_photoIdx + 1) % _shots.length;
      });
    });
  }

  Future<void> _loadShots(String source) async {
    try {
      List<_Shot> shots;
      if (source == 'online') {
        final r = await fetchBingShots();
        shots = [for (final o in r) _Shot(o.url, true, o.caption)];
      } else {
        final m = await kChannel.invokeMapMethod<String, dynamic>('listWallpapers');
        final files = ((m?['files'] as List?) ?? const []).cast<String>().toList()
          ..shuffle(Random());
        shots = [for (final f in files.take(20)) _Shot(f, false)];
      }
      if (mounted) setState(() => _shots = shots);
    } catch (_) {}
  }

  @override
  void dispose() {
    _t?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  Widget _image(_Shot shot) {
    Widget err(BuildContext _, Object __, StackTrace? ___) => const ColoredBox(color: Colors.black);
    return shot.net
        ? Image.network(shot.src,
            fit: BoxFit.cover, cacheWidth: 1920, gaplessPlayback: true, errorBuilder: err)
        : Image.file(File(shot.src),
            fit: BoxFit.cover, cacheWidth: 1920, gaplessPlayback: true, errorBuilder: err);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final h24 = s.clock24;
    final m = _now.minute.toString().padLeft(2, '0');
    final time = h24
        ? '${_now.hour.toString().padLeft(2, '0')}:$m'
        : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m';
    final ampm = h24 ? '' : (_now.hour < 12 ? ' AM' : ' PM');
    final date = '${_weekdays[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}';
    final w = widget.weather;
    final shot = _shots.isNotEmpty ? _shots[_photoIdx % _shots.length] : null;

    final bg = shot != null
        ? AnimatedSwitcher(
            duration: Duration(milliseconds: s.perfMode ? 300 : 1500),
            child: SizedBox.expand(
              key: ValueKey(shot.src),
              child: AnimatedBuilder(
                animation: _zoom,
                builder: (_, child) =>
                    Transform.scale(scale: 1 + 0.08 * _zoom.value, child: child),
                child: _image(shot),
              ),
            ),
          )
        : Backdrop(tint: HSVColor.fromAHSV(1, _hue, 0.65, 0.85).toColor());

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (_, v, child) => Opacity(opacity: v, child: child),
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        bg,
        if (shot != null) const ColoredBox(color: Color(0x66000000)),
        if (shot != null && shot.caption.isNotEmpty)
          Positioned(
              left: 72,
              right: 72,
              bottom: 44,
              child: Text(shot.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, color: Colors.white70))),
        AnimatedAlign(
          alignment: _spots[_spot],
          duration: const Duration(seconds: 3),
          curve: Curves.easeInOut,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(time,
                  style: const TextStyle(
                      fontSize: 170,
                      fontWeight: FontWeight.w200,
                      letterSpacing: -4,
                      height: 1,
                      shadows: [Shadow(color: Color(0x80000000), blurRadius: 30)])),
              if (ampm.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 16),
                  child: Text(ampm,
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300)),
                ),
            ]),
            const SizedBox(height: 8),
            Text(date,
                style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w400,
                    shadows: [Shadow(color: Color(0x80000000), blurRadius: 20)])),
            if (w != null) ...[
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(w.icon, size: 40),
                const SizedBox(width: 14),
                Text('${w.temp.round()}°  ${w.label}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w400)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class ScreensaverScreen extends StatefulWidget {
  const ScreensaverScreen({super.key});
  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen> {
  Future<void> _preview() async {
    final s = SettingsScope.read(context);
    WeatherNow? w;
    if (s.weatherLat != null && s.weatherLon != null) {
      try {
        w = await WeatherApi.now(s.weatherLat!, s.weatherLon!, s.weatherF);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (ctx, __, ___) => Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent) {
              Navigator.of(ctx).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          },
          child: ScreensaverView(weather: w),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'Screensaver',
      subtitle:
          'Shown on the home screen when nothing has been pressed for a while. Fire OS has its own screensaver and may start it first: set this shorter than Amazon\'s, or turn Amazon\'s off in Tune-up.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Start after', style: TextStyle(fontSize: 30, color: Colors.white70)),
          const SizedBox(height: 14),
          Wrap(spacing: 16, runSpacing: 16, children: [
            for (final m in const [0, 1, 2, 5, 10])
              Opt(
                  autofocus: m == s.ssMinutes || (m == 5 && ![0, 1, 2, 5, 10].contains(s.ssMinutes)),
                  label: m == 0 ? 'Off' : '$m min',
                  selected: s.ssMinutes == m,
                  onSelect: () => s.change(() => s.ssMinutes = m)),
          ]),
          const SizedBox(height: 32),
          const Text('Background', style: TextStyle(fontSize: 30, color: Colors.white70)),
          const SizedBox(height: 14),
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(
                label: 'Moving colors',
                selected: s.ssSource == 'colors',
                onSelect: () => s.change(() => s.ssSource = 'colors')),
            Opt(
                label: 'My photos',
                selected: s.ssSource == 'mine',
                onSelect: () => s.change(() => s.ssSource = 'mine')),
            Opt(
                label: 'Online photos',
                selected: s.ssSource == 'online',
                onSelect: () => s.change(() => s.ssSource = 'online')),
          ]),
          if (s.ssSource == 'online')
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('Uses the internet: Bing\'s daily photos. Falls back to colors if offline.',
                  style: TextStyle(fontSize: 22, color: Colors.white60)),
            ),
          const SizedBox(height: 36),
          PillButton(label: 'Preview now', primary: true, onSelect: _preview),
        ]),
      ),
    );
  }
}

// ───────────────────────── backup ─────────────────────────

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String _msg = '';

  Future<void> _backup() async {
    final s = SettingsScope.read(context);
    try {
      await kChannel.invokeMethod<bool>('requestStorage');
      final paths = await kChannel.invokeListMethod<String>(
          'exportBackup', jsonEncode(s.toJson(secrets: false)));
      setState(() => _msg = (paths == null || paths.isEmpty)
          ? 'Could not write the backup file.'
          : 'Saved to:\n${paths.join('\n')}');
    } catch (_) {
      setState(() => _msg = 'Could not write the backup file.');
    }
  }

  Future<void> _restore() async {
    final s = SettingsScope.read(context);
    try {
      await kChannel.invokeMethod<bool>('requestStorage');
      final m = await kChannel.invokeMapMethod<String, dynamic>('importBackup');
      if (m == null) {
        setState(() => _msg = 'No backup file found. Back up first, or copy Foyer-backup.json into Download.');
        return;
      }
      final data = jsonDecode(m['json'] as String);
      if (data is! Map) throw const FormatException('bad file');
      if (!mounted) return;
      await showMenu2(context, 'Replace your settings?', [
        MenuChoice('Restore from backup', () {
          s.restore(Map<String, dynamic>.from(data));
          setState(() => _msg = 'Restored from ${m['path']}. Plex needs to be linked again.');
        }),
        MenuChoice('Cancel', () {}),
      ]);
    } catch (_) {
      setState(() => _msg = 'That backup file could not be read.');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
        title: 'Backup and restore',
        subtitle:
            'Saves your name, apps, look, weather and screensaver. Your Plex sign-in is not included for safety, so link it again after restoring.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PillButton(label: 'Back up now', primary: true, autofocus: true, onSelect: _backup),
          const SizedBox(height: 20),
          PillButton(label: 'Restore latest backup', onSelect: _restore),
          const SizedBox(height: 32),
          if (_msg.isNotEmpty)
            Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70)),
        ]),
      );
}

// ───────────────────────── tune-up ─────────────────────────

class TuneUpScreen extends StatefulWidget {
  const TuneUpScreen({super.key});
  @override
  State<TuneUpScreen> createState() => _TuneUpScreenState();
}

class _TuneUpScreenState extends State<TuneUpScreen> {
  Map<String, dynamic> _d = const {};
  Map<String, int> _state = const {};
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    kChannel.setMethodCallHandler((call) async {
      if (call.method == 'adbLog') _addLog(call.arguments as String);
      return null;
    });
    _scan();
  }

  @override
  void dispose() {
    kChannel.setMethodCallHandler(null);
    _logScroll.dispose();
    super.dispose();
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  Future<void> _scan() async {
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('diagnostics',
          {'packages': [...kAdsPkgs, ...kContentPkgs, kAmazonSaver, kAmazonHome]});
      if (!mounted || m == null) return;
      setState(() {
        _d = m;
        _state = (m['states'] as Map).map((k, v) => MapEntry(k as String, v as int));
      });
    } catch (_) {}
  }

  int _active(List<String> pkgs) => pkgs.where((p) => _state[p] == 1).length;
  int _present(List<String> pkgs) => pkgs.where((p) => (_state[p] ?? 0) != 0).length;

  String _friendly(Object? error) => adbFriendly(error);

  Future<void> _free() async {
    final before = (_d['ramFreeMb'] as int?) ?? 0;
    await _run('Freeing memory', ['am kill-all', 'pm trim-caches 999G']);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _scan();
    final after = (_d['ramFreeMb'] as int?) ?? 0;
    _addLog('Free memory: $before MB -> $after MB');
  }

  Future<void> _report() async {
    final cfg = SettingsScope.read(context);
    final settings = cfg.toJson(secrets: false)
      ..remove('weatherCity')
      ..remove('weatherLat')
      ..remove('weatherLon')
      ..remove('name')
      ..remove('updateUrl');
    final b = StringBuffer()
      ..writeln('Foyer debug report')
      ..writeln('Time: ${DateTime.now()}')
      ..writeln('App: ${_d['version'] ?? '?'}')
      ..writeln('Device: ${_d['model']} (${_d['device']})')
      ..writeln('Android: ${_d['android']}')
      ..writeln('RAM: ${_d['ramFreeMb']} MB free of ${_d['ramTotalMb']} MB')
      ..writeln('Storage free: ${_d['storageFreeMb']} MB')
      ..writeln('ADB debugging: ${_d['adbEnabled']}   on-device ADB reachable: ${_d['adbPort']}')
      ..writeln('Home key service: ${_d['homeKey']}')
      ..writeln('Settings: ${jsonEncode(settings)}')
      ..writeln('Packages (1 = on, 2 = disabled, 0 = not installed):');
    _state.forEach((k, v) => b.writeln('  $k = $v'));
    b
      ..writeln('Log:')
      ..writeln(_log.join('\n'));
    try {
      final paths = await kChannel.invokeListMethod<String>('saveReport', b.toString());
      _addLog(paths == null || paths.isEmpty
          ? 'Could not save the report.'
          : 'Report saved:\n${paths.join('\n')}');
    } catch (_) {
      _addLog('Could not save the report.');
    }
  }

  Future<void> _run(String title, List<String> cmds, {Future<void> Function()? after}) async {
    if (_busy) return;
    if (cmds.isEmpty) {
      _addLog('$title: nothing to do.');
      return;
    }
    setState(() => _busy = true);
    _addLog('▶ $title');
    try {
      final res = await kChannel.invokeMapMethod<String, dynamic>('adbRun', {'commands': cmds});
      if (res?['ok'] == true) {
        _addLog('Done.');
        if (after != null) await after();
      } else {
        _addLog(_friendly(res?['error']));
        _addLog('Or run this from your computer:');
        for (final c in cmds) {
          _addLog('adb shell $c');
        }
      }
    } catch (e) {
      _addLog(_friendly(e));
    }
    if (mounted) setState(() => _busy = false);
    await _scan();
  }

  List<String> _disableCmds(List<String> pkgs) =>
      [for (final p in pkgs) if (_state[p] == 1) 'pm disable-user --user 0 $p'];

  List<String> _enableCmds(List<String> pkgs) =>
      [for (final p in pkgs) if (_state[p] == 2) 'pm enable $p'];

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 290, child: Text(k, style: const TextStyle(fontSize: 24, color: Colors.white54))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 24))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final saverOff = _state[kAmazonSaver] == 2;
    final ramT = (_d['ramTotalMb'] as int?) ?? 0;
    final ramF = (_d['ramFreeMb'] as int?) ?? 0;
    final stor = (_d['storageFreeMb'] as int?) ?? 0;
    String yn(Object? b, String yes, String no) => b == true ? yes : no;
    return SettingsPage(
      title: 'Tune-up',
      subtitle:
          'Removes Amazon ads and extras without a computer. Needs ADB debugging on (Settings > My Fire TV > Developer options). The first time, the TV asks you to allow it: choose Always allow. Everything here can be undone.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _kv('Device', '${_d['model'] ?? '…'} (${_d['device'] ?? ''})'),
                  _kv('Android', '${_d['android'] ?? '…'}'),
                  _kv('Memory', ramT == 0 ? '…' : '$ramF MB free of $ramT MB'),
                  _kv('Storage free', stor == 0 ? '…' : '${(stor / 1024).toStringAsFixed(1)} GB'),
                  _kv('ADB debugging', yn(_d['adbEnabled'], 'On', 'Off')),
                  _kv('On-device ADB', yn(_d['adbPort'], 'Reachable', 'Not reachable')),
                  _kv('Home button', yn(_d['homeKey'], 'On', 'Off')),
                  _kv('Ads and tracking', '${_active(kAdsPkgs)} still active of ${_present(kAdsPkgs)}'),
                  _kv('Amazon extras', '${_active(kContentPkgs)} still active of ${_present(kContentPkgs)}'),
                  _kv('Amazon home', _state[kAmazonHome] == 2 ? 'Disabled (Foyer is home)' : 'Active'),
                  _kv('Amazon screensaver', saverOff ? 'Off' : (_state[kAmazonSaver] == 1 ? 'On' : 'Not found')),
                ]),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: Colors.black38, borderRadius: BorderRadius.circular(24)),
                child: SingleChildScrollView(
                  controller: _logScroll,
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                        _log.isEmpty ? 'Activity shows here.' : _log.join('\n'),
                        style: const TextStyle(
                            fontSize: 20, fontFamily: 'monospace', color: Colors.white70)),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        Wrap(spacing: 18, runSpacing: 18, children: [
          PillButton(label: 'Scan again', autofocus: true, onSelect: _scan),
          PillButton(
              label: 'Remove ads',
              primary: true,
              onSelect: () => _run('Disabling ads and tracking', _disableCmds(kAdsPkgs))),
          PillButton(
              label: 'Remove extras',
              primary: true,
              onSelect: () => _run('Disabling Amazon extras', _disableCmds(kContentPkgs))),
          PillButton(label: 'Free up memory', primary: true, onSelect: _free),
          PillButton(label: 'Save debug report', onSelect: _report),
          PillButton(label: 'Restart stick', onSelect: () => restartStick(context)),
          PillButton(
              label: 'Undo all',
              onSelect: () => _run('Restoring everything',
                  _enableCmds([...kAdsPkgs, ...kContentPkgs, kAmazonSaver]))),
          PillButton(
              label: 'Fix Home button',
              onSelect: () => _run(
                    'Granting permission',
                    ['pm grant $kAppPackage android.permission.WRITE_SECURE_SETTINGS'],
                    after: () async {
                      await kChannel.invokeMethod('setHomeKey', {'enabled': true});
                      _addLog('Home button turned on.');
                    },
                  )),
          PillButton(
              label: _state[kAmazonHome] == 2 ? 'Restore Amazon home' : 'Use as my Home screen',
              primary: true,
              onSelect: () {
                if (_state[kAmazonHome] == 2) {
                  _run('Restoring Amazon home', ['pm enable $kAmazonHome']);
                } else {
                  showMenu2(context, 'Replace Amazon home?', [
                    MenuChoice('Yes, make Foyer my home screen',
                        () => _run('Switching home screen', ['pm disable-user --user 0 $kAmazonHome'])),
                    MenuChoice('You can undo this with Restore Amazon home.', null),
                    MenuChoice('Cancel', () {}),
                  ]);
                }
              }),
          PillButton(
              label: saverOff ? 'Amazon screensaver on' : 'Amazon screensaver off',
              onSelect: () => saverOff
                  ? _run('Turning Amazon screensaver on', ['pm enable $kAmazonSaver'])
                  : _run('Turning Amazon screensaver off',
                      ['pm disable-user --user 0 $kAmazonSaver'])),
        ]),
      ]),
    );
  }
}


// ───────────────────────── updates ─────────────────────────

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  String _ver = '…';
  int _build = 0;
  String _msg = '';
  double? _prog;
  bool _busy = false;
  UpdateInfo? _found = kUpdate.value;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final m = await kChannel.invokeMapMethod<String, dynamic>('appVersion');
        _build = (m?['code'] as num?)?.toInt() ?? 0;
        if (mounted) setState(() => _ver = '${m?['name']} ($_build)');
      } catch (_) {}
    }();
  }

  Future<void> _check() async {
    final url = SettingsScope.read(context).updateUrl;
    if (url.isEmpty) {
      setState(() => _msg = 'Set an update link first.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Checking…';
    });
    try {
      final r = await UpdateApi.check(url, _build);
      kUpdate.value = r;
      if (!mounted) return;
      setState(() {
        _found = r;
        _msg = r == null
            ? 'You are up to date.'
            : 'Version ${r.version} is available.${r.notes.isEmpty ? '' : '\n${r.notes}'}';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Could not check: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _install() async {
    final u = _found;
    if (u == null || _busy) return;
    setState(() {
      _busy = true;
      _prog = 0;
      _msg = 'Downloading…';
    });
    try {
      final path = (await kChannel.invokeMethod<String>('updatePath')) ?? '';
      await UpdateApi.download(u.url, path, (p) {
        if (mounted) setState(() => _prog = p);
      });
      final r = await kChannel.invokeMethod<String>('installApk', {'path': path});
      if (!mounted) return;
      setState(() => _msg = r == 'needsPermission'
          ? 'Allow Foyer to install apps on the screen that just opened, then press Install again.'
          : (r == 'started' ? 'Confirm the install on the next screen.' : 'The download could not be installed.'));
    } catch (e) {
      if (mounted) setState(() => _msg = 'Update failed: $e');
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _prog = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 260, child: Text(k, style: const TextStyle(fontSize: 26, color: Colors.white54))),
            Expanded(child: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26))),
          ]),
        );
    return SettingsPage(
      title: 'Updates',
      subtitle:
          'Checks a link you set for a newer Foyer. The link points to a small update.json file next to the APK (see the README).',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          kv('Installed', _ver),
          kv('Update link', s.updateUrl.isEmpty ? 'Not set' : s.updateUrl),
          const SizedBox(height: 18),
          Wrap(spacing: 18, runSpacing: 18, children: [
            PillButton(
                label: 'Set update link',
                autofocus: true,
                onSelect: () async {
                  final v = await askText(context, 'Update link', s.updateUrl,
                      hint: 'https://…/update.json', maxLength: 300);
                  if (v != null) {
                    s.change(() => s.updateUrl = v);
                    kUpdate.value = null;
                    setState(() => _found = null);
                  }
                }),
            PillButton(label: 'Check now', primary: true, onSelect: _check),
            if (_found != null)
              PillButton(label: 'Download and install ${_found!.version}', primary: true, onSelect: _install),
          ]),
          const SizedBox(height: 26),
          if (_prog != null)
            SizedBox(
                width: 700,
                child: LinearProgressIndicator(value: _prog, minHeight: 10, borderRadius: BorderRadius.circular(6))),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70)),
            ),
        ]),
      ),
    );
  }
}

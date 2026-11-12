import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, NetworkInterface, InternetAddressType;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'server.dart';
import 'sports.dart';
import 'system.dart';
import 'sounds.dart';
import 'seasons.dart';
import 'scenes.dart';
import 'setup.dart';
import 'remote.dart';
import 'idle.dart';
import 'keep.dart';
import 'weatherfx.dart';
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
    // painted scenes with the big clock behind the scenery
    if (s.wallMode == 'scenes') return SceneView(which: s.wallValue);
    // holidays tint the wallpaper (your own photo stays as it is)
    final look = kSeasonLooks[activeSeason(s)];
    if (look != null && s.wallMode != 'photo') return Backdrop(tint: look.tint);
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
        body: Stack(fit: StackFit.expand, children: [
          const Positioned.fill(child: SettingsBackdrop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(140, 72, 140, 56),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 52, fontWeight: FontWeight.w700, letterSpacing: -1)),
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
const MethodChannel kPhoneChannel = MethodChannel('leclair/phone');

Future<String?> askText(BuildContext context, String title, String initial,
    {String hint = '', int maxLength = 40}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _AskTextDialog(title: title, initial: initial, hint: hint, maxLength: maxLength),
  );
}

class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog(
      {required this.title, required this.initial, required this.hint, required this.maxLength});
  final String title;
  final String initial;
  final String hint;
  final int maxLength;
  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _url;
  bool _got = false;

  @override
  void initState() {
    super.initState();
    kPhoneChannel.setMethodCallHandler((call) async {
      if (call.method == 'text' && mounted) {
        var t = (call.arguments as String? ?? '').trim();
        if (t.length > widget.maxLength) t = t.substring(0, widget.maxLength);
        setState(() {
          _c.text = t;
          _c.selection = TextSelection.collapsed(offset: t.length);
          _got = true;
        });
      }
      return null;
    });
    () async {
      try {
        final u = await kPhoneChannel
            .invokeMethod<String>('start', {'title': widget.title, 'hint': widget.hint});
        if (mounted) setState(() => _url = u);
      } catch (_) {}
    }();
  }

  @override
  void dispose() {
    kPhoneChannel.setMethodCallHandler(null);
    kPhoneChannel.invokeMethod<bool>('stop').catchError((_) => null);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final showQr = _url != null && !_got;
    // Sits at the top of the screen, with the QR code beside the field, so the TV's
    // keyboard (which rises from the bottom) never covers either.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 48, left: 40, right: 40),
      child: Glass(
        radius: 40,
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            SizedBox(
              width: 760,
              child: TextField(
                controller: _c,
                autofocus: true,
                maxLength: widget.maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600),
                decoration: _fieldDeco().copyWith(hintText: widget.hint),
              ),
            ),
            if (!showQr) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: 760,
                child: Text(
                  _got ? 'Got it from your phone. Choose Done.' : 'Typing is easier on your phone, when the TV is on Wi-Fi.',
                  style: TextStyle(fontSize: 22, color: _got ? const Color(0xFF8CE99A) : Colors.white60),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(label: 'Cancel', onSelect: () => Navigator.of(ctx).pop()),
              const SizedBox(width: 20),
              PillButton(
                  label: 'Done',
                  primary: true,
                  autofocus: _got,
                  onSelect: () => Navigator.of(ctx).pop(_c.text.trim())),
            ]),
          ]),
          if (showQr) ...[
            const SizedBox(width: 40),
            Container(width: 1.5, height: 250, color: Colors.white24),
            const SizedBox(width: 40),
            SizedBox(
              width: 250,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                QrCode(text: _url!, size: 210),
                const SizedBox(height: 12),
                const Text('Scan to type on your phone',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Same Wi-Fi as the TV',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 19, color: Colors.white54)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Friendly text for on-device ADB failures.
String adbFriendly(Object? error) {
  final e = '$error';
  if (!kIsFireTv) {
    if (e.contains('refused') || e.contains('ECONNREFUSED')) {
      return 'Debugging is not switched on yet. Turn on USB debugging (or Wireless debugging) in Developer options, then try again.';
    }
    if (e.contains('imed out') || e.contains('Timeout')) {
      return 'No answer. If an "Allow debugging" box appeared on the TV, choose Always allow, then try again.';
    }
    if (e.contains('EOF') || e.contains('reset')) {
      return 'The TV closed the connection. Look for an "Allow debugging" box, choose Always allow, then try again.';
    }
    return 'Debugging problem: $e';
  }
  if (e.contains('refused') || e.contains('ECONNREFUSED')) {
    return 'Could not reach on-device ADB. Turn on ADB debugging in Settings > My Fire TV > Developer options. Some newer Fire OS updates block this for apps; if it still fails, run the command from a computer instead.';
  }
  if (e.contains('imed out') || e.contains('Timeout')) {
    return 'No answer. If a prompt appeared on the TV, choose Always allow, then try again.';
  }
  if (e.contains('EOF') || e.contains('reset')) {
    return 'This Fire TV hangs up on apps that try to use its ADB, before any Allow prompt. It is a Fire OS limit, not a setting. Run the clean-up from a computer instead: bash tools/tuneup.sh <stick IP> in the Foyer folder.';
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

/// One row in the settings: icon, title, a small line, and an optional value on the right.
class HubEntry {
  HubEntry(this.icon, this.title, this.subtitle, this.onSelect, {this.value = ''});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final String value;
}

class _Group {
  _Group(this.icon, this._title, this._subtitle, this.items);

  // "Fire TV tools" only makes sense on a Fire TV.
  String get title => (!kIsFireTv && _title == 'Fire TV tools') ? 'TV tools' : _title;
  String get subtitle => (!kIsFireTv && _title == 'Fire TV tools') ? 'Home button, tune-up, remote buttons' : _subtitle;
  final IconData icon;
  final String _title;
  final String _subtitle;
  final List<HubEntry> Function(BuildContext c, Settings s) items;
}

/// Opens one step of the first-run setup on its own (0 name/clock, 1 glass, 2 apps, 3 Plex, 4 Home button, 5 sports).
void _editStep(BuildContext c, int step) => _push(
    c, SetupScreen(firstRun: false, only: step, onDone: () => Navigator.of(c).pop()));

Future<void> openFireSettings(BuildContext context) async {
  var r = 'failed';
  try {
    r = (await kChannel.invokeMethod<String>('openFireSettings')) ?? 'failed';
  } catch (_) {}
  if (r != 'ok' && context.mounted) {
    showInfo(context, 'Could not open Fire TV settings',
        'Double-press Home for the Amazon home screen, or run on your computer: adb shell am start -a android.settings.SETTINGS');
  }
}

Future<void> openAmazonHome(BuildContext context) async {
  try {
    await kChannel.invokeMethod<bool>('openAmazonHome');
  } catch (_) {}
}

final List<_Group> _groups = [
  _Group(Icons.home_rounded, 'Home screen', 'Name, apps, weather, sports', (c, s) => [
    HubEntry(Icons.badge_rounded, 'Name and clock',
        '${s.name}, ${s.clock24 ? '24-hour' : '12-hour'} clock', () => _editStep(c, 0)),
    HubEntry(Icons.apps_rounded, 'Pinned apps',
        s.personName.isEmpty ? '${s.pinned.length} on your home screen' : '${s.pinned.length} for ${s.personName}',
        () => _editStep(c, 2)),
    HubEntry(Icons.people_alt_rounded, 'People',
        s.profiles.length < 2 ? 'Give each person their own apps and teams' : s.profiles.map((p) => p.name).join(', '),
        () => _push(c, const PeopleScreen())),
    HubEntry(Icons.video_library_rounded, 'Plex',
        s.plexToken.isEmpty ? 'Link your Plex so Keep watching shows your Plex shows' : 'Linked${s.plexName.isEmpty ? '' : ' to ${s.plexName}'}',
        () => _editStep(c, 3)),
    HubEntry(Icons.play_circle_outline_rounded, 'Keep watching',
        !s.keepWatching
            ? 'Off'
            : 'On${s.nowPlaying ? ', with the song that\'s playing' : ''}'
                '${s.keepHidden.length + s.keepHiddenApps.length > 0 ? ' · ${s.keepHidden.length + s.keepHiddenApps.length} hidden' : ''}',
        () => _push(c, const KeepWatchingScreen())),
    HubEntry(
        Icons.wb_sunny_rounded,
        'Weather',
        s.weatherCity.isEmpty
            ? 'Off'
            : '${s.weatherCity}, ${s.weatherF ? 'Fahrenheit' : 'Celsius'}',
        () => _push(c, const WeatherScreen())),
    HubEntry(
        Icons.sports_score_rounded,
        'Sports',
        s.sportsTeams.isEmpty
            ? 'Pick your teams for live scores and alerts'
            : '${s.sportsTeams.length} teams · alerts ${s.scoreAlerts == 0 ? 'off' : (s.scoreDelay > 0 ? 'on, ${s.scoreDelay} s delay' : 'on')}',
        () => _push(c, const SportsSettingsScreen())),
    HubEntry(Icons.cloud_sync_rounded, 'Foyer Drop',
        s.serverUrl.isEmpty || s.serverToken.isEmpty ? 'Not linked' : 'Linked to ${s.serverUrl}',
        () => _push(c, const ServerScreen())),
  ]),
  _Group(Icons.palette_rounded, 'Appearance', 'Glass style, wallpaper, holidays, sounds', (c, s) => [
    HubEntry(
        Icons.blur_on_rounded,
        'Glass style',
        s.liquid ? (s.perfMode ? 'Liquid glass (blur is off in Performance mode)' : 'Liquid glass') : 'Simple glass',
        () => _editStep(c, 1)),
    HubEntry(
        Icons.wallpaper_rounded,
        'Wallpaper',
        s.wallMode == 'scenes'
            ? (s.wallValue.isEmpty
                ? 'Scenes, taking turns'
                : (s.wallValue == 'auto' ? 'Scenes, following the sun' : 'Scene: ${sceneName(s.wallValue)}'))
            : s.wallMode == 'photo'
            ? 'Your photo'
            : (s.wallMode == 'preset'
                ? kWallPresets[clampIdx(int.tryParse(s.wallValue) ?? 0, kWallPresets.length - 1)].name
                : 'Follows the selected app'),
        () => _push(c, const WallpaperScreen())),
    HubEntry(Icons.speed_rounded, 'Performance mode',
        s.perfMode ? 'On: no blur, lighter animations' : 'Off',
        () => s.change(() => s.perfMode = !s.perfMode)),
    HubEntry(Icons.wb_twilight_rounded, 'Light follows the day',
        s.dayLightOn ? 'On: warmer at sunset, dimmer late at night' : 'Off: the same all day', () {
      s.change(() {
        s.dayLightOn = !s.dayLightOn;
        kDayLight = s.dayLightOn;
      });
      kDayTick.value++;
    }),
    HubEntry(Icons.thunderstorm_rounded, 'Weather on the background',
        s.weatherFx ? 'On: rain, snow and fog when it\'s like that outside' : 'Off',
        () => _push(c, const WeatherFxScreen())),
    HubEntry(Icons.celebration_rounded, 'Seasonal themes',
        s.seasonal ? 'On: Halloween, Christmas, New Year and Easter' : 'Off',
        () => _push(c, const SeasonsScreen())),
    HubEntry(Icons.music_note_rounded, 'Sounds',
        '${kSoundNames[s.soundLevel]}: a soft tick when you move around', () {
      s.change(() {
        s.soundLevel = (s.soundLevel + 1) % 3;
        kSoundLevel = s.soundLevel;
      });
    }),
  ]),
  _Group(Icons.bedtime_rounded, 'Screensaver and power', 'Screensaver, start on boot, restart', (c, s) => [
    HubEntry(Icons.bedtime_rounded, 'Screensaver',
        s.ssMinutes == 0 ? 'Off' : 'Starts after ${s.ssMinutes} min idle',
        () => _push(c, const ScreensaverScreen())),
    HubEntry(Icons.nights_stay_rounded, 'Smart idle', smartIdleSummary(s),
        () => _push(c, const SmartIdleScreen())),
    HubEntry(Icons.tv_off_rounded, 'Screen off',
        'Picture off, sound keeps playing. Any button brings it back', () => screenOffNow(c)),
    HubEntry(Icons.power_settings_new_rounded, 'Start on boot',
        s.autoStart ? 'On: opens Foyer when the stick starts' : 'Off',
        () => s.change(() => s.autoStart = !s.autoStart)),
    if (kIsFireTv)
      HubEntry(Icons.restart_alt_rounded, 'Restart Fire TV',
          'Reboots the stick (needs ADB debugging on)', () => restartStick(c)),
    if (!kIsFireTv)
      HubEntry(Icons.restart_alt_rounded, 'Restart or sleep',
          'Restart the TV box, or put it to sleep', () => _push(c, const PowerScreen())),
  ]),
  // The title stays "Fire TV tools" on a Fire TV; on other boxes the page shows only what applies.
  _Group(Icons.build_rounded, 'Fire TV tools', 'Home button, tune-up, remote buttons', (c, s) => [
    HubEntry(
        Icons.keyboard_return_rounded,
        'Home button',
        kIsFireTv ? 'Keep Foyer in front of Amazon\'s home' : 'Make Foyer this TV\'s home screen',
        () => _editStep(c, 4)),
    if (kIsFireTv)
      HubEntry(Icons.home_work_rounded, 'Amazon home screen',
          'Open the stock Fire TV home for a moment', () => openAmazonHome(c)),
    if (kIsFireTv)
      HubEntry(Icons.build_rounded, 'Tune-up',
          'Debug report and how to remove Amazon ads', () => _push(c, const TuneUpScreen())),
    if (!kIsFireTv)
      HubEntry(Icons.cleaning_services_rounded, 'Tune-up',
          'Switch off Google\'s ads, tracking and extra apps', () => _push(c, const GoogleTuneUpScreen())),
    HubEntry(Icons.settings_remote_rounded, 'Remote buttons',
        s.remoteKeys.values.any((v) => v.isNotEmpty)
            ? 'Custom buttons are set'
            : 'Choose what the star, YouTube and Netflix buttons open',
        () => _push(c, const RemoteButtonsScreen())),
  ]),
  _Group(Icons.system_update_rounded, 'Backup and updates', 'Updates, backup, run setup again', (c, s) => [
    HubEntry(
        Icons.system_update_rounded,
        'Updates',
        kUpdate.value != null
            ? 'Version ${kUpdate.value!.version} is available'
            : (s.updateUrl.isEmpty ? 'Set up an update link' : 'Check for a newer version'),
        () => _push(c, const UpdateScreen())),
    HubEntry(Icons.backup_rounded, 'Backup and restore',
        'Save your settings to a file, or load them back',
        () => _push(c, const BackupScreen())),
    HubEntry(Icons.card_giftcard_rounded, 'Reset for someone new',
        'Giving this box away? Clears your accounts and settings, keeps the TV set up', () {
      showMenu2(c, 'Reset for someone new?', [
        MenuChoice('Forgets your name, apps, Plex, Foyer Drop, teams, remote buttons and tokens. '
            'Foyer stays the home screen with ads off, and the next start opens the welcome setup.', null),
        MenuChoice('Reset now', () {
          Navigator.of(c).popUntil((r) => r.isFirst);
          s.resetForSomeoneNew();
        }),
        MenuChoice('Cancel', () {}),
      ]);
    }),
    HubEntry(Icons.restart_alt_rounded, 'Run setup again',
        'The guided setup from the first day. Your settings are kept',
        () => _push(c, FirstRunSetup(onDone: () => Navigator.of(c).pop()))),
  ]),
];

class _Section {
  _Section(this.icon, this.title, this.rows, {this.dot = false});
  final IconData icon;
  final String title;
  final List<HubEntry> rows;
  final bool dot;
}

/// Settings, two panes: the sections down the left, the chosen section's rows on the right.
/// Up and down move, Right or OK goes into a section, Left or Back comes back out,
/// and Back on the left closes settings.
class SettingsHub extends StatefulWidget {
  const SettingsHub({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  State<SettingsHub> createState() => _SettingsHubState();
}

class _SettingsHubState extends State<SettingsHub> {
  int _sel = 0;
  bool _inRight = false;
  Map<String, dynamic> _tv = {};
  final List<FocusNode> _left = [];
  final List<FocusNode> _right = [];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTv();
  }

  Future<void> _loadTv() async {
    if (kIsFireTv) return;
    final i = await sysCall('info');
    if (mounted) setState(() => _tv = i);
  }

  @override
  void dispose() {
    for (final n in [..._left, ..._right]) {
      n.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  FocusNode _node(List<FocusNode> l, int i) {
    while (l.length <= i) {
      l.add(FocusNode());
    }
    return l[i];
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    _loadTv();
  }

  List<_Section> _sections(BuildContext c, Settings s) {
    final up = kUpdate.value;
    return [
      if (up != null)
        _Section(Icons.system_update_rounded, 'Update available', [
          HubEntry(Icons.system_update_rounded, 'Install version ${up.version}', 'Takes about a minute. Your settings stay',
              () => _open(const UpdateScreen())),
        ], dot: true),
      if (!kIsFireTv)
        _Section(Icons.tv_rounded, 'TV settings', tvSettingsEntries(c, _tv, _open)),
      for (final g in _groups) _Section(g.icon, g.title, g.items(c, s)),
      if (kIsFireTv)
        _Section(Icons.settings_rounded, 'Fire TV settings', [
          HubEntry(Icons.settings_rounded, 'Open Fire TV settings', 'The stock Wi-Fi, display and sound settings',
              () => openFireSettings(c)),
        ]),
      if (s.devMode)
        _Section(Icons.developer_mode_rounded, 'Developer options', [
          HubEntry(Icons.developer_mode_rounded, 'Developer options', 'Where updates come from, GitHub repo and access token',
              () => _open(const DeveloperScreen())),
        ]),
    ];
  }

  void _toRight() {
    if (_right.isNotEmpty) _right.first.requestFocus();
  }

  void _toLeft() => _node(_left, _sel).requestFocus();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateInfo?>(
        valueListenable: kUpdate,
        builder: (context, _, __) => _build(context),
      );

  Widget _build(BuildContext context) {
    final s = SettingsScope.of(context);
    final secs = _sections(context, s);
    if (_sel >= secs.length) _sel = secs.length - 1;
    final sec = secs[_sel];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_inRight) {
          _toLeft();
        } else {
          widget.onClose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          const Positioned.fill(child: SettingsBackdrop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(96, 72, 110, 48),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── left: the sections ──
              SizedBox(
                width: 560,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 18),
                    child: Text('Settings',
                        style: TextStyle(fontSize: 58, fontWeight: FontWeight.w700, letterSpacing: -1)),
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, e) {
                          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                          final k = e.logicalKey;
                          if (k == LogicalKeyboardKey.arrowRight) {
                            _toRight();
                            return KeyEventResult.handled;
                          }
                          // stay in the list at its ends
                          if (k == LogicalKeyboardKey.arrowDown && _sel >= secs.length - 1) return KeyEventResult.handled;
                          if (k == LogicalKeyboardKey.arrowUp && _sel <= 0) return KeyEventResult.handled;
                          if (k == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
                          return KeyEventResult.ignored;
                        },
                        child: SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (var i = 0; i < secs.length; i++)
                              _SideItem(
                                section: secs[i],
                                node: _node(_left, i),
                                autofocus: i == _sel,
                                chosen: i == _sel,
                                onFocus: () {
                                  _inRight = false;
                                  if (_sel != i) {
                                    setState(() => _sel = i);
                                    if (_scroll.hasClients) _scroll.jumpTo(0);
                                  }
                                },
                                onSelect: _toRight,
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 48),
              // ── right: the chosen section ──
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(sec.title,
                        key: ValueKey(sec.title),
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 34),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (f) => setState(() => _inRight = f),
                        onKeyEvent: (_, e) {
                          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
                          final k = e.logicalKey;
                          if (k == LogicalKeyboardKey.arrowLeft) {
                            _toLeft();
                            return KeyEventResult.handled;
                          }
                          final n = sec.rows.length;
                          if (k == LogicalKeyboardKey.arrowDown && n > 0 && _right[n - 1].hasFocus) {
                            return KeyEventResult.handled;
                          }
                          if (k == LogicalKeyboardKey.arrowUp && n > 0 && _right[0].hasFocus) {
                            return KeyEventResult.handled;
                          }
                          if (k == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
                          return KeyEventResult.ignored;
                        },
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 30),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (var i = 0; i < sec.rows.length; i++)
                              SettingRow(entry: sec.rows[i], node: _node(_right, i)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(_inRight ? 'OK to open  ·  Left or Back to go back' : 'Right or OK to open  ·  Back to close',
                      style: const TextStyle(fontSize: 21, color: Colors.white38)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The calm, dark background behind every settings page.
class SettingsBackdrop extends StatelessWidget {
  const SettingsBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: Backdrop(tint: kDefaultTint)),
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xD9000000), Color(0x99000000)]))),
      ]);
}

class _SideItem extends StatelessWidget {
  const _SideItem(
      {required this.section,
      required this.node,
      required this.autofocus,
      required this.chosen,
      required this.onFocus,
      required this.onSelect});
  final _Section section;
  final FocusNode node;
  final bool autofocus;
  final bool chosen;
  final VoidCallback onFocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FocusButton(
          focusNode: node,
          autofocus: autofocus,
          scale: 1.0,
          scrollIntoView: true,
          onFocusChange: (f) {
            if (f) onFocus();
          },
          onSelect: onSelect,
          builder: (_, f) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 540,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: f ? Colors.white : (chosen ? Colors.white.withAlpha(34) : Colors.transparent),
            ),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: f ? Colors.black.withAlpha(20) : Colors.white.withAlpha(24),
                ),
                child: Icon(section.icon, size: 30, color: f ? Colors.black : Colors.white),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Text(section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: f || chosen ? FontWeight.w600 : FontWeight.w500,
                        color: f ? Colors.black : (chosen ? Colors.white : Colors.white70))),
              ),
              if (section.dot)
                Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(color: Color(0xFFFF9F0A), shape: BoxShape.circle)),
            ]),
          ),
        ),
      );
}

/// A row on the right side of settings (and on the TV settings pages).
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.entry, this.node, this.autofocus = false});
  final HubEntry entry;
  final FocusNode? node;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FocusButton(
          focusNode: node,
          autofocus: autofocus,
          scale: 1.0,
          scrollIntoView: true,
          onSelect: entry.onSelect,
          builder: (_, f) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: f ? Colors.white : Colors.white.withAlpha(20),
              boxShadow: f ? const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))] : null,
            ),
            child: Row(children: [
              Icon(entry.icon, size: 34, color: f ? Colors.black : Colors.white70),
              const SizedBox(width: 24),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w600, color: f ? Colors.black : Colors.white)),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 21, color: f ? Colors.black54 : Colors.white54)),
                  ],
                ]),
              ),
              if (entry.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(entry.value,
                      style: TextStyle(fontSize: 26, color: f ? Colors.black54 : Colors.white60)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(Icons.chevron_right_rounded, size: 36, color: f ? Colors.black45 : Colors.white38),
              ),
            ]),
          ),
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
      subtitle: 'Scenes with a big clock, a colour style, or one of your photos.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Scenes', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Painted landscapes with a big clock tucked behind the scenery.',
              style: TextStyle(fontSize: 22, color: Colors.white60)),
          const SizedBox(height: 18),
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(
                autofocus: s.wallMode == 'scenes',
                label: 'Take turns (every 20 s)',
                selected: s.wallMode == 'scenes' && s.wallValue.isEmpty,
                onSelect: () => s.change(() {
                      s.wallMode = 'scenes';
                      s.wallValue = '';
                    })),
            Opt(
                label: 'Follow the sun',
                selected: s.wallMode == 'scenes' && s.wallValue == 'auto',
                onSelect: () => s.change(() {
                      s.wallMode = 'scenes';
                      s.wallValue = 'auto';
                    })),
          ]),
          if (s.wallMode == 'scenes' && s.wallValue == 'auto')
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                  s.weatherCity.isEmpty
                      ? 'Set a weather place (Home screen → Weather) and the scenes follow the real sunrise and sunset there. Until then, they go by the clock.'
                      : 'The meadow at sunrise, the misty forest in the morning, the Matterhorn at midday, the volcano at golden hour and the starry lake after dark, using today\'s sunrise and sunset in ${s.weatherCity}.',
                  style: const TextStyle(fontSize: 23, color: Colors.white54)),
            ),
          const SizedBox(height: 20),
          Wrap(spacing: 20, runSpacing: 20, children: [
            for (final k in kSceneOrder)
              FocusButton(
                scrollIntoView: true,
                onSelect: () => s.change(() {
                  s.wallMode = 'scenes';
                  s.wallValue = k;
                }),
                builder: (_, focused) {
                  final sel = s.wallMode == 'scenes' && s.wallValue == k;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 320,
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: focused ? Colors.white : (sel ? Colors.white70 : Colors.white24),
                            width: focused ? 3.5 : 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(fit: StackFit.expand, children: [
                          // a small live copy of the scene, clock and all
                          FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(width: 1920, height: 1080, child: SceneView(which: k, thumb: true))),
                          if (sel)
                            const Positioned(
                                top: 8, right: 8, child: Icon(Icons.check_circle, size: 36, color: Colors.white)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(sceneName(k), style: const TextStyle(fontSize: 22, color: Colors.white70)),
                  ]);
                },
              ),
          ]),
          const SizedBox(height: 36),
          const Text('Colours', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Wrap(spacing: 16, runSpacing: 16, children: [
            Opt(
                autofocus: s.wallMode != 'scenes',
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
  _Shot(this.src, this.net, [this.caption = '', this.token = '']);
  final String src;
  final bool net;
  final String caption;
  final String token;
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
    if (cfg.ssSource == 'drop') kDrop.photosStamp.addListener(_reloadDrop);
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
      if (source == 'drop') {
        final cfg = SettingsScope.read(context);
        final urls = (await DropApi.photoUrls(cfg.serverUrl, cfg.serverToken)).toList()
          ..shuffle(Random());
        shots = [for (final u in urls.take(30)) _Shot(u, true, '', cfg.serverToken)];
      } else if (source == 'online') {
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

  /// New photos were sent while the screensaver is up: show them without waiting.
  void _reloadDrop() {
    if (mounted) _loadShots('drop');
  }

  @override
  void dispose() {
    kDrop.photosStamp.removeListener(_reloadDrop);
    _t?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  Widget _image(_Shot shot) {
    Widget err(BuildContext _, Object __, StackTrace? ___) => const ColoredBox(color: Colors.black);
    return shot.net
        ? Image.network(shot.src,
            headers: shot.token.isEmpty ? null : {'Authorization': 'Bearer ${shot.token}'},
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
            if (s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty)
              Opt(
                  label: 'Photo drop',
                  selected: s.ssSource == 'drop',
                  onSelect: () => s.change(() => s.ssSource = 'drop')),
            Opt(
                label: 'Online photos',
                selected: s.ssSource == 'online',
                onSelect: () => s.change(() => s.ssSource = 'online')),
          ]),
          if (s.ssSource == 'drop')
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('Uses photos sent to your Foyer Drop server. Falls back to colors if it is offline.',
                  style: TextStyle(fontSize: 22, color: Colors.white60)),
            ),
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
  String _ip = '<stick IP>';

  @override
  void initState() {
    super.initState();
    () async {
      try {
        for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final a in ni.addresses) {
            if (!a.isLoopback) {
              if (mounted) setState(() => _ip = a.address);
              return;
            }
          }
        }
      } catch (_) {}
    }();
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
          'Fire OS does not let apps remove Amazon ads and extras, so this is done once from a computer on the same Wi-Fi. Everything can be undone.',
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
                        'On a computer on the same Wi-Fi, open the Foyer folder and run:\n\n'
                        'bash tools/tuneup.sh $_ip\n\n'
                        'To undo it:\n\n'
                        'bash tools/tuneup.sh $_ip undo\n\n'
                        'Step-by-step help: GUIDE.md in the Foyer GitHub repo.'
                        '${_log.isEmpty ? '' : '\n\n' + _log.join('\n')}',
                        style: const TextStyle(
                            fontSize: 22, fontFamily: 'monospace', color: Colors.white70)),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        Wrap(spacing: 18, runSpacing: 18, children: [
          PillButton(label: 'Scan again', autofocus: true, onSelect: _scan),
          PillButton(label: 'Save debug report', onSelect: _report),
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
  String _name = '0';
  int _build = 0;
  String _msg = '';
  double? _prog;
  bool _busy = false;
  UpdateInfo? _found = kUpdate.value;
  int _taps = 0;

  void _tapVersion() {
    final s = SettingsScope.read(context);
    if (s.devMode) {
      setState(() => _msg = 'Developer options are already on (Settings › Developer options).');
      return;
    }
    _taps++;
    if (_taps >= 7) {
      s.change(() => s.devMode = true);
      setState(() => _msg = 'You\'re now a developer. Developer options are at the bottom of Settings.');
    } else if (_taps >= 3) {
      setState(() => _msg = '${7 - _taps} more to turn on developer options.');
    }
  }

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final m = await kChannel.invokeMapMethod<String, dynamic>('appVersion');
        _build = (m?['code'] as num?)?.toInt() ?? 0;
        _name = (m?['name'] as String?) ?? '0';
        if (mounted) setState(() => _ver = '$_name ($_build)');
      } catch (_) {}
      // look right away, so the button already says "Download and install" when there's one
      if (mounted && SettingsScope.read(context).updateUrl.isNotEmpty) _check(auto: true);
    }();
  }

  /// One button: Check now, which becomes Download and install once an update is found.
  /// Pressing Check now and finding one goes straight on to install it.
  Future<void> _check({bool auto = false}) async {
    final cfg = SettingsScope.read(context);
    if (cfg.updateUrl.isEmpty) {
      setState(() => _msg = 'Set the GitHub repo first.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = 'Checking…';
    });
    UpdateInfo? r;
    try {
      r = await UpdateApi.check(cfg.updateUrl, cfg.updateToken, _build, _name,
          dropUrl: cfg.serverUrl, dropToken: cfg.serverToken);
      kUpdate.value = r;
      if (!mounted) return;
      setState(() {
        _found = r;
        _msg = r == null
            ? 'You\'re up to date.'
            : 'Version ${r.version} is ready.${r.notes.trim().isEmpty ? '' : '\n\n${plainNotes(r.notes)}'}';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Could not check: ${UpdateApi.friendly(e)}');
    }
    if (mounted) setState(() => _busy = false);
    if (!auto && r != null && mounted) await _install();
  }

  Future<void> _install() async {
    final u = _found;
    if (u == null || _busy) return;
    final cfg = SettingsScope.read(context);
    setState(() {
      _busy = true;
      _prog = 0;
      _msg = 'Downloading…';
    });
    try {
      final path = (await kChannel.invokeMethod<String>('updatePath')) ?? '';
      final viaDrop = cfg.updateUrl.trim() == UpdateApi.dropSource;
      await UpdateApi.download(u.url, path, viaDrop ? cfg.serverToken : cfg.updateToken, (p) {
        if (mounted) setState(() => _prog = p);
      });
      final r = await kChannel.invokeMethod<String>('installApk', {'path': path});
      if (!mounted) return;
      setState(() => _msg = r == 'needsPermission'
          ? 'Allow Foyer to install apps on the screen that just opened, then press the button again.'
          : (r == 'started'
              ? (kIsFireTv
                  ? 'Confirm the install on the next screen.'
                  : 'Installing ${u.version}… The screen goes dark for a moment and Foyer comes back by itself.')
              : 'The download could not be installed.'));
    } catch (e) {
      if (mounted) setState(() => _msg = 'Update failed: ${UpdateApi.friendly(e)}');
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
          'New versions come from your Foyer Drop server (only signed-in TVs can get them), or from a GitHub repo.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // press the version 7 times for Developer options (like Android's build number)
          FocusButton(
            scale: 1.0,
            onSelect: _tapVersion,
            builder: (_, f) => AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: f ? Colors.white.withAlpha(30) : Colors.transparent,
              ),
              child: kv('Version', _ver),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: kv('Updates from',
              s.updateUrl.trim() == UpdateApi.dropSource
                  ? (s.serverUrl.isEmpty ? 'Foyer Drop (link it in Settings › Foyer Drop)' : 'Foyer Drop')
                  : 'GitHub')),
          const SizedBox(height: 18),
          PillButton(
              key: const ValueKey('update-main'),
              label: _prog != null
                  ? 'Downloading… ${((_prog ?? 0) * 100).round()}%'
                  : (_busy
                      ? 'Checking…'
                      : (_found != null ? 'Download and install ${_found!.version}' : 'Check now')),
              primary: true,
              autofocus: true,
              onSelect: () => _found != null ? _install() : _check()),
          const SizedBox(height: 26),
          if (_prog != null)
            SizedBox(
                width: 700,
                child: LinearProgressIndicator(value: _prog, minHeight: 10, borderRadius: BorderRadius.circular(6))),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                  width: 1400,
                  child: Text(_msg,
                      maxLines: 16,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 24, height: 1.4, color: Colors.white70))),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── sports: teams, alerts, delay ─────────────────────────

class SportsSettingsScreen extends StatelessWidget {
  const SportsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    Widget heading(String t, [String sub = '']) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 0, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 23, color: Colors.white54)),
          ]),
        );
    Widget chip(String label, bool selected, VoidCallback onSelect, {bool first = false}) => Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 16),
          child: Opt(label: label, selected: selected, onSelect: onSelect, autofocus: first),
        );
    return SettingsPage(
      title: 'Sports',
      subtitle: 'Live scores on the home screen, and alerts over whatever you\'re watching.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Your teams',
              s.sportsTeams.isEmpty ? 'None yet' : s.sportsTeams.map((t) => t.league == 'f1' ? 'Formula 1' : t.name).join(', ')),
          Wrap(children: [
            for (var i = 0; i < kLeagues.length; i++)
              Builder(builder: (_) {
                final l = kLeagues[i];
                final n = s.countIn(l.key);
                final on = l.key == 'f1' ? s.follows(FollowedTeam.f1) : n > 0;
                return chip(
                    l.key == 'f1' ? (on ? 'Formula 1: on' : 'Formula 1') : (n > 0 ? '${l.label} · $n' : l.label),
                    on,
                    () {
                      if (l.key == 'f1') {
                        s.change(() => s.toggleTeam(FollowedTeam.f1));
                      } else {
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => SportsTeamsScreen(league: l)));
                      }
                    },
                    first: i == 0);
              }),
          ]),
          heading('Score alerts', 'A note in the top corner when your teams score, even during Netflix or Plex'),
          Wrap(children: [
            for (var i = 0; i < kScoreAlertNames.length; i++)
              chip(kScoreAlertNames[i], s.scoreAlerts == i, () {
                s.change(() {
                  s.scoreAlerts = i;
                  kScoreAlertLevel = i;
                });
              }),
            if (s.scoreAlerts > 0)
              chip('Show a sample', false, showSampleAlert),
          ]),
          if (s.scoreAlerts > 0) ...[
            heading('Alert size', 'Selecting a size shows a sample'),
            Wrap(children: [
              for (var i = 0; i < kScoreSizeNames.length; i++)
                chip(kScoreSizeNames[i], s.scoreSize == i, () {
                  s.change(() {
                    s.scoreSize = i;
                    kScoreAlertSize = i;
                  });
                  showSampleAlert();
                }),
            ]),
            heading('Alert delay',
                'Streams run 20 to 60 seconds behind live. If alerts show up before the goal does, hold them back.'),
            Wrap(children: [
              for (final d in kScoreDelays)
                chip(d == 0 ? 'None (fastest)' : '$d seconds', s.scoreDelay == d, () {
                  s.change(() {
                    s.scoreDelay = d;
                    kScoreAlertDelay = d;
                  });
                }),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ───────────────────────── developer options ─────────────────────────

/// Hidden until the version on the Updates page is pressed 7 times.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});
  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  String _msg = '';

  void _changed() => kUpdate.value = null;

  Future<void> _loadTokenFile(Settings s) async {
    try {
      await kChannel.invokeMethod<bool>('requestStorage');
      final t = await kChannel.invokeMethod<String>('readTokenFile');
      if (t == null || t.isEmpty) {
        setState(() => _msg = 'No foyer-token.txt found. Send it from your computer first (see the README).');
      } else {
        final clean = UpdateApi.cleanToken(t);
        s.change(() => s.updateToken = clean);
        _changed();
        setState(() => _msg = 'Token loaded (${clean.length} characters) and the file was deleted from the TV.');
      }
    } catch (_) {
      setState(() => _msg = 'Could not read the token file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final drop = s.updateUrl.trim() == UpdateApi.dropSource;
    return SettingsPage(
      title: 'Developer options',
      subtitle: 'For whoever looks after this TV. Changing these can stop updates from arriving.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 18),
              child: SizedBox(width: 1300, child: Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70))),
            ),
          SysRow(
              icon: Icons.cloud_download_rounded,
              title: 'Updates come from',
              subtitle: drop ? 'Your Foyer Drop server: only signed-in TVs can download' : 'A GitHub repo',
              value: drop ? 'Foyer Drop' : 'GitHub',
              autofocus: true,
              onSelect: () {
                s.change(() => s.updateUrl = drop ? 'matthewsleclair-hue/Foyer' : UpdateApi.dropSource);
                _changed();
              }),
          if (!drop) ...[
            SysRow(
                icon: Icons.source_rounded,
                title: 'GitHub repo',
                subtitle: 'owner/repo with the releases',
                value: s.updateUrl,
                onSelect: () async {
                  final v = await askText(context, 'GitHub repo', s.updateUrl, hint: 'owner/repo', maxLength: 120);
                  if (v != null && v.trim().isNotEmpty) {
                    s.change(() => s.updateUrl = v.trim());
                    _changed();
                  }
                }),
            SysRow(
                icon: Icons.key_rounded,
                title: s.updateToken.isEmpty ? 'Type access token' : 'Change access token',
                subtitle: 'A read-only token, needed for a private repo',
                value: s.updateToken.isEmpty ? 'None' : 'Set',
                onSelect: () async {
                  final v = await askText(context, 'GitHub access token', '', hint: 'github_pat_…', maxLength: 200);
                  if (v != null) {
                    s.change(() => s.updateToken = UpdateApi.cleanToken(v));
                    _changed();
                  }
                }),
            SysRow(
                icon: Icons.file_open_rounded,
                title: 'Load token from file',
                subtitle: 'Reads foyer-token.txt sent from a computer, then deletes it',
                onSelect: () => _loadTokenFile(s)),
          ],
          SysRow(
              icon: Icons.developer_mode_rounded,
              title: 'Turn off developer options',
              subtitle: 'Hides this page again',
              onSelect: () {
                s.change(() => s.devMode = false);
                Navigator.of(context).pop();
              }),
        ]),
      ),
    );
  }
}

// ───────────────────────── QR code ─────────────────────────

/// A QR code drawn on the TV (ZXing, on the Android side), on a white card so any phone reads it.
class QrCode extends StatefulWidget {
  const QrCode({super.key, required this.text, this.size = 240});
  final String text;
  final double size;
  @override
  State<QrCode> createState() => _QrCodeState();
}

class _QrCodeState extends State<QrCode> {
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    _make();
  }

  @override
  void didUpdateWidget(QrCode old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _make();
  }

  Future<void> _make() async {
    try {
      final b = await kChannel.invokeMethod<Uint8List>('qrPng', {'text': widget.text, 'size': 480});
      if (mounted) setState(() => _png = b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Container(
        width: widget.size,
        height: widget.size,
        padding: EdgeInsets.all(widget.size * 0.05),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: _png == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black26))
            : Image.memory(_png!, filterQuality: FilterQuality.none, gaplessPlayback: true),
      );
}

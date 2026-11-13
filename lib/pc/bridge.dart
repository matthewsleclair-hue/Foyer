// Foyer for PC: answers the calls the TV app makes to Android, the Windows way.
// Settings live in %APPDATA%\Foyer, apps open as programs or as full-screen Edge
// windows, Home on the remote (or the phone) brings Foyer back, and the Foyer Drop
// phone remote presses keys on the PC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'apps.dart';
import 'win.dart';

const String kPcVersion = String.fromEnvironment('FOYER_VERSION', defaultValue: '0.0.0');
const int kPcBuild = int.fromEnvironment('FOYER_BUILD', defaultValue: 0);

String _env(String k) => Platform.environment[k] ?? '';
String get _dataDir => '${_env('APPDATA')}\\Foyer';
String get _localDir => '${_env('LOCALAPPDATA')}\\Foyer';

class PcBridge {
  static Future<void> init() async {
    await Directory(_dataDir).create(recursive: true);
    await Directory(_localDir).create(recursive: true);
    // Home on the remote: close the streaming window and come back to Foyer
    Win.watchHome(goHome);
    // a game controller works Foyer's screens; Back + Start leaves a game
    Win.watchPad(onLeaveGame: () {
      if (_gamePid != 0) goHome();
    });
    await refreshStoreApps(force: true);
  }

  /// Back to Foyer's home screen from anywhere.
  static Future<void> goHome() async {
    if (!Win.foyerInFront) {
      await closeWebApps();
      await closeStoreApp();
      await closeGame();
    }
    Win.toFront();
    kGoHome?.call();
  }
}

Future<dynamic> pcChannel(String channel, String method, dynamic args) async {
  final a = args is Map ? args : const {};
  switch (method) {
    // ── the basics ──
    case 'deviceInfo':
      return {'fireTv': false, 'model': 'PC', 'defaultHome': true};
    case 'appVersion':
      return {'code': kPcBuild, 'name': kPcVersion};
    case 'loadSettings':
      {
        final f = File('$_dataDir\\settings.json');
        return {'json': await f.exists() ? await f.readAsString() : ''};
      }
    case 'saveSettings':
      {
        final json = '${a['json'] ?? ''}';
        await File('$_dataDir\\settings.json').writeAsString(json);
        _startAtLogin(json);
        return true;
      }
    case 'homeKeyStatus':
      return {'enabled': true, 'canWrite': true, 'restricted': false};
    case 'setHomeKey':
      return true;

    // ── apps ──
    case 'listApps':
      await refreshStoreApps();
      return [
        for (final p in kPcApps)
          if (available(p)) {'package': p.id, 'label': p.label, 'icon': await tileArt(p, square: true)}
      ];
    case 'getApps':
      {
        final want = ((a['packages'] as List?) ?? const []).map((e) => '$e').toSet();
        return [
          for (final p in kPcApps)
            if (want.contains(p.id) && available(p))
              {'package': p.id, 'label': p.label, 'image': await tileArt(p), 'wide': true, 'color': p.color}
        ];
      }
    case 'launch':
      return launchPcApp('${a['package']}');
    case 'openUrl':
      return openWeb('${a['url']}');
    case 'openLink':
      return false; // Plex links: Foyer then just opens Plex
    case 'closeAllApps':
      await closeWebApps();
      return 0;
    case 'killApp':
      await closeWebApps();
      return true;

    // ── games ──
    case 'gamesDir':
      {
        final d = Directory('${_env('USERPROFILE')}\\Documents\\Foyer Games');
        await d.create(recursive: true);
        return d.path;
      }
    case 'gamesStatus':
      return {'retroarch': _retroArch() != null, 'dolphin': _dolphin() != null};
    case 'launchGame':
      return launchGame('${a['path']}', '${a['system']}', '${a['core']}');

    // ── Foyer Drop ──
    case 'dropConfig':
      PcRemote.configure('${a['url'] ?? ''}', '${a['token'] ?? ''}');
      return true;

    // ── sleep, screen ──
    case 'sleepTimer':
      return PcSleep.start((a['minutes'] as num?)?.toInt() ?? 0);
    case 'sleepStatus':
      return PcSleep.endAt;
    case 'tvOffSoon':
      return PcSleep.start(1);
    case 'screenOff':
      Win.monitorOff();
      return true;

    // ── score alerts: a card in Foyer when Foyer is on screen ──
    case 'alert':
      _showAlert(a);
      return true;

    // ── things a PC doesn't have ──
    case 'watchNext':
    case 'nowPlaying':
      return {'ok': false};
    case 'soundscapeStatus':
    case 'soundscape':
      return '';
    case 'remoteKeysStatus':
      return {'running': true};
    case 'smartIdle':
    case 'play': // navigation sounds
      return true;
  }
  throw MissingPluginException('$method is not on PC');
}

// ───────────────────────── opening things ─────────────────────────

String? _edge() {
  for (final p in [
    '${_env('ProgramFiles(x86)')}\\Microsoft\\Edge\\Application\\msedge.exe',
    '${_env('ProgramFiles')}\\Microsoft\\Edge\\Application\\msedge.exe',
  ]) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

const String _tvAgent =
    'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 76.0.3809.146/6.0 TV Safari/537.36';

/// A website as its own full-screen window (Edge, Foyer's own profile so sign-ins stay).
Future<bool> openWeb(String url, {bool tv = false}) async {
  if (url.isEmpty) return false;
  // YouTube links play in YouTube's TV page, made for remotes
  final yt = RegExp(r'youtu(?:\.be/|be\.com/watch\?v=)([\w-]{6,})').firstMatch(url);
  if (yt != null) {
    url = 'https://www.youtube.com/tv#/watch?v=${yt.group(1)}';
    tv = true;
  }
  await closeWebApps();
  final edge = _edge();
  if (edge == null) {
    await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
    return true;
  }
  await Process.start(
      edge,
      [
        '--app=$url',
        '--start-fullscreen',
        '--user-data-dir=$_localDir\\${tv ? 'EdgeTV' : 'Edge'}',
        '--no-first-run',
        '--no-default-browser-check',
        '--autoplay-policy=no-user-gesture-required',
        // arrows hop between the tiles and buttons on any site, like a TV app
        '--enable-spatial-navigation',
        if (tv) '--user-agent=$_tvAgent',
      ],
      mode: ProcessStartMode.detached);
  return true;
}

/// Closes the streaming windows Foyer opened (never your other Edge windows).
Future<void> closeWebApps() async {
  try {
    await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe'\" | "
          "Where-Object { \$_.CommandLine -like '*\\Foyer\\Edge*' } | "
          'ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }',
    ]);
  } catch (_) {}
}

/// The Store app Foyer opened last (its package family), so Home can close it.
String _storeFamily = '';

/// Closes the Store app Foyer opened, so a show stops when you go back to Foyer.
Future<void> closeStoreApp() async {
  final fam = _storeFamily;
  if (fam.isEmpty) return;
  _storeFamily = '';
  try {
    await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$p = Get-AppxPackage | Where-Object { \$_.PackageFamilyName -eq '$fam' } | Select-Object -First 1; "
          "if (\$p) { Get-Process | Where-Object { \$_.Path -and \$_.Path.StartsWith(\$p.InstallLocation) } | "
          'Stop-Process -Force -ErrorAction SilentlyContinue }',
    ]);
  } catch (_) {}
}

/// Whether to use the Microsoft Store app when it's installed (Settings > Home screen).
bool get _preferStore {
  final c = kNavKey.currentContext;
  return c == null || SettingsScope.read(c).pcStoreApps;
}

Future<bool> launchPcApp(String id) async {
  PcApp? app;
  for (final p in kPcApps) {
    if (p.id == id) app = p;
  }
  if (app == null) return false;
  final exe = installedExe(app);
  final storeId = _preferStore ? storeAppId(app) : null;
  try {
    // a real program wins (Plex HTPC, Spotify), then the Store app, then the website
    if (exe == null && storeId != null) {
      await closeWebApps();
      await closeStoreApp();
      _storeFamily = storeId.split('!').first;
      await Process.start('explorer.exe', ['shell:AppsFolder\\$storeId'], mode: ProcessStartMode.detached);
      Win.fullScreenNext(); // Store apps open in a window: make it full screen
      return true;
    }
    if (exe != null) {
      if (app.uri.isNotEmpty && app.id == 'pc.steam') {
        await Process.start('cmd', ['/c', 'start', '', app.uri], mode: ProcessStartMode.detached);
      } else {
        await Process.start(exe, const [], mode: ProcessStartMode.detached);
      }
      // programs like Spotify open windowed (Plex HTPC and Kodi already fill the screen;
      // Steam may show a sign-in box first, so it's left alone)
      if (app.id != 'pc.steam') Win.fullScreenNext();
      return true;
    }
    return openWeb(app.url, tv: app.tv);
  } catch (_) {
    return false;
  }
}

// ───────────────────────── start with Windows ─────────────────────────

bool? _autoStartSet;

void _startAtLogin(String json) {
  bool want = true;
  try {
    final j = jsonDecode(json);
    if (j is Map && j['autoStart'] is bool) want = j['autoStart'] as bool;
  } catch (_) {}
  if (_autoStartSet == want) return;
  _autoStartSet = want;
  const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  final args = want
      ? ['add', key, '/v', 'Foyer', '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}"', '/f']
      : ['delete', key, '/v', 'Foyer', '/f'];
  Process.run('reg', args).catchError((Object _) => ProcessResult(0, 1, '', ''));
}

// ───────────────────────── sleep timer ─────────────────────────

class PcSleep {
  static int endAt = 0;
  static Timer? _t;

  static int start(int minutes) {
    _t?.cancel();
    if (minutes <= 0) {
      endAt = 0;
      return 0;
    }
    endAt = DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    _t = Timer(Duration(minutes: minutes), () {
      endAt = 0;
      closeWebApps();
      // sleep (or hibernate, if that's how Windows is set up)
      Process.run('rundll32.exe', ['powrprof.dll,SetSuspendState', '0,1,0']);
    });
    return endAt;
  }
}

// ───────────────────────── the phone remote (Foyer Drop) ─────────────────────────

class PcRemote {
  static String _url = '', _token = '';
  static bool _running = false;

  static void configure(String url, String token) {
    _url = url.replaceAll(RegExp(r'/+$'), '');
    _token = token;
    if (!_running && _url.isNotEmpty && _token.isNotEmpty) _loop();
  }

  static Future<void> _loop() async {
    _running = true;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    while (_url.isNotEmpty && _token.isNotEmpty) {
      try {
        final req = await http.getUrl(Uri.parse('$_url/api/tv/keys'));
        req.headers.set('Authorization', 'Bearer $_token');
        final res = await req.close().timeout(const Duration(seconds: 40));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode == 200) {
          final keys = (jsonDecode(body) as Map)['keys'] as List? ?? const [];
          for (final k in keys) {
            if (k is Map) await _act('${k['type']}', '${k['value']}');
          }
        } else {
          await Future.delayed(Duration(seconds: res.statusCode == 401 || res.statusCode == 404 ? 30 : 5));
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    _running = false;
  }

  static const Map<String, int> _keys = {
    'up': vkUp,
    'down': vkDown,
    'left': vkLeft,
    'right': vkRight,
    'ok': vkReturn,
    'back': vkBack,
    'menu': vkApps,
    'play': vkPlayPause,
    'rewind': vkLeft,
    'forward': vkRight,
    'volup': vkVolUp,
    'voldown': vkVolDown,
    'mute': vkMute,
  };

  static Future<void> _act(String type, String value) async {
    if (type == 'text') {
      // typed on the phone: paste it where the cursor is
      await Clipboard.setData(ClipboardData(text: value));
      Win.press(vkV, ctrl: true);
      return;
    }
    if (type != 'key') return;
    if (value == 'home') {
      await PcBridge.goHome();
      return;
    }
    final vk = _keys[value];
    if (vk != null) Win.press(vk);
  }
}

// ───────────────────────── score alerts ─────────────────────────

void _showAlert(Map a) {
  if (!Win.foyerInFront) return;
  final overlay = kNavKey.currentState?.overlay;
  if (overlay == null) return;
  final color = (a['color'] is int) ? Color(0xFF000000 | (a['color'] as int)) : const Color(0xFF1C7ED6);
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => Positioned(
      top: 40,
      right: 60,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 620,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.6)!]),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 14))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${a['emoji'] ?? ''}  ${a['event'] ?? ''}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 8),
              Text('${a['away'] ?? ''} ${a['awayScore'] ?? ''}  –  ${a['homeScore'] ?? ''} ${a['home'] ?? ''}',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white)),
              if ('${a['line'] ?? ''}'.isNotEmpty)
                Text('${a['line']}', style: const TextStyle(fontSize: 22, color: Colors.white70)),
            ]),
          ),
        ),
      ),
    ),
  );
  overlay.insert(e);
  Timer(const Duration(seconds: 9), () => e.remove());
}

// ───────────────────────── games ─────────────────────────

String? _first(List<String> paths) {
  for (final p in paths) {
    if (p.isNotEmpty && File(p).existsSync()) return p;
  }
  return null;
}

String? _retroArch() => _first([
      'C:\\RetroArch-Win64\\retroarch.exe',
      '${_env('APPDATA')}\\RetroArch\\retroarch.exe',
      '${_env('ProgramFiles')}\\RetroArch\\retroarch.exe',
      '${_env('ProgramFiles(x86)')}\\Steam\\steamapps\\common\\RetroArch\\retroarch.exe',
      '${_env('USERPROFILE')}\\scoop\\apps\\retroarch\\current\\retroarch.exe',
    ]);

String? _dolphin() => _first([
      '${_env('ProgramFiles')}\\Dolphin\\Dolphin.exe',
      '${_env('ProgramFiles')}\\Dolphin-x64\\Dolphin.exe',
      '${_env('LOCALAPPDATA')}\\Programs\\Dolphin\\Dolphin.exe',
      'C:\\Dolphin-x64\\Dolphin.exe',
      'C:\\Dolphin\\Dolphin.exe',
    ]);

int _gamePid = 0;

/// Opens a game full screen: RetroArch with the right core, or Dolphin for GameCube and Wii.
Future<String> launchGame(String path, String system, String core) async {
  await closeGame();
  await closeWebApps();
  try {
    if (system == 'gc') {
      final d = _dolphin();
      if (d == null) return 'missing:dolphin';
      final p = await Process.start(
          d, ['-b', '-C', 'Dolphin.Display.Fullscreen=True', '-e', path],
          mode: ProcessStartMode.detached);
      _gamePid = p.pid;
      return 'ok';
    }
    final ra = _retroArch();
    if (ra == null) return 'missing:retroarch';
    final dll = '${File(ra).parent.path}\\cores\\${core}_libretro.dll';
    if (!File(dll).existsSync()) return 'missing:core:$core';
    final p = await Process.start(ra, ['-f', '-L', dll, path], mode: ProcessStartMode.detached);
    _gamePid = p.pid;
    return 'ok';
  } catch (_) {
    return 'error';
  }
}

/// Closes the game Foyer opened (Back + Start on the controller, or Home).
Future<void> closeGame() async {
  final pid = _gamePid;
  if (pid == 0) return;
  _gamePid = 0;
  try {
    await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
  } catch (_) {}
}

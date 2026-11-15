import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:flutter/services.dart';
import 'aerial.dart';
import 'extras.dart';
import 'games.dart';
import 'glass.dart';
import 'idle.dart';
import 'keep.dart';
import 'plex.dart';
import 'qol.dart';
import 'screens.dart';
import 'seasons.dart';
import 'setup.dart';
import 'sounds.dart';
import 'search.dart';
import 'server.dart';
import 'sports.dart';
import 'sync.dart';
import 'update.dart';
import 'weather.dart';
import 'weatherfx.dart';
import 'videobg.dart';

const FoyerChannel kChannel = FoyerChannel('leclair/launcher');

/// Foyer for PC answers the native calls in Dart (lib/pc/bridge.dart); on Android this stays null.
typedef ChannelOverride = Future<dynamic> Function(String channel, String method, dynamic args);
ChannelOverride? kChannelOverride;

/// True when Foyer runs on a Windows PC (Foyer for PC).
bool kIsPc = false;

/// Foyer for PC's own Updates page (it updates from a zip, not an APK). Set by lib/pc.
Widget Function()? kPcUpdateScreen;

/// Foyer for PC: checks for and installs an update without asking (set by main_pc.dart).
Future<bool> Function(Settings)? kPcAutoUpdate;

/// Back to the home screen from anywhere (Home on a PC remote). Set by the app shell.
VoidCallback? kGoHome;

/// A MethodChannel that Foyer for PC can answer itself.
class FoyerChannel extends MethodChannel {
  const FoyerChannel(super.name);

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final o = kChannelOverride;
    if (o != null) return (await o(name, method, arguments)) as T?;
    return super.invokeMethod<T>(method, arguments);
  }

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    final o = kChannelOverride;
    if (o != null) {
      final r = await o(name, method, arguments);
      return r == null ? null : (r as List).cast<T>();
    }
    return super.invokeListMethod<T>(method, arguments);
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(String method, [dynamic arguments]) async {
    final o = kChannelOverride;
    if (o != null) {
      final r = await o(name, method, arguments);
      return r == null ? null : (r as Map).cast<K, V>();
    }
    return super.invokeMapMethod<K, V>(method, arguments);
  }
}
const int kMaxPinned = 8;
const Color kDefaultTint = Color(0xFF3B5BDB);
const String kPlexPackage = 'com.plexapp.android';

/// Pre-selected on first run if they're installed.
List<String> kSuggested = [
  'com.netflix.ninja',
  'com.amazon.amazonvideo.livingroom',
  'com.google.android.youtube.tv',
  kPlexPackage,
  'ca.bell.fiberemote',
  'com.apple.atve.amazon.appletv',
  'com.amazon.firetv.youtube',
  'com.disney.disneyplus',
  'ca.bellmedia.cravetv',
];
const List<String> kNameIdeas = ['Home', 'Living Room', 'Bedroom', 'Basement'];

/// Jiggle mode (hold OK on an app): the package being moved, or null.
final ValueNotifier<String?> kJiggle = ValueNotifier(null);

final Set<LogicalKeyboardKey> _selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

int? _build;
/// True on Amazon Fire TV devices, which need the Home button workaround and Amazon clean-up.
/// Other Android TV boxes (Google TV) let Foyer be the real home screen.
bool kIsFireTv = true;
String kDeviceModel = '';

/// Returns whether Home already lands on Foyer by itself (the stock launcher is off).
Future<bool> loadDevice() async {
  try {
    final m = await kChannel.invokeMapMethod<String, dynamic>('deviceInfo');
    kIsFireTv = m?['fireTv'] as bool? ?? true;
    kDeviceModel = '${m?['model'] ?? ''}';
    return m?['defaultHome'] as bool? ?? false;
  } catch (_) {
    return false;
  }
}

String? _buildName;
Future<void> _loadVersion() async {
  if (_build != null) return;
  try {
    final m = await kChannel.invokeMapMethod<String, dynamic>('appVersion');
    _build = (m?['code'] as num?)?.toInt() ?? 0;
    _buildName = (m?['name'] as String?) ?? '0';
  } catch (_) {
    _build = 0;
    _buildName = '0';
  }
}

Future<int> appBuild() async {
  await _loadVersion();
  return _build ?? 0;
}

Future<String> appName() async {
  await _loadVersion();
  return _buildName ?? '0';
}

int clampIdx(int i, int hi) => i < 0 ? 0 : (i > hi ? hi : i);

// ───────────────────────── settings ─────────────────────────

/// One person who watches this TV: their name, their apps and their teams.
class Profile {
  Profile(this.name, this.pinned, this.teams);
  final String name;
  final List<String> pinned;
  final List<FollowedTeam> teams;

  Map<String, dynamic> toJson() => {'name': name, 'pinned': pinned, 'teams': [for (final t in teams) t.toJson()]};

  static Profile? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['name'];
    if (n is! String || n.trim().isEmpty) return null;
    final p = j['pinned'];
    final t = j['teams'];
    return Profile(
      n.trim(),
      p is List ? p.whereType<String>().take(kMaxPinned).toList() : <String>[],
      t is List ? [for (final x in t) if (FollowedTeam.fromJson(x) != null) FollowedTeam.fromJson(x)!] : <FollowedTeam>[],
    );
  }
}

class Settings extends ChangeNotifier {
  String name = 'Home';
  bool liquid = false;
  bool clock24 = false;
  /// 'en' or 'fr' (Settings → Appearance → Language, or the first setup step)
  String _lang = 'en';
  String get lang => _lang;
  /// keep a copy of these settings on Foyer Drop, for other boxes to copy (sync.dart)
  bool syncOn = true;
  /// app logos in clear glass, the focused one in colour (Appearance → App icons)
  bool glassIcons = false;
  /// a muted looping clip behind the home screen (videobg.dart)
  bool videoOn = false;
  String videoUrl = '';
  /// install new versions by themselves, when nobody is using the TV
  bool autoUpdate = true;
  /// apps opened from Foyer, newest first (Back twice on home)
  List<String> recentApps = [];
  void noteRecent(String pkg) {
    if (pkg.isEmpty || pkg == kGamesTile) return;
    recentApps = [pkg, ...recentApps.where((p) => p != pkg)].take(8).toList();
    _persist();
  }
  set lang(String v) {
    final was = _lang;
    _lang = v == 'fr' ? 'fr' : 'en';
    kLang = _lang;
    if (was != _lang) makeGamesTileArt(); // the Games tile has its name painted in
  }
  List<String> pinned = [];
  bool setupDone = false;
  String plexToken = '';
  String plexUrl = '';
  String plexName = '';
  String clientId = '';
  // v5
  String weatherCity = '';
  double? weatherLat;
  double? weatherLon;
  bool weatherF = false;
  String wallMode = 'scenes'; // scenes | glow | preset | photo (new boxes start on the photo scenes)
  String wallValue = '';
  int ssMinutes = 5; // 0 = off
  String ssSource = 'colors'; // colors | mine | online | drop
  bool autoStart = true;
  bool perfMode = false;
  int soundLevel = 1; // 0 off, 1 quiet, 2 normal
  bool seasonal = true; // Halloween, Christmas, New Year and Easter looks
  int scoreAlerts = 2; // 0 off, 1 scores only, 2 scores + start + final
  bool dayLightOn = true; // background warms at sunset and dims at night
  bool devMode = false; // Developer options (press the version 7 times in Updates)
  String fireplaceUrl = ''; // YouTube video for the flame button ('' = Foyer's pick)
  int scoreDelay = 0; // seconds, to stay behind a delayed stream
  int scoreSize = 1; // alert pop-up: 0 small, 1 medium, 2 large
  bool weatherFx = true; // rain, snow and fog over the background when it's like that outside
  bool keepWatching = true; // the Keep watching row on the home screen
  bool gamesOnHome = true; // a Games tile at the start of the app row (once there are games)
  Map<String, int> gamesPlayed = {}; // game file -> when it was last played (ms)
  bool pcStoreApps = true; // Foyer for PC: open the Microsoft Store app when it's installed
  bool nowPlaying = true; // the song playing behind Foyer, first in that row
  List<String> keepHidden = []; // shows hidden from Keep watching ("package|title")
  List<String> keepHiddenApps = []; // apps hidden from Keep watching
  /// The people who watch this TV, each with their own apps and teams. Empty = just one.
  /// The active person's apps and teams live in `pinned` and `sportsTeams` while they're picked.
  List<Profile> profiles = [];
  int activeProfile = 0;
  // Smart idle
  bool idleOn = false;
  int idleMinutes = 30; // nothing pressed on the home screen for this long...
  String idleAction = 'clock'; // ...then: clock | screenoff | tvoff
  int pausedMinutes = 30; // a paused show or song turns the TV off after this (0 = never)
  bool quietHours = false; // 11 pm to 6 am: shorter waits

  /// Custom remote buttons: "313" = pressed, "313L" = held -> app package, "foyer" or "" (normal).
  Map<String, String> remoteKeys = {};
  /// Where updates come from. New boxes use your Foyer Drop server ("drop"): only TVs
  /// signed in to it can download Foyer, and no GitHub token is needed.
  String updateUrl = UpdateApi.dropSource;
  String updateToken = '';
  /// TMDB key for Search everything, typed in Developer options (else the one built in)
  String tmdbKey = '';
  List<FollowedTeam> sportsTeams = [];

  /// Apps kept off the phone page's "Open on TV" list.
  List<String> dropHidden = [];
  String serverUrl = '';
  String serverToken = '';

  /// The profiles with the active person's current apps and teams filled in.
  List<Profile> _profilesNow() => [
        for (var i = 0; i < profiles.length; i++)
          i == activeProfile ? Profile(profiles[i].name, [...pinned], [...sportsTeams]) : profiles[i]
      ];

  /// Who's watching ('' when there's only one person).
  String get personName => profiles.length > 1 ? profiles[activeProfile].name : '';

  void switchProfile(int i) {
    if (i == activeProfile || i < 0 || i >= profiles.length) return;
    profiles = _profilesNow();
    activeProfile = i;
    pinned = [...profiles[i].pinned];
    sportsTeams = [...profiles[i].teams];
    notifyListeners();
    _persist();
  }

  /// Adds someone. The first time, the person already using the TV becomes [firstName].
  void addPerson(String name, {String firstName = 'Me'}) {
    change(() {
      if (profiles.isEmpty) profiles = [Profile(firstName, [...pinned], [...sportsTeams])];
      profiles = [..._profilesNow(), Profile(name, [...pinned], [])];
    });
  }

  void renamePerson(int i, String name) => change(() {
        profiles = _profilesNow();
        profiles[i] = Profile(name, profiles[i].pinned, profiles[i].teams);
      });

  void removePerson(int i) => change(() {
        final all = _profilesNow()..removeAt(i);
        if (activeProfile >= all.length || i == activeProfile) activeProfile = 0;
        else if (i < activeProfile) activeProfile--;
        pinned = [...all[activeProfile].pinned];
        sportsTeams = [...all[activeProfile].teams];
        profiles = all.length > 1 ? all : []; // one person left: back to a plain TV
        if (profiles.isEmpty) activeProfile = 0;
      });

  void movePerson(int i, int dir) => change(() {
        final all = _profilesNow();
        final j = i + dir;
        if (j < 0 || j >= all.length) return;
        final x = all.removeAt(i);
        all.insert(j, x);
        if (activeProfile == i) {
          activeProfile = j;
        } else if (activeProfile == j) {
          activeProfile = i;
        }
        profiles = all;
      });

  bool follows(FollowedTeam t) => sportsTeams.any((x) => x.league == t.league && x.id == t.id);
  int countIn(String league) => sportsTeams.where((t) => t.league == league).length;
  void toggleTeam(FollowedTeam t) {
    if (follows(t)) {
      sportsTeams = sportsTeams.where((x) => !(x.league == t.league && x.id == t.id)).toList();
    } else {
      sportsTeams = [...sportsTeams, t];
    }
  }

  Map<String, dynamic> toJson({bool secrets = true}) => {
        'v': 5,
        'setupDone': setupDone,
        'name': name,
        'liquid': liquid,
        'clock24': clock24,
        'lang': lang,
        'syncOn': syncOn,
        'glassIcons': glassIcons,
        'videoOn': videoOn,
        'videoUrl': videoUrl,
        'autoUpdate': autoUpdate,
        'recentApps': recentApps,
        'pinned': pinned,
        'weatherCity': weatherCity,
        'weatherLat': weatherLat,
        'weatherLon': weatherLon,
        'weatherF': weatherF,
        'wallMode': wallMode,
        'wallValue': wallValue,
        'ssMinutes': ssMinutes,
        'ssSource': ssSource,
        'autoStart': autoStart,
        'perfMode': perfMode,
        'soundLevel': soundLevel,
        'seasonal': seasonal,
        'scoreAlerts': scoreAlerts,
        'dayLight': dayLightOn,
        'devMode': devMode,
        'fireplaceUrl': fireplaceUrl,
        'scoreDelay': scoreDelay,
        'alertSize': scoreSize,
        'weatherFx': weatherFx,
        'keepWatching': keepWatching,
        'pcStoreApps': pcStoreApps,
        'gamesOnHome': gamesOnHome,
        'gamesPlayed': gamesPlayed,
        'nowPlaying': nowPlaying,
        'keepHidden': keepHidden,
        'keepHiddenApps': keepHiddenApps,
        'profiles': [for (final x in _profilesNow()) x.toJson()],
        'activeProfile': activeProfile,
        'idleOn': idleOn,
        'idleMinutes': idleMinutes,
        'idleAction': idleAction,
        'pausedMinutes': pausedMinutes,
        'quietHours': quietHours,
        'remoteKeys': remoteKeys,
        'updateUrl': updateUrl,
        'sportsTeams': [for (final t in sportsTeams) t.toJson()],
        'serverUrl': serverUrl,
        'dropHidden': dropHidden,
        if (secrets) ...{
          'serverToken': serverToken,
          'plexToken': plexToken,
          'plexUrl': plexUrl,
          'plexName': plexName,
          'clientId': clientId,
          'updateToken': updateToken,
          'tmdbKey': tmdbKey,
        },
      };

  static String _s(Object? v, String d) => v is String ? v : d;
  static bool _b(Object? v, bool d) => v is bool ? v : d;

  void applyJson(Map<String, dynamic> j, {bool secrets = true}) {
    setupDone = _b(j['setupDone'], setupDone);
    final n = _s(j['name'], name).trim();
    if (n.isNotEmpty) name = n;
    liquid = _b(j['liquid'], liquid);
    clock24 = _b(j['clock24'], clock24);
    lang = _s(j['lang'], lang);
    syncOn = _b(j['syncOn'], syncOn);
    glassIcons = _b(j['glassIcons'], glassIcons);
    videoOn = _b(j['videoOn'], videoOn);
    videoUrl = _s(j['videoUrl'], videoUrl);
    autoUpdate = _b(j['autoUpdate'], autoUpdate);
    final ra = j['recentApps'];
    if (ra is List) recentApps = ra.whereType<String>().take(8).toList();
    final pin = j['pinned'];
    if (pin is List) {
      pinned = pin.whereType<String>().take(kMaxPinned).toList();
    } else if (pin is String) {
      pinned = pin.split(',').where((e) => e.isNotEmpty).toList();
    }
    weatherCity = _s(j['weatherCity'], weatherCity);
    final la = j['weatherLat'], lo = j['weatherLon'];
    weatherLat = la is num ? la.toDouble() : (j.containsKey('weatherLat') ? null : weatherLat);
    weatherLon = lo is num ? lo.toDouble() : (j.containsKey('weatherLon') ? null : weatherLon);
    weatherF = _b(j['weatherF'], weatherF);
    final wm = _s(j['wallMode'], wallMode);
    wallMode = (wm == 'preset' || wm == 'photo' || wm == 'scenes') ? wm : 'glow';
    wallValue = _s(j['wallValue'], wallValue);
    final ss = j['ssMinutes'];
    if (ss is num) ssMinutes = ss.toInt();
    final src = j['ssSource'];
    if (src is String && (src == 'mine' || src == 'online' || src == 'colors' || src == 'drop' || src == 'aerial')) {
      ssSource = src;
    } else if (j['ssPhotos'] == true) {
      ssSource = 'mine';
    }
    autoStart = _b(j['autoStart'], autoStart);
    perfMode = _b(j['perfMode'], perfMode);
    final sl = j['soundLevel'];
    if (sl is num) soundLevel = sl.toInt().clamp(0, 2).toInt();
    kSoundLevel = soundLevel;
    seasonal = _b(j['seasonal'], seasonal);
    dayLightOn = _b(j['dayLight'], dayLightOn);
    devMode = _b(j['devMode'], devMode);
    fireplaceUrl = _s(j['fireplaceUrl'], fireplaceUrl);
    kDayLight = dayLightOn;
    final sa = j['scoreAlerts'];
    if (sa is num) scoreAlerts = sa.toInt().clamp(0, 2).toInt();
    kScoreAlertLevel = scoreAlerts;
    final sd = j['scoreDelay'];
    if (sd is num) scoreDelay = sd.toInt().clamp(0, 120).toInt();
    kScoreAlertDelay = scoreDelay;
    final ss2 = j['alertSize'];
    if (ss2 is num) scoreSize = ss2.toInt().clamp(0, 2).toInt();
    kScoreAlertSize = scoreSize;
    weatherFx = _b(j['weatherFx'], weatherFx);
    keepWatching = _b(j['keepWatching'], keepWatching);
    pcStoreApps = _b(j['pcStoreApps'], pcStoreApps);
    gamesOnHome = _b(j['gamesOnHome'], gamesOnHome);
    final gp = j['gamesPlayed'];
    if (gp is Map) gamesPlayed = {for (final e in gp.entries) if (e.value is num) '${e.key}': (e.value as num).toInt()};
    nowPlaying = _b(j['nowPlaying'], nowPlaying);
    final kh = j['keepHidden'];
    if (kh is List) keepHidden = kh.whereType<String>().toList();
    final ka = j['keepHiddenApps'];
    if (ka is List) keepHiddenApps = ka.whereType<String>().toList();
    final pr = j['profiles'];
    if (pr is List) profiles = [for (final x in pr) if (Profile.fromJson(x) != null) Profile.fromJson(x)!];
    final ap = j['activeProfile'];
    if (ap is num) activeProfile = ap.toInt();
    if (activeProfile < 0 || activeProfile >= profiles.length) activeProfile = 0;
    idleOn = _b(j['idleOn'], idleOn);
    final im = j['idleMinutes'];
    if (im is num) idleMinutes = im.toInt().clamp(5, 240).toInt();
    final ia = j['idleAction'];
    if (ia == 'clock' || ia == 'screenoff' || ia == 'tvoff') idleAction = ia as String;
    final pm = j['pausedMinutes'];
    if (pm is num) pausedMinutes = pm.toInt().clamp(0, 240).toInt();
    quietHours = _b(j['quietHours'], quietHours);
    final rk = j['remoteKeys'];
    if (rk is Map) remoteKeys = {for (final e in rk.entries) '${e.key}': '${e.value}'};
    updateUrl = _s(j['updateUrl'], updateUrl);
    final st = j['sportsTeams'];
    if (st is List) {
      sportsTeams = [for (final x in st) if (FollowedTeam.fromJson(x) != null) FollowedTeam.fromJson(x)!];
    }
    serverUrl = _s(j['serverUrl'], serverUrl);
    final dh = j['dropHidden'];
    if (dh is List) dropHidden = dh.whereType<String>().toList();
    if (secrets) {
      serverToken = _s(j['serverToken'], serverToken);
      plexToken = _s(j['plexToken'], plexToken);
      plexUrl = _s(j['plexUrl'], plexUrl);
      plexName = _s(j['plexName'], plexName);
      clientId = _s(j['clientId'], clientId);
      updateToken = _s(j['updateToken'], updateToken);
      tmdbKey = _s(j['tmdbKey'], tmdbKey);
    }
  }

  Future<void> load() async {
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('loadSettings');
      if (m != null) {
        final raw = m['json'];
        if (raw is String && raw.isNotEmpty) {
          final d = jsonDecode(raw);
          if (d is Map) applyJson(Map<String, dynamic>.from(d));
        } else {
          // settings saved by an older version
          applyJson({
            'setupDone': m['setupDone'],
            'name': m['name'],
            'liquid': m['liquid'],
            'clock24': m['clock24'],
            'pinned': m['pinned'],
            'plexToken': m['plexToken'],
            'plexUrl': m['plexUrl'],
            'plexName': m['plexName'],
            'clientId': m['clientId'],
          });
        }
      }
    } catch (_) {}
    if (clientId.isEmpty) {
      final r = Random.secure();
      clientId = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _persist();
    }
    notifyListeners();
    syncSoon(this, soon: const Duration(minutes: 2)); // so the other boxes can see this one
  }

  Future<void> save({
    required String name,
    required bool liquid,
    required bool clock24,
    required List<String> pinned,
    required String plexToken,
    required String plexUrl,
    required String plexName,
  }) async {
    this.name = name;
    this.liquid = liquid;
    this.clock24 = clock24;
    this.pinned = pinned;
    this.plexToken = plexToken;
    this.plexUrl = plexUrl;
    this.plexName = plexName;
    setupDone = true;
    notifyListeners();
    await _persist();
  }

  void setPinned(List<String> p) {
    pinned = p;
    notifyListeners();
    _persist();
  }

  /// Run a mutation, then rebuild listeners and save.
  void change(VoidCallback fn) {
    fn();
    notifyListeners();
    _persist();
  }

  /// Settings > Backup and updates > Reset for someone new: forget everything personal
  /// (name, apps, Plex, Foyer Drop, teams, remote buttons, tokens) and open the welcome
  /// setup on the next start. The TV-level setup (Foyer as home screen, debugging trust,
  /// remote helper, tune-up) stays, so the next person doesn't have to redo it.
  Future<void> resetForSomeoneNew() async {
    final fresh = Settings();
    applyJson(fresh.toJson(secrets: true), secrets: true);
    remoteKeys = {};
    sportsTeams = [];
    pinned = [];
    dropHidden = [];
    serverUrl = '';
    serverToken = '';
    updateUrl = UpdateApi.dropSource;
    updateToken = '';
    final r = Random.secure();
    clientId = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    setupDone = false;
    try {
      await kChannel.invokeMethod('dropConfig', {'url': '', 'token': ''});
    } catch (_) {}
    notifyListeners();
    await _persist();
  }

  /// Apply a backup file. Plex sign-in and client id stay as they are on this TV.
  void restore(Map<String, dynamic> j) {
    applyJson(j, secrets: false);
    setupDone = true;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      await kChannel.invokeMethod('saveSettings', {'json': jsonEncode(toJson())});
    } catch (_) {}
    syncSoon(this);
  }
}

class SettingsScope extends InheritedNotifier<Settings> {
  SettingsScope({super.key, required Settings settings, required super.child})
      : super(notifier: settings);

  /// Listens for changes (use inside build).
  static Settings of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

  /// Reads once, no rebuilds (use outside build).
  static Settings read(BuildContext c) =>
      c.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}

Future<bool> launchPackage(String pkg) async {
  final ok = (await kChannel.invokeMethod<bool>('launch', {'package': pkg})) ?? false;
  final ctx = kNavKey.currentContext;
  if (ok && ctx != null) SettingsScope.read(ctx).noteRecent(pkg);
  return ok;
}

// ───────────────────────── app shell ─────────────────────────

final GlobalKey<NavigatorState> kNavKey = GlobalKey<NavigatorState>();
const FoyerChannel kNavChannel = FoyerChannel('leclair/nav');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  installUiSounds();
  runApp(SettingsScope(settings: Settings(), child: const LauncherApp()));
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: kNavKey,
        debugShowCheckedModeBanner: false,
        title: 'Foyer TV',
        // Plus Jakarta Sans everywhere (fonts/, added to the project by tools/patch_fonts.py)
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: 'PlusJakartaSans'),
        // Design on a fixed 1920x1080 canvas and scale it to the real screen.
        builder: (context, child) => _LangHost(
          child: ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: 1920, height: 1080, child: child),
            ),
          ),
        ),
        home: const Root(),
      );
}

/// Rebuilds the words on every page when the language changes.
class _LangHost extends StatelessWidget {
  const _LangHost({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LangScope(lang: SettingsScope.of(context).lang, child: child);
}

enum _Mode { home, hub }

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _ready = false;
  _Mode _mode = _Mode.home;

  @override
  void initState() {
    super.initState();
    void goHome() {
      kNavKey.currentState?.popUntil((r) => r.isFirst);
      if (mounted) setState(() => _mode = _Mode.home);
    }

    kGoHome = goHome;
    kNavChannel.setMethodCallHandler((call) async {
      if (call.method == 'goHome') goHome();
    });
    Future.wait([SettingsScope.read(context).load(), loadDevice()]).then((_) {
      if (mounted) setState(() => _ready = true);
      // goal pop-ups, also while another app is playing
      if (mounted) kScoreAlerts.start(() => SettingsScope.read(context));
      // let the background follow the time of day
      Timer.periodic(const Duration(minutes: 5), (_) => kDayTick.value++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    if (!_ready) return const ColoredBox(color: Colors.black);
    // The step-by-step setup only runs once. After that each part lives in Settings.
    if (!s.setupDone) {
      return FirstRunSetup(onDone: () => setState(() => _mode = _Mode.home));
    }
    if (_mode == _Mode.hub) {
      return SettingsHub(onClose: () => setState(() => _mode = _Mode.home));
    }
    return HomeScreen(onOpenSettings: () => setState(() => _mode = _Mode.hub));
  }
}

// ───────────────────────── shared widgets ─────────────────────────

class InstalledApp {
  InstalledApp(this.package, this.label, this.icon);
  final String package;
  final String label;
  final Uint8List icon;
}

Future<List<InstalledApp>> fetchInstalledApps() async {
  try {
    final raw = await kChannel.invokeListMethod<Map>('listApps');
    return (raw ?? const [])
        .map((m) => InstalledApp(
            m['package'] as String, m['label'] as String, m['icon'] as Uint8List))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Frosted glass. Simple = gradient + border. Liquid = real backdrop blur + rim light.
class Glass extends StatelessWidget {
  const Glass(
      {super.key,
      required this.child,
      this.radius = 32,
      this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      this.liquid});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool? liquid; // null = follow the saved setting

  @override
  Widget build(BuildContext context) {
    final cfg = SettingsScope.of(context);
    final wantLiquid = liquid ?? cfg.liquid;
    final r = BorderRadius.circular(radius);

    if (!wantLiquid) {
      // Simple glass: a flat, matte, slightly dark panel. No blur, no shine.
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: r,
          color: const Color(0x8C12141C),
          border: Border.all(color: Colors.white.withAlpha(46), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 14, offset: const Offset(0, 6))
          ],
        ),
        child: child,
      );
    }

    // Liquid glass: frosted blur, a diagonal sheen, a glow along the top and a bright rim.
    // Performance mode keeps the look but skips the blur, which is the expensive part.
    final panel = CustomPaint(
      foregroundPainter: _RimPainter(radius),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withAlpha(96),
              Colors.white.withAlpha(30),
              Colors.white.withAlpha(12),
              Colors.white.withAlpha(52),
            ],
            stops: const [0, 0.32, 0.68, 1],
          ),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withAlpha(46), Colors.white.withAlpha(0)],
            stops: const [0, 0.42],
          ),
        ),
        child: child,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: [
        BoxShadow(
            color: Colors.black.withAlpha(96), blurRadius: 30, offset: const Offset(0, 14))
      ]),
      child: cfg.perfMode
          ? panel
          : ClipRRect(
              borderRadius: r,
              child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: panel)),
    );
  }
}

/// The bright edge of liquid glass: strong at the top-left, fading, then catching light again
/// at the bottom-right.
class _RimPainter extends CustomPainter {
  const _RimPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.9), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xE6FFFFFF), Color(0x33FFFFFF), Color(0x1AFFFFFF), Color(0x99FFFFFF)],
        stops: [0, 0.35, 0.7, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => old.radius != radius;
}

/// Wallpaper: dark base with two soft glows that take the given tint.
// ───────────────────────── light that follows the day ─────────────────────────

/// Settings > Appearance > Light follows the day.
bool kDayLight = true;

/// Bumped every few minutes so backdrops pick up the new time of day.
final ValueNotifier<int> kDayTick = ValueNotifier(0);

const Color _kSunset = Color(0xFFFF8A3D);

/// How warm (0..1) and how dim (0..1) the background is at this time of day.
/// Bright and neutral by day, warm around sunrise and sunset, dim late at night.
(double, double) dayLight(DateTime t) {
  if (!kDayLight) return (0.0, 0.0);
  const keys = <List<double>>[
    [0, 0.10, 0.55],
    [5.5, 0.10, 0.55],
    [7, 0.25, 0.15],
    [9, 0.0, 0.0],
    [16.5, 0.0, 0.0],
    [18.5, 0.45, 0.05],
    [20, 0.30, 0.25],
    [22.5, 0.15, 0.45],
    [24, 0.10, 0.55],
  ];
  final h = t.hour + t.minute / 60.0;
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i], b = keys[i + 1];
    if (h >= a[0] && h <= b[0]) {
      final f = (h - a[0]) / (b[0] - a[0]);
      return (a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f);
    }
  }
  return (0.0, 0.0);
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.tint});
  final Color tint;

  Widget _glow(Alignment a, Color c, double size) => Align(
        alignment: a,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [c.withAlpha(0x70), c.withAlpha(0)])),
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: kDayTick,
        builder: (_, __, ___) => _build(context),
      );

  Widget _build(BuildContext context) {
    final (warmth, dim) = dayLight(DateTime.now());
    final shown = Color.lerp(tint, _kSunset, warmth)!;
    final body = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: shown),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (_, c, __) {
        final t = c ?? tint;
        final hsv = HSVColor.fromColor(t);
        final t2 = hsv.withHue((hsv.hue + 45) % 360).toColor();
        return DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                const Color(0xFF05060C),
                Color.lerp(const Color(0xFF0A0D1C), t, 0.18)!,
                const Color(0xFF05060C)
              ])),
          child: Stack(children: [
            _glow(const Alignment(-0.8, -0.7), t, 1000),
            _glow(const Alignment(0.9, 0.3), t2, 850),
          ]),
        );
      },
    );
    if (dim <= 0.01) return body;
    return Stack(fit: StackFit.expand, children: [
      body,
      // late at night the background dims down (text and tiles stay bright)
      IgnorePointer(child: ColoredBox(color: Colors.black.withAlpha((dim * 255).round()))),
    ]);
  }
}

/// Anything the remote can focus. Select (on release) activates; holding Select long-presses.
class FocusButton extends StatefulWidget {
  const FocusButton(
      {super.key,
      required this.onSelect,
      required this.builder,
      this.onLongPress,
      this.autofocus = false,
      this.scale = 1.05,
      this.scrollIntoView = false,
      this.focusNode,
      this.onFocusChange});
  final double scale;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback onSelect;
  final VoidCallback? onLongPress;
  final Widget Function(BuildContext context, bool focused) builder;
  final bool autofocus;
  final bool scrollIntoView;
  @override
  State<FocusButton> createState() => _FocusButtonState();
}

class _FocusButtonState extends State<FocusButton> {
  bool _f = false;
  bool _down = false;
  bool _long = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _f = f);
        widget.onFocusChange?.call(f);
        if (f && widget.scrollIntoView) {
          Scrollable.ensureVisible(context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
        }
      },
      onKeyEvent: (_, e) {
        if (!_selectKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
        if (e is KeyDownEvent) {
          _down = true;
          _long = false;
        } else if (e is KeyRepeatEvent) {
          if (_down && !_long && widget.onLongPress != null) {
            _long = true;
            widget.onLongPress!();
          }
        } else if (e is KeyUpEvent) {
          final fire = _down && !_long;
          _down = false;
          _long = false;
          if (fire) widget.onSelect();
        }
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _f ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: widget.builder(context, _f),
        ),
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton(
      {super.key,
      required this.label,
      required this.onSelect,
      this.primary = false,
      this.autofocus = false});
  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => FocusButton(
        onSelect: onSelect,
        autofocus: autofocus,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            color: f
                ? Colors.white
                : (primary ? Colors.white.withAlpha(60) : Colors.white.withAlpha(22)),
            border: Border.all(color: Colors.white.withAlpha(f ? 255 : 80), width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: f ? Colors.black : Colors.white)),
        ),
      );
}

/// Small rounded choice (names, 12/24-hour).
class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label, required this.selected, required this.onSelect});
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) => FocusButton(
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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

/// App icon + name card used in the setup picker and the All Apps screen.
class AppChip extends StatelessWidget {
  const AppChip(
      {super.key,
      required this.app,
      required this.selected,
      required this.onSelect,
      this.onLongPress,
      this.badge,
      this.autofocus = false});
  final InstalledApp app;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onLongPress;
  final Widget? badge;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        onSelect: onSelect,
        onLongPress: onLongPress,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 200,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: selected ? Colors.white.withAlpha(50) : Colors.white.withAlpha(16),
            border: Border.all(
                color: f ? Colors.white : Colors.white.withAlpha(selected ? 150 : 40),
                width: f ? 3 : 1.5),
          ),
          child: Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(app.icon, width: 64, height: 64, gaplessPlayback: true)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22)),
                ),
              ]),
            ),
            if (badge != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration:
                        const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: badge),
              ),
          ]),
        ),
      );
}

class MenuChoice {
  MenuChoice(this.label, this.onSelect);
  final String label;
  final VoidCallback? onSelect;
}

/// Small glass popup of choices.
Future<void> showMenu2(BuildContext context, String title, List<MenuChoice> items) {
  return showDialog<void>(
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
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SizedBox(
                  width: 520,
                  child: items[i].onSelect == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(items[i].label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 24, color: Colors.white70)))
                      : FocusButton(
                          autofocus: i == 0,
                          onSelect: () {
                            Navigator.of(ctx).pop();
                            items[i].onSelect!();
                          },
                          builder: (_, f) => AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              color: f ? Colors.white : Colors.white.withAlpha(22),
                              border: Border.all(
                                  color: Colors.white.withAlpha(f ? 255 : 70)),
                            ),
                            child: Text(items[i].label,
                                style: TextStyle(
                                    fontSize: 28, color: f ? Colors.black : Colors.white)),
                          ),
                        ),
                ),
              ),
          ]),
        ),
      ),
    ),
  );
}

// ───────────────────────── setup ─────────────────────────

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.firstRun, required this.onDone, this.only});
  final bool firstRun;
  final int? only; // edit just this step from Settings
  final VoidCallback onDone;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const int kSteps = 6;
  int _step = 0;
  late final TextEditingController _name;
  late bool _liquid;
  late bool _clock24;
  late List<String> _pinned;
  List<InstalledApp> _installed = const [];
  bool _loadingApps = true;

  // plex
  late String _plexToken;
  late String _plexUrl;
  late String _plexName;
  PlexPin? _pin;
  Timer? _poll;
  String _plexMsg = '';

  // home button
  bool _hkEnabled = false;
  bool _hkCanEnable = false;

  @override
  void initState() {
    super.initState();
    final s = SettingsScope.read(context);
    _step = widget.only ?? 0;
    _name = TextEditingController(text: s.name);
    _liquid = s.liquid;
    _clock24 = s.clock24;
    _pinned = [...s.pinned];
    _plexToken = s.plexToken;
    _plexUrl = s.plexUrl;
    _plexName = s.plexName;
    _loadApps();
    _refreshHomeKey();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await fetchInstalledApps();
    if (!mounted) return;
    setState(() {
      _installed = apps;
      _loadingApps = false;
      if (_pinned.isEmpty) {
        final have = apps.map((a) => a.package).toSet();
        _pinned = kSuggested.where(have.contains).toList();
      }
    });
  }

  Future<void> _refreshHomeKey() async {
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('homeKeyStatus');
      if (!mounted || m == null) return;
      setState(() {
        _hkEnabled = m['enabled'] as bool? ?? false;
        _hkCanEnable = m['canEnable'] as bool? ?? false;
      });
    } catch (_) {}
    if (!kIsFireTv) _refreshIsHome();
  }


  Future<void> _setHomeKey(bool on) async {
    try {
      await kChannel.invokeMethod('setHomeKey', {'enabled': on});
    } catch (_) {}
    await _refreshHomeKey();
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
    _pin = null;
  }

  void _back() {
    _stopPoll();
    if (widget.only != null) {
      widget.onDone();
      return;
    }
    if (_step > 0) {
      setState(() => _step--);
    } else if (!widget.firstRun) {
      widget.onDone();
    }
  }

  void _next() {
    _stopPoll();
    if (widget.only == null && _step < kSteps - 1) {
      setState(() => _step++);
      if (_step == 4) _refreshHomeKey();
      return;
    }
    final n = _name.text.trim();
    SettingsScope.read(context).save(
      name: n.isEmpty ? 'Home' : n,
      liquid: _liquid,
      clock24: _clock24,
      pinned: _pinned,
      plexToken: _plexToken,
      plexUrl: _plexUrl,
      plexName: _plexName,
    );
    widget.onDone();
  }

  void _toggle(String pkg) {
    setState(() {
      if (_pinned.contains(pkg)) {
        _pinned.remove(pkg);
      } else if (_pinned.length < kMaxPinned) {
        _pinned.add(pkg);
      }
    });
  }

  Future<void> _startPlexLink() async {
    final api = PlexApi(SettingsScope.read(context).clientId);
    setState(() => _plexMsg = 'Contacting plex.tv…');
    try {
      final pin = await api.startPin();
      if (!mounted) return;
      setState(() {
        _pin = pin;
        _plexMsg = '';
      });
      var tries = 0;
      _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
        tries++;
        if (tries > 300) {
          _stopPoll();
          if (mounted) setState(() => _plexMsg = 'The code expired. Try again.');
          return;
        }
        try {
          final token = await api.checkPin(pin.id);
          if (token == null || !mounted || _pin == null) return;
          _stopPoll();
          setState(() => _plexMsg = 'Linked. Looking for your server…');
          final server = await api.findServer(token);
          if (!mounted) return;
          setState(() {
            if (server == null) {
              _plexMsg = 'Linked, but no reachable Plex server was found on your account.';
            } else {
              _plexToken = server.token;
              _plexUrl = server.baseUrl;
              _plexName = server.name;
              _plexMsg = '';
            }
          });
        } catch (_) {}
      });
    } catch (_) {
      if (mounted) {
        setState(() => _plexMsg = 'Could not reach plex.tv. Check the internet connection and try again.');
      }
    }
  }

  void _unlinkPlex() => setState(() {
        _plexToken = '';
        _plexUrl = '';
        _plexName = '';
        _plexMsg = '';
      });

  static const _titles = [
    'Name your home',
    'Choose a glass style',
    'Pin your apps',
    'Plex row',
    'Home button',
    'Sports scores',
  ];
  static const _subs = [
    'This shows in the welcome message on your home screen.',
    'Liquid glass blurs the wallpaper behind each panel. It looks best, but can stutter on slower TV boxes.',
    'Pick up to $kMaxPinned apps for your home screen. They appear in the order you select them.',
    'Optional. Show Continue Watching from your Plex server on the home screen.',
    'Make the Home button on your remote open Foyer instead of the TV\'s own home screen.',
    'Optional. Pick the teams you follow and their live scores show on your home screen.',
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          const Positioned.fill(child: RepaintBoundary(child: Backdrop(tint: kDefaultTint))),
          Padding(
            padding: const EdgeInsets.fromLTRB(160, 90, 160, 70),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.only == null) ...[
                Text('Step ${_step + 1} of $kSteps',
                    style: const TextStyle(fontSize: 24, color: Colors.white54)),
                const SizedBox(height: 10),
              ],
              Text(_titles[_step],
                  style: const TextStyle(
                      fontSize: 68, fontWeight: FontWeight.w700, letterSpacing: -1)),
              const SizedBox(height: 12),
              SizedBox(
                  width: 1300,
                  child: Text(_subs[_step],
                      style: const TextStyle(fontSize: 28, color: Colors.white70))),
              const SizedBox(height: 40),
              Expanded(child: _stepBody()),
              const SizedBox(height: 24),
              _footer(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _footer() => Row(children: [
        if (_step > 0 || !widget.firstRun)
          PillButton(
              key: ValueKey('back$_step'),
              label: (_step > 0 && widget.only == null) ? 'Back' : 'Cancel',
              onSelect: _back),
        const Spacer(),
        if (_step == 2)
          Padding(
            padding: const EdgeInsets.only(right: 32),
            child: Text('${_pinned.length} of $kMaxPinned selected',
                style: const TextStyle(fontSize: 26, color: Colors.white70)),
          ),
        PillButton(
            key: ValueKey('next$_step'),
            label: widget.only != null ? 'Save' : (_step == kSteps - 1 ? 'Done' : 'Next'),
            primary: true,
            autofocus: _step == 0,
            onSelect: _next),
      ]);

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _nameStep();
      case 1:
        return _glassStep();
      case 2:
        return _appsStep();
      case 3:
        return _plexStep();
      case 4:
        return _homeKeyStep();
      default:
        return _sportsStep();
    }
  }

  Widget _sportsStep() {
    final s = SettingsScope.of(context);
    final names = s.sportsTeams.map((t) => t.league == 'f1' ? 'Formula 1' : t.name).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 20, runSpacing: 20, children: [
          for (final l in kLeagues)
            _Choice(
                label: l.key == 'f1'
                    ? (s.follows(FollowedTeam.f1) ? 'Formula 1: on' : 'Formula 1')
                    : (s.countIn(l.key) > 0 ? '${l.label} · ${s.countIn(l.key)}' : l.label),
                selected: l.key == 'f1' ? s.follows(FollowedTeam.f1) : s.countIn(l.key) > 0,
                onSelect: () async {
                  if (l.key == 'f1') {
                    s.change(() => s.toggleTeam(FollowedTeam.f1));
                  } else {
                    await Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => SportsTeamsScreen(league: l)));
                    if (mounted) setState(() {});
                  }
                }),
        ]),
        const SizedBox(height: 28),
        SizedBox(
            width: 1300,
            child: Text(
                names.isEmpty ? 'No teams yet. You can skip this and add them later in Settings.' : 'Following: ${names.join(', ')}',
                style: const TextStyle(fontSize: 26, color: Colors.white70))),
      ]),
    );
  }

  Widget _label(String t) =>
      Text(t, style: const TextStyle(fontSize: 24, color: Colors.white54));

  Widget _nameStep() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FocusButton(
          autofocus: true,
          onSelect: () async {
            final v = await askText(context, 'Name your home', _name.text,
                hint: 'Home', maxLength: 24);
            if (v != null && v.isNotEmpty) setState(() => _name.text = v);
          },
          builder: (_, f) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 900,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: f ? Colors.white : Colors.white.withAlpha(24),
              border: Border.all(color: Colors.white.withAlpha(f ? 255 : 80), width: f ? 3 : 1.5),
            ),
            child: Row(children: [
              Expanded(
                child: Text(_name.text.isEmpty ? 'Home' : _name.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        color: f ? Colors.black : Colors.white)),
              ),
              Icon(Icons.edit_rounded, size: 40, color: f ? Colors.black54 : Colors.white54),
            ]),
          ),
        ),
        const SizedBox(height: 28),
        _label('Or pick one:'),
        const SizedBox(height: 14),
        Wrap(spacing: 20, runSpacing: 20, children: [
          for (final n in kNameIdeas)
            _Choice(
                label: n,
                selected: false,
                onSelect: () => setState(() => _name.text = n)),
        ]),
        const SizedBox(height: 28),
        _label('Clock:'),
        const SizedBox(height: 14),
        Row(children: [
          _Choice(
              label: '12-hour',
              selected: !_clock24,
              onSelect: () => setState(() => _clock24 = false)),
          const SizedBox(width: 20),
          _Choice(
              label: '24-hour',
              selected: _clock24,
              onSelect: () => setState(() => _clock24 = true)),
        ]),
      ]);

  Widget _glassStep() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _glassCard(false, 'Simple glass', 'Smooth everywhere. A flat, matte panel with no blur or shine.'),
        const SizedBox(width: 48),
        _glassCard(true, 'Liquid glass',
            'Frosted blur with a bright rim and a sheen. Prettiest, heavier on the GPU.'),
      ]);

  Widget _glassCard(bool liquid, String title, String body) {
    final selected = _liquid == liquid;
    return FocusButton(
      autofocus: selected,
      onSelect: () => setState(() => _liquid = liquid),
      builder: (_, f) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 620,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(46),
            border: Border.all(
                color: f ? Colors.white : (selected ? Colors.white54 : Colors.transparent),
                width: 3)),
        child: Glass(
          liquid: liquid,
          radius: 40,
          padding: const EdgeInsets.all(36),
          child: SizedBox(
            height: 230,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700))),
                if (selected) const Icon(Icons.check_circle_rounded, size: 42),
              ]),
              const SizedBox(height: 16),
              Text(body, style: const TextStyle(fontSize: 26, color: Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _appsStep() {
    if (_loadingApps) {
      return const Align(
          alignment: Alignment.topLeft,
          child: Text('Looking for your apps…',
              style: TextStyle(fontSize: 30, color: Colors.white70)));
    }
    if (_installed.isEmpty) {
      return const Text('No apps found.', style: TextStyle(fontSize: 30));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 20, runSpacing: 20, children: [
        for (var i = 0; i < _installed.length; i++)
          Builder(builder: (_) {
            final a = _installed[i];
            final order = _pinned.indexOf(a.package);
            return AppChip(
              app: a,
              autofocus: i == 0,
              selected: order >= 0,
              badge: order >= 0
                  ? Text('${order + 1}',
                      style: const TextStyle(
                          color: Colors.black, fontSize: 22, fontWeight: FontWeight.w700))
                  : null,
              onSelect: () => _toggle(a.package),
            );
          }),
      ]),
    );
  }

  Widget _plexStep() {
    final linked = _plexToken.isNotEmpty && _plexUrl.isNotEmpty;
    const body = TextStyle(fontSize: 28, color: Colors.white70);
    if (linked) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Linked to $_plexName', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('What you\'re watching in Plex shows up in Keep watching on the home screen.', style: body),
        const SizedBox(height: 32),
        PillButton(label: 'Unlink', autofocus: true, onSelect: _unlinkPlex),
      ]);
    }
    if (_pin != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('On your phone or computer, open plex.tv/link and enter:', style: body),
        const SizedBox(height: 20),
        Glass(
          radius: 40,
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 24),
          child: Text(_pin!.code.split('').join(' '),
              style: const TextStyle(fontSize: 110, fontWeight: FontWeight.w700, letterSpacing: 6)),
        ),
        const SizedBox(height: 16),
        const Text('Waiting for you to enter the code…', style: body),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PillButton(label: 'Link Plex account', autofocus: true, onSelect: _startPlexLink),
      const SizedBox(height: 24),
      if (_plexMsg.isNotEmpty) Text(_plexMsg, style: body),
      if (_plexMsg.isEmpty) const Text('Select Next to skip this.', style: body),
    ]);
  }

  bool _isHome = false;

  Future<void> _refreshIsHome() async {
    final h = await loadDevice();
    if (mounted) setState(() => _isHome = h);
  }

  String _gMsg = '';
  bool _gBusy = false;

  /// Google's home, and Google's setup app. The setup app must go too: with Google's
  /// home off, its recovery screen can grab Home and crash-loop the Streamer.
  /// (It also holds the saved Wi-Fi, so the TV may need Wi-Fi picked again once.)
  static const _stockHome = [
    'com.google.android.apps.tv.launcherx',
    'com.google.android.tungsten.setupwraith',
  ];

  Future<void> _openTvSettings(String page) async {
    try {
      await kChannel.invokeMethod<bool>('openSettings', {'page': page});
    } catch (_) {}
  }

  /// One press: Foyer uses the TV's own debugging link to switch the stock home screen off.
  Future<void> _takeOver({bool undo = false}) async {
    if (_gBusy) return;
    setState(() {
      _gBusy = true;
      _gMsg = 'Working… If the TV asks to allow debugging, choose Always allow.';
    });
    final err = await adbQuick([
      if (!undo) 'pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS',
      // lets the remote helper switch on (Android blocks it for apps updated from an APK file)
      if (!undo) 'appops set com.leclair.leclair_home ACCESS_RESTRICTED_SETTINGS allow',
      // lets TV settings > Bluetooth work right away
      if (!undo) 'pm grant com.leclair.leclair_home android.permission.BLUETOOTH_SCAN',
      if (!undo) 'pm grant com.leclair.leclair_home android.permission.BLUETOOTH_CONNECT',
      for (final p in _stockHome) undo ? 'pm enable $p' : 'pm disable-user --user 0 $p',
      // make Foyer the chosen home app
      if (!undo) 'cmd package set-home-activity com.leclair.leclair_home/.MainActivity',
    ]);
    // the remote helper brings back the YouTube button, which only Google's home answered
    if (err == null && !undo) {
      try {
        await kChannel.invokeMethod<bool>('setHomeKey', {'enabled': true});
      } catch (_) {}
    }
    final home = await loadDevice();
    if (!mounted) return;
    setState(() {
      _gBusy = false;
      _isHome = home;
      if (err != null) {
        _gMsg = err;
      } else if (undo) {
        _gMsg = 'The TV\'s own home screen is back on.';
      } else {
        _gMsg = home
            ? 'Done. The Home button now opens Foyer.'
            : 'Almost there. Press Home on the remote; if the TV asks which home app to use, pick Foyer TV and Always.';
      }
    });
    _refreshHomeKey();
  }

  /// Google TV and other Android TV boxes: the stock home screen can simply be switched off.
  Widget _googleHomeStep() {
    const body = TextStyle(fontSize: 26, color: Colors.white70);
    Widget line(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(width: 1300, child: Text('$n   $t', style: body)),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isHome ? 'Foyer is your home screen.' : 'Make Foyer the home screen',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_isHome) ...[
          const SizedBox(
              width: 1300,
              child: Text('The Home button opens Foyer directly. Nothing else to do.', style: body)),
          const SizedBox(height: 20),
          Wrap(spacing: 16, runSpacing: 16, children: [
            PillButton(label: 'Check again', autofocus: true, onSelect: _refreshIsHome),
            PillButton(label: 'Bring back the TV\'s own home screen', onSelect: () => _takeOver(undo: true)),
          ]),
        ] else ...[
          line('1', 'Open About and press "Android TV OS build" 7 times, until it says you are a developer.'),
          line('2', 'Open Developer options and turn on USB debugging.'),
          line('3', 'Come back here and press Make Foyer the home screen. Choose Always allow if the TV asks.'),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 16, children: [
            PillButton(label: '1  Open About', autofocus: true, onSelect: () => _openTvSettings('about')),
            PillButton(label: '2  Open Developer options', onSelect: () => _openTvSettings('developer')),
            PillButton(label: '3  Make Foyer the home screen', primary: true, onSelect: _takeOver),
          ]),
          const SizedBox(height: 26),
          const SizedBox(
              width: 1300,
              child: Text(
                  'Would rather not turn on debugging? The Home button service catches the Home key instead. It works, with a brief flash of the TV\'s own home screen now and then.',
                  style: TextStyle(fontSize: 22, color: Colors.white54))),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 16, children: [
            if (_hkEnabled)
              PillButton(label: 'Home button service: on (turn off)', onSelect: () => _setHomeKey(false))
            else if (_hkCanEnable)
              PillButton(label: 'Turn on the Home button service', onSelect: () => _setHomeKey(true))
            else
              PillButton(
                  label: 'Open Accessibility, then turn on "Foyer Home button"',
                  onSelect: () => _openTvSettings('accessibility')),
            PillButton(label: 'Check again', onSelect: () {
              _refreshHomeKey();
            }),
          ]),
        ],
        const SizedBox(height: 20),
        SizedBox(width: 1300, child: Text(_gMsg, style: body)),
      ]),
    );
  }

  Widget _homeKeyStep() {
    if (!kIsFireTv) return _googleHomeStep();
    const body = TextStyle(fontSize: 26, color: Colors.white70);
    const mono = TextStyle(fontSize: 22, fontFamily: 'monospace');
    Widget cmd(String t) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(18)),
          child: Text(t, style: mono),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_hkEnabled ? 'The Home button service is on.' : 'Home button service',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const SizedBox(
            width: 1300,
            child: Text(
                'Fire OS does not allow Amazon\'s home screen to be turned off. Instead, Foyer watches for it and brings itself back to the front, and it also catches the Home key. Double-press Home to reach Amazon\'s home when you want it.',
                style: body)),
        const SizedBox(height: 22),
        if (_hkEnabled)
          PillButton(label: 'Turn off', autofocus: true, onSelect: () => _setHomeKey(false))
        else if (_hkCanEnable)
          PillButton(label: 'Turn on', primary: true, autofocus: true, onSelect: () => _setHomeKey(true))
        else ...[
          const Text('One-time permission. Run this on your computer, then choose Check again:', style: body),
          const SizedBox(height: 10),
          cmd('adb shell pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS'),
          const SizedBox(height: 16),
          PillButton(label: 'Check again', autofocus: true, onSelect: _refreshHomeKey),
        ],
      ]),
    );
  }
}

// ───────────────────────── all apps ─────────────────────────

class AllAppsScreen extends StatefulWidget {
  const AllAppsScreen({super.key});
  @override
  State<AllAppsScreen> createState() => _AllAppsScreenState();
}

class _AllAppsScreenState extends State<AllAppsScreen> {
  List<InstalledApp> _apps = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    fetchInstalledApps().then((a) {
      if (mounted) {
        setState(() {
          _apps = a;
          _loading = false;
        });
      }
    });
  }

  void _pinMenu(InstalledApp a) {
    final s = SettingsScope.read(context);
    final pinned = s.pinned.contains(a.package);
    final full = !pinned && s.pinned.length >= kMaxPinned;
    showMenu2(context, a.label, [
      if (pinned)
        MenuChoice('Remove from home', () => removeFromHome(context, a.package, a.label))
      else if (full)
        MenuChoice('Home screen is full ($kMaxPinned apps)', null)
      else
        MenuChoice('Pin to home', () => s.setPinned([...s.pinned, a.package])),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pinned = SettingsScope.of(context).pinned;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        const Positioned.fill(child: RepaintBoundary(child: Backdrop(tint: kDefaultTint))),
        Padding(
          padding: const EdgeInsets.fromLTRB(120, 80, 120, 60),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('All apps',
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w700, letterSpacing: -1)),
            const SizedBox(height: 10),
            const Text('Select to open. Hold Select to pin or unpin. Up from the top row goes back home.',
                style: TextStyle(fontSize: 26, color: Colors.white70)),
            const SizedBox(height: 32),
            Expanded(
              child: _loading
                  ? const Text('Loading…', style: TextStyle(fontSize: 28, color: Colors.white70))
                  : Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      // Up from the top row: back to the home screen
                      onKeyEvent: (_, e) {
                        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowUp) {
                          if (!(primaryFocus?.focusInDirection(TraversalDirection.up) ?? false)) {
                            Navigator.of(context).maybePop();
                          }
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(spacing: 20, runSpacing: 20, children: [
                        for (var i = 0; i < _apps.length; i++)
                          AppChip(
                            app: _apps[i],
                            autofocus: i == 0,
                            selected: pinned.contains(_apps[i].package),
                            badge: pinned.contains(_apps[i].package)
                                ? const Icon(Icons.push_pin_rounded, size: 22, color: Colors.black)
                                : null,
                            onSelect: () => launchPackage(_apps[i].package),
                            onLongPress: () => _pinMenu(_apps[i]),
                          ),
                      ]),
                    ),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── home ─────────────────────────

class AppInfo {
  AppInfo(this.package, this.label, this.image, this.wide, this.color);
  final String package;
  final String label;
  final Uint8List image; // 16:9 banner (wide) or icon
  final bool wide;
  final int color;

  Color get glow {
    final h = HSVColor.fromColor(Color(color));
    return h
        .withSaturation(h.saturation.clamp(0.45, 1.0).toDouble())
        .withValue(h.value.clamp(0.55, 0.9).toDouble())
        .toColor();
  }
}

Widget appArt(AppInfo a, double w) {
  if (a.wide) {
    return Image.memory(a.image,
        fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
  }
  final c = a.glow;
  final s = w * 0.38;
  return DecoratedBox(
    decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.withAlpha(210), Color.lerp(c, Colors.black, 0.6)!])),
    child: Center(
      child: SizedBox(
        width: s,
        height: s,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(s * 0.24),
            child: Image.memory(a.image, fit: BoxFit.cover, gaplessPlayback: true)),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenSettings});
  final VoidCallback onOpenSettings;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, AppInfo> _cache = {};
  bool _loaded = false;
  bool _loading = false;
  bool _again = false;
  bool _leaving = false;
  final ValueNotifier<int> _focus = ValueNotifier(0);


  WeatherNow? _weather;
  String _weatherSig = '\u0000';
  Timer? _weatherTimer;

  Timer? _idleTimer;
  Timer? _updateTimer;
  Timer? _toastTimer;
  DateTime? _lastUpdateCheck;
  String _toastShownFor = '';
  bool _toast = false;

  void _onUpdateFound() {
    final u = kUpdate.value;
    if (u == null || !mounted) return;
    final key = '${u.version}+${u.build}';
    if (_toastShownFor == key) return;
    _toastShownFor = key;
    setState(() => _toast = true);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _toast = false);
    });
  }
  String _updateSig = '\u0000';
  DateTime _lastKey = DateTime.now();
  bool _fg = true;
  bool _saverUp = false;

  late final AnimationController _intro =
      AnimationController(
          vsync: this,
          duration: Duration(milliseconds: SettingsScope.read(context).perfMode ? 450 : 1200));
  late final Animation<double> _fadeEarly =
      CurvedAnimation(parent: _intro, curve: const Interval(0.0, 0.4));
  late final Animation<double> _fadeLate =
      CurvedAnimation(parent: _intro, curve: const Interval(0.45, 1.0));
  late final Animation<Offset> _dockSlide =
      Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _intro,
              curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic)));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _weatherTimer = Timer.periodic(const Duration(minutes: 20), (_) => _loadWeather(force: true));
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _checkUpdate(force: true);
      _maybeAutoUpdate();
    });
    _sportsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadSports());
    kDrop.onCommand = _onDropCommand;
    kDrop.appsProvider = () async {
      // Settings screens replace the home screen, so read settings from the app itself,
      // not from this screen (which may be gone by the time this runs).
      final ctx = kNavKey.currentContext;
      if (ctx == null) throw StateError('the app is still starting');
      final hidden = SettingsScope.read(ctx).dropHidden.toSet();
      final all = await fetchInstalledApps();
      // an empty list here means the lookup failed, not that the TV has no apps
      if (all.isEmpty) throw StateError('could not list apps');
      return [
        for (final a in all)
          if (!hidden.contains(a.package))
            {'package': a.package, 'label': a.label, 'icon': base64Encode(a.icon)}
      ];
    };
    var dropTick = 0;
    _dropTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // on the home screen every 5 seconds; behind another app every 15, for "put on …"
      if (!mounted || (!_fg && dropTick++ % 3 != 0)) return;
      final s = SettingsScope.read(context);
      kDrop.refresh(s.serverUrl, s.serverToken);
    });
    kUpdate.addListener(_onUpdateFound);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _idleTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkIdle());
    startNetWatch();
    startBatteryWatch();
    // games: look for them now and then, and show the Games tile once there are some
    kGames.addListener(_onGames);
    makeGamesTileArt().then((_) => scanGames());
    _gamesTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted && _fg) scanGames();
    });
    _keepTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _fg && SettingsScope.read(context).keepWatching) refreshKeepWatching();
    });
    // the song playing behind Foyer: checked every few seconds while the home screen is up
    _nowTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_fg) return;
      final s = SettingsScope.read(context);
      if (s.keepWatching && s.nowPlaying) {
        refreshNowPlaying();
      } else if (kNow.value != null) {
        kNow.value = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && SettingsScope.read(context).keepWatching) refreshKeepWatching(force: true);
    });
  }

  Timer? _sportsTimer;
  Timer? _keepTimer;
  Timer? _gamesTimer;

  void _onGames() {
    if (mounted) setState(() {});
  }
  Timer? _nowTimer;

  /// "Open on TV" from the phone page. Only acts while Foyer is on screen.
  void _onDropCommand(String type, String value) {
    if (!mounted) return;
    // "put on Bluey" from the phone works even while another app is on screen
    if (type == 'play') {
      putOn(value, SettingsScope.read(context));
      return;
    }
    if (!_fg) return;
    if (type == 'open') {
      _openPkg(value);
    } else if (type == 'url') {
      kChannel.invokeMethod<bool>('openUrl', {'url': value}).catchError((Object _) => false);
    }
  }
  Timer? _dropTimer;

  void _loadSports() {
    if (!mounted || !_fg) return;
    final s = SettingsScope.read(context);
    kSports.refresh(s.sportsTeams, s.clock24);
    kDrop.refresh(s.serverUrl, s.serverToken);
  }

  bool _onAnyKey(KeyEvent e) {
    _lastKey = DateTime.now();
    _idleActed = false;
    return false;
  }

  bool _idleActed = false;
  BuildContext? _saverCtx;

  void _checkIdle() {
    _maybeAutoUpdate();
    if (!mounted || !_fg || _leaving) return;
    final s = SettingsScope.read(context);
    // Smart idle: a long while with nobody pressing anything on the home screen
    if (s.idleOn &&
        !_idleActed &&
        (_saverUp || ModalRoute.of(context)?.isCurrent == true) &&
        DateTime.now().difference(_lastKey) >= smartIdleWait(s)) {
      _idleActed = true;
      _smartIdle(s.idleAction);
      return;
    }
    if (_saverUp) return;
    final mins = s.ssMinutes;
    if (mins <= 0) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (DateTime.now().difference(_lastKey) >= Duration(minutes: mins)) _showSaver();
  }

  Future<void> _showSaver() async {
    _saverUp = true;
    final nav = Navigator.of(context);
    await nav.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, __, ___) {
        var closed = false;
        _saverCtx = ctx;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            onKeyEvent: (_, e) {
              // aerial screensaver: Down shows where it is instead of waking
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.arrowDown &&
                  SettingsScope.read(context).ssSource == 'aerial') {
                kAerialWhere.value++;
                return KeyEventResult.handled;
              }
              if (e is KeyDownEvent && !closed) {
                closed = true;
                Navigator.of(ctx).pop();
              }
              return KeyEventResult.handled; // the wake-up press does nothing else
            },
            child: ScreensaverView(weather: _weather),
          ),
        );
      },
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    _lastKey = DateTime.now();
    _saverUp = false;
    _saverCtx = null;
  }

  Future<void> _smartIdle(String action) async {
    // the screensaver steps aside first
    final sc = _saverCtx;
    if (_saverUp && sc != null && sc.mounted) Navigator.of(sc).pop();
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (action == 'tvoff' || action == 'screenoff') {
      if (action == 'tvoff') {
        kChannel.invokeMethod('tvOffSoon').catchError((Object _) => null);
      } else {
        await screenOffNow(context);
      }
      // the button that wakes the TV is used up by the helper, so start the wait over here
      _lastKey = DateTime.now();
      _idleActed = false;
      return;
    }
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 800),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, __, ___) => Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent) Navigator.of(ctx).pop();
          return KeyEventResult.handled; // the wake-up press does nothing else
        },
        child: const DimClockView(),
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    _lastKey = DateTime.now();
    _idleActed = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // runs on first build and whenever settings change
    _load();
    _loadWeather();
    _loadSports();
    _checkUpdate();
    syncSmartIdle(SettingsScope.read(context));
  }

  @override
  void dispose() {
    _endZoom();
    WidgetsBinding.instance.removeObserver(this);
    _weatherTimer?.cancel();
    _sportsTimer?.cancel();
    _dropTimer?.cancel();
    _idleTimer?.cancel();
    _keepTimer?.cancel();
    _gamesTimer?.cancel();
    kGames.removeListener(_onGames);
    _nowTimer?.cancel();
    _updateTimer?.cancel();
    _toastTimer?.cancel();
    kUpdate.removeListener(_onUpdateFound);
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _intro.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _fg = s == AppLifecycleState.resumed;
    if (_fg) _lastKey = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      if (SettingsScope.read(context).keepWatching) refreshKeepWatching(force: true);
      _loadWeather(force: true);
      _loadSports();
      _endZoom();
      if (_leaving) setState(() => _leaving = false);
      _load();
      _checkUpdate(force: true);
      checkNetNow();
    }
  }

  Future<void> _load() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    do {
      _again = false;
      await _loadOnce();
    } while (_again && mounted);
    _loading = false;
    if (!mounted) return;
    setState(() => _loaded = true);
    if (!_intro.isAnimating && !_intro.isCompleted) _intro.forward();
  }

  Future<void> _loadOnce() async {
    final pinned = SettingsScope.read(context).pinned;
    final missing = pinned.where((p) => !_cache.containsKey(p)).toList();
    if (missing.isEmpty) return;
    try {
      final raw = await kChannel.invokeListMethod<Map>('getApps', {'packages': missing});
      final fresh = (raw ?? const [])
          .map((m) => AppInfo(m['package'] as String, m['label'] as String,
              m['image'] as Uint8List, m['wide'] as bool, m['color'] as int))
          .toList();
      if (!mounted) return;
      // decode artwork up front so nothing pops in during the intro
      await Future.wait(fresh.map((a) => precacheImage(MemoryImage(a.image), context)));
      if (!mounted) return;
      for (final a in fresh) {
        _cache[a.package] = a;
      }
      // packages that aren't installed: remember so we don't ask again every time
      for (final p in missing) {
        if (!_cache.containsKey(p)) _cache[p] = _missingMarker;
      }
      setState(() {});
    } catch (_) {}
  }

  static final AppInfo _missingMarker = AppInfo('', '', Uint8List(0), false, 0);

  List<AppInfo> _shown(List<String> pinned) => [
        // Games first, once there are some (Settings > Home screen > Games can hide it)
        if (SettingsScope.read(context).gamesOnHome && kGames.value.isNotEmpty && kGamesTileArt != null)
          AppInfo(kGamesTile, 'Games', kGamesTileArt!, true, 0xFF6D5BD0),
        for (final p in pinned)
          if (_cache[p] != null && _cache[p] != _missingMarker) _cache[p]!
      ];

  bool _autoBusy = false;
  DateTime? _autoTried;

  /// Updates install by themselves (Settings → Backup and updates → Updates): when the home
  /// screen has sat untouched for 10 minutes, or in the middle of the night. Never while
  /// you're using Foyer. Fire TV always asks first, so it's left to the Updates page there.
  Future<void> _maybeAutoUpdate() async {
    if (!mounted || _autoBusy) return;
    final s = SettingsScope.read(context);
    if (!s.autoUpdate || !s.setupDone) return;
    final now = DateTime.now();
    final night = now.hour >= 2 && now.hour < 5;
    final idleHome = _fg &&
        !_leaving &&
        (_saverUp || ModalRoute.of(context)?.isCurrent == true) &&
        now.difference(_lastKey) >= const Duration(minutes: 10);
    if (!night && !idleHome) return;
    final tried = _autoTried;
    if (tried != null && now.difference(tried) < const Duration(hours: 3)) return;
    if (kIsPc) {
      final f = kPcAutoUpdate;
      if (f == null) return;
      _autoBusy = true;
      _autoTried = now;
      try {
        await f(s);
      } catch (_) {}
      _autoBusy = false;
      return;
    }
    if (kIsFireTv) return;
    final u = kUpdate.value;
    if (u == null) return;
    _autoBusy = true;
    _autoTried = now;
    try {
      await autoInstallUpdate(s, u);
    } catch (_) {}
    _autoBusy = false;
  }

  Future<void> _checkUpdate({bool force = false}) async {
    if (kIsPc) return; // Foyer for PC updates from its own download, not the TV's
    final s = SettingsScope.read(context);
    final url = s.updateUrl;
    if (url.isEmpty) {
      _updateSig = '';
      kUpdate.value = null;
      return;
    }
    if (!force && url == _updateSig) return;
    final now = DateTime.now();
    if (force && _lastUpdateCheck != null && now.difference(_lastUpdateCheck!).inSeconds < 60) return;
    _lastUpdateCheck = now;
    _updateSig = url;
    try {
      kUpdate.value =
          await UpdateApi.check(url, s.updateToken, await appBuild(), await appName(),
              dropUrl: s.serverUrl, dropToken: s.serverToken);
    } catch (_) {}
  }

  Future<void> _loadWeather({bool force = false}) async {
    final s = SettingsScope.read(context);
    final lat = s.weatherLat, lon = s.weatherLon;
    if (s.weatherCity.isEmpty || lat == null || lon == null) {
      _weatherSig = '';
      if (_weather != null && mounted) setState(() => _weather = null);
      return;
    }
    final sig = '$lat|$lon|${s.weatherF}';
    if (!force && sig == _weatherSig) return;
    _weatherSig = sig;
    try {
      final w = await WeatherApi.now(lat, lon, s.weatherF);
      if (mounted) setState(() => _weather = w);
    } catch (_) {}
  }

  Future<void> _openPkg(String pkg) async {
    kJiggle.value = null;
    if (_leaving) return;
    if (pkg == kGamesTile) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GamesScreen()));
      return;
    }
    // a soundscape gives way to the app you open
    if (kSoundscape.value.isNotEmpty) setSoundscape('');
    final zoom = !SettingsScope.read(context).perfMode && _zoomFrom(pkg);
    setState(() => _leaving = true);
    await Future.delayed(Duration(milliseconds: zoom ? 300 : 190));
    final ok = await launchPackage(pkg);
    if (!ok) _endZoom();
    if (!ok && mounted) setState(() => _leaving = false);
    Future.delayed(const Duration(milliseconds: 1500), () {
      _endZoom();
      if (mounted && _leaving) setState(() => _leaving = false);
    });
  }

  OverlayEntry? _zoom;

  void _endZoom() {
    _zoom?.remove();
    _zoom = null;
  }

  /// The app's tile grows to fill the screen, then the app opens: like stepping into it.
  bool _zoomFrom(String pkg) {
    _endZoom();
    final node = FocusManager.instance.primaryFocus;
    final overlay = Overlay.maybeOf(context);
    final box = overlay?.context.findRenderObject() as RenderBox?;
    if (node == null || overlay == null || box == null || !box.hasSize) return false;
    final r = node.rect;
    final from = Rect.fromPoints(box.globalToLocal(r.topLeft), box.globalToLocal(r.bottomRight));
    if (from.width < 20 || from.height < 20) return false;
    final to = Offset.zero & box.size;
    final info = _cache[pkg];
    final color = info?.glow ?? kDefaultTint;
    _zoom = OverlayEntry(
      builder: (_) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        builder: (_, t, __) {
          final rr = Rect.lerp(from, to, t)!;
          final iconW = info == null ? 0.0 : (info.wide ? 520.0 : 220.0) * (0.55 + 0.45 * t);
          return Positioned.fromRect(
            rect: rr,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28 * (1 - t)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [Color.lerp(color, Colors.black, 0.15)!, Color.lerp(color, Colors.black, 0.75)!],
                  ),
                ),
                child: info == null
                    ? const SizedBox.expand()
                    : Center(
                        child: Opacity(
                          opacity: (1 - (t - 0.6).clamp(0.0, 0.4) * 1.5).clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(info.wide ? 18 : 44),
                            child: SizedBox(
                              width: iconW.clamp(1.0, rr.width),
                              child: Image.memory(info.image, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_zoom!);
    return true;
  }


  void _openAllApps() {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const AllAppsScreen(),
      // rises from the app row (a slide, not a zoom: the zoom left a strip on some sticks)
      transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child)),
    ));
  }

  /// Hold OK on an app: jiggle mode, like rearranging on an iPhone or Apple TV.
  void _tileHold(AppInfo a, int index, int count) {
    if (a.package == kGamesTile || !SettingsScope.read(context).pinned.contains(a.package)) {
      _tileMenu(a, index, count);
      return;
    }
    kJiggle.value = a.package;
  }

  void _moveTile(String pkg, int dir) {
    final s = SettingsScope.read(context);
    final p = [...s.pinned];
    final i = p.indexOf(pkg);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= p.length) return;
    p.removeAt(i);
    p.insert(j, pkg);
    s.setPinned(p);
  }

  void _tileMenu(AppInfo a, int index, int count) {
    final s = SettingsScope.read(context);
    if (a.package == kGamesTile) {
      showMenu2(context, 'Games', [
        MenuChoice('Hide Games from the home screen', () => s.change(() => s.gamesOnHome = false)),
        MenuChoice('Cancel', () {}),
      ]);
      return;
    }
    void move(int dir) {
      final p = [...s.pinned];
      final i = p.indexOf(a.package);
      final j = i + dir;
      if (i < 0 || j < 0 || j >= p.length) return;
      p.removeAt(i);
      p.insert(j, a.package);
      s.setPinned(p);
    }

    showMenu2(context, a.label, [
      if (index > 0) MenuChoice('Move left', () => move(-1)),
      if (index < count - 1) MenuChoice('Move right', () => move(1)),
      MenuChoice('App info', () => kChannel.invokeMethod('appInfo', {'package': a.package})),
      MenuChoice('Close app', () => closeApp(context, a.package, a.label)),
      MenuChoice('Clear data…', () => clearAppData(context, a.package, a.label)),
      MenuChoice('Uninstall', () => kChannel.invokeMethod('uninstall', {'package': a.package})),
      MenuChoice('Remove from home', () => removeFromHome(context, a.package, a.label)),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final apps = _shown(settings.pinned);
    return PopScope(
      canPop: false,
      // Back twice quickly: recent apps
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (kJiggle.value != null) {
          kJiggle.value = null; // Back: done moving
        } else {
          homeBack(context);
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // Menu button on the remote opens settings
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.contextMenu) {
            widget.onOpenSettings();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _focus,
                  builder: (_, i, __) => Wallpaper(
                      video: true,
                      tint: (apps.isEmpty || i >= apps.length)
                          ? kDefaultTint
                          : apps[clampIdx(i, apps.length - 1)].glow),
                ),
              ),
            ),
            // rain, snow or fog when it's like that outside
            if (settings.weatherFx && _weather != null)
              Positioned.fill(child: WeatherFx(kind: fxFor(_weather!.code), light: settings.perfMode)),
            // holiday leaves, bats, snow, confetti or petals
            Positioned.fill(
                child: SeasonLayer(season: activeSeason(settings), light: settings.perfMode)),
            Positioned.fill(
              child: AnimatedScale(
                scale: _leaving ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeIn,
                child: AnimatedOpacity(
                  opacity: _leaving ? 0 : 1,
                  duration: Duration(milliseconds: _leaving ? 200 : 350),
                  child: _content(apps, settings),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _content(List<AppInfo> apps, Settings settings) {
    final count = max(apps.length, 1); // the All apps tile only shows when nothing is pinned
    // room on the left for the two round buttons
    const avail = 1920.0 - 200 - 100 - 80;
    final tileW = ((avail - 28.0 * (count - 1)) / count).clamp(120.0, 240.0).toDouble();
    // the app tray is centred between x 200 and 1820; Keep watching starts at its left edge,
    // so the two always line up, however many apps there are
    final trayW = count * tileW + 28.0 * (count - 1) + 80;
    final keepLeft = 200.0 + max(0.0, (1620 - trayW) / 2);
    return Stack(children: [
      Positioned(
          left: 84,
          top: 30,
          child: FadeTransition(
              opacity: _fadeEarly,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                // a scene has its own big clock, unless a video background is playing over it
                ValueListenableBuilder<bool>(
                  valueListenable: kVideoPlaying,
                  builder: (_, video, __) => _HomeHeader(
                      season: activeSeason(settings),
                      weather: _weather,
                      clock: settings.wallMode != 'scenes' || video),
                ),
                // who's watching: under the greeting, clear of the scene's date in the middle
                if (settings.profiles.length > 1) ...[
                  const SizedBox(height: 18),
                  const ProfilePills(),
                ],
              ]))),
      Positioned(
          right: 72,
          top: 132,
          child: IgnorePointer(
              child: AnimatedOpacity(
                  opacity: _toast && kUpdate.value != null ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Glass(
                      radius: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.system_update_rounded, size: 28, color: Color(0xFFFF9F0A)),
                        const SizedBox(width: 12),
                        Text('Update ${kUpdate.value?.version ?? ''} is ready. Open Settings.',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                      ]))))),
      Positioned(
          right: 72,
          top: 44,
          child: FadeTransition(
              opacity: _fadeEarly,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ValueListenableBuilder<List<GameLine>>(
                    valueListenable: kSports.games,
                    builder: (_, g, __) => g.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 16), child: ScorePill(games: g))),
                const SoundscapePill(),
                const SleepPill(),

              ]))),
      Positioned(
          right: 96,
          bottom: 300,
          child: FadeTransition(
              opacity: _fadeLate,
              child: const DropCorner())),
      Positioned(
          // lined up with the left edge of the app tray, clear of the round buttons
          left: keepLeft,
          bottom: 300,
          child: FadeTransition(
              opacity: _fadeLate,
              child: !settings.keepWatching
                  ? _hero(apps)
                  : AnimatedBuilder(
                      animation: Listenable.merge([kKeep, kNow]),
                      builder: (_, __) => !KeepWatchingRow.hasAny
                          ? _hero(apps)
                          : KeepWatchingRow(onOpen: (item) => openKeepItem(item)),
                    ))),
      Positioned(
        left: 70,
        bottom: 44,
        child: FadeTransition(
          opacity: _fadeEarly,
          child: HomeSideButtons(
            onSettings: widget.onOpenSettings,
            onGoodnight: () => goodnightMenu(context),
            onSearch: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
            onOffline: () => netMenu(context),
          ),
        ),
      ),
      Positioned(
        left: 200,
        right: 100,
        bottom: 56,
        child: Center(
          child: FadeTransition(
            opacity: _fadeEarly,
            child: SlideTransition(
              position: _dockSlide,
              child: _Dock(
                apps: apps,
                tileW: tileW,
                intro: _intro,
                onFocused: (i) => _focus.value = i,
                onOpen: (a) => _openPkg(a.package),
                onMenu: (a, i) => _tileHold(a, i, apps.length),
                onMore: (a, i) {
                  kJiggle.value = null;
                  _tileMenu(a, i, apps.length);
                },
                onMove: _moveTile,
                onAllApps: _openAllApps,
              ),
            ),
          ),
        ),
      ),
      // a quiet hint under the app row: Down shows every app
      if (apps.isNotEmpty)
        Positioned(
          left: 200,
          right: 100,
          bottom: 8,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _fadeLate,
              child: ValueListenableBuilder<String?>(
                valueListenable: kJiggle,
                builder: (_, j, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (j == null) ...[
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: Colors.white54),
                    const SizedBox(width: 4),
                  ],
                  Text(j == null ? 'All apps' : 'Left / Right moves it  ·  OK when done  ·  Down for more',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: j == null ? Colors.white54 : Colors.white,
                          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 12)])),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _hero(List<AppInfo> apps) => ValueListenableBuilder<int>(
        valueListenable: _focus,
        builder: (_, i, __) {
          final label = i >= apps.length
              ? 'All Apps'
              : (apps.isEmpty ? '' : apps[clampIdx(i, apps.length - 1)].label);
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            layoutBuilder: (cur, prev) => Stack(
                alignment: Alignment.centerLeft, children: [...prev, if (cur != null) cur]),
            transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
                        .animate(a),
                    child: child)),
            child: Text(label,
                key: ValueKey(label),
                style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    shadows: [Shadow(color: Color(0x80000000), blurRadius: 24)])),
          );
        },
      );
}

/// Top left of the home screen: a big, calm clock, and "Good evening · 4° Cloudy" under it.
class _HomeHeader extends StatefulWidget {
  const _HomeHeader({required this.season, required this.weather, this.clock = true});
  final Season season;
  final WeatherNow? weather;

  /// false when the wallpaper is a scene, which has its own big clock
  final bool clock;
  @override
  State<_HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<_HomeHeader> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _now = DateTime.now();
    if (mounted) setState(() {});
    _t = Timer(Duration(seconds: 61 - _now.second), _tick); // one rebuild per minute
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String get _hello {
    final h = _now.hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final h24 = s.clock24;
    final m = _now.minute.toString().padLeft(2, '0');
    final time = h24 ? '${_now.hour.toString().padLeft(2, '0')}:$m' : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m';
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 4))];
    final w = widget.weather;
    const line = TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF), shadows: shadow);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (!widget.clock) const SizedBox(height: 22),
      if (widget.clock)
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(time,
            style: const TextStyle(
                fontSize: 104, fontWeight: FontWeight.w200, letterSpacing: -3, height: 1.0, shadows: shadow)),
        if (!h24) ...[
          const SizedBox(width: 10),
          Text(_now.hour < 12 ? 'AM' : 'PM',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w400, color: Colors.white70, shadows: shadow)),
        ],
      ]),
      const SizedBox(height: 6),
      Row(mainAxisSize: MainAxisSize.min, children: [
        // holidays keep their own greeting (and the New Year's Eve countdown)
        if (widget.season != Season.none)
          DefaultTextStyle.merge(style: const TextStyle(shadows: shadow), child: SeasonGreeting(season: widget.season, fallback: _hello))
        else
          Text(s.personName.isEmpty ? _hello : '$_hello, ${s.personName}', style: line),
        if (w != null) ...[
          Text('   ·   ', style: line.copyWith(color: Colors.white38)),
          Icon(w.icon, size: 32, color: Colors.white, shadows: shadow),
          const SizedBox(width: 10),
          Text('${w.temp.round()}°  ${w.label}', style: line),
        ],
      ]),
    ]);
  }
}

class _Dock extends StatelessWidget {
  const _Dock(
      {required this.apps,
      required this.tileW,
      required this.intro,
      required this.onFocused,
      required this.onOpen,
      required this.onMenu,
      required this.onMore,
      required this.onMove,
      required this.onAllApps});
  final List<AppInfo> apps;
  final double tileW;
  final Animation<double> intro;
  final ValueChanged<int> onFocused;
  final ValueChanged<AppInfo> onOpen;
  final void Function(AppInfo, int) onMenu;
  final void Function(AppInfo, int) onMore;
  final void Function(String, int) onMove;
  final VoidCallback onAllApps;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          // Down from the app row opens every app
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
              onAllApps();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Glass(
          radius: 44,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 34),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < apps.length; i++)
              Padding(
                // the key goes on the outer widget, so a moved app keeps its tile (and the
                // remote's focus) instead of the row rebuilding tiles by position
                key: ValueKey(apps[i].package),
                padding: EdgeInsets.only(left: i == 0 ? 0 : 28),
                child: _Tile(
                  index: i,
                  w: tileW,
                  intro: intro,
                  art: appArt(apps[i], tileW),
                  onFocused: onFocused,
                  onActivate: () => onOpen(apps[i]),
                  onLongPress: () => onMenu(apps[i], i),
                  pkg: apps[i].package,
                  glass: SettingsScope.of(context).glassIcons && apps[i].package != kGamesTile
                      ? GlassArt(app: apps[i])
                      : null,
                  onMove: (dir) => onMove(apps[i].package, dir),
                  onMore: () => onMore(apps[i], i),
                ),
              ),
            if (apps.isEmpty)
            Padding(
              padding: EdgeInsets.zero,
              child: _Tile(
                key: const ValueKey('__all_apps__'),
                index: apps.length,
                w: tileW,
                intro: intro,
                art: DecoratedBox(
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF3A3F55), Color(0xFF14172A)])),
                  child: Center(
                      child: Icon(Icons.apps_rounded, size: tileW * 0.34, color: Colors.white)),
                ),
                onFocused: onFocused,
                onActivate: onAllApps,
              ),
            ),
          ]),
        ),
        ),
      );
}

class _Tile extends StatefulWidget {
  const _Tile(
      {super.key,
      required this.index,
      required this.w,
      required this.intro,
      required this.art,
      required this.onFocused,
      required this.onActivate,
      this.onLongPress,
      this.pkg = '',
      this.glass,
      this.onMove,
      this.onMore});
  final int index;
  final double w;
  final Animation<double> intro;
  final Widget art;
  final ValueChanged<int> onFocused;
  final VoidCallback onActivate;
  final VoidCallback? onLongPress;
  final String pkg;
  final Widget? glass; // glass app icons: this shows until the tile is focused
  final ValueChanged<int>? onMove; // jiggle mode: -1 left, 1 right
  final VoidCallback? onMore; // jiggle mode: Down for the app's options
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with TickerProviderStateMixin {
  late final AnimationController _fc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200));
  late final Animation<double> _f = CurvedAnimation(
      parent: _fc, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _intro;
  final FocusNode _node = FocusNode();
  bool _pressed = false;
  bool _down = false;
  bool _long = false;
  bool _jdown = false; // OK pressed while jiggling (the hold that started it doesn't count)
  late final AnimationController _wig =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  bool get _jiggling => kJiggle.value != null;
  bool get _picked => kJiggle.value != null && kJiggle.value == widget.pkg;

  void _onJiggle() {
    if (!mounted) return;
    if (_jiggling && !SettingsScope.read(context).perfMode) {
      _wig.repeat(reverse: true);
    } else {
      _wig.stop();
      _wig.value = 0.5;
    }
    _jdown = false;
    setState(() {});
  }

  double get _h => widget.w * 9 / 16;

  @override
  void initState() {
    super.initState();
    final s = (0.25 + widget.index * 0.07).clamp(0.0, 0.5).toDouble();
    final e = (s + 0.45).clamp(0.0, 1.0).toDouble();
    _intro = CurvedAnimation(
        parent: widget.intro, curve: Interval(s, e, curve: Curves.easeOutCubic));
    _wig.value = 0.5;
    kJiggle.addListener(_onJiggle);
  }

  @override
  void didUpdateWidget(_Tile old) {
    super.didUpdateWidget(old);
    // a reorder changed our position while we hold focus: tell the home screen
    if (old.index != widget.index && _node.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFocused(widget.index);
      });
    }
    // jiggle mode: the app being moved always keeps the remote's focus
    if (_picked && !_node.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _picked) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    kJiggle.removeListener(_onJiggle);
    _node.dispose();
    _fc.dispose();
    _shine.dispose();
    _wig.dispose();
    super.dispose();
  }

  void _onFocus(bool f) {
    if (f) {
      _fc.forward();
      if (!SettingsScope.read(context).perfMode) _shine.forward(from: 0);
      widget.onFocused(widget.index);
    } else {
      _fc.reverse();
    }
  }

  Future<void> _activate() async {
    setState(() => _pressed = true);
    await Future.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    setState(() => _pressed = false);
    widget.onActivate();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_jiggling) {
      // Left/Right move the picked app, OK is done, Down shows its options
      final k = e.logicalKey;
      if (_selectKeys.contains(k)) {
        if (e is KeyDownEvent) _jdown = true;
        if (e is KeyUpEvent && _jdown) kJiggle.value = null;
        return KeyEventResult.handled;
      }
      if (e is KeyUpEvent) return KeyEventResult.ignored;
      if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
        if (_picked) widget.onMove?.call(k == LogicalKeyboardKey.arrowLeft ? -1 : 1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        if (_picked) widget.onMore?.call();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (!_selectKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _long = false;
    } else if (e is KeyRepeatEvent) {
      if (_down && !_long && widget.onLongPress != null) {
        _long = true;
        widget.onLongPress!();
      }
    } else if (e is KeyUpEvent) {
      final fire = _down && !_long;
      _down = false;
      _long = false;
      if (fire) _activate();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.index == 0,
      onFocusChange: _onFocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _activate,
        onLongPress: widget.onLongPress,
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: FadeTransition(
              opacity: _intro,
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _f, _wig]),
                child: _body(),
                builder: (_, child) {
                  // jiggle: the others wiggle, the one you're moving lifts up
                  final lift = _picked ? 1.0 : 0.0;
                  final turn = _jiggling && !_picked
                      ? (_wig.value - 0.5) * 0.035 * (widget.index.isEven ? 1 : -1)
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -16 * _f.value + 30 * (1 - _intro.value) - 14 * lift),
                    child: Transform.rotate(
                      angle: turn,
                      child: Transform.scale(
                          scale: (0.86 + 0.14 * _intro.value) * (1 + 0.14 * _f.value) * (1 + 0.06 * lift),
                          child: child),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final r = BorderRadius.circular(22);
    final w = widget.w;
    return SizedBox(
      width: w,
      height: _h,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
            child: FadeTransition(
                opacity: _f,
                child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: r, boxShadow: const [
                  BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 44,
                      spreadRadius: -6,
                      offset: Offset(0, 30))
                ])))),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: r, boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 8))
        ]))),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: r,
            child: Stack(fit: StackFit.expand, children: [
              if (widget.glass == null)
                widget.art
              else ...[
                widget.glass!,
                // the app you're on shows its own colours
                FadeTransition(opacity: _f, child: widget.art),
              ],
              const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                          stops: [0, 0.5]))),
              AnimatedBuilder(
                animation: _shine,
                builder: (_, __) {
                  if (!_shine.isAnimating) return const SizedBox.shrink();
                  final x = -w * 0.7 + w * 1.9 * Curves.easeInOut.transform(_shine.value);
                  return Transform.translate(
                    offset: Offset(x, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Transform.rotate(
                        angle: 0.35,
                        child: Container(
                            width: w * 0.35,
                            height: _h * 2,
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [
                              Color(0x00FFFFFF),
                              Color(0x40FFFFFF),
                              Color(0x00FFFFFF)
                            ]))),
                      ),
                    ),
                  );
                },
              ),
            ]),
          ),
        ),
        Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    borderRadius: r,
                    border: Border.all(color: const Color(0x40FFFFFF), width: 1.2)))),
      ]),
    );
  }
}

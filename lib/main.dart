import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'extras.dart';
import 'plex.dart';
import 'screens.dart';
import 'seasons.dart';
import 'setup.dart';
import 'sounds.dart';
import 'server.dart';
import 'sports.dart';
import 'update.dart';
import 'weather.dart';

const MethodChannel kChannel = MethodChannel('leclair/launcher');
const int kMaxPinned = 8;
const Color kDefaultTint = Color(0xFF3B5BDB);
const String kPlexPackage = 'com.plexapp.android';

/// Pre-selected on first run if they're installed.
const List<String> kSuggested = [
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

class Settings extends ChangeNotifier {
  String name = 'Home';
  bool liquid = false;
  bool clock24 = false;
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
  String wallMode = 'glow'; // glow | preset | photo
  String wallValue = '';
  int ssMinutes = 5; // 0 = off
  String ssSource = 'colors'; // colors | mine | online | drop
  bool autoStart = true;
  bool perfMode = false;
  int soundLevel = 1; // 0 off, 1 quiet, 2 normal
  bool seasonal = true; // Halloween, Christmas, New Year and Easter looks
  int scoreAlerts = 2; // 0 off, 1 scores only, 2 scores + start + final
  int scoreDelay = 0; // seconds, to stay behind a delayed stream
  int scoreSize = 1; // alert pop-up: 0 small, 1 medium, 2 large

  /// Custom remote buttons: "313" = pressed, "313L" = held -> app package, "foyer" or "" (normal).
  Map<String, String> remoteKeys = {};
  String updateUrl = 'matthewsleclair-hue/Foyer';
  String updateToken = '';
  List<FollowedTeam> sportsTeams = [];

  /// Apps kept off the phone page's "Open on TV" list.
  List<String> dropHidden = [];
  String serverUrl = '';
  String serverToken = '';

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
        'scoreDelay': scoreDelay,
        'alertSize': scoreSize,
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
    wallMode = (wm == 'preset' || wm == 'photo') ? wm : 'glow';
    wallValue = _s(j['wallValue'], wallValue);
    final ss = j['ssMinutes'];
    if (ss is num) ssMinutes = ss.toInt();
    final src = j['ssSource'];
    if (src is String && (src == 'mine' || src == 'online' || src == 'colors' || src == 'drop')) {
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
    final sa = j['scoreAlerts'];
    if (sa is num) scoreAlerts = sa.toInt().clamp(0, 2).toInt();
    kScoreAlertLevel = scoreAlerts;
    final sd = j['scoreDelay'];
    if (sd is num) scoreDelay = sd.toInt().clamp(0, 120).toInt();
    kScoreAlertDelay = scoreDelay;
    final ss2 = j['alertSize'];
    if (ss2 is num) scoreSize = ss2.toInt().clamp(0, 2).toInt();
    kScoreAlertSize = scoreSize;
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

Future<bool> launchPackage(String pkg) async =>
    (await kChannel.invokeMethod<bool>('launch', {'package': pkg})) ?? false;

// ───────────────────────── app shell ─────────────────────────

final GlobalKey<NavigatorState> kNavKey = GlobalKey<NavigatorState>();
const MethodChannel kNavChannel = MethodChannel('leclair/nav');

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
        title: 'Foyer',
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        // Design on a fixed 1920x1080 canvas and scale it to the real screen.
        builder: (context, child) => ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: 1920, height: 1080, child: child),
          ),
        ),
        home: const Root(),
      );
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
    kNavChannel.setMethodCallHandler((call) async {
      if (call.method == 'goHome') {
        kNavKey.currentState?.popUntil((r) => r.isFirst);
        if (mounted) setState(() => _mode = _Mode.home);
      }
    });
    Future.wait([SettingsScope.read(context).load(), loadDevice()]).then((_) {
      if (mounted) setState(() => _ready = true);
      // goal pop-ups, also while another app is playing
      if (mounted) kScoreAlerts.start(() => SettingsScope.read(context));
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
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint),
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
      this.scrollIntoView = false});
  final double scale;
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
      onFocusChange: (f) {
        setState(() => _f = f);
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
        const Text('Your Plex row will show on the home screen.', style: body),
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
            : 'Almost there. Press Home on the remote; if the TV asks which home app to use, pick Foyer and Always.';
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
        MenuChoice('Remove from home',
            () => s.setPinned(s.pinned.where((p) => p != a.package).toList()))
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
            const Text('Select to open. Hold Select to pin or unpin from your home screen.',
                style: TextStyle(fontSize: 26, color: Colors.white70)),
            const SizedBox(height: 32),
            Expanded(
              child: _loading
                  ? const Text('Loading…', style: TextStyle(fontSize: 28, color: Colors.white70))
                  : SingleChildScrollView(
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

  PlexRow? _plex;
  String _plexSig = '\u0000';
  Timer? _plexTimer;

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
    _plexTimer = Timer.periodic(const Duration(minutes: 15), (_) => _loadPlex(force: true));
    _weatherTimer = Timer.periodic(const Duration(minutes: 20), (_) => _loadWeather(force: true));
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) => _checkUpdate(force: true));
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
    _dropTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_fg) return;
      final s = SettingsScope.read(context);
      kDrop.refresh(s.serverUrl, s.serverToken);
    });
    kUpdate.addListener(_onUpdateFound);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _idleTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkIdle());
  }

  Timer? _sportsTimer;

  /// "Open on TV" from the phone page. Only acts while Foyer is on screen.
  void _onDropCommand(String type, String value) {
    if (!mounted || !_fg) return;
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
    return false;
  }

  void _checkIdle() {
    if (!mounted || !_fg || _saverUp || _leaving) return;
    final mins = SettingsScope.read(context).ssMinutes;
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
        return Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            autofocus: true,
            onKeyEvent: (_, e) {
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // runs on first build and whenever settings change
    _load();
    _loadPlex();
    _loadWeather();
    _loadSports();
    _checkUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plexTimer?.cancel();
    _weatherTimer?.cancel();
    _sportsTimer?.cancel();
    _dropTimer?.cancel();
    _idleTimer?.cancel();
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
      _loadWeather(force: true);
      _loadSports();
      if (_leaving) setState(() => _leaving = false);
      _load();
      _loadPlex(force: true);
      _checkUpdate(force: true);
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
        for (final p in pinned)
          if (_cache[p] != null && _cache[p] != _missingMarker) _cache[p]!
      ];

  /// Opens the title's own page in Plex; the Plex app if there's no link to use.
  Future<void> _openPlexItem(PlexItem it) async {
    // seasons open the show; movies and episodes open themselves
    final link = it.type == 'season' ? it.showLink : it.plexLink;
    if (link.isNotEmpty) {
      bool ok = false;
      try {
        ok = (await kChannel.invokeMethod<bool>('openLink', {'url': link, 'package': kPlexPackage})) ?? false;
      } catch (_) {}
      if (ok) return;
    }
    _openPkg(kPlexPackage);
  }

  Future<void> _loadPlex({bool force = false}) async {
    final s = SettingsScope.read(context);
    final sig = '${s.plexUrl}|${s.plexToken}';
    if (s.plexUrl.isEmpty || s.plexToken.isEmpty) {
      _plex = null;
      _plexSig = sig;
      return;
    }
    if (!force && sig == _plexSig) return;
    _plexSig = sig;
    try {
      final row = await PlexApi(s.clientId)
          .fetchRow(PlexServer(s.plexName, s.plexUrl, s.plexToken));
      if (mounted) setState(() => _plex = row.items.isEmpty ? null : row);
    } catch (_) {}
  }

  Future<void> _checkUpdate({bool force = false}) async {
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
          await UpdateApi.check(url, s.updateToken, await appBuild(), await appName());
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
    if (_leaving) return;
    setState(() => _leaving = true);
    await Future.delayed(const Duration(milliseconds: 190));
    final ok = await launchPackage(pkg);
    if (!ok && mounted) setState(() => _leaving = false);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _leaving) setState(() => _leaving = false);
    });
  }

  void _openFireplace() {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 700),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const FireplaceScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  void _openAllApps() {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const AllAppsScreen(),
      // plain fade: the zoom-in made a strip down the right edge of this screen on some sticks
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  void _tileMenu(AppInfo a, int index, int count) {
    final s = SettingsScope.read(context);
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
      MenuChoice('Remove from home',
          () => s.setPinned(s.pinned.where((p) => p != a.package).toList())),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final apps = _shown(settings.pinned);
    return PopScope(
      canPop: false,
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
                      tint: (apps.isEmpty || i >= apps.length)
                          ? kDefaultTint
                          : apps[clampIdx(i, apps.length - 1)].glow),
                ),
              ),
            ),
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
    final count = apps.length + 1; // + the All apps tile
    // room on the left for the two round buttons
    const avail = 1920.0 - 200 - 100 - 80;
    final tileW = ((avail - 28.0 * (count - 1)) / count).clamp(120.0, 240.0).toDouble();
    return Stack(children: [
      Positioned(
          left: 72,
          top: 44,
          child: FadeTransition(
              opacity: _fadeEarly,
              child: Glass(
                  radius: 40,
                  child: SeasonGreeting(
                      season: activeSeason(settings), fallback: 'Welcome to ${settings.name}')))),
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
                FocusButton(
                  onSelect: widget.onOpenSettings,
                  builder: (_, f) => AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(44),
                        border: Border.all(color: f ? Colors.white : Colors.transparent, width: 3)),
                    child: Glass(
                        radius: 40,
                        padding: const EdgeInsets.all(16),
                        child: ValueListenableBuilder<UpdateInfo?>(
                          valueListenable: kUpdate,
                          builder: (_, u, __) => Stack(clipBehavior: Clip.none, children: [
                            Icon(Icons.settings_rounded,
                                size: 30, color: f ? Colors.white : Colors.white70),
                            if (u != null)
                              Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFFF9F0A), shape: BoxShape.circle))),
                          ]),
                        )),
                  ),
                ),
                const SizedBox(width: 16),
                ValueListenableBuilder<List<GameLine>>(
                    valueListenable: kSports.games,
                    builder: (_, g, __) => g.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 16), child: ScorePill(games: g))),
                const SleepPill(),
                if (_weather != null) ...[
                  _WeatherPill(w: _weather!),
                  const SizedBox(width: 16),
                ],
                const _ClockPill(),
              ]))),
      if (_plex != null)
        Positioned(
            left: 96,
            right: 96,
            top: 190,
            child: FadeTransition(opacity: _fadeLate, child: _plexRow(_plex!))),
      Positioned(
          right: 96,
          bottom: 300,
          child: FadeTransition(
              opacity: _fadeLate,
              child: const DropCorner())),
      Positioned(
          left: 96,
          bottom: 300,
          child: FadeTransition(opacity: _fadeLate, child: _hero(apps))),
      Positioned(
        left: 70,
        bottom: 44,
        child: FadeTransition(
          opacity: _fadeEarly,
          child: HomeSideButtons(
            onFireplace: _openFireplace,
            onGoodnight: () => goodnightMenu(context),
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
                onMenu: (a, i) => _tileMenu(a, i, apps.length),
                onAllApps: _openAllApps,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _plexRow(PlexRow row) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(row.title,
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                shadows: [Shadow(color: Color(0x80000000), blurRadius: 16)])),
        const SizedBox(height: 16),
        FocusTraversalGroup(
          child: Row(children: [
            for (final it in row.items)
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: _PlexCard(item: it, onOpen: () => _openPlexItem(it)),
              ),
          ]),
        ),
      ]);

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

class _WeatherPill extends StatelessWidget {
  const _WeatherPill({required this.w});
  final WeatherNow w;
  @override
  Widget build(BuildContext context) => Glass(
        radius: 40,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(w.icon, size: 32),
          const SizedBox(width: 12),
          Text('${w.temp.round()}°',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _PlexCard extends StatelessWidget {
  const _PlexCard({required this.item, required this.onOpen});
  final PlexItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => FocusButton(
        onSelect: onOpen,
        builder: (_, f) => SizedBox(
          width: 320,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 320,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: f ? Colors.white : Colors.white.withAlpha(50), width: f ? 3 : 1.2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(f ? 150 : 70),
                      blurRadius: f ? 28 : 12,
                      offset: Offset(0, f ? 16 : 6))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(item.imageUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 640,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1D2B))),
                  if (item.progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 6,
                          backgroundColor: Colors.black54,
                          color: Colors.white),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            if (item.subtitle.isNotEmpty)
              Text(item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, color: Colors.white60)),
          ]),
        ),
      );
}

class _ClockPill extends StatefulWidget {
  const _ClockPill();
  @override
  State<_ClockPill> createState() => _ClockPillState();
}

class _ClockPillState extends State<_ClockPill> {
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

  @override
  Widget build(BuildContext context) {
    final h24 = SettingsScope.of(context).clock24;
    final m = _now.minute.toString().padLeft(2, '0');
    final text = h24
        ? '${_now.hour.toString().padLeft(2, '0')}:$m'
        : '${_now.hour % 12 == 0 ? 12 : _now.hour % 12}:$m ${_now.hour < 12 ? 'AM' : 'PM'}';
    return Glass(
        radius: 40,
        child: Text(text, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)));
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
      required this.onAllApps});
  final List<AppInfo> apps;
  final double tileW;
  final Animation<double> intro;
  final ValueChanged<int> onFocused;
  final ValueChanged<AppInfo> onOpen;
  final void Function(AppInfo, int) onMenu;
  final VoidCallback onAllApps;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        child: Glass(
          radius: 44,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 34),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < apps.length; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 28),
                child: _Tile(
                  key: ValueKey(apps[i].package),
                  index: i,
                  w: tileW,
                  intro: intro,
                  art: appArt(apps[i], tileW),
                  onFocused: onFocused,
                  onActivate: () => onOpen(apps[i]),
                  onLongPress: () => onMenu(apps[i], i),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(left: apps.isEmpty ? 0 : 28),
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
      this.onLongPress});
  final int index;
  final double w;
  final Animation<double> intro;
  final Widget art;
  final ValueChanged<int> onFocused;
  final VoidCallback onActivate;
  final VoidCallback? onLongPress;
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

  double get _h => widget.w * 9 / 16;

  @override
  void initState() {
    super.initState();
    final s = (0.25 + widget.index * 0.07).clamp(0.0, 0.5).toDouble();
    final e = (s + 0.45).clamp(0.0, 1.0).toDouble();
    _intro = CurvedAnimation(
        parent: widget.intro, curve: Interval(s, e, curve: Curves.easeOutCubic));
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
  }

  @override
  void dispose() {
    _node.dispose();
    _fc.dispose();
    _shine.dispose();
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
                animation: Listenable.merge([_intro, _f]),
                child: _body(),
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, -16 * _f.value + 30 * (1 - _intro.value)),
                  child: Transform.scale(
                      scale: (0.86 + 0.14 * _intro.value) * (1 + 0.14 * _f.value),
                      child: child),
                ),
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
              widget.art,
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

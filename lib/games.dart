// Games: your own game files, with their box art, played in the right emulator.
// Game Boy (Color/Advance), NES, SNES, N64 and Sega games play in RetroArch; GameCube and
// Wii in Dolphin. Files live in a Games folder on the box (on the TV: Foyer/Games on its
// storage; on a PC: Documents\Foyer Games). Games sent from a phone with Foyer Drop
// (Games tab) are downloaded into it by themselves.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'screens.dart';
import 'controllers.dart';

class GameSystem {
  const GameSystem(this.id, this.name, this.short, this.exts, this.color, this.thumbs, this.core);
  final String id; // also the folder name in the Games folder
  final String name;
  final String short;
  final List<String> exts;
  final int color;
  final String thumbs; // libretro-thumbnails collection, for box art
  final String core; // RetroArch core ('' = Dolphin)
  bool get dolphin => core.isEmpty;
}

const List<GameSystem> kSystems = [
  GameSystem('gba', 'Game Boy Advance', 'GBA', ['gba'], 0xFF4B3FB8, 'Nintendo - Game Boy Advance', 'mgba'),
  GameSystem('gbc', 'Game Boy Color', 'GBC', ['gbc'], 0xFF7E36C9, 'Nintendo - Game Boy Color', 'gambatte'),
  GameSystem('gb', 'Game Boy', 'Game Boy', ['gb'], 0xFF6E7D45, 'Nintendo - Game Boy', 'gambatte'),
  GameSystem('snes', 'Super Nintendo', 'SNES', ['sfc', 'smc'], 0xFF5B4CA8, 'Nintendo - Super Nintendo Entertainment System',
      'snes9x'),
  GameSystem('nes', 'NES', 'NES', ['nes'], 0xFFB0302A, 'Nintendo - Nintendo Entertainment System', 'fceumm'),
  GameSystem('n64', 'Nintendo 64', 'N64', ['n64', 'z64', 'v64'], 0xFF23824F, 'Nintendo - Nintendo 64', 'mupen64plus_next'),
  GameSystem('gc', 'GameCube and Wii', 'GameCube', ['iso', 'rvz', 'gcm', 'gcz', 'ciso', 'wbfs', 'wia'], 0xFF5E4E8C,
      'Nintendo - GameCube', ''),
  GameSystem('md', 'Mega Drive / Genesis', 'Genesis', ['md', 'gen', 'smd'], 0xFF202733, 'Sega - Mega Drive - Genesis',
      'genesis_plus_gx'),
  GameSystem('sms', 'Master System', 'Master System', ['sms'], 0xFF3A3F4A, 'Sega - Master System - Mark III',
      'genesis_plus_gx'),
  GameSystem('gg', 'Game Gear', 'Game Gear', ['gg'], 0xFF2C3550, 'Sega - Game Gear', 'genesis_plus_gx'),
];

GameSystem? systemFor(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  for (final s in kSystems) {
    if (s.exts.contains(ext)) return s;
  }
  return null;
}

class Game {
  Game(this.path, this.title, this.system, this.size);
  final String path;
  final String title; // the file name without its extension, e.g. "Advance Wars (USA)"
  final GameSystem system;
  final int size;

  /// The title without the region and version bits, for the card: "Advance Wars".
  String get name => title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '').trim();
}

/// Every game on this box. Empty until the first scan.
final ValueNotifier<List<Game>> kGames = ValueNotifier(const []);
String _dir = '';

Future<String> gamesFolder() async {
  if (_dir.isNotEmpty) return _dir;
  try {
    _dir = (await kChannel.invokeMethod<String>('gamesDir')) ?? '';
  } catch (_) {}
  return _dir;
}

/// Looks through the Games folder (and its folders, a few levels deep).
Future<void> scanGames() async {
  final dir = await gamesFolder();
  if (dir.isEmpty) return;
  final out = <Game>[];
  try {
    await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final p = e.path;
      if (p.contains('${Platform.pathSeparator}.')) continue; // .covers and hidden files
      final sys = systemFor(p);
      if (sys == null) continue;
      final name = p.split(Platform.pathSeparator).last;
      final title = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      int size = 0;
      try {
        size = await e.length();
      } catch (_) {}
      out.add(Game(p, title, sys, size));
    }
  } catch (_) {}
  out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  kGames.value = out;
}

// ───────────────────────── box art ─────────────────────────

final Map<String, Future<Uint8List?>> _covers = {};

/// Box art from the libretro thumbnails collection (matched by the game's file name,
/// which works best with the usual "Title (Region)" names). Cached in the Games folder.
Future<Uint8List?> coverFor(Game g) => _covers.putIfAbsent(g.path, () => _cover(g));

Future<Uint8List?> _cover(Game g) async {
  final dir = await gamesFolder();
  if (dir.isEmpty) return null;
  final sep = Platform.pathSeparator;
  final safe = g.title.replaceAll(RegExp(r'[&*/:`<>?\\|"]'), '_');
  final cache = File('$dir$sep.covers$sep${g.system.id}$sep$safe.png');
  final none = File('${cache.path}.none');
  try {
    if (await cache.exists()) return await cache.readAsBytes();
    if (await none.exists()) return null;
    await cache.parent.create(recursive: true);
    final repo = g.system.thumbs.replaceAll(' ', '_');
    final url = 'https://raw.githubusercontent.com/libretro-thumbnails/$repo/master/Named_Boxarts/'
        '${Uri.encodeComponent(safe)}.png';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final res = await (await c.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        await none.writeAsString('');
        return null;
      }
      final b = BytesBuilder();
      await for (final chunk in res) {
        b.add(chunk);
      }
      final bytes = b.takeBytes();
      await cache.writeAsBytes(bytes);
      return bytes;
    } finally {
      c.close(force: true);
    }
  } catch (_) {
    return null;
  }
}

// ───────────────────────── playing ─────────────────────────

/// Opens the game in its emulator. Explains what to install when the emulator is missing.
Future<void> playGame(BuildContext context, Game g) async {
  final s = SettingsScope.read(context);
  s.change(() => s.gamesPlayed = {...s.gamesPlayed, g.path: DateTime.now().millisecondsSinceEpoch});
  String r = 'error';
  try {
    r = (await kChannel.invokeMethod<String>(
            'launchGame', {'path': g.path, 'system': g.system.id, 'core': g.system.core})) ??
        'error';
  } catch (_) {}
  if (r == 'ok' || !context.mounted) return;
  if (r == 'missing:retroarch' || r == 'missing:dolphin') {
    final ra = r == 'missing:retroarch';
    final name = ra ? 'RetroArch' : 'Dolphin';
    showMenu2(context, '$name isn\'t installed', [
      MenuChoice(
          ra
              ? '${g.system.name} games play in RetroArch, a free player for classic consoles.'
              : 'GameCube and Wii games play in Dolphin, a free emulator.',
          null),
      MenuChoice(kIsPc ? 'Open the $name download page' : 'Get $name from the Play Store', () {
        final url = kIsPc
            ? (ra ? 'https://www.retroarch.com/?page=platforms' : 'https://dolphin-emu.org/download/')
            : 'market://details?id=${ra ? 'com.retroarch.aarch64' : 'org.dolphinemu.dolphinemu'}';
        kChannel.invokeMethod('openUrl', {'url': url}).catchError((Object _) => null);
      }),
      MenuChoice('Cancel', () {}),
    ]);
    return;
  }
  if (r.startsWith('missing:core')) {
    showInfo(context, 'RetroArch needs its ${g.system.short} part',
        'Open RetroArch once: Main Menu → Online Updater → Core Downloader, then pick '
        '"${_coreLabel(g.system.core)}". After that, ${g.system.short} games open straight from Foyer.');
    return;
  }
  showInfo(context, 'Couldn\'t open ${g.name}', 'The emulator didn\'t start. Try opening it once by itself, then try again.');
}

String _coreLabel(String core) => switch (core) {
      'mgba' => 'Nintendo - Game Boy Advance (mGBA)',
      'gambatte' => 'Nintendo - Game Boy / Color (Gambatte)',
      'snes9x' => 'Nintendo - SNES / SFC (Snes9x - Current)',
      'fceumm' => 'Nintendo - NES / Famicom (FCEUmm)',
      'mupen64plus_next' => 'Nintendo - Nintendo 64 (Mupen64Plus-Next)',
      _ => 'Sega - MS/GG/MD/CD (Genesis Plus GX)',
    };

// ───────────────────────── games sent with Foyer Drop ─────────────────────────

bool _syncing = false;

/// Downloads games sent from a phone into the Games folder, and removes ones taken off
/// Foyer Drop (only those that came from it). Runs when Foyer Drop says something changed.
Future<void> syncDropGames(String url, String token) async {
  if (_syncing || url.isEmpty || token.isEmpty) return;
  _syncing = true;
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final dir = await gamesFolder();
    if (dir.isEmpty) return;
    final sep = Platform.pathSeparator;
    final manifest = File('$dir$sep.drop.json');
    Map<String, dynamic> have = {};
    try {
      have = Map<String, dynamic>.from(jsonDecode(await manifest.readAsString()) as Map);
    } catch (_) {}
    final req = await c.getUrl(Uri.parse('$url/api/games'));
    req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return;
    }
    final list = (jsonDecode(await res.transform(utf8.decoder).join()) as Map)['games'] as List? ?? const [];
    final ids = <String>{};
    for (final g in list) {
      if (g is! Map) continue;
      final id = '${g['id']}', name = '${g['name']}';
      ids.add(id);
      if (have.containsKey(id)) continue;
      final sys = systemFor(name);
      if (sys == null) continue;
      final file = File('$dir$sep${sys.id}$sep$name');
      await file.parent.create(recursive: true);
      final r = await c.getUrl(Uri.parse('$url/games/$id'));
      r.headers.set('Authorization', 'Bearer $token');
      final resp = await r.close();
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        continue;
      }
      final part = File('${file.path}.part');
      final sink = part.openWrite();
      await resp.pipe(sink);
      await part.rename(file.path);
      have[id] = file.path;
    }
    // taken off Foyer Drop: take it off the TV too
    for (final id in have.keys.toList()) {
      if (ids.contains(id)) continue;
      try {
        await File('${have[id]}').delete();
      } catch (_) {}
      have.remove(id);
    }
    await manifest.writeAsString(jsonEncode(have));
    await scanGames();
  } catch (_) {
  } finally {
    c.close(force: true);
    _syncing = false;
  }
}

// ───────────────────────── the Games tile on the home screen ─────────────────────────

const String kGamesTile = 'foyer.games';
Uint8List? kGamesTileArt;
String _tileLang = '';

Future<void> makeGamesTileArt() async {
  if (kGamesTileArt != null && _tileLang == kLang) return;
  _tileLang = kLang;
  const w = 640.0, h = 360.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
            Offset.zero, const Offset(w, h), [const Color(0xFF6D5BD0), const Color(0xFF1E1A3D)]));
  final icon = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(Icons.sports_esports_rounded.codePoint),
          style: TextStyle(fontFamily: Icons.sports_esports_rounded.fontFamily, fontSize: 150, color: Colors.white)),
      textDirection: TextDirection.ltr)
    ..layout();
  icon.paint(c, Offset((w - icon.width) / 2, 60));
  final t = TextPainter(
      text: TextSpan(
          text: tr('Games'),
          style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 64, fontWeight: FontWeight.w800, color: Colors.white)),
      textDirection: TextDirection.ltr)
    ..layout();
  t.paint(c, Offset((w - t.width) / 2, 220));
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  kGamesTileArt = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

// ───────────────────────── the Games screen ─────────────────────────

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});
  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  @override
  void initState() {
    super.initState();
    scanGames();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return ValueListenableBuilder<List<Game>>(
      valueListenable: kGames,
      builder: (_, games, __) {
        final recent = [...games.where((g) => s.gamesPlayed.containsKey(g.path))]
          ..sort((a, b) => (s.gamesPlayed[b.path] ?? 0).compareTo(s.gamesPlayed[a.path] ?? 0));
        final rows = <Widget>[];
        var first = true;
        void row(String title, List<Game> list) {
          if (list.isEmpty) return;
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 0, 16),
            child: Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          ));
          rows.add(SizedBox(
            height: 330,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 24),
              itemBuilder: (_, i) => _GameCard(game: list[i], autofocus: first && i == 0),
            ),
          ));
          rows.add(const SizedBox(height: 26));
          first = false;
        }

        row('Continue playing', recent.take(10).toList());
        for (final sys in kSystems) {
          row(sys.name, games.where((g) => g.system.id == sys.id).toList());
        }
        return SettingsPage(
          title: 'Games',
          subtitle: games.isEmpty ? null : '${games.length} ${games.length == 1 ? 'game' : 'games'}',
          actions: [PillButton(label: 'Games settings', onSelect: () => _open(context))],
          child: games.isEmpty
              ? _Empty(onSettings: () => _open(context))
              : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows)),
        );
      },
    );
  }

  void _open(BuildContext c) =>
      Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const GamesSettingsScreen()));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onSettings});
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: gamesFolder(),
        builder: (_, f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('No games yet', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          const Text('• From your phone: Foyer Drop → Games → Choose game files. They show up here by themselves.',
              style: TextStyle(fontSize: 26, color: Colors.white70)),
          const SizedBox(height: 10),
          Text('• Or copy them into the Games folder: ${f.data ?? '…'}',
              style: const TextStyle(fontSize: 26, color: Colors.white70)),
          const SizedBox(height: 10),
          const Text('Game Boy Advance, Game Boy, NES, SNES, N64, Sega and GameCube/Wii games. Only use games you own.',
              style: TextStyle(fontSize: 22, color: Colors.white54)),
          const SizedBox(height: 30),
          PillButton(label: 'Games settings', autofocus: true, onSelect: onSettings),
        ]),
      );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, this.autofocus = false});
  final Game game;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        scale: 1.06,
        onSelect: () => playGame(context, game),
        onLongPress: () => _menu(context),
        builder: (_, f) => SizedBox(
          width: 230,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 230,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Color(game.system.color),
                border: Border.all(color: Colors.white.withAlpha(f ? 255 : 40), width: f ? 4 : 1.5),
                boxShadow: f ? const [BoxShadow(color: Color(0x88000000), blurRadius: 30, offset: Offset(0, 12))] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Uint8List?>(
                future: coverFor(game),
                builder: (_, snap) => snap.data != null
                    ? Container(
                        color: Colors.black.withAlpha(60),
                        padding: const EdgeInsets.all(10),
                        child: Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true))
                    : Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.sports_esports_rounded, size: 64, color: Colors.white70),
                          const SizedBox(height: 12),
                          Text(game.name,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                        ]),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(game.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: f ? Colors.white : Colors.white70)),
            Text(game.system.short, style: const TextStyle(fontSize: 18, color: Colors.white38)),
          ]),
        ),
      );

  void _menu(BuildContext context) => showMenu2(context, game.name, [
        MenuChoice('Play', () => playGame(context, game)),
        MenuChoice('Delete from this ${kIsPc ? 'PC' : 'TV'}', () async {
          try {
            await File(game.path).delete();
          } catch (_) {}
          scanGames();
        }),
        MenuChoice('Cancel', () {}),
      ]);
}

// ───────────────────────── Games settings ─────────────────────────

class GamesSettingsScreen extends StatefulWidget {
  const GamesSettingsScreen({super.key});
  @override
  State<GamesSettingsScreen> createState() => _GamesSettingsScreenState();
}

class _GamesSettingsScreenState extends State<GamesSettingsScreen> {
  /// Starts a game (a GBA one if there is one) and collects what RetroArch said: a report
  /// to show (and photograph) when something doesn't start.
  Future<void> _check(BuildContext context) async {
    final games = kGames.value.where((g) => !g.system.dolphin).toList();
    if (games.isEmpty) return;
    final g = games.firstWhere((x) => x.system.id == 'gba', orElse: () => games.first);
    showInfo(context, 'Checking with ${g.name}',
        'RetroArch opens for about 10 seconds, then Foyer comes back with what it found. Leave the remote for a moment.');
    String report = '';
    try {
      report = (await kChannel.invokeMethod<String>('diagnoseGame', {'path': g.path, 'core': g.system.core})) ?? '';
    } catch (e) {
      report = 'Couldn\'t check: $e';
    }
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r is! PopupRoute); // the "Checking" note
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
              title: 'What RetroArch said',
              subtitle: 'Also saved in the Games folder as retroarch-check.txt. A photo of this screen is enough to find the problem.',
              child: _ReportView(report),
            )));
  }

  Map<String, dynamic> _st = {};
  String _dirPath = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gamesFolder();
    Map<String, dynamic> st = {};
    try {
      st = (await kChannel.invokeMapMethod<String, dynamic>('gamesStatus')) ?? {};
    } catch (_) {}
    if (mounted) {
      setState(() {
        _dirPath = d;
        _st = st;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final ra = _st['retroarch'] == true, dol = _st['dolphin'] == true;
    Widget line(bool ok, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 30, color: ok ? const Color(0xFF8CE99A) : Colors.white38),
            const SizedBox(width: 14),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 24, color: Colors.white70))),
          ]),
        );
    return SettingsPage(
      title: 'Games settings',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Games tile on the home screen', style: TextStyle(fontSize: 28, color: Colors.white70)),
          const SizedBox(height: 14),
          Wrap(spacing: 16, children: [
            Opt(
                autofocus: true,
                label: 'Show it',
                selected: s.gamesOnHome,
                onSelect: () => s.change(() => s.gamesOnHome = true)),
            Opt(label: 'Hide it', selected: !s.gamesOnHome, onSelect: () => s.change(() => s.gamesOnHome = false)),
          ]),
          const SizedBox(height: 34),
          const Text('Players', style: TextStyle(fontSize: 28, color: Colors.white70)),
          const SizedBox(height: 14),
          line(ra, ra ? 'RetroArch is installed (Game Boy, NES, SNES, N64, Sega)' : 'RetroArch isn\'t installed (Game Boy, NES, SNES, N64, Sega)'),
          line(dol, dol ? 'Dolphin is installed (GameCube and Wii)' : 'Dolphin isn\'t installed (GameCube and Wii)'),
          const SizedBox(height: 8),
          Text(
              'In RetroArch, download each console\'s part once: Main Menu → Online Updater → Core Downloader → '
              'mGBA (Game Boy Advance), Gambatte (Game Boy), FCEUmm (NES), Snes9x (SNES), Mupen64Plus-Next (N64), '
              'Genesis Plus GX (Sega).${kIsPc ? '' : ' Plug in a controller, or pair one over Bluetooth.'}',
              style: const TextStyle(fontSize: 22, color: Colors.white54)),
          const SizedBox(height: 34),
          const Text('Adding games', style: TextStyle(fontSize: 28, color: Colors.white70)),
          const SizedBox(height: 14),
          const Text('From your phone or computer: Foyer Drop → Games → Choose game files.',
              style: TextStyle(fontSize: 24, color: Colors.white70)),
          const SizedBox(height: 8),
          Text('Or copy them into the Games folder: $_dirPath',
              style: const TextStyle(fontSize: 24, color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
              kIsPc
                  ? 'To play: OK opens a game. Back + Start on the controller (held a moment), or Home on the remote, closes it and comes back to Foyer.'
                  : 'To play: OK opens a game. Home on the remote comes back to Foyer.',
              style: const TextStyle(fontSize: 22, color: Colors.white54)),
          const SizedBox(height: 8),
          const Text('Only use games you own.', style: TextStyle(fontSize: 22, color: Colors.white54)),
        ]),
      ),
      actions: [
        if (!kIsPc && kGames.value.isNotEmpty)
          PillButton(label: 'Check that games work', onSelect: () => _check(context)),
        if (!kIsPc)
          PillButton(
              label: 'Add a controller',
              onSelect: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ControllerPairScreen()))),
        PillButton(
            label: 'Look for games again',
            onSelect: () async {
              await scanGames();
              await _load();
            }),
      ],
    );
  }
}


/// Long text that the remote's up and down arrows scroll.
class _ReportView extends StatefulWidget {
  const _ReportView(this.text);
  final String text;
  @override
  State<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<_ReportView> {
  final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyUpEvent || !_c.hasClients) return KeyEventResult.ignored;
          final k = e.logicalKey;
          final step = k == LogicalKeyboardKey.arrowDown ? 220.0 : (k == LogicalKeyboardKey.arrowUp ? -220.0 : 0.0);
          if (step == 0) return KeyEventResult.ignored;
          _c.animateTo((_c.offset + step).clamp(0.0, _c.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
          return KeyEventResult.handled;
        },
        child: SingleChildScrollView(
          controller: _c,
          child: Text(widget.text,
              style: const TextStyle(fontSize: 19, height: 1.35, fontFamily: 'monospace', color: Colors.white70)),
        ),
      );
}

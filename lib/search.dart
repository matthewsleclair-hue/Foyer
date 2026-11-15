// Search everything: type a show, a movie, an app or a game. Foyer shows which of your
// streaming apps have it (from TMDB, through your Foyer Drop server, for Canada), what's on
// your Plex, and matching apps and games. Picking a service opens that app on its search
// for the show (or just the app, when it doesn't take searches from outside).
import 'dart:io' show HttpException;
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'games.dart';
import 'plex.dart';
import 'screens.dart';
import 'server.dart';
import 'tmdb.dart';
import 'jw.dart';

/// Streaming services: their name on TMDB (squashed, see _squash) → the app on a TV and on a PC.
const Map<String, List<String>> _tvApps = {
  'netflix': ['com.netflix.ninja', 'com.netflix.mediaclient'],
  'crave': ['ca.bellmedia.cravetv', 'ca.bellmedia.crave'],
  'disneyplus': ['com.disney.disneyplus'],
  'primevideo': ['com.amazon.amazonvideo.livingroom', 'com.amazon.avod.thirdpartyclient'],
  'appletv': ['com.apple.atve.androidtv.appletv', 'com.apple.atve.amazon.appletv'],
  'paramountplus': ['com.cbs.ott', 'com.cbs.ca'],
  'youtube': ['com.google.android.youtube.tv', 'com.google.android.youtube.tvunplugged'],
  'plex': ['com.plexapp.android'],
  'tubi': ['com.tubitv'],
  'plutotv': ['tv.pluto.android'],
  'cbcgem': ['ca.cbc.android.cbctv'],
  'crunchyroll': ['com.crunchyroll.crunchyroid'],
};
const Map<String, String> _pcApps = {
  'netflix': 'pc.netflix',
  'crave': 'pc.crave',
  'disneyplus': 'pc.disney',
  'primevideo': 'pc.prime',
  'appletv': 'pc.appletv',
  'paramountplus': 'pc.paramount',
  'youtube': 'pc.youtube',
  'plex': 'pc.plex',
};

/// "Amazon Prime Video with Ads" → "primevideowithads", "Disney Plus" → "disneyplus"
String _squash(String s) => s
    .toLowerCase()
    .replaceAll('+', 'plus')
    .replaceAll('amazon ', '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// The service's key ('netflix') for a TMDB provider name, or ''.
String _keyFor(String provider) {
  final p = _squash(provider);
  final keys = _tvApps.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (p.startsWith(k)) return k;
  }
  return '';
}

/// The app on this box for a streaming service ('netflix'), if it's installed.
InstalledApp? appForService(String key, List<InstalledApp> installed) {
  if (key.isEmpty) return null;
  final want = kIsPc ? [if (_pcApps[key] != null) _pcApps[key]!] : (_tvApps[key] ?? const <String>[]);
  for (final p in want) {
    for (final a in installed) {
      if (a.package == p) return a;
    }
  }
  // an app with the same name, under a package Foyer doesn't know
  for (final a in installed) {
    if (_squash(a.label).startsWith(key)) return a;
  }
  return null;
}

/// "Put on Bluey" from the phone (Foyer Drop): finds the show, picks a service that includes it
/// and that this box has (the apps on the home screen first), and opens the show there.
/// When none of the apps has it, a note on the TV says where it is.
Future<void> putOn(String name, Settings s) async {
  void note(String event, String line) => kChannel.invokeMethod('alert', {
        'emoji': '🔎',
        'event': tr(event),
        'line': line,
        'color': '74C0FC',
        'size': 1,
      }).catchError((_) => null);
  List<JwTitle> found;
  try {
    found = await jwFind(name, lang: s.lang);
  } catch (_) {
    note('Couldn\'t search right now', name);
    return;
  }
  if (found.isEmpty) {
    note('Nothing found', name);
    return;
  }
  // the exact name first (Bluey, not "Bluey's Big Play"), then JustWatch's order
  final want = _squash(name);
  final titles = [...found]..sort((a, b) => (_squash(a.title) == want ? 0 : 1) - (_squash(b.title) == want ? 0 : 1));
  final installed = await fetchInstalledApps();
  final pinned = s.pinned;
  for (final t in titles.take(3)) {
    final offers = [
      for (final o in t.offers)
        if (o.kind == 'included') (o, appForService(_keyFor(o.service), installed))
    ];
    final mine = [for (final x in offers) if (x.$2 != null) x]
      // apps on the home screen first, in their order
      ..sort((a, b) {
        int rank(InstalledApp app) {
          final i = pinned.indexOf(app.package);
          return i < 0 ? 999 : i;
        }
        return rank(a.$2!) - rank(b.$2!);
      });
    if (mine.isNotEmpty) {
      final (o, app) = mine.first;
      final key = _keyFor(o.service);
      final how = await openTitleIn(app!.package, key, t.title, t, sameService: (n) => n == o.service);
      if (how.isNotEmpty) {
        s.noteRecent(app.package);
        if (how == 'opened') note('Search for it there', '${t.title} · ${app.label}');
        return;
      }
    }
    if (offers.isNotEmpty && _squash(t.title) == want) {
      final where = {for (final x in offers) x.$1.service}.take(3).join(', ');
      note('Not on your apps', '${t.title} · $where');
      return;
    }
  }
  note('Not streaming here', titles.first.title);
}

class _Service {
  _Service(this.name, this.key, this.app, this.how);
  final String name; // as TMDB calls it
  final String key; // 'netflix', or ''
  final InstalledApp? app; // the app on this box, if it's there
  final String how; // included, rent, buy
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';
  bool _busy = false;
  String _note = '';
  int _run = 0;
  String _country = 'CA';
  int _hidden = 0; // results left out because they aren't streaming here
  List<InstalledApp> _installed = const [];
  List<Map<String, dynamic>> _watch = const [];
  List<PlexItem> _plex = const [];
  List<InstalledApp> _apps = const [];
  List<Game> _games = const [];

  @override
  void initState() {
    super.initState();
    fetchInstalledApps().then((a) {
      if (!mounted) return;
      setState(() => _installed = a);
      if (_q.isNotEmpty) _local(_q);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(first: true));
  }

  Future<void> _ask({bool first = false}) async {
    final t = await askText(context, 'Search', _q, hint: 'A show, a movie, an app or a game', maxLength: 60);
    if (!mounted) return;
    if (t == null || t.trim().isEmpty) {
      if (first && _q.isEmpty) Navigator.of(context).maybePop();
      return;
    }
    _search(t.trim());
  }

  void _local(String q) {
    final n = q.toLowerCase();
    setState(() {
      _apps = [
        for (final a in _installed)
          if (a.label.toLowerCase().contains(n)) a
      ].take(12).toList();
      _games = [
        for (final g in kGames.value)
          if (g.name.toLowerCase().contains(n) || g.title.toLowerCase().contains(n)) g
      ].take(12).toList();
    });
  }

  Future<void> _search(String q) async {
    final s = SettingsScope.read(context);
    final run = ++_run;
    setState(() {
      _q = q;
      _busy = true;
      _note = '';
      _watch = const [];
      _plex = const [];
      _hidden = 0;
    });
    _local(q);
    final jobs = <Future<void>>[];
    if (s.plexUrl.isNotEmpty && s.plexToken.isNotEmpty) {
      jobs.add(PlexApi(s.clientId)
          .search(PlexServer(s.plexName, s.plexUrl, s.plexToken), q)
          .then((l) {
        if (mounted && run == _run) setState(() => _plex = l);
      }).catchError((_) {}));
    }
    final key = s.tmdbKey.isNotEmpty ? s.tmdbKey : kBuiltInTmdbKey;
    final linked = s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty;
    if (key.isNotEmpty || linked) {
      jobs.add(myCountry().then((country) async {
        _country = country;
        final l = key.isNotEmpty
            ? await tmdbSearch(key, q, s.lang, country: country)
            : await DropApi.search(s.serverUrl, s.serverToken, q, s.lang, country: country);
        // only what's streaming here: at least one service that includes it (not just rent or buy)
        final here = [
          for (final r in l)
            if ((r['providers'] as List? ?? const []).any((p) => p is Map && p['how'] == 'included')) r
        ];
        if (mounted && run == _run) {
          setState(() {
            _watch = here;
            _hidden = l.length - here.length;
          });
        }
      }).catchError((Object e) {
        if (mounted && run == _run) {
          setState(() => _note = e is HttpException ? e.message : 'Couldn\'t search the streaming apps right now.');
        }
      }));
    } else {
      _note = 'Add a TMDB key in Developer options, or link Foyer Drop, to also see which streaming apps have it.';
    }
    await Future.wait(jobs);
    if (mounted && run == _run) setState(() => _busy = false);
  }

  InstalledApp? _appFor(String key) => appForService(key, _installed);

  List<_Service> _services(Map<String, dynamic> r) {
    final out = <_Service>[];
    final seen = <String>{};
    for (final p in (r['providers'] as List? ?? const [])) {
      if (p is! Map) continue;
      final name = '${p['name']}';
      final key = _keyFor(name);
      final app = _appFor(key);
      // "Netflix" and "Netflix basic with Ads" are the same app
      final id = app?.package ?? (key.isEmpty ? name : key);
      if (!seen.add('$id|${p['how'] == 'included'}')) continue;
      out.add(_Service(name, key, app, '${p['how']}'));
    }
    return out;
  }

  Future<void> _openService(_Service sv, Map<String, dynamic> r) async {
    final app = sv.app;
    if (app == null) return;
    final s = SettingsScope.read(context);
    final title = '${r['title'] ?? _q}';
    // the show's own page in the app, from JustWatch; the app's search if there's no link
    JwTitle? jw;
    try {
      jw = jwMatch(await jwFind(title, lang: s.lang), title, int.tryParse('${r['year']}') ?? 0, r['kind'] == 'tv');
    } catch (_) {}
    var how = await openTitleIn(app.package, sv.key, title, jw,
        sameService: (n) => n == sv.name || (sv.key.isNotEmpty && _keyFor(n) == sv.key));
    if (how.isEmpty) how = await launchPackage(app.package) ? 'opened' : '';
    if (how.isNotEmpty) s.noteRecent(app.package);
    if (!mounted) return;
    if (how == 'opened') {
      showInfo(context, app.label, 'Search for “$title” there: ${app.label} doesn\'t let Foyer type it in for you.');
    } else if (how.isEmpty) {
      showInfo(context, app.label, 'Couldn\'t open ${app.label}.');
    }
  }

  Future<void> _openPlex(PlexItem p) async {
    final link = p.type == 'season' ? p.showLink : p.plexLink;
    var ok = false;
    if (link.isNotEmpty) {
      try {
        ok = (await kChannel.invokeMethod<bool>('openLink', {'url': link, 'package': kPlexPackage})) ?? false;
      } catch (_) {}
    }
    if (!ok) {
      final pc = kIsPc ? 'pc.plex' : kPlexPackage;
      try {
        ok = (await kChannel.invokeMethod<String>('searchInApp', {'package': pc, 'query': p.title, 'key': 'plex'})) !=
            null;
      } catch (_) {}
      if (!ok) await launchPackage(pc);
    }
  }

  // ── looks ──

  static const _h = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white);
  static const _dim = TextStyle(fontSize: 22, color: Colors.white60, height: 1.3);

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 34),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _h),
          const SizedBox(height: 14),
          ...children,
        ]),
      );

  Widget _chip(String label, VoidCallback onSelect, {Widget? leading, bool autofocus = false}) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: f ? Colors.white : Colors.white.withAlpha(28),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withAlpha(f ? 255 : 60), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Text(label,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: f ? Colors.black : Colors.white)),
          ]),
        ),
      );

  Widget _poster(String url, {double w = 120, double h = 180}) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: w,
          height: h,
          child: url.isEmpty
              ? Container(color: Colors.white10, child: const Icon(Icons.movie_rounded, size: 48, color: Colors.white38))
              : Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.white10, child: const Icon(Icons.movie_rounded, size: 48, color: Colors.white38))),
        ),
      );

  Widget _watchCard(Map<String, dynamic> r, bool first) {
    final sv = _services(r);
    final mine = [for (final x in sv) if (x.app != null && x.how == 'included') x];
    final elsewhere = [for (final x in sv) if (x.app == null && x.how == 'included') x.name];
    final rent = [for (final x in sv) if (x.how != 'included') x.name].toSet().toList();
    final year = '${r['year'] ?? ''}';
    final kind = r['kind'] == 'tv' ? 'Series' : 'Movie';
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _poster('${r['poster'] ?? ''}'),
        const SizedBox(width: 26),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['title']}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(year.isEmpty ? kind : '$kind · $year', style: _dim),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (var i = 0; i < mine.length; i++)
                _chip(
                  mine[i].app!.label,
                  () => _openService(mine[i], r),
                  autofocus: first && i == 0,
                  leading: mine[i].app!.icon.isEmpty
                      ? null
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(mine[i].app!.icon, width: 36, height: 36, fit: BoxFit.cover)),
                ),
              if (mine.isEmpty)
                _chip(
                  'Not on your apps',
                  () {},
                  autofocus: first,
                ),
            ]),
            if (elsewhere.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${tr('Also on')} ${elsewhere.join(', ')}', style: _dim),
            ],
            if (rent.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${tr('Rent or buy:')} ${rent.join(', ')}', style: _dim),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nothing = !_busy && _q.isNotEmpty && _watch.isEmpty && _plex.isEmpty && _apps.isEmpty && _games.isEmpty;
    var first = true;
    bool takeFirst() {
      final f = first;
      first = false;
      return f;
    }

    return SettingsPage(
      title: 'Search',
      subtitle: _q.isEmpty ? 'Shows, movies, apps and games' : '“$_q”',
      actions: [PillButton(label: 'New search', onSelect: _ask)],
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text('Searching…', style: TextStyle(fontSize: 26, color: Colors.white70)),
            ),
          if (_watch.isNotEmpty)
            _section('Where to watch', [for (final r in _watch) _watchCard(r, takeFirst())]),
          if (_plex.isNotEmpty)
            _section('On your Plex', [
              Wrap(spacing: 22, runSpacing: 22, children: [
                for (final p in _plex)
                  FocusButton(
                    autofocus: takeFirst(),
                    scrollIntoView: true,
                    onSelect: () => _openPlex(p),
                    builder: (_, f) => AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 340,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: f ? Colors.white : Colors.transparent, width: 3),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _poster(p.imageUrl, w: 328, h: 184),
                        const SizedBox(height: 8),
                        Text(p.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (p.subtitle.isNotEmpty) Text(p.subtitle, style: _dim, maxLines: 1),
                      ]),
                    ),
                  ),
              ]),
            ]),
          if (_apps.isNotEmpty)
            _section('Apps', [
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final a in _apps)
                  _chip(a.label, () => launchPackage(a.package),
                      autofocus: takeFirst(),
                      leading: a.icon.isEmpty
                          ? null
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(a.icon, width: 36, height: 36, fit: BoxFit.cover))),
              ]),
            ]),
          if (_games.isNotEmpty)
            _section('Games', [
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final g in _games)
                  _chip('${g.name} · ${g.system.short}', () => playGame(context, g), autofocus: takeFirst()),
              ]),
            ]),
          if (nothing)
            Text(
                _hidden > 0
                    ? '${tr('Nothing for “{}” is streaming in {} right now.').replaceFirst('{}', _q).replaceFirst('{}', tr(countryName(_country)))}'
                    : 'Nothing found for “$_q”.',
                style: const TextStyle(fontSize: 28, color: Colors.white70)),
          if (!_busy && _hidden > 0 && !nothing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  tr('Only showing what\'s streaming in {}.').replaceFirst('{}', tr(countryName(_country))),
                  style: _dim),
            ),
          if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note, style: _dim)),
          // TMDB's terms ask apps using its data to say so
          if (_watch.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                  'Where to watch comes from TMDB (themoviedb.org) and JustWatch. This product uses the TMDB API but is not endorsed or certified by TMDB.',
                  style: TextStyle(fontSize: 18, color: Colors.white38, height: 1.3)),
            ),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';

/// Live scores for the teams you follow, from ESPN's public (unofficial) data.
/// It can change without notice, so everything here fails quietly and the pill just hides.

class League {
  const League(this.key, this.label, this.path);
  final String key;
  final String label;
  final String path;
}

const List<League> kLeagues = [
  League('nhl', 'NHL', 'hockey/nhl'),
  League('mlb', 'MLB', 'baseball/mlb'),
  League('nba', 'NBA', 'basketball/nba'),
  League('nfl', 'NFL', 'football/nfl'),
  League('f1', 'F1', 'racing/f1'),
];

League leagueOf(String key) => kLeagues.firstWhere((l) => l.key == key, orElse: () => kLeagues.first);

class FollowedTeam {
  const FollowedTeam(this.league, this.id, this.abbr, this.name);
  final String league;
  final String id;
  final String abbr;
  final String name;

  Map<String, dynamic> toJson() => {'league': league, 'id': id, 'abbr': abbr, 'name': name};

  static FollowedTeam? fromJson(Object? j) {
    if (j is! Map) return null;
    final l = j['league'], i = j['id'];
    if (l is! String || i is! String || l.isEmpty || i.isEmpty) return null;
    return FollowedTeam(l, i, '${j['abbr'] ?? ''}', '${j['name'] ?? ''}');
  }

  static const FollowedTeam f1 = FollowedTeam('f1', 'f1', 'F1', 'Formula 1');
}

class GameLine {
  GameLine({
    required this.league,
    required this.state,
    this.awayAbbr = '',
    this.awayScore = '',
    this.homeAbbr = '',
    this.homeScore = '',
    this.detail = '',
    this.title = '',
  });
  final String league; // key
  final String state; // pre | in | post
  final String awayAbbr, awayScore, homeAbbr, homeScore;
  final String detail;
  final String title; // race name for F1
}

String _clockText(DateTime utc, bool h24) {
  final d = utc.toLocal();
  final now = DateTime.now();
  final m = d.minute.toString().padLeft(2, '0');
  final String t;
  if (h24) {
    t = '${d.hour.toString().padLeft(2, '0')}:$m';
  } else {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    t = '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  if (d.year == now.year && d.month == now.month && d.day == now.day) return t;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]} $t';
}

String _scoreOf(Object? v) {
  if (v == null) return '';
  if (v is Map) return '${v['displayValue'] ?? v['value'] ?? ''}';
  final s = '$v';
  return s == 'null' ? '' : s.split('.').first;
}

class SportsApi {
  static const _base = 'https://site.api.espn.com/apis/site/v2/sports';

  static Future<dynamic> _get(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw HttpException('ESPN answered ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }

  static Future<List<FollowedTeam>> teams(League l) async {
    final j = await _get('$_base/${l.path}/teams?limit=100');
    final out = <FollowedTeam>[];
    final sports = j['sports'];
    final leagues = (sports is List && sports.isNotEmpty) ? sports[0]['leagues'] : null;
    final teams = (leagues is List && leagues.isNotEmpty) ? leagues[0]['teams'] : null;
    if (teams is List) {
      for (final t in teams) {
        final tm = t is Map ? t['team'] : null;
        if (tm is! Map) continue;
        final id = '${tm['id'] ?? ''}';
        if (id.isEmpty) continue;
        final name = '${tm['displayName'] ?? tm['name'] ?? ''}';
        out.add(FollowedTeam(l.key, id, '${tm['abbreviation'] ?? name}', name));
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  static Future<List<GameLine>> games(List<FollowedTeam> followed, bool h24) async {
    final out = <GameLine>[];
    final byLeague = <String, List<FollowedTeam>>{};
    for (final t in followed) {
      byLeague.putIfAbsent(t.league, () => []).add(t);
    }
    for (final entry in byLeague.entries) {
      try {
        final l = leagueOf(entry.key);
        final j = await _get('$_base/${l.path}/scoreboard');
        final events = j['events'];
        if (events is! List) continue;
        if (l.key == 'f1') {
          final g = _race(events, h24);
          if (g != null) out.add(g);
          continue;
        }
        final ids = entry.value.map((t) => t.id).toSet();
        for (final e in events) {
          final g = _game(l.key, e, ids, h24);
          if (g != null) out.add(g);
        }
      } catch (_) {
        // one league failing should not hide the others
      }
    }
    // live first, then upcoming, then finished
    int rank(GameLine g) => g.state == 'in' ? 0 : (g.state == 'pre' ? 1 : 2);
    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out;
  }

  static GameLine? _game(String league, Object? e, Set<String> ids, bool h24) {
    if (e is! Map) return null;
    final comps = e['competitions'];
    if (comps is! List || comps.isEmpty) return null;
    final cs = comps[0]['competitors'];
    if (cs is! List || cs.length < 2) return null;
    String ab = '', as_ = '', hb = '', hs = '';
    var mine = false;
    for (final c in cs) {
      if (c is! Map) continue;
      final tm = c['team'];
      final id = tm is Map ? '${tm['id']}' : '';
      final abbr = tm is Map ? '${tm['abbreviation'] ?? tm['shortDisplayName'] ?? ''}' : '';
      if (ids.contains(id)) mine = true;
      if (c['homeAway'] == 'home') {
        hb = abbr;
        hs = _scoreOf(c['score']);
      } else {
        ab = abbr;
        as_ = _scoreOf(c['score']);
      }
    }
    if (!mine) return null;
    final st = e['status'] is Map ? e['status'] as Map : const {};
    final type = st['type'] is Map ? st['type'] as Map : const {};
    final state = '${type['state'] ?? 'pre'}';
    String detail;
    if (state == 'pre') {
      final d = DateTime.tryParse('${e['date']}');
      detail = d == null ? 'Today' : _clockText(d, h24);
    } else if (state == 'in') {
      detail = '${type['shortDetail'] ?? type['detail'] ?? 'Live'}';
    } else {
      detail = '${type['shortDetail'] ?? 'Final'}';
    }
    return GameLine(
        league: league,
        state: state,
        awayAbbr: ab,
        awayScore: as_,
        homeAbbr: hb,
        homeScore: hs,
        detail: detail);
  }

  /// F1 has no home or away: show a live session, or the next race weekend if it is close.
  static GameLine? _race(List events, bool h24) {
    final now = DateTime.now().toUtc();
    for (final e in events) {
      if (e is! Map) continue;
      final name = '${e['shortName'] ?? e['name'] ?? 'Grand Prix'}';
      final st = e['status'] is Map ? e['status'] as Map : const {};
      final type = st['type'] is Map ? st['type'] as Map : const {};
      final state = '${type['state'] ?? 'pre'}';
      final d = DateTime.tryParse('${e['date']}');
      if (state == 'in') {
        var session = '${type['shortDetail'] ?? 'Live'}';
        final comps = e['competitions'];
        if (comps is List) {
          for (final c in comps) {
            if (c is! Map) continue;
            final cst = c['status'] is Map ? (c['status'] as Map)['type'] : null;
            if (cst is Map && cst['state'] == 'in') {
              final t = c['type'];
              if (t is Map && t['abbreviation'] != null) session = '${t['abbreviation']} live';
            }
          }
        }
        return GameLine(league: 'f1', state: 'in', title: name, detail: session);
      }
      if (state == 'pre' && d != null) {
        final diff = d.difference(now);
        if (diff.inHours >= -2 && diff.inHours <= 72) {
          return GameLine(league: 'f1', state: 'pre', title: name, detail: _clockText(d, h24));
        }
      }
    }
    return null;
  }
}

/// Keeps the list of games for the home screen up to date without hammering the server.
class SportsFeed {
  final ValueNotifier<List<GameLine>> games = ValueNotifier(const []);
  String _sig = '';
  DateTime? _last;
  bool _busy = false;

  Future<void> refresh(List<FollowedTeam> teams, bool h24, {bool force = false}) async {
    if (teams.isEmpty) {
      _sig = '';
      if (games.value.isNotEmpty) games.value = const [];
      return;
    }
    final sig = '${teams.map((t) => '${t.league}:${t.id}').join(',')}|$h24';
    final live = games.value.any((g) => g.state == 'in');
    final age = _last == null ? 9999 : DateTime.now().difference(_last!).inSeconds;
    final due = sig != _sig || force || age >= (live ? 45 : 300);
    if (!due || _busy) return;
    _busy = true;
    _sig = sig;
    _last = DateTime.now();
    try {
      games.value = await SportsApi.games(teams, h24);
    } catch (_) {
      // keep showing the last good result
    }
    _busy = false;
  }
}

final SportsFeed kSports = SportsFeed();

// ───────────────────────── the pill on the home screen ─────────────────────────

class ScorePill extends StatefulWidget {
  const ScorePill({super.key, required this.games});
  final List<GameLine> games;
  @override
  State<ScorePill> createState() => _ScorePillState();
}

class _ScorePillState extends State<ScorePill> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && widget.games.length > 1) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) return const SizedBox.shrink();
    final g = widget.games[_i % widget.games.length];
    return Glass(
      radius: 40,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: KeyedSubtree(key: ValueKey('${g.league}${g.awayAbbr}${g.homeAbbr}${g.title}'), child: _row(g)),
      ),
    );
  }

  Widget _row(GameLine g) {
    const strong = TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
    const soft = TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: Colors.white70);
    final lg = leagueOf(g.league).label;
    final kids = <Widget>[
      if (g.state == 'in')
        Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 10),
            decoration: const BoxDecoration(color: Color(0xFFFF453A), shape: BoxShape.circle)),
      Text(lg, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white54)),
      const SizedBox(width: 12),
    ];
    if (g.league == 'f1') {
      kids.add(Text(g.title, style: strong));
    } else if (g.state == 'pre') {
      kids.add(Text('${g.awayAbbr} @ ${g.homeAbbr}', style: strong));
    } else {
      final a = int.tryParse(g.awayScore), h = int.tryParse(g.homeScore);
      final fin = g.state == 'post';
      final aWin = fin && a != null && h != null && a > h;
      final hWin = fin && a != null && h != null && h > a;
      kids.addAll([
        Text('${g.awayAbbr} ${g.awayScore}', style: aWin || !fin ? strong : soft),
        const Text('  –  ', style: soft),
        Text('${g.homeAbbr} ${g.homeScore}', style: hWin || !fin ? strong : soft),
      ]);
    }
    kids.addAll([const SizedBox(width: 14), Text(g.detail, style: soft)]);
    return Row(mainAxisSize: MainAxisSize.min, children: kids);
  }
}

// ───────────────────────── choosing teams ─────────────────────────

class SportsTeamsScreen extends StatefulWidget {
  const SportsTeamsScreen({super.key, required this.league});
  final League league;
  @override
  State<SportsTeamsScreen> createState() => _SportsTeamsScreenState();
}

class _SportsTeamsScreenState extends State<SportsTeamsScreen> {
  List<FollowedTeam>? _teams;
  String _err = '';

  @override
  void initState() {
    super.initState();
    SportsApi.teams(widget.league).then((t) {
      if (!mounted) return;
      setState(() {
        _teams = t;
        if (t.isEmpty) _err = 'No teams came back. Try again later.';
      });
    }).catchError((Object _) {
      if (mounted) setState(() => _err = 'Could not load the team list. Check the internet connection.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: '${widget.league.label} teams',
      subtitle: 'Choose the teams to follow. Their scores show on your home screen on game days.',
      child: _teams == null && _err.isEmpty
          ? const Text('Loading…', style: TextStyle(fontSize: 28, color: Colors.white70))
          : (_err.isNotEmpty
              ? Text(_err, style: const TextStyle(fontSize: 28, color: Colors.white70))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Wrap(spacing: 16, runSpacing: 16, children: [
                    for (var i = 0; i < _teams!.length; i++)
                      _TeamChip(
                        key: ValueKey(_teams![i].id),
                        name: _teams![i].name,
                        selected: s.follows(_teams![i]),
                        autofocus: i == 0,
                        onSelect: () => s.change(() => s.toggleTeam(_teams![i])),
                      ),
                  ]),
                )),
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip(
      {super.key,
      required this.name,
      required this.selected,
      required this.onSelect,
      this.autofocus = false});
  final String name;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        scale: 1.0,
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            color: f ? Colors.white : (selected ? Colors.white.withAlpha(56) : Colors.white.withAlpha(22)),
            border: Border.all(
                color: Colors.white.withAlpha(f ? 255 : (selected ? 170 : 70)), width: selected ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.check_rounded, size: 26, color: f ? Colors.black : Colors.white),
              ),
            Text(name, style: TextStyle(fontSize: 24, color: f ? Colors.black : Colors.white)),
          ]),
        ),
      );
}

// ───────────────────────── score alerts ─────────────────────────

/// 0 off, 1 scores only, 2 scores plus game start and final (Settings > Home screen > Score alerts).
int kScoreAlertLevel = 2;
const List<String> kScoreAlertNames = ['Off', 'Scores only', 'Scores, start and final'];

/// Watches the games of the teams you follow and pops a note over whatever is playing
/// when someone scores. Runs while Foyer is in the background too.
class ScoreAlerts {
  Map<String, GameLine> _last = {};
  bool _primed = false;
  Timer? _t;

  void start(Settings Function() read) {
    if (_t != null) return;
    kSports.games.addListener(_onGames);
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (kScoreAlertLevel == 0) return;
      try {
        final s = read();
        if (s.sportsTeams.isNotEmpty) kSports.refresh(s.sportsTeams, s.clock24);
      } catch (_) {}
    });
  }

  String _key(GameLine g) => '${g.league}|${g.awayAbbr}|${g.homeAbbr}|${g.title}';

  static int _n(String v) => int.tryParse(v.trim()) ?? 0;

  static String _what(String league, int pts, String team) {
    switch (league) {
      case 'nhl':
        return '🚨 $team goal!';
      case 'mlb':
        return pts == 1 ? '⚾ $team scores' : '⚾ $team scores $pts runs';
      case 'nfl':
        if (pts >= 6) return '🏈 $team touchdown!';
        if (pts == 3) return '🏈 $team field goal';
        if (pts == 2) return '🏈 $team, 2 points';
        return '🏈 $team scores';
      default:
        return '$team scores';
    }
  }

  void _alert(String title, String line) {
    kChannel.invokeMethod('alert', {'title': title, 'line': line}).catchError((_) => null);
  }

  void _onGames() {
    final now = {for (final g in kSports.games.value) _key(g): g};
    if (!_primed) {
      // first look: remember where things stand, don't announce old goals
      _last = now;
      _primed = now.isNotEmpty;
      return;
    }
    if (kScoreAlertLevel > 0) {
      for (final e in now.entries) {
        final g = e.value, old = _last[e.key];
        if (old == null) continue;
        final line = g.league == 'f1'
            ? g.title
            : '${g.awayAbbr} ${g.awayScore} – ${g.homeScore} ${g.homeAbbr}   ·   ${g.detail}';
        final starting = old.state == 'pre' && g.state == 'in';
        final ended = old.state == 'in' && g.state == 'post';
        if (starting && kScoreAlertLevel >= 2) {
          _alert(g.league == 'f1' ? '🏁 Formula 1 is live' : 'Starting now', g.league == 'f1' ? g.title : '${g.awayAbbr} at ${g.homeAbbr}');
          continue;
        }
        if (g.league != 'f1' && g.league != 'nba' && (g.state == 'in' || ended)) {
          final da = _n(g.awayScore) - _n(old.awayScore), dh = _n(g.homeScore) - _n(old.homeScore);
          // NFL extra points on their own aren't worth a pop-up
          final pts = da > dh ? da : dh;
          if (pts > 0 && !(g.league == 'nfl' && pts == 1)) {
            _alert(_what(g.league, pts, da > dh ? g.awayAbbr : g.homeAbbr), line);
            continue;
          }
        }
        if (ended && kScoreAlertLevel >= 2) _alert('Final', line.split('   ·   ').first);
      }
    }
    _last = now;
  }
}

final ScoreAlerts kScoreAlerts = ScoreAlerts();

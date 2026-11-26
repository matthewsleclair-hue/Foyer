import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
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
    this.awayColor = '',
    this.homeColor = '',
  });
  final String league; // key
  final String state; // pre | in | post
  final String awayAbbr, awayScore, homeAbbr, homeScore;
  final String detail;
  final String title; // race name for F1
  final String awayColor, homeColor; // team colours from ESPN, hex without '#'
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
  return '${shortDay(d.weekday)} $t';
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
    String ab = '', as_ = '', hb = '', hs = '', ac = '', hc = '';
    var mine = false;
    for (final c in cs) {
      if (c is! Map) continue;
      final tm = c['team'];
      final id = tm is Map ? '${tm['id']}' : '';
      final abbr = tm is Map ? '${tm['abbreviation'] ?? tm['shortDisplayName'] ?? ''}' : '';
      if (ids.contains(id)) mine = true;
      final col = tm is Map ? '${tm['color'] ?? ''}' : '';
      if (c['homeAway'] == 'home') {
        hb = abbr;
        hs = _scoreOf(c['score']);
        hc = col;
      } else {
        ab = abbr;
        as_ = _scoreOf(c['score']);
        ac = col;
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
        detail: detail,
        awayColor: ac == 'null' ? '' : ac,
        homeColor: hc == 'null' ? '' : hc);
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
    final soon = games.value.any((g) => g.state == 'pre');
    final age = _last == null ? 9999 : DateTime.now().difference(_last!).inSeconds;
    // live game: every 8 s, so a goal shows within ~10 s of ESPN having it.
    // a game today that hasn't started: every minute, to catch puck drop. Otherwise every 5 min.
    final due = sig != _sig || force || age >= (live ? 8 : (soon ? 60 : 300));
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

/// Seconds to hold an alert so it doesn't beat your stream (which runs behind live).
int kScoreAlertDelay = 0;
const List<int> kScoreDelays = [0, 15, 30, 45, 60];

/// Pop-up size: 0 small, 1 medium (default), 2 large.
int kScoreAlertSize = 1;
const List<String> kScoreSizeNames = ['Small', 'Medium', 'Large'];

const Map<String, String> _leagueEmoji = {'nhl': '🏒', 'mlb': '⚾', 'nba': '🏀', 'nfl': '🏈', 'f1': '🏁'};

/// Sends one alert to the pop-up drawn over other apps.
///   event: "GOAL", "FINAL"…   side: which team's number to light up ('away', 'home' or '').
void showScoreAlert({
  required String league,
  required String event,
  String away = '',
  String awayScore = '',
  String home = '',
  String homeScore = '',
  String detail = '',
  String side = '',
  String color = '',
  String line = '',
  bool once = true,
}) {
  // the very same pop-up twice within a few minutes is always a repeat, never news
  final sig = '$league|$event|$away $awayScore|$home $homeScore|$line';
  final t = DateTime.now();
  _recentAlerts.removeWhere((_, at) => t.difference(at).inMinutes >= 5);
  if (once && _recentAlerts.containsKey(sig)) return;
  _recentAlerts[sig] = t;
  kChannel.invokeMethod('alert', {
      'emoji': _leagueEmoji[league] ?? '🏆',
      'event': tr(event),
      'away': away,
      'awayScore': awayScore,
      'home': home,
      'homeScore': homeScore,
      'detail': detail,
      'side': side,
      'color': color,
      'line': line,
      'size': kScoreAlertSize,
    }).catchError((_) => null);
}

final Map<String, DateTime> _recentAlerts = {};

/// Sample on the Sports page: a Canadiens goal at the Bell Centre. Go Habs Go.
void showSampleAlert() => showScoreAlert(
    league: 'nhl',
    event: 'GOAL · MTL',
    away: 'TOR',
    awayScore: '1',
    home: 'MTL',
    homeScore: '2',
    detail: '3rd period · 4:21',
    side: 'home',
    color: 'af1e2d',
    once: false);
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
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (kScoreAlertLevel == 0) return;
      try {
        final s = read();
        if (s.sportsTeams.isNotEmpty) kSports.refresh(s.sportsTeams, s.clock24);
      } catch (_) {}
    });
  }

  String _key(GameLine g) => '${g.league}|${g.awayAbbr}|${g.homeAbbr}|${g.title}';

  static int _n(String v) => int.tryParse(v.trim()) ?? 0;

  static String _what(String league, int pts) {
    switch (league) {
      case 'nhl':
        return 'GOAL';
      case 'mlb':
        return pts == 1 ? 'RUN' : '$pts RUNS';
      case 'nfl':
        if (pts >= 6) return 'TOUCHDOWN';
        if (pts == 3) return 'FIELD GOAL';
        if (pts == 2) return 'SAFETY';
        return 'SCORE';
      default:
        return 'SCORE';
    }
  }

  void _later(void Function() send) {
    if (kScoreAlertDelay > 0) {
      Timer(Duration(seconds: kScoreAlertDelay), send);
    } else {
      send();
    }
  }

  void _game(GameLine g, String event, {String side = ''}) => _later(() => showScoreAlert(
      league: g.league,
      event: event,
      away: g.awayAbbr,
      awayScore: g.awayScore,
      home: g.homeAbbr,
      homeScore: g.homeScore,
      detail: g.detail,
      side: side,
      color: side == 'home' ? g.homeColor : (side == 'away' ? g.awayColor : '')));

  // What has already been announced for each game, so a stale copy of the scoreboard
  // (ESPN's servers sometimes hand back one that's a few seconds old: the goal vanishes for
  // one check, then "comes back") never pops the same goal, start or final twice.
  final Map<String, _Told> _told = {};

  void _onGames() {
    final now = {for (final g in kSports.games.value) _key(g): g};
    if (!_primed) {
      // first look: remember where things stand, don't announce old goals
      for (final e in now.entries) {
        _told[e.key] = _Told.from(e.value);
      }
      _last = now;
      _primed = now.isNotEmpty;
      return;
    }
    if (kScoreAlertLevel > 0) {
      for (final e in now.entries) {
        final g = e.value, old = _last[e.key];
        final t = _told[e.key];
        if (old == null || t == null) {
          // a game we haven't seen yet (or one that dropped out for a check): just note it
          _told[e.key] ??= _Told.from(g);
          continue;
        }
        final a = _n(g.awayScore), h = _n(g.homeScore);
        // the score went down: a goal taken back on review, or a stale copy. Only believe it
        // once it has stayed down for a few checks, so the stale copy can't re-announce a goal.
        if (a < t.away || h < t.home) {
          if (++t.lower >= 3) {
            t.away = a;
            t.home = h;
            t.lower = 0;
            // the next goal may bring back the very same score: let that pop-up through
            _recentAlerts.removeWhere((k, _) => k.contains('|${g.awayAbbr} ') && k.contains('|${g.homeAbbr} '));
          }
        } else {
          t.lower = 0;
        }
        final starting = g.state == 'in' && old.state == 'pre' && !t.started;
        final ended = g.state == 'post' && old.state == 'in' && !t.ended;
        if (g.state != 'pre') t.started = true;
        if (starting && kScoreAlertLevel >= 2) {
          if (g.league == 'f1') {
            _later(() => showScoreAlert(league: 'f1', event: 'FORMULA 1 · LIVE', line: g.title));
          } else {
            _game(g, 'STARTING NOW');
          }
          continue;
        }
        if (g.league != 'f1' && g.league != 'nba' && (g.state == 'in' || g.state == 'post')) {
          final da = a - t.away, dh = h - t.home;
          if (da > 0) t.away = a;
          if (dh > 0) t.home = h;
          // NFL extra points on their own aren't worth a pop-up
          final pts = da > dh ? da : dh;
          if (pts > 0 && !(g.league == 'nfl' && pts == 1)) {
            final away = da > dh;
            _game(g, '${_what(g.league, pts)} · ${away ? g.awayAbbr : g.homeAbbr}', side: away ? 'away' : 'home');
            if (ended) t.ended = true;
            continue;
          }
        }
        if (ended) {
          t.ended = true;
          if (kScoreAlertLevel >= 2) _game(g, 'FINAL', side: a == h ? '' : (a > h ? 'away' : 'home'));
        }
      }
    }
    // forget games that are long gone (keeps the list from growing over weeks)
    if (_told.length > 60) _told.removeWhere((k, _) => !now.containsKey(k));
    _last = now;
  }
}

class _Told {
  _Told(this.away, this.home, this.started, this.ended);
  factory _Told.from(GameLine g) => _Told(ScoreAlerts._n(g.awayScore), ScoreAlerts._n(g.homeScore),
      g.state != 'pre', g.state == 'post');
  int away, home;
  bool started, ended;
  int lower = 0;
}

final ScoreAlerts kScoreAlerts = ScoreAlerts();

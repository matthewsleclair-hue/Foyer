// Settings survive a backup and restore (and a copy to another box) with nothing lost.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:leclair_home/main.dart';
import 'package:leclair_home/update.dart';

/// Every setting changed away from its default, so a field that isn't saved or read back shows.
Object? changed(String k, Object? v) {
  if (v is bool) return !v;
  if (v is int) return v == 0 ? 1 : (v == 1 ? 2 : v + 1);
  if (v is double) return v + 1.5;
  if (v is String) return '${v}x';
  return v;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => kChannelOverride = (ch, method, args) async => null);

  test('every setting comes back from a backup', () {
    final a = Settings();
    final j = a.toJson();
    final skip = {'v', 'updatesV', 'lang', 'wallMode', 'ssSource', 'idleAction', 'updateUrl', 'activeProfile', 'profiles'};
    final m = <String, dynamic>{
      for (final e in j.entries) e.key: skip.contains(e.key) ? e.value : changed(e.key, e.value),
      'lang': 'fr',
      'wallMode': 'photo',
      'ssSource': 'online',
      'idleAction': 'tvoff',
      'updateUrl': 'someone/fork',
      'weatherLat': 45.5,
      'weatherLon': -73.6,
      'pinned': ['com.netflix.ninja', 'com.google.android.youtube.tv'],
      'recentApps': ['com.netflix.ninja'],
      'keepHidden': ['a|b'],
      'keepHiddenApps': ['c'],
      'dropHidden': ['d'],
      'remoteKeys': {'313': 'com.netflix.ninja'},
      'gamesPlayed': {'mario.nes': 5},
      'sportsTeams': [
        {'league': 'nhl', 'id': '10', 'abbr': 'MTL', 'name': 'Canadiens'}
      ],
      // keep the numbers inside the ranges applyJson allows
      'idleMinutes': 45,
      'pausedMinutes': 20,
      'scoreDelay': 30,
      'ssMinutes': 10,
      'scoreAlerts': 1,
    };
    final b = Settings()..applyJson(jsonDecode(jsonEncode(m)) as Map<String, dynamic>);
    final back = b.toJson();
    final lost = <String>[];
    for (final k in m.keys) {
      if (k == 'v' || k == 'updatesV') continue;
      if (jsonEncode(back[k]) != jsonEncode(m[k])) lost.add('$k: saved ${jsonEncode(m[k])}, came back ${jsonEncode(back[k])}');
    }
    expect(lost, isEmpty, reason: lost.join('\n'));
  });

  test('old boxes on Foyer Drop updates move to GitHub once', () {
    final s = Settings()..applyJson({'updateUrl': UpdateApi.dropSource});
    expect(s.updateUrl, UpdateApi.publicRepo);
    final t = Settings()..applyJson({'updateUrl': UpdateApi.dropSource, 'updatesV': 2});
    expect(t.updateUrl, UpdateApi.dropSource, reason: 'choosing Foyer Drop again sticks');
  });

  test('copy to another box leaves the keys behind', () {
    final j = (Settings()
          ..plexToken = 'secret'
          ..tmdbKey = 'k')
        .toJson(secrets: false);
    expect(j.containsKey('plexToken'), isFalse);
    expect(j.containsKey('tmdbKey'), isFalse);
    expect(j.containsKey('serverToken'), isFalse);
  });
}

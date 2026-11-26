// Score alerts: one pop-up per goal, start and final, even when ESPN hands back a stale
// scoreboard for a check or two.
import 'package:flutter_test/flutter_test.dart';
import 'package:leclair_home/main.dart';
import 'package:leclair_home/sports.dart';

final sent = <Map>[];

GameLine g(String state, int a, int h) =>
    GameLine(league: 'nhl', state: state, awayAbbr: 'TOR', homeAbbr: 'MTL', awayScore: '$a', homeScore: '$h');

void feed(GameLine x) => kSports.games.value = [x];

List<String> events() => [for (final m in sent) '${m['event']} ${m['awayScore']}-${m['homeScore']}'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    kChannelOverride = (ch, method, args) async {
      if (method == 'alert') sent.add(args as Map);
      return null;
    };
    kScoreAlertLevel = 2;
    kScoreAlertDelay = 0;
    // throws: start() only needs it for its own refresh timer, which this test doesn't use
    kScoreAlerts.start(() => throw StateError('no settings in tests'));
  });

  test('a game from start to final, with a stale scoreboard in the middle', () {
    feed(g('pre', 0, 0)); // first look: nothing announced
    feed(g('in', 0, 0)); // puck drop
    feed(g('pre', 0, 0)); // stale copy
    feed(g('in', 0, 0)); // back: no second "starting now"
    feed(g('in', 0, 1)); // goal MTL
    feed(g('in', 0, 0)); // stale copy: the goal vanishes...
    feed(g('in', 0, 1)); // ...and comes back: must not pop again
    feed(g('in', 1, 1)); // goal TOR
    feed(g('post', 1, 1)); // final (tied in a test, fine)
    feed(g('in', 1, 1)); // stale
    feed(g('post', 1, 1)); // no second final
    expect(events(), ['STARTING NOW 0-0', 'GOAL · MTL 0-1', 'GOAL · TOR 1-1', 'FINAL 1-1']);
  });

  test('a goal taken back on review, then a real one', () {
    sent.clear();
    final x = GameLine(league: 'nhl', state: 'in', awayAbbr: 'BOS', homeAbbr: 'OTT', awayScore: '0', homeScore: '0');
    GameLine y(int a, int h) =>
        GameLine(league: 'nhl', state: 'in', awayAbbr: 'BOS', homeAbbr: 'OTT', awayScore: '$a', homeScore: '$h');
    kSports.games.value = [x];
    kSports.games.value = [y(1, 0)]; // goal BOS
    for (var i = 0; i < 4; i++) {
      kSports.games.value = [y(0, 0)]; // overturned, stays that way
    }
    kSports.games.value = [y(1, 0)]; // a new BOS goal later
    expect(events(), ['GOAL · BOS 1-0', 'GOAL · BOS 1-0']);
  });
}

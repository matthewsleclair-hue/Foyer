// Opens the real home screen, the first setup and the settings hub, in English and in French,
// and fails on any drawing error (text that doesn't fit, a crash while building, ...).
// Runs in real time (LiveTestWidgetsFlutterBinding) because the home screen starts timers
// that keep running for as long as Foyer does.
import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leclair_home/main.dart';
import 'package:leclair_home/seasons.dart';

Map<String, dynamic> base(String lang, bool setupDone) => {
      'setupDone': setupDone,
      'lang': lang,
      'name': 'Leclair',
      'pinned': ['com.netflix.ninja', 'com.google.android.youtube.tv', 'com.plexapp.android'],
      'weatherCity': '',
      'keepWatching': true,
      'updatesV': 2,
      'updateUrl': '',
      'autoUpdate': false,
    };

final calls = <String>{};

Future<void> open(WidgetTester tester, Map<String, dynamic> settings) async {
  kChannelOverride = (ch, method, args) async {
    calls.add('$ch.$method');
    if (method == 'loadSettings') return {'json': jsonEncode(settings)};
    return null;
  };
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(SettingsScope(settings: Settings(), child: const LauncherApp()));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  // the real font, so text that wouldn't fit on the TV doesn't fit here either
  setUpAll(() async {
    final f = FontLoader('PlusJakartaSans');
    for (final w in ['ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      f.addFont(rootBundle.load('fonts/PlusJakartaSans-$w.ttf'));
    }
    await f.load();
  });

  for (final lang in ['en', 'fr']) {
    testWidgets('home screen ($lang)', (tester) async {
      await open(tester, base(lang, true));
      expect(tester.takeException(), isNull);
      expect(find.byType(LauncherApp), findsOneWidget);
    });

    testWidgets('first setup ($lang)', (tester) async {
      await open(tester, base(lang, false));
      expect(tester.takeException(), isNull);
    });

    for (final season in Season.values) {
      testWidgets('home in season ${season.name} ($lang)', (tester) async {
        kSeasonPreview.value = season;
        await open(tester, base(lang, true));
        expect(tester.takeException(), isNull);
        kSeasonPreview.value = null;
      });
    }
  }

  test('Easter', () {
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
    expect(seasonFor(DateTime(2026, 3, 17)), Season.stPatricks);
    expect(seasonFor(DateTime(2026, 2, 14)), Season.valentines);
    expect(seasonFor(DateTime(2026, 12, 25)), Season.christmas);
    expect(seasonFor(DateTime(2027, 1, 2)), Season.newYear);
    expect(seasonFor(DateTime(2026, 7, 1)), Season.none);
  });
}

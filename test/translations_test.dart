// The French list: every changing part ({}) in the English has a place in the French,
// and patterns fill in the way they should.
import 'package:flutter_test/flutter_test.dart';
import 'package:leclair_home/fr.dart';
import 'package:leclair_home/i18n.dart';

int holes(String s) => RegExp(r'\{\d?\}').allMatches(s).length;

void main() {
  test('every {} in English has a place in French', () {
    final bad = <String>[];
    kFr.forEach((en, fr) {
      final e = '{}'.allMatches(en).length;
      if (e == 0) return;
      if (holes(fr) < e) bad.add('$en  →  $fr');
    });
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no empty or untranslated-looking French', () {
    final bad = [for (final e in kFr.entries) if (e.value.trim().isEmpty) e.key];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('patterns and pieces', () {
    kLang = 'fr';
    expect(tr('Settings'), isNot('Settings'));
    // a pattern with one changing word leaves longer text alone
    final removeKey = kFr.keys.firstWhere((k) => k == 'Remove {}', orElse: () => '');
    if (removeKey.isNotEmpty) {
      expect(tr('Remove Netflix'), isNot('Remove Netflix'));
      expect(tr('Remove the trash can now'), 'Remove the trash can now');
    }
    kLang = 'en';
    expect(tr('Settings'), 'Settings');
  });

  test('dates', () {
    kLang = 'fr';
    expect(longDate(DateTime(2026, 11, 1)), 'Dimanche 1er novembre');
    expect(shortDate(DateTime(2026, 2, 3)), '3 févr.');
    kLang = 'en';
    expect(longDate(DateTime(2026, 11, 1)), 'Sunday, November 1');
  });
}

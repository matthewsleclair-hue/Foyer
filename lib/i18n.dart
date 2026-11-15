// Languages: English (as written in the code) and French.
//
// Every file imports `material.dart hide Text` and gets this Text instead. It looks the
// English words up in the French list (fr.dart) when it's built, so `const Text('…')`
// stays const and the whole of Foyer TV switches language at once, without restarting.
// Words with a changing part ("Remove {}") are matched as patterns.
import 'package:flutter/widgets.dart' as w;
import 'package:flutter/painting.dart';
import 'fr.dart';

/// 'en' or 'fr'. Set by Settings; read by tr() for text that isn't a Text widget.
String kLang = 'en';

final Map<String, String> _memo = {};
List<(RegExp, String)>? _patterns;

List<(RegExp, String)> _compile() {
  final out = <(RegExp, String)>[];
  kFr.forEach((k, v) {
    if (!k.contains('{}')) return;
    final parts = k.split('{}');
    // with only one real word around the changing part ("Remove {}"), the part has to be a
    // single word or number, so a note or a show title that happens to start that way
    // ("Remove the trash") is left alone
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(parts.join(' ')).length;
    final part = words < 2 ? r'(\S+?)' : '(.+?)';
    final re = StringBuffer('^');
    for (var i = 0; i < parts.length; i++) {
      re.write(RegExp.escape(parts[i]));
      if (i < parts.length - 1) re.write(part);
    }
    re.write(r'$');
    out.add((RegExp(re.toString(), dotAll: true), v));
  });
  // longer patterns first, so "Remove {}?" wins over "Remove {}"
  out.sort((a, b) => b.$1.pattern.length.compareTo(a.$1.pattern.length));
  return out;
}

/// The words in the current language.
String tr(String s, [String? lang]) {
  final l = lang ?? kLang;
  if (l != 'fr' || s.isEmpty) return s;
  final hit = kFr[s];
  if (hit != null) return hit;
  final m = _memo[s];
  if (m != null) return m;
  final r = _translate(s);
  if (_memo.length > 3000) _memo.clear();
  _memo[s] = r;
  return r;
}

String _translate(String s) {
  final trimmed = s.trim();
  if (trimmed != s && trimmed.isNotEmpty) {
    final t = tr(trimmed);
    if (t != trimmed) return s.replaceFirst(trimmed, t);
  }
  for (final (re, fr) in _patterns ??= _compile()) {
    final m = re.firstMatch(s);
    if (m == null) continue;
    final caps = [for (var i = 1; i <= m.groupCount; i++) tr(m.group(i)!)];
    var i = 0;
    return fr.replaceAllMapped(RegExp(r'\{(\d?)\}'), (x) {
      final n = x.group(1)!;
      final idx = n.isEmpty ? i++ : int.parse(n);
      return idx < caps.length ? caps[idx] : '';
    });
  }
  // "Good evening · 4° Cloudy", "Netflix · 2 h left": each piece on its own
  for (final sep in const [' · ', ' — ', '\n']) {
    if (s.contains(sep)) {
      final parts = s.split(sep);
      final t = parts.map(tr).join(sep);
      if (t != s) return t;
    }
  }
  // "4° Cloudy"
  final temp = RegExp(r'^(-?\d+° ?)(.+)$').firstMatch(s);
  if (temp != null) {
    final t = tr(temp.group(2)!);
    if (t != temp.group(2)) return '${temp.group(1)}$t';
  }
  return s;
}

/// Above every page, so Text rebuilds when the language changes.
class LangScope extends w.InheritedWidget {
  const LangScope({super.key, required this.lang, required super.child});
  final String lang;
  @override
  bool updateShouldNotify(LangScope old) => old.lang != lang;
}

/// Flutter's Text, in the chosen language.
class Text extends w.StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textScaler,
  });
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextScaler? textScaler;

  @override
  w.Widget build(w.BuildContext context) {
    final lang = context.dependOnInheritedWidgetOfExactType<LangScope>()?.lang ?? kLang;
    return w.Text(
      tr(data, lang),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textScaler: textScaler,
    );
  }
}

const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _daysFr = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsFr = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/// "Thursday, November 12" or "jeudi 12 novembre".
String longDate(DateTime d) => kLang == 'fr'
    ? '${_cap(_daysFr[d.weekday - 1])} ${d.day == 1 ? '1er' : d.day} ${_monthsFr[d.month - 1]}'
    : '${_daysEn[d.weekday - 1]}, ${_monthsEn[d.month - 1]} ${d.day}';

/// "Nov 12" or "12 nov."
String shortDate(DateTime d) {
  if (kLang == 'fr') {
    final m = _monthsFr[d.month - 1];
    return '${d.day} ${m.length > 5 ? '${m.substring(0, 4)}.' : m}';
  }
  return '${_monthsEn[d.month - 1].substring(0, 3)} ${d.day}';
}

/// "Mon" or "lun."
String shortDay(int weekday) =>
    kLang == 'fr' ? '${_daysFr[weekday - 1].substring(0, 3)}.' : _daysEn[weekday - 1].substring(0, 3);

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

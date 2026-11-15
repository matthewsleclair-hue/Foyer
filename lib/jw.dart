// Opening the show itself: JustWatch (the same lists TMDB's "where to watch" comes from) gives,
// for each service that has a title, a link that opens that title in the service's TV app
// (an Android TV intent) and its web page. Search uses it when you pick an app, and so does
// "put on …" from the phone. No key needed. If a link doesn't work, Foyer falls back to the
// app's own search screen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'main.dart';
import 'tmdb.dart';

class JwOffer {
  JwOffer(this.service, this.kind, this.tvLink, this.webLink);
  final String service; // the service's name, "Netflix"
  final String kind; // included, rent, buy
  final String tvLink; // intent://… or https://… for the TV app ('' if none)
  final String webLink; // the title's page on the service's website
}

class JwTitle {
  JwTitle(this.title, this.year, this.isShow, this.offers);
  final String title;
  final int year;
  final bool isShow;
  final List<JwOffer> offers;
}

const _query = r'''
query Find($country: Country!, $language: Language!, $first: Int!, $filter: TitleFilter) {
  popularTitles(country: $country, first: $first, filter: $filter) {
    edges { node { objectType
      content(country: $country, language: $language) { title originalReleaseYear }
      offers(country: $country, platform: ANDROID_TV) {
        monetizationType deeplinkURL(platform: ANDROID_TV) standardWebURL
        package { clearName }
      } } } } }''';

final Map<String, (DateTime, List<JwTitle>)> _cache = {};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Titles matching a name, best first, with every way to watch them where this box is.
Future<List<JwTitle>> jwFind(String name, {String lang = 'en'}) async {
  final country = await myCountry();
  final ck = '${_norm(name)}|$country|$lang';
  final hit = _cache[ck];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(hours: 6)) return hit.$2;
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await c.postUrl(Uri.parse('https://apis.justwatch.com/graphql')).timeout(const Duration(seconds: 8));
    req.headers.contentType = ContentType.json;
    req.headers.set('User-Agent', 'FoyerTV');
    final body = utf8.encode(jsonEncode({
      'query': _query,
      'variables': {
        'country': country,
        'language': lang == 'fr' ? 'fr' : 'en',
        'first': 8,
        'filter': {'searchQuery': name},
      },
    }));
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close().timeout(const Duration(seconds: 12));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('JustWatch answered ${res.statusCode}');
    final j = jsonDecode(text);
    final edges = (((j is Map ? j['data'] : null) as Map?)?['popularTitles'] as Map?)?['edges'] as List? ?? const [];
    final out = <JwTitle>[];
    for (final e in edges) {
      final n = (e is Map ? e['node'] : null);
      if (n is! Map) continue;
      final content = n['content'] as Map? ?? const {};
      final offers = <JwOffer>[];
      for (final o in (n['offers'] as List? ?? const [])) {
        if (o is! Map) continue;
        final m = '${o['monetizationType']}';
        final kind = (m == 'RENT') ? 'rent' : (m == 'BUY' ? 'buy' : 'included');
        offers.add(JwOffer('${(o['package'] as Map?)?['clearName'] ?? ''}', kind,
            '${o['deeplinkURL'] ?? ''}', _unescape('${o['standardWebURL'] ?? ''}')));
      }
      out.add(JwTitle('${content['title'] ?? ''}', (content['originalReleaseYear'] as num?)?.toInt() ?? 0,
          n['objectType'] == 'SHOW', offers));
    }
    if (_cache.length > 100) _cache.clear();
    _cache[ck] = (DateTime.now(), out);
    return out;
  } finally {
    c.close(force: true);
  }
}

String _unescape(String s) => s.replaceAll('&amp;', '&');

/// The JustWatch title that is this TMDB result: same name, and the year within one.
JwTitle? jwMatch(List<JwTitle> found, String title, int year, bool isShow) {
  final want = _norm(title);
  JwTitle? loose;
  for (final t in found) {
    if (_norm(t.title) != want) continue;
    if (t.isShow != isShow) continue;
    if (year == 0 || t.year == 0 || (t.year - year).abs() <= 1) return t;
    loose ??= t;
  }
  return loose;
}

/// Opens a title in one app: its own page if JustWatch has a link that this app takes,
/// otherwise the app's search for it, otherwise just the app.
/// Returns 'title', 'search', 'opened' or '' (couldn't open).
Future<String> openTitleIn(String package, String serviceKey, String title, JwTitle? jw,
    {required bool Function(String service) sameService}) async {
  JwOffer? pick;
  if (jw != null) {
    for (final o in jw.offers) {
      if (o.kind != 'included') continue;
      // the offer for this app: its link names the app, or it's the same service
      final mine = o.tvLink.contains(package) || sameService(o.service);
      if (mine) {
        pick = o;
        break;
      }
    }
  }
  try {
    return (await kChannel.invokeMethod<String>('openTitle', {
          'package': package,
          'uri': pick?.tvLink ?? '',
          'web': pick?.webLink ?? '',
          'query': title,
          'key': serviceKey,
        })) ??
        '';
  } catch (_) {
    return '';
  }
}

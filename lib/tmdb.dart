// "Where to watch" straight from TMDB (its lists come from JustWatch), for Search everything.
// The key is built into the app by GitHub (the TMDB_KEY secret, see tools/set-tmdb-key.sh), or
// typed in Developer options. Without one, search asks your Foyer Drop server instead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String kBuiltInTmdbKey = String.fromEnvironment('TMDB_KEY');

final Map<String, (DateTime, List<Map<String, dynamic>>)> _cache = {};

Future<dynamic> _get(String key, String path, Map<String, String> q) async {
  final params = {...q};
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final v4 = key.startsWith('eyJ'); // a "read access token"; otherwise a v3 "API key"
    if (!v4) params['api_key'] = key;
    final req = await c.getUrl(Uri.https('api.themoviedb.org', '/3$path', params)).timeout(const Duration(seconds: 8));
    req.headers.set('Accept', 'application/json');
    if (v4) req.headers.set('Authorization', 'Bearer $key');
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 401) throw const HttpException('TMDB refused the key. Check it in Developer options.');
    if (res.statusCode != 200) throw HttpException('TMDB answered ${res.statusCode}');
    return jsonDecode(body);
  } finally {
    c.close(force: true);
  }
}

Future<List<Map<String, dynamic>>> _providers(String key, String kind, int id, String country) async {
  try {
    final j = await _get(key, '/$kind/$id/watch/providers', const {});
    final c = (j is Map ? (j['results'] as Map?)?[country] : null) as Map?;
    if (c == null) return const [];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final how in const ['flatrate', 'free', 'ads', 'rent', 'buy']) {
      for (final p in (c[how] as List?) ?? const []) {
        if (p is! Map) continue;
        final name = '${p['provider_name'] ?? ''}';
        if (name.isEmpty || !seen.add(name)) continue;
        out.add({'name': name, 'how': (how == 'rent' || how == 'buy') ? how : 'included'});
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Same answer as Foyer Drop's /api/search: title, year, poster and who has it.
Future<List<Map<String, dynamic>>> tmdbSearch(String key, String q, String lang, {String country = 'CA'}) async {
  final ck = '$q|$lang|$country'.toLowerCase();
  final hit = _cache[ck];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(hours: 6)) return hit.$2;
  final j = await _get(key, '/search/multi', {
    'query': q,
    'language': lang == 'fr' ? 'fr-CA' : 'en-CA',
    'region': country,
    'include_adult': 'false',
  });
  final items = [
    for (final r in (j is Map ? (j['results'] as List?) : null) ?? const [])
      if (r is Map && (r['media_type'] == 'movie' || r['media_type'] == 'tv')) r
  ].take(10).toList();
  final provs = await Future.wait([for (final r in items) _providers(key, '${r['media_type']}', r['id'] as int, country)]);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < items.length; i++) {
    final r = items[i];
    final date = '${r['release_date'] ?? r['first_air_date'] ?? ''}';
    out.add({
      'id': r['id'],
      'kind': r['media_type'],
      'title': '${r['title'] ?? r['name'] ?? ''}',
      'year': date.length >= 4 ? date.substring(0, 4) : '',
      'poster': r['poster_path'] != null ? 'https://image.tmdb.org/t/p/w342${r['poster_path']}' : '',
      'providers': provs[i],
    });
  }
  if (_cache.length > 200) _cache.clear();
  _cache[ck] = (DateTime.now(), out);
  return out;
}

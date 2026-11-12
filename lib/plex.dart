import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PlexItem {
  PlexItem(this.title, this.subtitle, this.imageUrl, this.progress,
      {this.ratingKey = '', this.showKey = '', this.type = '', this.server = '', this.viewedAt = 0});
  final String title;
  final String subtitle;
  final String imageUrl; // '' when there is no artwork
  final double? progress; // 0..1 for partly watched items
  final String ratingKey; // this movie or episode
  final String showKey; // the show, for episodes and seasons
  final String type; // movie, episode, season, show
  final String server; // the server's machineIdentifier
  final int viewedAt; // when it was last watched (seconds since 1970), 0 if unknown

  /// A link that opens this title's page in the Plex app (Plex for Android TV 2026 format;
  /// the older plex://server:// and plex://preplay links now just open Plex's home).
  String get plexLink {
    if (server.isEmpty || ratingKey.isEmpty) return '';
    final key = Uri.encodeComponent('/library/metadata/$ratingKey');
    if (type == 'show') return 'plex://libraries/$server/unmatched/tv/$key';
    return 'plex://libraries/$server/unmatched/$key';
  }

  /// Fallback: the show's page, for when an episode link doesn't open.
  String get showLink {
    if (server.isEmpty || showKey.isEmpty) return '';
    return 'plex://libraries/$server/unmatched/tv/${Uri.encodeComponent('/library/metadata/$showKey')}';
  }
}

class PlexRow {
  PlexRow(this.title, this.items);
  final String title;
  final List<PlexItem> items;
}

class PlexServer {
  PlexServer(this.name, this.baseUrl, this.token);
  final String name;
  final String baseUrl;
  final String token;
}

class PlexPin {
  PlexPin(this.id, this.code);
  final int id;
  final String code;
}

/// Minimal Plex client: plex.tv/link sign-in, server discovery, and the home row.
class PlexApi {
  PlexApi(this.clientId);
  final String clientId;

  Map<String, String> get _base => {
        'Accept': 'application/json',
        'X-Plex-Product': 'Foyer',
        'X-Plex-Version': '1.0',
        'X-Plex-Client-Identifier': clientId,
        'X-Plex-Device-Name': 'Fire TV',
        'X-Plex-Platform': 'Android',
      };

  // Only skip certificate checks for a bare IP address (a server on your own network).
  bool _isIp(String host) => InternetAddress.tryParse(host) != null;

  Future<dynamic> _json(String method, Uri uri,
      {Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 10)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    client.badCertificateCallback = (cert, host, port) => _isIp(host);
    try {
      final req = await client.openUrl(method, uri);
      for (final e in _base.entries) {
        req.headers.set(e.key, e.value);
      }
      if (headers != null) {
        for (final e in headers.entries) {
          req.headers.set(e.key, e.value);
        }
      }
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) {
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      return body.isEmpty ? null : jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  // ── sign in with a 4-character code at plex.tv/link ──

  Future<PlexPin> startPin() async {
    final j = await _json('POST', Uri.parse('https://plex.tv/api/v2/pins?strong=false'));
    return PlexPin(j['id'] as int, j['code'] as String);
  }

  /// Returns the account token once the code has been entered, otherwise null.
  Future<String?> checkPin(int id) async {
    final j = await _json('GET', Uri.parse('https://plex.tv/api/v2/pins/$id'));
    final t = j['authToken'];
    return (t is String && t.isNotEmpty) ? t : null;
  }

  // ── find a reachable server on the account ──

  Future<PlexServer?> findServer(String accountToken) async {
    final list = await _json(
        'GET', Uri.parse('https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1'),
        headers: {'X-Plex-Token': accountToken});
    if (list is! List) return null;
    final servers = list
        .where((d) => ((d['provides'] as String?) ?? '').split(',').contains('server'))
        .toList()
      ..sort((a, b) => (b['owned'] == true ? 1 : 0) - (a['owned'] == true ? 1 : 0));
    for (final d in servers) {
      final token = (d['accessToken'] as String?) ?? accountToken;
      final conns = ((d['connections'] as List?) ?? const []).cast<Map>();
      final candidates = <String>[
        for (final c in conns)
          if (c['local'] == true) 'http://${c['address']}:${c['port']}',
        for (final c in conns)
          if (c['local'] == true) 'https://${c['address']}:${c['port']}',
        for (final c in conns)
          if (c['local'] != true && c['relay'] != true) c['uri'] as String,
        for (final c in conns)
          if (c['relay'] == true) c['uri'] as String,
      ];
      for (final base in candidates) {
        try {
          await _json('GET', Uri.parse('$base/identity'),
              headers: {'X-Plex-Token': token}, timeout: const Duration(seconds: 4));
          return PlexServer((d['name'] as String?) ?? 'Plex', base, token);
        } catch (_) {}
      }
    }
    return null;
  }

  // ── the row ──

  final Map<String, String> _machine = {};

  /// The server's machineIdentifier, needed for links into the Plex app.
  Future<String> machineId(PlexServer s) async {
    final cached = _machine[s.baseUrl];
    if (cached != null) return cached;
    try {
      final j = await _json('GET', Uri.parse('${s.baseUrl}/identity'), headers: {'X-Plex-Token': s.token});
      final id = '${j?['MediaContainer']?['machineIdentifier'] ?? ''}';
      if (id.isNotEmpty) _machine[s.baseUrl] = id;
      return id;
    } catch (_) {
      return '';
    }
  }

  Future<PlexRow> fetchRow(PlexServer s) async {
    final mid = await machineId(s);
    Future<List<PlexItem>> grab(String path) async {
      final uri = Uri.parse('${s.baseUrl}$path').replace(
          queryParameters: {'X-Plex-Container-Start': '0', 'X-Plex-Container-Size': '12'});
      final j = await _json('GET', uri, headers: {'X-Plex-Token': s.token});
      final meta = (j?['MediaContainer']?['Metadata'] as List?) ?? const [];
      return meta
          .whereType<Map>()
          .map((m) => _item(m, s, mid))
          .where((i) => i.imageUrl.isNotEmpty)
          .take(5)
          .toList();
    }

    var items = await grab('/library/onDeck');
    if (items.isNotEmpty) return PlexRow('Continue Watching', items);
    items = await grab('/library/recentlyAdded');
    return PlexRow('Recently Added', items);
  }

  /// What you're part way through (Plex's "Continue Watching"), newest first.
  Future<List<PlexItem>> onDeck(PlexServer s, {int max = 6}) async {
    final mid = await machineId(s);
    final uri = Uri.parse('${s.baseUrl}/library/onDeck')
        .replace(queryParameters: {'X-Plex-Container-Start': '0', 'X-Plex-Container-Size': '$max'});
    final j = await _json('GET', uri, headers: {'X-Plex-Token': s.token});
    final meta = (j?['MediaContainer']?['Metadata'] as List?) ?? const [];
    final items = meta.whereType<Map>().map((m) => _item(m, s, mid, thumb: true)).toList();
    items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return items;
  }

  PlexItem _item(Map m, PlexServer s, String mid, {bool thumb = false}) {
    final type = (m['type'] as String?) ?? '';
    String title;
    String sub;
    String? path;
    if (type == 'episode') {
      title = (m['grandparentTitle'] ?? m['title'] ?? '').toString();
      sub = 'S${m['parentIndex'] ?? '?'} E${m['index'] ?? '?'}  ${m['title'] ?? ''}'.trim();
      path = (m['thumb'] ?? m['grandparentArt']) as String?;
    } else if (type == 'season') {
      title = (m['parentTitle'] ?? m['title'] ?? '').toString();
      sub = (m['title'] ?? '').toString();
      path = (m['art'] ?? m['parentArt'] ?? m['thumb']) as String?;
    } else {
      title = (m['title'] ?? '').toString();
      sub = m['year'] != null ? '${m['year']}' : '';
      path = (m['art'] ?? m['thumb']) as String?;
    }
    double? progress;
    final off = m['viewOffset'];
    final dur = m['duration'];
    if (off is num && dur is num && dur > 0) {
      progress = (off / dur).clamp(0.0, 1.0).toDouble();
    }
    final url = path == null
        ? ''
        : '${s.baseUrl}/photo/:/transcode?width=${thumb ? 360 : 640}&height=${thumb ? 202 : 360}&minSize=1&upscale=1'
            '&url=${Uri.encodeComponent(path)}&X-Plex-Token=${s.token}';
    final seen = m['lastViewedAt'];
    final show = type == 'episode' ? m['grandparentRatingKey'] : (type == 'season' ? m['parentRatingKey'] : null);
    return PlexItem(title, sub, url, progress,
        ratingKey: '${m['ratingKey'] ?? ''}',
        showKey: show == null ? '' : '$show',
        type: type,
        server: mid,
        viewedAt: seen is num ? seen.toInt() : 0);
  }
}

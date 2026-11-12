import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class UpdateInfo {
  UpdateInfo(this.version, this.build, this.url, this.notes);
  final String version;
  final int build;
  final String url;
  final String notes;
}

/// Set when a newer version is known (checked on the home screen and in Settings > Updates).
final ValueNotifier<UpdateInfo?> kUpdate = ValueNotifier<UpdateInfo?>(null);

/// Two sources are understood:
///  1. GitHub: "owner/repo" (or the repo URL). Reads the latest Release. Tag format: v1.0.0+26110920
///     (version, then +build number). The first .apk attached to the release is the download.
///     A private repo needs a read-only access token.
///  2. A link to a small JSON file: {"version":"1.0.1","build":26110901,"url":"https://.../Foyer.apk","notes":""}
class UpdateApi {
  static String? githubRepo(String s) {
    final m = RegExp(r'^(?:https?://github\.com/)?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$')
        .firstMatch(s.trim());
    return m == null ? null : '${m[1]}/${m[2]}';
  }

  /// GitHub tokens only contain letters, digits, '_' and '-'. Drop anything else (spaces, quotes, newlines).
  static String cleanToken(String t) => t.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'Foyer';

  static Future<dynamic> _getJson(Uri uri, String token) async {
    final c = _client();
    try {
      final req = await c.getUrl(uri);
      req.headers.set('Accept', 'application/vnd.github+json');
      token = cleanToken(token);
      if (token.isNotEmpty && uri.host == 'api.github.com') {
        req.headers.set('Authorization', 'Bearer $token');
      }
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }

  static bool _semverGreater(String a, String b) {
    List<int> p(String v) => v.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 4; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// "drop" = your own Foyer Drop server: only TVs signed in to it can update.
  static const String dropSource = 'drop';

  static Future<UpdateInfo?> _checkDrop(String dropUrl, String dropToken, int currentBuild) async {
    if (dropUrl.isEmpty || dropToken.isEmpty) {
      throw const FormatException('Link Foyer Drop first (Settings › Home screen › Foyer Drop). Updates come from there.');
    }
    final base = dropUrl.endsWith('/') ? dropUrl.substring(0, dropUrl.length - 1) : dropUrl;
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse('$base/api/update'));
      req.headers.set('Authorization', 'Bearer $dropToken');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null; // nothing published there yet
      if (res.statusCode >= 400) throw HttpException('Foyer Drop HTTP ${res.statusCode}');
      final j = jsonDecode(body);
      if (j is! Map) throw const FormatException('Unexpected reply from Foyer Drop');
      final build = (j['build'] as num?)?.toInt() ?? 0;
      if (build <= currentBuild) return null;
      return UpdateInfo('${j['version'] ?? ''}', build, '$base/api/update/apk', '${j['notes'] ?? ''}');
    } finally {
      c.close(force: true);
    }
  }

  /// Returns null if you're up to date. Throws if the source can't be read.
  static Future<UpdateInfo?> check(String source, String token, int currentBuild, String currentName,
      {String dropUrl = '', String dropToken = ''}) async {
    if (source.trim() == dropSource) return _checkDrop(dropUrl, dropToken, currentBuild);
    final repo = githubRepo(source);
    if (repo != null) {
      final j = await _getJson(Uri.https('api.github.com', '/repos/$repo/releases/latest'), token);
      if (j is! Map) throw const FormatException('Unexpected reply from GitHub');
      var tag = (j['tag_name'] ?? '').toString();
      if (tag.startsWith('v') || tag.startsWith('V')) tag = tag.substring(1);
      final parts = tag.split('+');
      final version = parts.first;
      final build = parts.length > 1 ? int.tryParse(parts[1]) : null;
      final newer = build != null ? build > currentBuild : _semverGreater(version, currentName);
      if (!newer) return null;
      Map? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is Map && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
          apk = a;
          break;
        }
      }
      if (apk == null) throw const FormatException('The latest release has no .apk file attached');
      // with a token, go through the API (works for private repos); otherwise the plain link
      final url = (cleanToken(token).isNotEmpty ? apk['url'] : apk['browser_download_url']).toString();
      return UpdateInfo(version, build ?? 0, url, (j['body'] ?? '').toString());
    }
    if (!source.trim().startsWith('http')) {
      throw const FormatException('Use owner/repo for GitHub, or a link to an update file');
    }
    final j = await _getJson(Uri.parse(source.trim()), '');
    if (j is! Map) throw const FormatException('Not an update file');
    final build = (j['build'] as num?)?.toInt() ?? 0;
    final url = (j['url'] ?? '').toString();
    if (!url.startsWith('http')) throw const FormatException('The update file has no download link');
    if (build <= currentBuild) return null;
    return UpdateInfo((j['version'] ?? '').toString(), build, url, (j['notes'] ?? '').toString());
  }

  static Future<void> download(
      String url, String path, String token, void Function(double) onProgress) async {
    token = cleanToken(token);
    final c = _client();
    try {
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 6; hop++) {
        final req = await c.getUrl(uri);
        req.followRedirects = false; // never send the token to another host
        if (uri.host == 'api.github.com') {
          req.headers.set('Accept', 'application/octet-stream');
          if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
        } else if (uri.path.endsWith('/api/update/apk') && hop == 0 && token.isNotEmpty) {
          // Foyer Drop: the TV's own sign-in (only on the first hop, never to a redirect)
          req.headers.set('Authorization', 'Bearer $token');
        }
        final res = await req.close();
        if (res.isRedirect) {
          final loc = res.headers.value('location');
          await res.drain<void>();
          if (loc == null) throw const HttpException('Bad redirect');
          uri = uri.resolve(loc);
          continue;
        }
        if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
        final total = res.contentLength;
        var got = 0;
        final sink = File(path).openWrite();
        try {
          await for (final chunk in res) {
            sink.add(chunk);
            got += chunk.length;
            if (total > 0) onProgress(got / total);
          }
        } finally {
          await sink.close();
        }
        return;
      }
      throw const HttpException('Too many redirects');
    } finally {
      c.close(force: true);
    }
  }

  static String friendly(Object e) {
    final m = '$e';
    if (m.contains('Foyer Drop HTTP 401')) return 'Foyer Drop doesn\'t recognise this TV any more. Link it again in Settings › Foyer Drop.';
    if (m.contains('404')) {
      return 'Not found. Check the repo name and that a release exists. A private repo needs an access token.';
    }
    if (m.contains('401') || m.contains('403')) {
      return 'GitHub refused the request. Check the access token, or wait a bit if you hit the rate limit.';
    }
    if (m.contains('SocketException') || m.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    return m.replaceAll('FormatException: ', '').replaceAll('Exception: ', '');
  }
}

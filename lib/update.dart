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

/// Update file format (host anywhere with a direct link):
/// {"version":"1.0.1","build":26110901,"url":"https://.../Foyer.apk","notes":"What's new"}
class UpdateApi {
  /// Returns null if you're up to date. Throws if the link can't be read.
  static Future<UpdateInfo?> check(String source, int currentBuild) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(Uri.parse(source.trim()));
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      if (j is! Map) throw const FormatException('Not an update file');
      final build = (j['build'] as num?)?.toInt() ?? 0;
      final url = (j['url'] ?? '').toString();
      if (!url.startsWith('http')) throw const FormatException('The update file has no download link');
      if (build <= currentBuild) return null;
      return UpdateInfo((j['version'] ?? '').toString(), build, url, (j['notes'] ?? '').toString());
    } finally {
      c.close(force: true);
    }
  }

  static Future<void> download(String url, String path, void Function(double) onProgress) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(url));
      final res = await req.close();
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
    } finally {
      c.close(force: true);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class OnlineShot {
  OnlineShot(this.url, this.caption);
  final String url;
  final String caption;
}

/// Bing's daily photos: free, no key. Used for the "Online photos" screensaver.
Future<List<OnlineShot>> fetchBingShots() async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await c.getUrl(
        Uri.parse('https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    final list = (j is Map ? j['images'] : null) as List? ?? const [];
    final out = <OnlineShot>[];
    for (final m in list) {
      if (m is Map && m['url'] is String) {
        final cap = (m['copyright'] ?? '').toString();
        out.add(OnlineShot('https://www.bing.com${m['url']}', cap));
      }
    }
    return out;
  } finally {
    c.close(force: true);
  }
}

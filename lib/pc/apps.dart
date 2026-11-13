// The apps Foyer for PC can open. Streaming services open as their own full-screen
// window in Microsoft Edge (Netflix plays in 4K there); installed programs (Plex, Kodi,
// Spotify, Steam) open as themselves and only show when they're installed.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PcApp {
  const PcApp(this.id, this.label, this.color, {this.url = '', this.exe = const [], this.uri = '', this.tv = false});
  final String id; // shows up as the app's "package" in Foyer
  final String label;
  final int color;
  final String url; // opened in Edge, full screen
  final List<String> exe; // places the program is usually installed (first that exists wins)
  final String uri; // or a link the program understands (steam://...)
  final bool tv; // the TV version of the site (YouTube's leanback page)
}

String _env(String k) => Platform.environment[k] ?? '';

List<PcApp> get kPcApps => [
      PcApp('pc.plex', 'Plex', 0xFFE5A00D, exe: [
        '${_env('ProgramFiles')}\\Plex\\Plex HTPC\\Plex HTPC.exe',
        '${_env('LOCALAPPDATA')}\\Programs\\Plex HTPC\\Plex HTPC.exe',
        '${_env('ProgramFiles')}\\Plex\\Plex\\Plex.exe',
        '${_env('LOCALAPPDATA')}\\Programs\\Plex\\Plex.exe',
      ], url: 'https://app.plex.tv/desktop'),
      const PcApp('pc.netflix', 'Netflix', 0xFFE50914, url: 'https://www.netflix.com/browse'),
      const PcApp('pc.youtube', 'YouTube', 0xFFFF0000, url: 'https://www.youtube.com/tv', tv: true),
      const PcApp('pc.prime', 'Prime Video', 0xFF1A98FF, url: 'https://www.primevideo.com'),
      const PcApp('pc.disney', 'Disney+', 0xFF113CCF, url: 'https://www.disneyplus.com'),
      const PcApp('pc.crave', 'Crave', 0xFF0A2D6E, url: 'https://www.crave.ca'),
      const PcApp('pc.appletv', 'Apple TV', 0xFF1C1C1E, url: 'https://tv.apple.com'),
      const PcApp('pc.paramount', 'Paramount+', 0xFF0064FF, url: 'https://www.paramountplus.com'),
      const PcApp('pc.twitch', 'Twitch', 0xFF9146FF, url: 'https://www.twitch.tv'),
      PcApp('pc.spotify', 'Spotify', 0xFF1DB954,
          exe: ['${_env('APPDATA')}\\Spotify\\Spotify.exe'], uri: 'spotify:', url: 'https://open.spotify.com'),
      PcApp('pc.kodi', 'Kodi', 0xFF17B2E7, exe: ['${_env('ProgramFiles')}\\Kodi\\kodi.exe']),
      PcApp('pc.steam', 'Steam', 0xFF1B2838,
          exe: ['${_env('ProgramFiles(x86)')}\\Steam\\steam.exe', '${_env('ProgramFiles')}\\Steam\\steam.exe'],
          uri: 'steam://open/bigpicture'),
    ];

/// Apps on the home screen of a brand-new Foyer for PC.
const List<String> kPcSuggested = ['pc.plex', 'pc.netflix', 'pc.youtube', 'pc.prime', 'pc.disney', 'pc.crave', 'pc.spotify'];

String? installedExe(PcApp a) {
  for (final p in a.exe) {
    if (p.isNotEmpty && File(p).existsSync()) return p;
  }
  return null;
}

/// Shown when it's a website, or the program is installed.
bool available(PcApp a) => a.url.isNotEmpty || installedExe(a) != null;

final Map<String, Uint8List> _art = {};

/// A tile for the app: its colour, and its name in Foyer's font (no logos).
Future<Uint8List> tileArt(PcApp a, {bool square = false}) async {
  final key = '${a.id}|$square';
  final cached = _art[key];
  if (cached != null) return cached;
  final w = square ? 192.0 : 640.0, h = square ? 192.0 : 360.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final base = Color(a.color);
  final dark = Color.lerp(base, Colors.black, 0.55)!;
  c.drawRect(Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [Color.lerp(base, Colors.white, 0.08)!, dark]));
  // a soft light in the corner, like Foyer's glass
  c.drawCircle(Offset(w * 0.15, h * 0.1), w * 0.6,
      Paint()..shader = ui.Gradient.radial(Offset(w * 0.15, h * 0.1), w * 0.6, [const Color(0x33FFFFFF), const Color(0x00FFFFFF)]));
  final text = square ? a.label.characters.first : a.label;
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: square ? 96 : (a.label.length > 9 ? 62 : 76),
            fontWeight: FontWeight.w800,
            letterSpacing: square ? 0 : -1.5,
            color: Colors.white)),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w - 48);
  tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  _art[key] = bytes;
  return bytes;
}

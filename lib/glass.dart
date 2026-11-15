// Glass app icons (like Apple's clear icons): each app's logo with its own background taken
// away, drawn in soft white on a sheet of glass. The app you're on shows its real colours.
//
// How: the logo is shrunk to a small working size; the colours along its edges are taken as the
// background; every pixel is scored by how far it is from the nearest of them, and that score
// becomes the glyph's opacity. A picture that doesn't split cleanly (a photo, or a logo that
// fills nearly all of it) gets a quiet grey version instead. Worked out once per app, off the
// main thread.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';

final Map<String, ui.Image?> _glyphs = {};
final Set<String> _working = {};

/// Bumps when a glyph is ready, so tiles redraw.
final ValueNotifier<int> kGlyphs = ValueNotifier(0);

Future<void> _make(String key, Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
    final src = (await codec.getNextFrame()).image;
    final w = src.width, h = src.height;
    final bd = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
    src.dispose();
    if (bd == null) throw StateError('no pixels');
    final out = await compute(_cut, (bd.buffer.asUint8List(), w, h));
    if (out == null) {
      _glyphs[key] = null;
    } else {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(out, w, h, ui.PixelFormat.rgba8888, done.complete);
      _glyphs[key] = await done.future;
    }
  } catch (_) {
    _glyphs[key] = null;
  }
  _working.remove(key);
  kGlyphs.value++;
}

/// The white glyph as RGBA pixels, or null when the picture doesn't split cleanly.
Uint8List? _cut((Uint8List, int, int) a) {
  final (px, w, h) = a;
  // background: the common colours in a thin band just inside the edges
  final band = max(2, (min(w, h) * 0.05).round());
  final bins = <int, int>{};
  var total = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final e = min(min(x, w - 1 - x), min(y, h - 1 - y));
      if (e > band) continue;
      final i = (y * w + x) * 4;
      if (px[i + 3] < 200) continue;
      final k = ((px[i] >> 3) << 10) | ((px[i + 1] >> 3) << 5) | (px[i + 2] >> 3);
      bins[k] = (bins[k] ?? 0) + 1;
      total++;
    }
  }
  if (total < 40) return null;
  final common = bins.entries.where((e) => e.value / total >= 0.005).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final pal = [
    for (final e in common.take(48))
      [((e.key >> 10) & 31) * 8 + 4, ((e.key >> 5) & 31) * 8 + 4, (e.key & 31) * 8 + 4]
  ];
  if (pal.isEmpty) return null;
  final out = Uint8List(w * h * 4);
  var cover = 0.0;
  const t0 = 26.0, t1 = 70.0; // closer than t0 is background, farther than t1 is all logo
  for (var j = 0; j < w * h; j++) {
    final q = j * 4;
    final al = px[q + 3];
    if (al < 128) continue;
    var best = 1e9;
    for (final c in pal) {
      final dr = px[q] - c[0], dg = px[q + 1] - c[1], db = px[q + 2] - c[2];
      final d = (dr * dr + dg * dg + db * db).toDouble();
      if (d < best) best = d;
    }
    final d = sqrt(best);
    final k = ((d - t0) / (t1 - t0)).clamp(0.0, 1.0);
    if (k <= 0) continue;
    cover += k;
    out[q] = 255;
    out[q + 1] = 255;
    out[q + 2] = 255;
    out[q + 3] = (k * al).round();
  }
  final frac = cover / (w * h);
  if (frac < 0.004 || frac > 0.55) return null;
  return out;
}

/// An app's tile in glass: the white glyph on a frosted sheet (or a quiet grey version).
class GlassArt extends StatelessWidget {
  const GlassArt({super.key, required this.app});
  final AppInfo app;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: kGlyphs,
        builder: (_, __, ___) {
          final key = '${app.package}|${app.image.length}';
          if (!_glyphs.containsKey(key) && _working.add(key)) _make(key, app.image);
          final g = _glyphs[key];
          final blur = !SettingsScope.of(context).perfMode;
          return Stack(fit: StackFit.expand, children: [
            // frosted: the wallpaper behind, softly blurred (Performance mode skips the blur)
            if (blur)
              BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: const SizedBox.expand()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x38FFFFFF), Color(0x14FFFFFF)],
                ),
              ),
            ),
            if (g != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: app.wide ? 26 : 0, vertical: app.wide ? 20 : 0),
                child: FractionallySizedBox(
                  widthFactor: app.wide ? 1 : 0.44,
                  heightFactor: app.wide ? 1 : 0.62,
                  child: RawImage(image: g, fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.92)),
                ),
              )
            else if (_glyphs.containsKey(key))
              // didn't split cleanly: the app's own picture, grey and soft
              Opacity(
                opacity: 0.55,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0.33, 0.59, 0.11, 0, 0, //
                    0.33, 0.59, 0.11, 0, 0, //
                    0.33, 0.59, 0.11, 0, 0, //
                    0, 0, 0, 1, 0,
                  ]),
                  child: appArt(app, 200),
                ),
              ),
          ]);
        },
      );
}

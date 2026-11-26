// Video background: a muted clip that loops behind the home screen instead of the photo
// (Settings → Appearance → Video background). The photo stays until the clip plays and comes
// back if it won't. It pauses while another app is in front. TV only: Foyer for PC keeps
// its photos.
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'main.dart';
import 'screens.dart';

/// true while a clip is on screen (the home screen then shows its own clock).
final ValueNotifier<bool> kVideoPlaying = ValueNotifier(false);

bool videoWanted(Settings s) => !kIsPc && s.videoOn && s.videoUrl.trim().isNotEmpty;

class VideoBackground extends StatefulWidget {
  const VideoBackground({super.key, required this.url});
  final String url;
  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> with WidgetsBindingObserver {
  int? _id;
  double _w = 16, _h = 9;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(VideoBackground old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  Future<void> _start() async {
    setState(() {
      _id = null;
      _failed = false;
    });
    kVideoPlaying.value = false;
    Map? r;
    try {
      r = await kChannel.invokeMapMethod('videoStart', {'url': widget.url.trim()});
    } catch (_) {}
    if (!mounted) return;
    if (r == null || r['id'] is! int) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _id = r!['id'] as int;
      _w = ((r['width'] as num?) ?? 16).toDouble().clamp(1, 10000).toDouble();
      _h = ((r['height'] as num?) ?? 9).toDouble().clamp(1, 10000).toDouble();
    });
    kVideoPlaying.value = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // no clip running behind Netflix
    if (s == AppLifecycleState.resumed) {
      kChannel.invokeMethod('videoResume').catchError((_) => null);
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      kChannel.invokeMethod('videoPause').catchError((_) => null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kChannel.invokeMethod('videoStop').catchError((_) => null);
    kVideoPlaying.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    if (id == null || _failed) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (_, v, child) => Opacity(opacity: v, child: child),
      child: Stack(fit: StackFit.expand, children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: _w, height: _h, child: Texture(textureId: id)),
          ),
        ),
        // a soft shade so the clock and the apps read on any clip
        const DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x59000000), Color(0x14000000), Color(0x99000000)],
                    stops: [0, 0.45, 1]))),
      ]),
    );
  }
}

/// Settings → Appearance → Video background
Future<void> videoMenu(BuildContext context) async {
  final s = SettingsScope.read(context);
  if (kIsPc) {
    await showMenu2(context, 'Video background', [
      MenuChoice('Video backgrounds are on the TV version of Foyer only, for now.', null),
      MenuChoice('OK', () {}),
    ]);
    return;
  }
  Future<void> askLink() async {
    final v = await askText(context, 'Video link', s.videoUrl,
        hint: 'https://… .mp4 (or a file on this TV)', maxLength: 600);
    if (v != null && v.trim().isNotEmpty) s.change(() {
      s.videoUrl = v.trim();
      s.videoOn = true;
    });
  }

  if (s.videoUrl.trim().isEmpty) return askLink();
  await showMenu2(context, 'Video background', [
    MenuChoice('A muted clip that loops behind the home screen. The photo stays if it won\'t play.', null),
    MenuChoice(s.videoOn ? 'Turn it off' : 'Turn it on', () => s.change(() => s.videoOn = !s.videoOn)),
    MenuChoice('Change the video link', askLink),
    MenuChoice('Cancel', () {}),
  ]);
}

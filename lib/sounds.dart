// Soft navigation sounds: a tick when moving, a pop on OK, a drop on Back.
// Hooked in once for the whole app, so every screen gets them.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'main.dart';

const FoyerChannel _ch = FoyerChannel('leclair/sound');

/// 0 off, 1 quiet, 2 normal (Settings > Appearance > Sounds).
int kSoundLevel = 1;

const List<String> kSoundNames = ['Off', 'Quiet', 'Normal'];

final Set<LogicalKeyboardKey> _arrows = {
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};
final Set<LogicalKeyboardKey> _ok = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};
final Set<LogicalKeyboardKey> _back = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape};

DateTime _lastArrow = DateTime(2000);
DateTime _lastMove = DateTime(2000);
FocusNode? _lastFocus;
bool _installed = false;

void uiSound(String name) {
  if (kSoundLevel <= 0) return;
  _ch.invokeMethod('play', {'name': name, 'volume': kSoundLevel == 1 ? 0.35 : 0.8}).catchError((_) => null);
}

void installUiSounds() {
  if (_installed) return;
  _installed = true;
  HardwareKeyboard.instance.addHandler((e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      if (_arrows.contains(k)) _lastArrow = DateTime.now();
      if (e is KeyDownEvent && _back.contains(k)) uiSound('back');
    } else if (e is KeyUpEvent && _ok.contains(k)) {
      uiSound('select');
    }
    return false; // never swallow the key
  });
  FocusManager.instance.addListener(() {
    final f = FocusManager.instance.primaryFocus;
    if (identical(f, _lastFocus)) return;
    _lastFocus = f;
    final now = DateTime.now();
    // only when the remote moved focus (not when a page opens)
    if (now.difference(_lastArrow).inMilliseconds > 300) return;
    if (now.difference(_lastMove).inMilliseconds < 35) return;
    _lastMove = now;
    uiSound('move');
  });
}

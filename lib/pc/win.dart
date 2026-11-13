// Small Windows helpers for Foyer for PC, straight to the Windows API (no plugins):
// full screen, bringing Foyer to the front, pressing keys for the phone remote,
// watching for the remote's Home button, and switching the monitor off.
import 'dart:async';
import 'dart:ffi';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');

final int Function(Pointer<Uint16>, Pointer<Uint16>) _findWindow = _user32
    .lookupFunction<IntPtr Function(Pointer<Uint16>, Pointer<Uint16>), int Function(Pointer<Uint16>, Pointer<Uint16>)>(
        'FindWindowW');
final int Function(int) _setForeground =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final int Function() _getForeground = _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
final int Function(int, int) _showWindow =
    _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final void Function(int, int, int, int) _keybd = _user32
    .lookupFunction<Void Function(Uint8, Uint8, Uint32, UintPtr), void Function(int, int, int, int)>('keybd_event');
final int Function(int) _asyncKey = _user32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');
final int Function(int, int, int) _setLong = _user32
    .lookupFunction<IntPtr Function(IntPtr, Int32, IntPtr), int Function(int, int, int)>('SetWindowLongPtrW');
final int Function(int, int, int, int, int, int, int) _setPos = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');
final int Function(int) _metrics = _user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');
final int Function(int, int, int, int) _postMessage = _user32
    .lookupFunction<Int32 Function(IntPtr, Uint32, UintPtr, IntPtr), int Function(int, int, int, int)>('PostMessageW');
final Pointer<Void> Function(int) _alloc =
    _ole32.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('CoTaskMemAlloc');
final void Function(Pointer<Void>) _free =
    _ole32.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CoTaskMemFree');

// Windows key codes
const int vkBack = 0xA6; // Browser Back
const int vkHome = 0xAC; // Browser Home (the Home button on most PC remotes)
const int vkReturn = 0x0D;
const int vkEscape = 0x1B;
const int vkLeft = 0x25, vkUp = 0x26, vkRight = 0x27, vkDown = 0x28;
const int vkApps = 0x5D; // the menu key
const int vkPlayPause = 0xB3;
const int vkMute = 0xAD, vkVolDown = 0xAE, vkVolUp = 0xAF;
const int vkControl = 0x11, vkV = 0x56, vkAlt = 0x12;

class Win {
  static int _hwnd = 0;

  static Pointer<Uint16> _wide(String s) {
    final p = _alloc((s.length + 1) * 2).cast<Uint16>();
    for (var i = 0; i < s.length; i++) {
      p[i] = s.codeUnitAt(i);
    }
    p[s.length] = 0;
    return p;
  }

  /// Foyer's own window (Flutter's standard window class).
  static int get window {
    if (_hwnd != 0) return _hwnd;
    final cls = _wide('FLUTTER_RUNNER_WIN32_WINDOW');
    try {
      _hwnd = _findWindow(cls, Pointer<Uint16>.fromAddress(0));
    } finally {
      _free(cls.cast());
    }
    return _hwnd;
  }

  static bool get foyerInFront => window != 0 && _getForeground() == window;

  /// Borderless, covering the whole screen, like a TV app.
  static void fullScreen() {
    final h = window;
    if (h == 0) return;
    const wsPopup = 0x80000000, wsVisible = 0x10000000;
    _setLong(h, -16, wsPopup | wsVisible); // GWL_STYLE
    // SWP_FRAMECHANGED | SWP_SHOWWINDOW
    _setPos(h, 0, 0, 0, _metrics(0), _metrics(1), 0x0020 | 0x0040);
  }

  /// Brings Foyer back in front of whatever is open.
  static void toFront() {
    final h = window;
    if (h == 0) return;
    // Windows only lets the app that got the last key press take the front, so press Alt first.
    _keybd(vkAlt, 0, 0, 0);
    _keybd(vkAlt, 0, 2, 0);
    _showWindow(h, 9); // SW_RESTORE
    _setForeground(h);
    fullScreen();
  }

  /// Presses (and lets go of) a key, for the phone remote.
  static void press(int vk, {bool ctrl = false}) {
    if (ctrl) _keybd(vkControl, 0, 0, 0);
    _keybd(vk, 0, 0, 0);
    _keybd(vk, 0, 2, 0); // KEYEVENTF_KEYUP
    if (ctrl) _keybd(vkControl, 0, 2, 0);
  }

  /// Turns the monitor or TV picture off; any key or mouse move brings it back.
  static void monitorOff() => _postMessage(0xFFFF, 0x0112, 0xF170, 2); // HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER

  static Timer? _watch;
  static bool _homeDown = false;

  /// Watches for the remote's Home button even while another app is in front.
  static void watchHome(void Function() onHome) {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(milliseconds: 90), (_) {
      final down = (_asyncKey(vkHome) & 0x8000) != 0;
      if (down && !_homeDown) onHome();
      _homeDown = down;
    });
  }
}

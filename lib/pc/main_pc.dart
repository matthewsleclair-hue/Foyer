// Foyer for PC: the same Foyer as on the TV, running on a Windows PC plugged into the TV.
// Build: flutter build windows -t lib/pc/main_pc.dart   (the GitHub workflow does it)
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../i18n.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'apps.dart';
import 'bridge.dart';
import 'update_pc.dart';
import 'win.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kIsPc = true;
  kSuggested = kPcSuggested;
  kChannelOverride = pcChannel;
  kPcUpdateScreen = () => const PcUpdateScreen();
  kPcAutoUpdate = (s) async {
    final u = await checkPcUpdate(s);
    if (u == null) return false;
    await installPcUpdate(u, s, (_) {}); // closes Foyer for a moment and opens the new one
    return true;
  };
  await PcBridge.init();
  runApp(SettingsScope(settings: Settings(), child: const PcShell(child: LauncherApp())));
  // borderless full screen once the window exists, and again a moment later in case Windows moved it
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Win.fullScreen();
    Timer(const Duration(seconds: 2), Win.toFront);
    startPcUpdateChecks();
  });
}

/// The keys a PC remote (or keyboard) sends: Escape and Back go back, Home goes home,
/// and the menu key opens Settings like it does on the TV.
class PcShell extends StatelessWidget {
  const PcShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.browserBack ||
              k == LogicalKeyboardKey.backspace ||
              k == LogicalKeyboardKey.goBack) {
            kNavKey.currentState?.maybePop();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.browserHome || k == LogicalKeyboardKey.home) {
            PcBridge.goHome();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );
}

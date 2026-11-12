// Your Homarr (or any web) dashboard on the TV. Connected in Settings > Home screen >
// Dashboard; only then does its button show above the fireplace and the moon.
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';
import 'system.dart';

const List<int> kDashZooms = [50, 75, 100];
const Map<int, String> kDashZoomNames = {50: 'Small (fits the most)', 75: 'Medium', 100: 'Large'};

Future<void> openDashboard(BuildContext context) async {
  final s = SettingsScope.read(context);
  if (s.homarrUrl.isEmpty) return;
  bool ok = false;
  try {
    ok = (await kChannel.invokeMethod<bool>('openDashboard', {'url': s.homarrUrl, 'zoom': s.homarrZoom})) ?? false;
  } catch (_) {}
  if (!ok && context.mounted) showInfo(context, 'Could not open the dashboard', 'Check the address in Settings › Home screen › Dashboard.');
}

/// Adds http:// when someone types just an address like 192.168.2.24:7575.
String cleanDashUrl(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return '';
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    final local = RegExp(r'^(\d{1,3}\.){3}\d{1,3}').hasMatch(u) || u.startsWith('localhost');
    u = '${local ? 'http' : 'https'}://$u';
  }
  return u;
}

class DashboardSettingsScreen extends StatelessWidget {
  const DashboardSettingsScreen({super.key});

  Future<void> _edit(BuildContext context, Settings s) async {
    final v = await askText(context, 'Dashboard address', s.homarrUrl,
        hint: 'http://192.168.2.10:7575  or  https://home.example.com', maxLength: 200);
    if (v == null) return;
    s.change(() => s.homarrUrl = cleanDashUrl(v));
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final on = s.homarrUrl.isNotEmpty;
    return SettingsPage(
      title: 'Dashboard',
      subtitle: 'Show your Homarr dashboard on the TV. Once it\'s connected, a dashboard button '
          'appears above the fireplace on the home screen.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SysRow(
              icon: Icons.link_rounded,
              title: on ? 'Address' : 'Connect your dashboard',
              subtitle: on ? s.homarrUrl : 'Type the address you open Homarr at (you can type it on your phone)',
              autofocus: true,
              onSelect: () => _edit(context, s)),
          if (on) ...[
            SysRow(
                icon: Icons.play_arrow_rounded,
                title: 'Open it now',
                subtitle: 'Up and down scroll · Menu refreshes · Back closes',
                onSelect: () => openDashboard(context)),
            SysRow(
                icon: Icons.zoom_in_rounded,
                title: 'Size',
                subtitle: 'Smaller fits more of the dashboard on screen',
                value: kDashZoomNames[s.homarrZoom] ?? '${s.homarrZoom}%',
                onSelect: () => showMenu2(context, 'Dashboard size', [
                      for (final z in kDashZooms)
                        MenuChoice(kDashZoomNames[z]!, () => s.change(() => s.homarrZoom = z)),
                      MenuChoice('Cancel', () {}),
                    ])),
            SysRow(
                icon: Icons.link_off_rounded,
                title: 'Remove the dashboard',
                subtitle: 'The button on the home screen goes away',
                onSelect: () => s.change(() => s.homarrUrl = '')),
          ],
          const SizedBox(height: 18),
          const SizedBox(
            width: 1300,
            child: Text(
                'If Homarr asks you to sign in, do it once inside the dashboard; Foyer remembers it. '
                'Or make the board public in Homarr so it opens without signing in.',
                style: TextStyle(fontSize: 23, color: Colors.white54)),
          ),
        ]),
      ),
    );
  }
}

// Settings > TV settings > VPN. On Android TV every VPN works through its own app, which
// also holds the login. Foyer shows whether a VPN is on, and opens the app (or its Play Store page).
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'screens.dart';
import 'system.dart';

class VpnInfo {
  const VpnInfo(this.name, this.package, this.blurb);
  final String name;
  final String package;
  final String blurb;
}

const List<VpnInfo> kVpns = [
  VpnInfo('NordVPN', 'com.nordvpn.android', 'Popular and fast. Sign in with your Nord Account.'),
  VpnInfo('ExpressVPN', 'com.expressvpn.vpn', 'Simple and reliable. The TV app signs in with your email.'),
  VpnInfo('Surfshark', 'com.surfshark.vpnclient.android', 'One account covers every device in the house.'),
  VpnInfo('Proton VPN', 'ch.protonvpn.android', 'From the makers of Proton Mail. Has a free plan.'),
  VpnInfo('CyberGhost', 'de.mobileconcepts.cyberghost', 'Has servers set up for streaming.'),
  VpnInfo('Private Internet Access', 'com.privateinternetaccess.android', 'Budget friendly with lots of settings.'),
  VpnInfo('Mullvad', 'net.mullvad.mullvadvpn', 'Private by design: no email needed, just an account number.'),
  VpnInfo('Tailscale', 'com.tailscale.ipn', 'Reach your home network (Plex, servers) from anywhere.'),
  VpnInfo('OpenVPN Connect', 'net.openvpn.openvpn', 'For a VPN your work or your own server gives you as a .ovpn file.'),
  VpnInfo('WireGuard', 'com.wireguard.android', 'For WireGuard configs from your router or server.'),
];

class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});
  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> with WidgetsBindingObserver {
  Set<String> _installed = {};
  bool _vpnOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // back from a VPN app or the Play Store: look again
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final info = await sysCall('info');
    List<String> got = [];
    try {
      got = (await kSystem.invokeListMethod<String>('installed', {'packages': [for (final v in kVpns) v.package]})) ?? [];
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _vpnOn = info['vpn'] == true;
      _installed = got.toSet();
    });
  }

  /// Installed: open it (sign in and connect there). Not installed: its Play Store page.
  Future<void> _open(VpnInfo v) async {
    if (_installed.contains(v.package)) {
      await launchPackage(v.package);
      return;
    }
    try {
      await kChannel.invokeMethod<bool>('openLink', {
        'url': 'market://details?id=${v.package}',
        'package': 'com.android.vending',
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mine = [for (final v in kVpns) if (_installed.contains(v.package)) v];
    final others = [for (final v in kVpns) if (!_installed.contains(v.package)) v];
    Widget row(VpnInfo v, bool first) => SysRow(
        icon: Icons.vpn_lock_rounded,
        title: v.name,
        subtitle: v.blurb,
        value: _installed.contains(v.package) ? 'Open' : 'Get',
        autofocus: first,
        onSelect: () => _open(v));
    return SettingsPage(
      title: 'VPN',
      subtitle: _vpnOn
          ? '🔒 This TV is connected through a VPN right now.'
          : 'No VPN is on. Each VPN signs in and connects in its own app: pick one to open it, or to get it from the Play Store.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (mine.isNotEmpty) ...[
            const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 0, 12),
                child: Text('On this TV', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white54))),
            for (var i = 0; i < mine.length; i++) row(mine[i], i == 0),
          ],
          Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 0, 12),
              child: Text(mine.isEmpty ? 'Popular VPNs' : 'More VPNs',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white54))),
          for (var i = 0; i < others.length; i++) row(others[i], mine.isEmpty && i == 0),
          const SizedBox(height: 10),
          const SizedBox(
            width: 1300,
            child: Text(
                'Some streaming apps block VPNs, or show a different country\'s shows while one is on. '
                'If Netflix or Crave acts up, turn the VPN off in its app.',
                style: TextStyle(fontSize: 22, color: Colors.white38)),
          ),
        ]),
      ),
    );
  }
}

// Settings > TV settings > VPN. On Android TV every VPN works through its own app, which
// also holds the login. Foyer shows whether a VPN is on, opens or installs the app, and
// shows a QR code that takes your phone to that VPN's sign-in page.
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';
import 'system.dart';
import 'vpn_qr.dart';

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

  void _open(VpnInfo v) => showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => _VpnDialog(vpn: v, installed: _installed.contains(v.package)),
      ).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final mine = [for (final v in kVpns) if (_installed.contains(v.package)) v];
    final others = [for (final v in kVpns) if (!_installed.contains(v.package)) v];
    Widget row(VpnInfo v, bool first) => SysRow(
        icon: Icons.vpn_lock_rounded,
        title: v.name,
        subtitle: v.blurb,
        value: _installed.contains(v.package) ? 'Installed' : '',
        autofocus: first,
        onSelect: () => _open(v));
    return SettingsPage(
      title: 'VPN',
      subtitle: _vpnOn
          ? '🔒 This TV is connected through a VPN right now.'
          : 'No VPN is on. Each VPN works through its own app; pick one to open it or get it.',
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

class _VpnDialog extends StatelessWidget {
  const _VpnDialog({required this.vpn, required this.installed});
  final VpnInfo vpn;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Glass(
          radius: 40,
          padding: const EdgeInsets.all(44),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            // white card behind the code so any phone camera reads it
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Image.memory(vpn.qrPng, width: 300, height: 300, filterQuality: FilterQuality.none),
            ),
            const SizedBox(width: 44),
            SizedBox(
              width: 620,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vpn.name, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(vpn.blurb, style: const TextStyle(fontSize: 24, color: Colors.white70)),
                const SizedBox(height: 22),
                const Text('Scan with your phone to sign in, check your plan or sign up.',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(vpn.url.replaceFirst('https://', ''), style: const TextStyle(fontSize: 21, color: Colors.white54)),
                const SizedBox(height: 10),
                Text(
                    installed
                        ? 'Then open the app on the TV and sign in there too; most show a short code or their own QR code to make it easy.'
                        : 'Then get the app on the TV and sign in there; most show a short code or their own QR code to make it easy.',
                    style: const TextStyle(fontSize: 22, color: Colors.white54)),
                const SizedBox(height: 28),
                Wrap(spacing: 18, runSpacing: 18, children: [
                  if (installed)
                    PillButton(
                        label: 'Open ${vpn.name}',
                        primary: true,
                        autofocus: true,
                        onSelect: () {
                          close();
                          launchPackage(vpn.package);
                        })
                  else
                    PillButton(
                        label: 'Get it from the Play Store',
                        primary: true,
                        autofocus: true,
                        onSelect: () {
                          close();
                          kChannel.invokeMethod<bool>('openLink', {
                            'url': 'market://details?id=${vpn.package}',
                            'package': 'com.android.vending',
                          }).catchError((_) => false);
                        }),
                  PillButton(label: 'Close', onSelect: close),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

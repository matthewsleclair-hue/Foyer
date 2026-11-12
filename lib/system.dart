// The TV's own settings, inside Foyer: Wi-Fi, Bluetooth, picture, sound, apps,
// storage, name and power. Built for Google TV / Android TV boxes, where Foyer
// can use the TV's debugging link (set up by "Make Foyer the home screen").
// Anything Android keeps locked away opens the stock page, and Back or Home
// comes straight back to Foyer.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'screens.dart';

const MethodChannel kSystem = MethodChannel('leclair/system');
const String _me = 'com.leclair.leclair_home';

// ───────────────────────── helpers ─────────────────────────

class AdbResult {
  AdbResult(this.out, this.error);
  final List<String> out;
  final String? error;
  bool get ok => error == null;
  String at(int i) => i < out.length ? out[i] : '';
}

/// Runs shell commands on the TV and returns what each one printed.
Future<AdbResult> adbOut(List<String> cmds, {bool eofOk = false}) async {
  try {
    final res = await kChannel.invokeMapMethod<String, dynamic>('adbRun', {'commands': cmds});
    if (res?['ok'] == true) {
      return AdbResult([for (final o in (res?['outputs'] as List? ?? const [])) '$o'], null);
    }
    final e = '${res?['error']}';
    if (eofOk && (e.contains('EOF') || e.contains('reset') || e.contains('closed'))) {
      return AdbResult(const [], null);
    }
    return AdbResult(const [], adbFriendly(e));
  } catch (e) {
    return AdbResult(const [], adbFriendly(e));
  }
}

/// Safe single-quoting for the TV's shell.
String shq(String s) => "'${s.replaceAll("'", "'\\''")}'";

Future<Map<String, dynamic>> sysCall(String method, [Map<String, dynamic>? args]) async {
  try {
    return (await kSystem.invokeMapMethod<String, dynamic>(method, args)) ?? {};
  } catch (_) {
    return {};
  }
}

Future<void> openStockPage(String page) async {
  try {
    await kSystem.invokeMethod('openPage', {'page': page});
  } catch (_) {}
}

String fmtBytes(num b) {
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
  if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(0)} MB';
  return '${(b / 1e3).toStringAsFixed(0)} KB';
}

void _go(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

const _body = TextStyle(fontSize: 26, color: Colors.white70);
const _good = Color(0xFF8CE99A);

/// One focusable row: icon, title, small line, and an optional value on the right.
class SysRow extends StatelessWidget {
  const SysRow(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle = '',
      this.value = '',
      required this.onSelect,
      this.autofocus = false,
      this.chevron = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FocusButton(
          autofocus: autofocus,
          scale: 1.0,
          scrollIntoView: true,
          onSelect: onSelect,
          builder: (_, f) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 1300,
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              color: f ? Colors.white : Colors.white.withAlpha(24),
              border: Border.all(color: Colors.white.withAlpha(f ? 255 : 60), width: 1.5),
            ),
            child: Row(children: [
              Icon(icon, size: 42, color: f ? Colors.black : Colors.white),
              const SizedBox(width: 28),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w700, color: f ? Colors.black : Colors.white)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 23, color: f ? Colors.black54 : Colors.white70)),
                  ],
                ]),
              ),
              if (value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w600, color: f ? Colors.black87 : Colors.white70)),
                ),
              if (chevron)
                Icon(Icons.chevron_right_rounded, size: 42, color: f ? Colors.black : Colors.white54),
            ]),
          ),
        ),
      );
}

Widget _heading(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 0, 14),
      child: Text(t, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white54)),
    );

Widget _note(String t, {Color color = Colors.white70}) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 18),
      child: SizedBox(width: 1300, child: Text(t, style: _body.copyWith(color: color))),
    );

Widget _list(List<Widget> rows) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );

// ───────────────────────── the hub ─────────────────────────

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});
  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  Map<String, dynamic> _i = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await sysCall('info');
    if (mounted) setState(() => _i = i);
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final link = _i['link'] ?? '';
    final net = link == 'ethernet' ? 'Wired' : (link == 'wifi' ? 'Wi-Fi' : (link == 'none' ? 'Not connected' : ''));
    final free = _i['storageFree'] as num?;
    return SettingsPage(
      title: 'TV settings',
      subtitle: 'Everything for the TV itself, without leaving Foyer.',
      child: _list([
        SysRow(
            icon: Icons.wifi_rounded,
            title: 'Network and internet',
            subtitle: 'Wi-Fi networks, passwords, wired connection',
            value: net,
            autofocus: true,
            onSelect: () => _open(const WifiScreen())),
        SysRow(
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth and remotes',
            subtitle: 'Headphones, speakers, game controllers, keyboards',
            onSelect: () => _open(const BluetoothScreen())),
        SysRow(
            icon: Icons.tv_rounded,
            title: 'Picture and display',
            subtitle: 'Resolution, refresh rate, when the screen turns off',
            onSelect: () => _open(const DisplayScreen())),
        SysRow(
            icon: Icons.volume_up_rounded,
            title: 'Sound',
            subtitle: 'Volume, mute, button sounds',
            onSelect: () => _open(const SoundScreen())),
        SysRow(
            icon: Icons.apps_rounded,
            title: 'Apps',
            subtitle: 'Open, close, reset, turn off or uninstall any app',
            onSelect: () => _open(const AppsManagerScreen())),
        SysRow(
            icon: Icons.sd_storage_rounded,
            title: 'Storage',
            subtitle: 'See what\'s free and clear app caches',
            value: free == null ? '' : '${fmtBytes(free)} free',
            onSelect: () => _open(const StorageScreen())),
        SysRow(
            icon: Icons.info_outline_rounded,
            title: 'Name and about',
            subtitle: 'Rename this TV, model, Android version, address',
            value: '${_i['name'] ?? ''}',
            onSelect: () => _open(const AboutTvScreen())),
        SysRow(
            icon: Icons.power_settings_new_rounded,
            title: 'Power',
            subtitle: 'Restart or put the TV to sleep',
            onSelect: () => _open(const PowerScreen())),
        SysRow(
            icon: Icons.more_horiz_rounded,
            title: 'More',
            subtitle: 'Google account, privacy, date, language, keyboard, system update',
            onSelect: () => _open(const MoreTvScreen())),
      ]),
    );
  }
}

// ───────────────────────── Wi-Fi ─────────────────────────

class _Net {
  _Net(this.ssid, this.rssi, this.sec);
  final String ssid;
  final int rssi;
  final String sec; // open, owe, wpa2, wpa3, eap, wep
  int get bars => rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -77 ? 2 : 1;
  bool get locked => sec != 'open' && sec != 'owe';
}

class _Saved {
  _Saved(this.id, this.ssid);
  final String id;
  final String ssid;
}

List<_Net> _parseScan(String out) {
  final best = <String, _Net>{};
  for (final raw in out.split('\n')) {
    final t = raw.trim().split(RegExp(r'\s+'));
    // BSSID  Frequency  RSSI  Age  SSID...  Flags
    if (t.length < 5 || !RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$').hasMatch(t[0])) continue;
    final rssi = int.tryParse(RegExp(r'-?\d+').stringMatch(t[2]) ?? '') ?? -100;
    var end = t.length;
    while (end > 4 && t[end - 1].startsWith('[')) {
      end--;
    }
    final flags = t.sublist(end).join();
    final ssid = t.sublist(4, end).join(' ');
    if (ssid.isEmpty) continue; // hidden network
    final sec = flags.contains('EAP')
        ? 'eap'
        : flags.contains('SAE') && !flags.contains('PSK')
            ? 'wpa3'
            : flags.contains('PSK')
                ? 'wpa2'
                : flags.contains('WEP')
                    ? 'wep'
                    : flags.contains('OWE')
                        ? 'owe'
                        : 'open';
    final old = best[ssid];
    if (old == null || old.rssi < rssi) best[ssid] = _Net(ssid, rssi, sec);
  }
  return best.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
}

List<_Saved> _parseSaved(String out) {
  final r = <_Saved>[];
  for (final raw in out.split('\n')) {
    final t = raw.trim().split(RegExp(r'\s+'));
    if (t.length < 3 || int.tryParse(t[0]) == null) continue;
    r.add(_Saved(t[0], t.sublist(1, t.length - 1).join(' ')));
  }
  return r;
}

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});
  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  bool _busy = false;
  bool _loaded = false;
  bool _on = true;
  String _current = '';
  int _rssi = 0;
  String _link = '';
  List<String> _ips = [];
  List<_Net> _nets = [];
  List<_Saved> _saved = [];
  String _msg = '';
  Color _msgColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _refresh(scan: true);
  }

  void _say(String m, [Color c = Colors.white70]) {
    if (mounted) setState(() {
      _msg = m;
      _msgColor = c;
    });
  }

  Future<void> _status() async {
    final i = await sysCall('info');
    final r = await adbOut(['cmd wifi status']);
    if (!mounted) return;
    setState(() {
      _link = '${i['link'] ?? ''}';
      _ips = [for (final x in (i['ips'] as List? ?? const [])) '$x'];
      if (r.ok) {
        final s = r.at(0);
        _on = !s.contains('Wifi is disabled');
        _current = RegExp(r'connected to "(.+?)"').firstMatch(s)?.group(1) ?? '';
        _rssi = int.tryParse(RegExp(r'RSSI: (-?\d+)').firstMatch(s)?.group(1) ?? '') ?? 0;
      }
    });
    if (!r.ok) _say(r.error!, const Color(0xFFFFB4A9));
  }

  Future<void> _refresh({bool scan = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (scan) _say('Looking for networks…');
    await _status();
    if (scan && _on) {
      final r = await adbOut(['cmd wifi start-scan', 'sleep 4', 'cmd wifi list-scan-results', 'cmd wifi list-networks']);
      if (r.ok) {
        _nets = _parseScan(r.at(2));
        _saved = _parseSaved(r.at(3));
        _say(_nets.isEmpty ? 'No networks found. Choose Scan again.' : '');
      } else {
        _say(r.error!, const Color(0xFFFFB4A9));
      }
    }
    if (mounted) setState(() {
      _busy = false;
      _loaded = true;
    });
  }

  Future<void> _toggle() async {
    if (_on) {
      // never switch Wi-Fi off from a single stray OK press
      return showMenu2(context, 'Turn Wi-Fi off?', [
        MenuChoice(
            _link == 'ethernet'
                ? 'The TV stays online through its network cable.'
                : 'The TV will have no internet until you turn it back on here.',
            null),
        MenuChoice('Keep Wi-Fi on', () {}),
        MenuChoice('Turn off', _switchWifi),
      ]);
    }
    return _switchWifi();
  }

  Future<void> _switchWifi() async {
    final r = await adbOut(['cmd wifi set-wifi-enabled ${_on ? 'disabled' : 'enabled'}']);
    if (!r.ok) return _say(r.error!, const Color(0xFFFFB4A9));
    _say(_on ? 'Turning Wi-Fi off…' : 'Turning Wi-Fi on…');
    await Future<void>.delayed(const Duration(seconds: 3));
    await _refresh(scan: true);
  }

  Future<void> _connect(_Net n, {String? hiddenSsid}) async {
    final ssid = hiddenSsid ?? n.ssid;
    if (n.sec == 'eap' || n.sec == 'wep') {
      return showMenu2(context, ssid, [
        MenuChoice('This network needs a sign-in type Foyer can\'t enter. Use the TV\'s own Wi-Fi page.', null),
        MenuChoice('Open Wi-Fi page', () => openStockPage('wifi')),
        MenuChoice('Cancel', () {}),
      ]);
    }
    var pass = '';
    if (n.locked) {
      final p = await askText(context, 'Password for $ssid', '', hint: 'Wi-Fi password', maxLength: 63);
      if (p == null || p.isEmpty) return;
      pass = p;
    }
    _say('Connecting to $ssid…');
    final r = await adbOut([
      'cmd wifi connect-network ${shq(ssid)} ${n.sec}${n.locked ? ' ${shq(pass)}' : ''}${hiddenSsid != null ? ' -h' : ''}'
    ]);
    if (!r.ok) return _say(r.error!, const Color(0xFFFFB4A9));
    final printed = r.at(0).toLowerCase();
    if (printed.contains('unknown command') || printed.contains('permission') || printed.contains('exception')) {
      return _cantDoIt(ssid);
    }
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _status();
      if (_current == ssid) {
        _say('Connected to $ssid.', _good);
        return _refresh(scan: true);
      }
    }
    _say('Not connected yet. Check the password and try again.', const Color(0xFFFFB4A9));
  }

  void _cantDoIt(String ssid) => showMenu2(context, ssid, [
        MenuChoice('This TV didn\'t let Foyer join the network. Use the TV\'s own Wi-Fi page.', null),
        MenuChoice('Open Wi-Fi page', () => openStockPage('wifi')),
        MenuChoice('Cancel', () {}),
      ]);

  Future<void> _forget(_Saved s) async {
    final r = await adbOut(['cmd wifi forget-network ${s.id}']);
    _say(r.ok ? 'Forgot ${s.ssid}.' : r.error!, r.ok ? _good : const Color(0xFFFFB4A9));
    await _refresh(scan: true);
  }

  void _netMenu(_Net n) {
    final saved = _saved.where((s) => s.ssid == n.ssid).toList();
    final isCurrent = n.ssid == _current;
    if (saved.isEmpty && !isCurrent) {
      _connect(n);
      return;
    }
    showMenu2(context, n.ssid, [
      if (isCurrent) MenuChoice('Connected', null),
      if (!isCurrent) MenuChoice('Connect', () => _connect(n)),
      if (saved.isNotEmpty) MenuChoice('Forget this network', () => _forget(saved.first)),
      MenuChoice('Cancel', () {}),
    ]);
  }

  Future<void> _addHidden() async {
    final ssid = await askText(context, 'Network name', '', hint: 'Exactly as it\'s spelled', maxLength: 32);
    if (ssid == null || ssid.isEmpty || !mounted) return;
    showMenu2(context, 'Security for $ssid', [
      MenuChoice('WPA2 / WPA3 password', () => _connect(_Net(ssid, 0, 'wpa2'), hiddenSsid: ssid)),
      MenuChoice('WPA3 only', () => _connect(_Net(ssid, 0, 'wpa3'), hiddenSsid: ssid)),
      MenuChoice('No password', () => _connect(_Net(ssid, 0, 'open'), hiddenSsid: ssid)),
      MenuChoice('Cancel', () {}),
    ]);
  }

  IconData _barsIcon(int b) => b >= 4
      ? Icons.signal_wifi_4_bar_rounded
      : b == 3
          ? Icons.network_wifi_3_bar_rounded
          : b == 2
              ? Icons.network_wifi_2_bar_rounded
              : Icons.network_wifi_1_bar_rounded;

  @override
  Widget build(BuildContext context) {
    final wired = _link == 'ethernet';
    final status = wired
        ? 'Connected with a cable'
        : _current.isNotEmpty
            ? 'Connected to $_current'
            : (_on ? 'Not connected' : 'Wi-Fi is off');
    return SettingsPage(
      title: 'Network and internet',
      subtitle: [status, if (_ips.isNotEmpty) 'Address ${_ips.first}'].join('   ·   '),
      actions: [
        PillButton(label: _busy ? 'Scanning…' : 'Scan again', onSelect: () => _refresh(scan: true)),
      ],
      child: _list([
        if (_msg.isNotEmpty) _note(_msg, color: _msgColor),
        SysRow(
            icon: _on ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            title: 'Wi-Fi',
            value: _on ? 'On' : 'Off',
            chevron: false,
            autofocus: true,
            onSelect: _toggle),
        if (wired) _note('A network cable is plugged in, so the TV uses that first. Wi-Fi is a backup.'),
        if (_on) _heading('Networks nearby'),
        if (_on && !_loaded) _note('Looking…'),
        for (final n in _nets)
          SysRow(
              icon: _barsIcon(n.bars),
              title: n.ssid,
              subtitle: n.ssid == _current
                  ? 'Connected${_rssi != 0 ? ' · ${const ['', 'weak', 'fair', 'good', 'excellent'][_Net('', _rssi, '').bars]} signal' : ''}'
                  : (_saved.any((s) => s.ssid == n.ssid) ? 'Saved' : (n.locked ? 'Password' : 'Open')),
              value: n.locked ? '🔒' : '',
              chevron: false,
              onSelect: () => _netMenu(n)),
        if (_on)
          SysRow(
              icon: Icons.add_rounded,
              title: 'Add a hidden network',
              subtitle: 'Type the name yourself',
              onSelect: _addHidden),
        SysRow(
            icon: Icons.open_in_new_rounded,
            title: 'More network options',
            subtitle: 'Proxy, fixed IP address and other rare settings (TV\'s own page)',
            onSelect: () => openStockPage('wifi')),
      ]),
    );
  }
}

// ───────────────────────── Bluetooth ─────────────────────────

class _Dev {
  _Dev(this.address, this.name, this.kind, this.paired);
  final String address;
  final String name;
  final String kind;
  final bool paired;
  factory _Dev.from(Map m) =>
      _Dev('${m['address']}', '${m['name']}', '${m['kind']}', m['paired'] == true);
  IconData get icon =>
      const {
        'audio': Icons.headphones_rounded,
        'input': Icons.sports_esports_rounded,
        'phone': Icons.smartphone_rounded,
        'computer': Icons.computer_rounded,
      }[kind] ??
      Icons.bluetooth_rounded;
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});
  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  Map<String, dynamic> _s = {};
  final Map<String, _Dev> _found = {};
  bool _scanning = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    kSystem.setMethodCallHandler(_onEvent);
    _load(grant: true);
  }

  @override
  void dispose() {
    kSystem.setMethodCallHandler(null);
    kSystem.invokeMethod('btStop').catchError((_) => null);
    super.dispose();
  }

  Future<dynamic> _onEvent(MethodCall call) async {
    if (!mounted) return null;
    final m = call.arguments is Map ? call.arguments as Map : const {};
    if (call.method == 'btFound') {
      final d = _Dev.from(m);
      if (!d.paired && d.name != d.address) setState(() => _found[d.address] = d);
    } else if (call.method == 'btBond') {
      final bond = m['bond'];
      if (bond == 12) {
        setState(() => _msg = 'Paired with ${m['name']}.');
        _found.remove('${m['address']}');
        _load();
      } else if (bond == 10) {
        _load();
      }
    } else if (call.method == 'btDone') {
      setState(() => _scanning = false);
    }
    return null;
  }

  Future<void> _load({bool grant = false}) async {
    var s = await sysCall('btState');
    if (grant && s['present'] == true && s['allowed'] == false) {
      setState(() => _msg = 'Giving Foyer Bluetooth access…');
      final r = await adbOut([
        'pm grant $_me android.permission.BLUETOOTH_SCAN',
        'pm grant $_me android.permission.BLUETOOTH_CONNECT',
      ]);
      if (!r.ok && mounted) setState(() => _msg = r.error!);
      s = await sysCall('btState');
      if (s['allowed'] == true && mounted) setState(() => _msg = '');
    }
    if (mounted) setState(() => _s = s);
  }

  Future<void> _toggle() async {
    final on = _s['on'] == true;
    setState(() => _msg = on ? 'Turning Bluetooth off…' : 'Turning Bluetooth on…');
    final cmd = on ? 'disable' : 'enable';
    final r = await adbOut(['cmd bluetooth_manager $cmd || svc bluetooth $cmd']);
    await Future<void>.delayed(const Duration(seconds: 2));
    await _load();
    if (mounted) setState(() => _msg = r.ok ? '' : r.error!);
  }

  Future<void> _scan() async {
    if (_s['on'] != true) return;
    final ok = (await kSystem.invokeMethod<bool>('btScan').catchError((_) => false)) ?? false;
    setState(() {
      _found.clear();
      _scanning = ok;
      _msg = ok
          ? 'Searching… Put your headphones, speaker or controller in pairing mode now.'
          : 'Could not start searching.';
    });
  }

  Future<void> _pair(_Dev d) async {
    final ok = (await kSystem.invokeMethod<bool>('btPair', {'address': d.address}).catchError((_) => false)) ?? false;
    setState(() => _msg = ok ? 'Pairing with ${d.name}… If a code shows, confirm it.' : 'Could not pair with ${d.name}.');
  }

  void _pairedMenu(_Dev d) => showMenu2(context, d.name, [
        MenuChoice('Forget this device', () async {
          final ok =
              (await kSystem.invokeMethod<bool>('btForget', {'address': d.address}).catchError((_) => false)) ?? false;
          if (!mounted) return;
          if (ok) {
            setState(() => _msg = 'Forgot ${d.name}.');
            _load();
          } else {
            showMenu2(context, d.name, [
              MenuChoice('This TV only lets its own page forget devices.', null),
              MenuChoice('Open Bluetooth page', () => openStockPage('bluetooth')),
              MenuChoice('Cancel', () {}),
            ]);
          }
        }),
        MenuChoice('Cancel', () {}),
      ]);

  @override
  Widget build(BuildContext context) {
    final paired = [for (final m in (_s['paired'] as List? ?? const [])) _Dev.from(m as Map)];
    final on = _s['on'] == true;
    final noBt = _s['present'] == false;
    final locked = _s['allowed'] == false;
    return SettingsPage(
      title: 'Bluetooth and remotes',
      subtitle: noBt ? 'This TV has no Bluetooth.' : (_s['name'] != null ? 'Shows up to others as "${_s['name']}"' : null),
      actions: [
        if (on) PillButton(label: _scanning ? 'Searching…' : 'Pair a new device', primary: true, onSelect: _scan),
      ],
      child: _list([
        if (_msg.isNotEmpty) _note(_msg),
        if (!noBt && !locked)
          SysRow(
              icon: on ? Icons.bluetooth_rounded : Icons.bluetooth_disabled_rounded,
              title: 'Bluetooth',
              value: on ? 'On' : 'Off',
              subtitle: on ? '' : 'Turn on to use headphones and controllers',
              chevron: false,
              autofocus: true,
              onSelect: _toggle),
        if (locked)
          SysRow(
              icon: Icons.lock_open_rounded,
              title: 'Let Foyer use Bluetooth',
              subtitle: 'Needs the one-time TV access from Home button setup',
              autofocus: true,
              onSelect: () => _load(grant: true)),
        if (on && paired.isNotEmpty) _heading('Paired'),
        for (final d in paired) SysRow(icon: d.icon, title: d.name, subtitle: 'Paired', onSelect: () => _pairedMenu(d)),
        if (on && (_scanning || _found.isNotEmpty)) _heading('Found nearby'),
        for (final d in _found.values)
          SysRow(icon: d.icon, title: d.name, subtitle: 'Select to pair', onSelect: () => _pair(d)),
        SysRow(
            icon: Icons.settings_remote_rounded,
            title: 'Remote and accessories page',
            subtitle: 'The TV\'s own page, for remote buttons and anything else',
            onSelect: () => openStockPage('bluetooth')),
      ]),
    );
  }
}

// ───────────────────────── picture ─────────────────────────

class _Mode {
  _Mode(this.w, this.h, this.hz);
  final int w;
  final int h;
  final double hz;
  factory _Mode.from(Map m) =>
      _Mode((m['w'] as num).toInt(), (m['h'] as num).toInt(), (m['hz'] as num).toDouble());
  String get res => h >= 2160 ? '4K' : (h >= 1080 ? '1080p' : (h >= 720 ? '720p' : '${h}p'));
  String get rate => '${hz.round() == hz ? hz.round() : hz.toStringAsFixed(2)} Hz';
  String get label => '$res · $rate';
  String get key => '${w}x${h}@${hz.toStringAsFixed(2)}';
}

const _timeouts = <int, String>{
  900000: '15 minutes',
  1800000: '30 minutes',
  3600000: '1 hour',
  14400000: '4 hours',
  -1: 'Never',
};

class DisplayScreen extends StatefulWidget {
  const DisplayScreen({super.key});
  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  List<_Mode> _modes = [];
  _Mode? _cur;
  List<int> _hdr = [];
  Map<String, dynamic> _i = {};
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await sysCall('displayModes');
    final i = await sysCall('info');
    if (!mounted) return;
    final seen = <String>{};
    final modes = <_Mode>[
      for (final m in (d['modes'] as List? ?? const []))
        if (seen.add(_Mode.from(m as Map).key)) _Mode.from(m)
    ]..sort((a, b) => b.h != a.h ? b.h.compareTo(a.h) : b.hz.compareTo(a.hz));
    setState(() {
      _modes = modes;
      _cur = d['current'] is Map ? _Mode.from(d['current'] as Map) : null;
      _hdr = [for (final x in (d['hdr'] as List? ?? const [])) (x as num).toInt()];
      _i = i;
    });
  }

  String get _hdrText {
    const names = {1: 'Dolby Vision', 2: 'HDR10', 3: 'HLG', 4: 'HDR10+'};
    final n = [for (final h in _hdr) if (names[h] != null) names[h]!];
    return n.isEmpty ? 'No HDR reported by the TV' : n.join(', ');
  }

  Future<void> _apply(_Mode? m) async {
    final before = _cur;
    final r = await adbOut([
      m == null
          ? 'cmd display clear-user-preferred-display-mode 0'
          // "0" = this screen. Without it Android 14 tries to save the choice as a system-wide
          // setting under the shell's identity and refuses its own write (SecurityException).
          : 'cmd display set-user-preferred-display-mode ${m.w} ${m.h} ${m.hz} 0'
    ]);
    if (!r.ok) return setState(() => _msg = r.error!);
    final printed = r.at(0).toLowerCase();
    if (printed.contains('unknown') || printed.contains('exception') || printed.contains('error')) {
      if (!mounted) return;
      final said = r.at(0).trim().split('\n').first;
      return showMenu2(context, 'Resolution', [
        MenuChoice('The TV didn\'t accept the change from Foyer.', null),
        if (said.isNotEmpty) MenuChoice('TV said: ${said.length > 140 ? '${said.substring(0, 140)}…' : said}', null),
        MenuChoice('Open display page', () => openStockPage('display')),
        MenuChoice('Cancel', () {}),
      ]);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await _load();
    if (m == null || !mounted) return;
    if (_cur != null && _cur!.key != m.key) {
      setState(() => _msg = 'The TV kept ${_cur!.label}. Your TV may not accept ${m.label} over this cable or input.');
      return;
    }
    final keep = await showDialog<bool>(
        context: context, barrierDismissible: false, builder: (_) => const _KeepDialog());
    if (keep != true) {
      await adbOut([
        before == null
            ? 'cmd display clear-user-preferred-display-mode 0'
            : 'cmd display set-user-preferred-display-mode ${before.w} ${before.h} ${before.hz} 0'
      ]);
      await Future<void>.delayed(const Duration(seconds: 3));
      await _load();
      if (mounted) setState(() => _msg = 'Went back to the old picture.');
    } else if (mounted) {
      setState(() => _msg = 'Picture set to ${m.label}.');
    }
  }

  /// The useful choices: 4K, 1080p and 720p at 60 and 50 Hz (59.94 only when 60 isn't there).
  /// Film rates like 24 Hz are left to the TV's "match frame rate".
  List<_Mode> get _menuModes {
    final out = <_Mode>[];
    for (final h in const [2160, 1080, 720]) {
      for (final target in const [60.0, 50.0]) {
        final near = _modes.where((m) => m.h == h && (m.hz - target).abs() < 0.2).toList();
        final alt = target == 60.0 ? _modes.where((m) => m.h == h && (m.hz - 59.94).abs() < 0.05).toList() : <_Mode>[];
        final pick = near.isNotEmpty ? near.first : (alt.isNotEmpty ? alt.first : null);
        if (pick != null) out.add(pick);
      }
    }
    return out.isEmpty ? _modes.take(8).toList() : out;
  }

  void _pickMode() => showMenu2(context, 'Resolution', [
        MenuChoice('Automatic (best for this TV)', () => _apply(null)),
        for (final m in _menuModes) MenuChoice(m.label + (m.key == _cur?.key ? '  ✓' : ''), () => _apply(m)),
        MenuChoice('Cancel', () {}),
      ]);

  Future<void> _setSleep(int ms) async {
    final r = await adbOut([
      'settings put system screen_off_timeout ${ms < 0 ? 2147483647 : ms}',
      'settings put secure sleep_timeout $ms',
      'settings put secure attentive_timeout $ms',
    ]);
    await _load();
    if (mounted) setState(() => _msg = r.ok ? 'Screen turns off: ${_timeouts[ms]}.' : r.error!);
  }

  Future<void> _ambient(bool on) async {
    final r = await adbOut(['settings put secure screensaver_enabled ${on ? 1 : 0}']);
    await _load();
    if (mounted && !r.ok) setState(() => _msg = r.error!);
  }

  String get _sleepText {
    final s = (_i['sleep'] as num?)?.toInt();
    final o = (_i['screenOff'] as num?)?.toInt();
    final v = (s != null && s != 0) ? s : o;
    if (v == null) return '';
    if (v < 0 || v >= 2147483647) return 'Never';
    return _timeouts[v] ?? '${(v / 60000).round()} min';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Picture and display',
      subtitle: _cur == null ? null : 'Right now: ${_cur!.label}   ·   $_hdrText',
      child: _list([
        if (_msg.isNotEmpty) _note(_msg),
        SysRow(
            icon: Icons.high_quality_rounded,
            title: 'Resolution and refresh rate',
            subtitle: 'Automatic picks the best your TV supports',
            value: _cur?.label ?? '',
            autofocus: true,
            onSelect: _modes.isEmpty ? () => openStockPage('display') : _pickMode),
        SysRow(
            icon: Icons.nightlight_round,
            title: 'Turn the screen off after',
            subtitle: 'When nothing is playing and no button is pressed',
            value: _sleepText,
            onSelect: () => showMenu2(context, 'Turn the screen off after', [
                  for (final e in _timeouts.entries) MenuChoice(e.value, () => _setSleep(e.key)),
                  MenuChoice('Cancel', () {}),
                ])),
        SysRow(
            icon: Icons.photo_library_rounded,
            title: 'Google\'s own screensaver',
            subtitle: 'Foyer has its own screensaver in Settings, so this can stay off',
            value: _i['screensaver'] == true ? 'On' : 'Off',
            chevron: false,
            onSelect: () => _ambient(_i['screensaver'] != true)),
        SysRow(
            icon: Icons.open_in_new_rounded,
            title: 'More picture options',
            subtitle: 'HDR format, colour, match frame rate (TV\'s own page)',
            onSelect: () => openStockPage('display')),
      ]),
    );
  }
}

/// "Keep this picture?" with a countdown, so a bad mode fixes itself.
class _KeepDialog extends StatefulWidget {
  const _KeepDialog();
  @override
  State<_KeepDialog> createState() => _KeepDialogState();
}

class _KeepDialogState extends State<_KeepDialog> {
  int _left = 15;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _t?.cancel();
        Navigator.of(context).pop(false);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Glass(
            radius: 40,
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Keep this picture?', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text('Going back in $_left seconds.', style: _body),
              const SizedBox(height: 28),
              Row(mainAxisSize: MainAxisSize.min, children: [
                PillButton(label: 'Go back', onSelect: () => Navigator.of(context).pop(false)),
                const SizedBox(width: 20),
                PillButton(label: 'Keep', primary: true, autofocus: true, onSelect: () => Navigator.of(context).pop(true)),
              ]),
            ]),
          ),
        ),
      );
}

// ───────────────────────── sound ─────────────────────────

class SoundScreen extends StatefulWidget {
  const SoundScreen({super.key});
  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen> {
  Map<String, dynamic> _v = {};
  bool? _clicks;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await sysCall('volume');
    final i = await sysCall('info');
    if (mounted) setState(() {
      _v = v;
      _clicks = i['soundEffects'] as bool?;
    });
  }

  Future<void> _step(bool up) async {
    final v = await sysCall('stepVolume', {'up': up});
    if (mounted) setState(() => _v = v);
  }

  Future<void> _mute() async {
    final v = await sysCall('mute', {'on': _v['muted'] != true});
    if (mounted) setState(() => _v = v);
  }

  Future<void> _toggleClicks() async {
    final r = await adbOut(['settings put system sound_effects_enabled ${_clicks == true ? 0 : 1}']);
    await _load();
    if (mounted && !r.ok) setState(() => _msg = r.error!);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = _v['fixed'] == true;
    final level = (_v['level'] as num?)?.toInt() ?? 0;
    final max = (_v['max'] as num?)?.toInt() ?? 0;
    final muted = _v['muted'] == true;
    return SettingsPage(
      title: 'Sound',
      child: _list([
        if (_msg.isNotEmpty) _note(_msg),
        if (fixed)
          _note('Your TV or soundbar controls the volume through HDMI. Use the volume buttons on the remote.')
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 24),
            child: Row(children: [
              PillButton(label: '−', autofocus: true, onSelect: () => _step(false)),
              const SizedBox(width: 24),
              SizedBox(
                width: 700,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : level / max,
                    minHeight: 26,
                    backgroundColor: Colors.white.withAlpha(30),
                    color: muted ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              PillButton(label: '+', onSelect: () => _step(true)),
              const SizedBox(width: 28),
              Text(muted ? 'Muted' : '$level / $max', style: _body),
            ]),
          ),
          SysRow(
              icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              title: 'Mute',
              value: muted ? 'On' : 'Off',
              chevron: false,
              onSelect: _mute),
        ],
        SysRow(
            icon: Icons.touch_app_rounded,
            title: 'Button sounds',
            subtitle: 'The little click when you move around',
            value: _clicks == null ? '' : (_clicks! ? 'On' : 'Off'),
            chevron: false,
            autofocus: fixed,
            onSelect: _toggleClicks),
        SysRow(
            icon: Icons.open_in_new_rounded,
            title: 'More sound options',
            subtitle: 'Surround sound, Dolby, audio output (TV\'s own page)',
            onSelect: () => openStockPage('sound')),
      ]),
    );
  }
}

// ───────────────────────── apps ─────────────────────────

class AppsManagerScreen extends StatefulWidget {
  const AppsManagerScreen({super.key});
  @override
  State<AppsManagerScreen> createState() => _AppsManagerScreenState();
}

class _AppsManagerScreenState extends State<AppsManagerScreen> {
  List<InstalledApp> _apps = [];
  List<String> _off = [];
  bool _loaded = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await fetchInstalledApps();
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final r = await adbOut(['pm list packages -d']);
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _off = [
        for (final l in r.at(0).split('\n'))
          if (l.trim().startsWith('package:')) l.trim().substring(8)
      ]..sort();
      _loaded = true;
    });
  }

  Future<void> _run(String done, List<String> cmds) async {
    final r = await adbOut(cmds);
    if (mounted) setState(() => _msg = r.ok ? done : r.error!);
    await _load();
  }

  void _menu(InstalledApp a) => showMenu2(context, a.label, [
        MenuChoice('Open', () => kChannel.invokeMethod('launch', {'package': a.package})),
        MenuChoice('Force close', () => _run('${a.label} was closed.', ['am force-stop ${a.package}'])),
        MenuChoice('Clear cache', () async {
          final r = await adbOut(['pm clear --cache-only ${a.package}']);
          final o = r.at(0).toLowerCase();
          if (!mounted) return;
          setState(() => _msg = !r.ok
              ? r.error!
              : (o.contains('success') ? 'Cleared the cache for ${a.label}.' : 'This TV can\'t clear one app\'s cache. Use Storage › Free up space.'));
        }),
        MenuChoice('Clear data…', () => clearAppData(context, a.package, a.label)),
        MenuChoice('Turn off', () => _run('${a.label} is off. Find it below to turn it back on.',
            ['am force-stop ${a.package}', 'pm disable-user --user 0 ${a.package}'])),
        MenuChoice('Uninstall', () => kChannel.invokeMethod('uninstall', {'package': a.package})),
        MenuChoice('Cancel', () {}),
      ]);

  @override
  Widget build(BuildContext context) => SettingsPage(
        title: 'Apps',
        subtitle: _loaded ? '${_apps.length} apps' : 'Loading…',
        child: _list([
          if (_msg.isNotEmpty) _note(_msg),
          for (var i = 0; i < _apps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: SysRow(
                  icon: Icons.apps_rounded,
                  title: _apps[i].label,
                  subtitle: _apps[i].package,
                  autofocus: i == 0,
                  onSelect: () => _menu(_apps[i])),
            ),
          if (_off.isNotEmpty) _heading('Turned off'),
          for (final p in _off)
            SysRow(
                icon: Icons.block_rounded,
                title: p,
                subtitle: 'Select to turn back on',
                onSelect: () => showMenu2(context, p, [
                      MenuChoice('Turn back on', () => _run('Turned $p back on.', ['pm enable $p'])),
                      MenuChoice('Cancel', () {}),
                    ])),
        ]),
      );
}

// ───────────────────────── storage ─────────────────────────

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic> _i = {};
  String _msg = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await sysCall('info');
    if (mounted) setState(() => _i = i);
  }

  Future<void> _free() async {
    if (_busy) return;
    final before = (_i['storageFree'] as num?) ?? 0;
    setState(() {
      _busy = true;
      _msg = 'Clearing app caches…';
    });
    final r = await adbOut(['pm trim-caches 1000G']);
    await _load();
    final after = (_i['storageFree'] as num?) ?? 0;
    if (mounted) setState(() {
      _busy = false;
      _msg = r.ok ? 'Done. Freed ${fmtBytes((after - before).clamp(0, 1e15))}. Apps keep you signed in.' : r.error!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final free = (_i['storageFree'] as num?) ?? 0;
    final total = (_i['storageTotal'] as num?) ?? 0;
    final ramF = (_i['ramFree'] as num?) ?? 0;
    final ramT = (_i['ramTotal'] as num?) ?? 0;
    return SettingsPage(
      title: 'Storage',
      child: _list([
        if (total > 0) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 10),
            child: Text('${fmtBytes(total - free)} used of ${fmtBytes(total)}', style: _body),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 30),
            child: SizedBox(
              width: 1300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                    value: (total - free) / total,
                    minHeight: 26,
                    backgroundColor: Colors.white.withAlpha(30),
                    color: Colors.white),
              ),
            ),
          ),
        ],
        if (_msg.isNotEmpty) _note(_msg),
        SysRow(
            icon: Icons.cleaning_services_rounded,
            title: _busy ? 'Working…' : 'Free up space',
            subtitle: 'Clears every app\'s temporary files. Nothing you saved is lost',
            autofocus: true,
            onSelect: _free),
        if (ramT > 0)
          SysRow(
              icon: Icons.memory_rounded,
              title: 'Memory',
              subtitle: 'Settings › Goodnight closes apps running in the background',
              value: '${fmtBytes(ramF)} free of ${fmtBytes(ramT)}',
              chevron: false,
              onSelect: () {}),
        SysRow(
            icon: Icons.apps_rounded,
            title: 'Remove apps',
            subtitle: 'Uninstall apps you don\'t use',
            onSelect: () => _go(context, const AppsManagerScreen())),
      ]),
    );
  }
}

// ───────────────────────── name and about ─────────────────────────

class AboutTvScreen extends StatefulWidget {
  const AboutTvScreen({super.key});
  @override
  State<AboutTvScreen> createState() => _AboutTvScreenState();
}

class _AboutTvScreenState extends State<AboutTvScreen> {
  Map<String, dynamic> _i = {};
  String _foyer = '';
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await sysCall('info');
    String v = '';
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('appVersion');
      v = '${m?['name'] ?? ''}';
    } catch (_) {}
    if (mounted) setState(() {
      _i = i;
      _foyer = v;
    });
  }

  Future<void> _rename() async {
    final n = await askText(context, 'Name this TV', '${_i['name'] ?? ''}', hint: 'Living room TV', maxLength: 30);
    if (n == null || n.isEmpty) return;
    final r = await adbOut([
      'settings put global device_name ${shq(n)}',
      'settings put secure bluetooth_name ${shq(n)}',
    ]);
    await _load();
    if (mounted) setState(() => _msg = r.ok ? 'Renamed. Phones and casting show "$n" (some after a restart).' : r.error!);
  }

  String _uptime() {
    final ms = (_i['uptime'] as num?)?.toInt() ?? 0;
    final h = ms ~/ 3600000;
    return h >= 24 ? '${h ~/ 24} days ${h % 24} h' : '$h h ${(ms ~/ 60000) % 60} min';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 0, 12),
        child: Row(children: [
          SizedBox(width: 360, child: Text(k, style: _body)),
          Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ips = [for (final x in (_i['ips'] as List? ?? const [])) '$x'];
    return SettingsPage(
      title: 'Name and about',
      child: _list([
        if (_msg.isNotEmpty) _note(_msg),
        SysRow(
            icon: Icons.edit_rounded,
            title: 'Name',
            subtitle: 'What phones see when casting or pairing',
            value: '${_i['name'] ?? ''}',
            autofocus: true,
            onSelect: _rename),
        const SizedBox(height: 10),
        _kv('Model', '${_i['maker'] ?? ''} ${_i['model'] ?? ''}'.trim()),
        _kv('Android', '${_i['android'] ?? ''}'),
        if ('${_i['security'] ?? ''}'.isNotEmpty) _kv('Security update', '${_i['security']}'),
        _kv('Foyer', _foyer),
        _kv('Address', ips.isEmpty ? 'Not connected' : ips.join(', ')),
        _kv('On for', _uptime()),
        const SizedBox(height: 10),
        SysRow(
            icon: Icons.system_update_alt_rounded,
            title: 'System update',
            subtitle: 'Check for an update to the TV itself (TV\'s own page)',
            onSelect: () => openStockPage('update')),
      ]),
    );
  }
}

// ───────────────────────── power ─────────────────────────

class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key});

  @override
  Widget build(BuildContext context) => SettingsPage(
        title: 'Power',
        child: _list([
          SysRow(
              icon: Icons.bedtime_rounded,
              title: 'Sleep now',
              subtitle: 'Turns the TV off too, if it supports HDMI control',
              autofocus: true,
              onSelect: () async {
                final r = await adbOut(['input keyevent KEYCODE_SLEEP']);
                if (!r.ok && context.mounted) showInfo(context, 'Could not sleep', r.error!);
              }),
          SysRow(
              icon: Icons.restart_alt_rounded,
              title: 'Restart',
              subtitle: 'Fixes most hiccups. Takes about a minute',
              onSelect: () => showMenu2(context, 'Restart the TV box?', [
                    MenuChoice('Restart now', () async {
                      final r = await adbOut(['reboot'], eofOk: true);
                      if (!r.ok && context.mounted) showInfo(context, 'Could not restart', r.error!);
                    }),
                    MenuChoice('Cancel', () {}),
                  ])),
        ]),
      );
}

// ───────────────────────── the rest ─────────────────────────

class MoreTvScreen extends StatelessWidget {
  const MoreTvScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String t, String s, String page, {bool first = false}) =>
        SysRow(icon: i, title: t, subtitle: s, autofocus: first, onSelect: () => openStockPage(page));
    return SettingsPage(
      title: 'More',
      subtitle: 'Google keeps these locked to its own pages. They open on top of Foyer; press Back to return.',
      child: _list([
        row(Icons.account_circle_rounded, 'Google account', 'Sign in, profiles, Play Store account', 'accounts',
            first: true),
        row(Icons.privacy_tip_rounded, 'Privacy', 'Location, usage data, ads personalization', 'privacy'),
        row(Icons.schedule_rounded, 'Date and time', 'Time zone and 24-hour clock', 'date'),
        row(Icons.language_rounded, 'Language', 'The TV\'s language', 'language'),
        row(Icons.keyboard_rounded, 'Keyboard', 'On-screen keyboard choice', 'keyboard'),
        row(Icons.accessibility_new_rounded, 'Accessibility', 'Captions, text size, screen reader', 'accessibility'),
        row(Icons.system_update_alt_rounded, 'System update', 'Updates to the TV itself', 'update'),
        row(Icons.settings_rounded, 'All TV settings', 'The full stock settings app', ''),
      ]),
    );
  }
}

// ───────────────────────── Google TV tune-up ─────────────────────────

class _Bloat {
  const _Bloat(this.pkg, this.name, this.what);
  final String pkg;
  final String name;
  final String what;
}

class _BloatGroup {
  const _BloatGroup(this.title, this.note, this.items);
  final String title;
  final String note;
  final List<_Bloat> items;
}

/// Based on the Google TV Streamer (kirkwood) and Chromecast with Google TV lists
/// from the CleanYourTV project. Only packages found on this TV are shown, and
/// everything is switched off (not removed), so each one can come back.
const List<_BloatGroup> _gtvGroups = [
  _BloatGroup('Ads, tracking and feedback', 'Safe to switch off.', [
    _Bloat('com.google.android.feedback', 'Google feedback', 'Sends reports and usage to Google'),
    _Bloat('com.android.tv.feedbackconsent', 'Feedback consent', 'Asks to share usage data'),
    _Bloat('com.google.android.tv.remotecontrol.logging', 'Remote logging', 'Logs how you use the remote'),
    _Bloat('com.google.android.apps.tv.netoscope', 'Network reporting', 'Sends network diagnostics'),
  ]),
  _BloatGroup('Ad personalization', 'Google\'s ad and learning services. If the Play Store or Assistant act up, turn these back on.', [
    _Bloat('com.google.android.adservices.api', 'Ad services', 'Privacy Sandbox ads'),
    _Bloat('com.google.android.ext.adservices.api', 'Ad services (extra)', 'Privacy Sandbox ads'),
    _Bloat('com.google.android.ondevicepersonalization.services', 'Ad personalization', 'Builds an ad profile on the TV'),
    _Bloat('com.google.android.federatedcompute', 'Federated learning', 'Trains Google models on your usage'),
  ]),
  _BloatGroup('Apps you might not use', 'Turn back on any time.', [
    _Bloat('com.google.android.play.games', 'Google Play Games', ''),
    _Bloat('com.google.android.videos', 'Google TV (movies store)', 'Needed only to watch movies you bought from Google'),
    _Bloat('com.google.android.marvin.talkback', 'TalkBack', 'Screen reader. Keep it if anyone needs it'),
    _Bloat('com.android.printspooler', 'Printing', 'Nobody prints from a TV'),
  ]),
];

/// Every package the Google TV tune-up can switch off (used by first-run setup).
List<String> get kGtvTuneUpPackages => [
      for (final g in _gtvGroups)
        for (final b in g.items) b.pkg
    ];

/// Never touched: things that break casting, the mic, the Play Store or the screensaver.
const Map<String, String> _gtvKeep = {
  'com.google.android.apps.mediashell': 'Casting from your phone',
  'com.google.android.katniss': 'Google Assistant (mic button)',
  'com.google.android.tv.remote.service': 'The remote\'s microphone',
  'com.android.vending': 'Play Store and app updates',
  'com.google.android.gms': 'Google Play services (sign-in, Netflix, Prime)',
  'com.google.android.apps.tv.dreamx': 'Google screensaver and Google Home panel',
};

class GoogleTuneUpScreen extends StatefulWidget {
  const GoogleTuneUpScreen({super.key});
  @override
  State<GoogleTuneUpScreen> createState() => _GoogleTuneUpScreenState();
}

class _GoogleTuneUpScreenState extends State<GoogleTuneUpScreen> {
  /// package -> 1 on, 2 off. Missing = not on this TV.
  Map<String, int> _state = {};
  bool _busy = false;
  bool _scanned = false;
  String _msg = '';
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final r = await adbOut(['pm list packages', 'pm list packages -d']);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _msg = r.error!;
        _scanned = true;
      });
      return;
    }
    Set<String> parse(String o) => {
          for (final l in o.split('\n'))
            if (l.trim().startsWith('package:')) l.trim().substring(8)
        };
    final all = parse(r.at(0));
    final off = parse(r.at(1));
    setState(() {
      _state = {for (final p in all) p: off.contains(p) ? 2 : 1};
      _scanned = true;
    });
  }

  List<_Bloat> _present(_BloatGroup g) => [for (final b in g.items) if (_state.containsKey(b.pkg)) b];

  Future<void> _run(String title, List<String> cmds) async {
    if (_busy || cmds.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = '$title…';
    });
    final r = await adbOut(cmds);
    for (var i = 0; i < cmds.length; i++) {
      final o = r.at(i).trim();
      _log.add('${cmds[i]}${o.isEmpty ? '' : '  →  ${o.split('\n').first}'}');
    }
    await _scan();
    if (mounted) setState(() {
      _busy = false;
      _msg = r.ok ? '$title: done.' : r.error!;
    });
  }

  String _off(String p) => 'pm disable-user --user 0 $p';
  String _on(String p) => 'pm enable $p';

  void _itemMenu(_Bloat b) {
    final off = _state[b.pkg] == 2;
    showMenu2(context, b.name, [
      if (b.what.isNotEmpty) MenuChoice(b.what, null),
      off
          ? MenuChoice('Turn back on', () => _run('Turning ${b.name} back on', [_on(b.pkg)]))
          : MenuChoice('Switch off', () => _run('Switching off ${b.name}', [_off(b.pkg)])),
      MenuChoice('Cancel', () {}),
    ]);
  }

  void _groupMenu(_BloatGroup g) {
    final items = _present(g);
    final anyOn = items.any((b) => _state[b.pkg] == 1);
    final anyOff = items.any((b) => _state[b.pkg] == 2);
    showMenu2(context, g.title, [
      MenuChoice(g.note, null),
      if (anyOn)
        MenuChoice('Switch all off', () => _run('Switching off ${g.title.toLowerCase()}',
            [for (final b in items) if (_state[b.pkg] == 1) _off(b.pkg)])),
      if (anyOff)
        MenuChoice('Turn all back on', () => _run('Turning ${g.title.toLowerCase()} back on',
            [for (final b in items) if (_state[b.pkg] == 2) _on(b.pkg)])),
      MenuChoice('Cancel', () {}),
    ]);
  }

  void _undoAll() {
    final cmds = [
      for (final g in _gtvGroups)
        for (final b in g.items)
          if (_state[b.pkg] == 2) _on(b.pkg)
    ];
    if (cmds.isEmpty) {
      setState(() => _msg = 'Nothing is switched off.');
      return;
    }
    showMenu2(context, 'Turn everything back on?', [
      MenuChoice('Everything this page switched off comes back, like a new TV.', null),
      MenuChoice('Turn all back on', () => _run('Turning everything back on', cmds)),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var first = true;
    for (final g in _gtvGroups) {
      final items = _present(g);
      if (items.isEmpty) continue;
      final off = items.where((b) => _state[b.pkg] == 2).length;
      rows.add(SysRow(
          icon: Icons.cleaning_services_rounded,
          title: g.title,
          subtitle: g.note,
          value: off == items.length ? 'All off' : (off == 0 ? 'On' : '$off of ${items.length} off'),
          autofocus: first,
          onSelect: () => _groupMenu(g)));
      first = false;
      for (final b in items) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 60),
          child: SysRow(
              icon: _state[b.pkg] == 2 ? Icons.block_rounded : Icons.circle_outlined,
              title: b.name,
              subtitle: b.what.isEmpty ? b.pkg : b.what,
              value: _state[b.pkg] == 2 ? 'Off' : 'On',
              chevron: false,
              onSelect: () => _itemMenu(b)),
        ));
      }
    }
    final home = _state['com.google.android.apps.tv.launcherx'];
    return SettingsPage(
      title: 'Tune-up',
      subtitle: 'Switch off Google\'s ads, tracking and apps you don\'t use. Nothing is deleted; every item can come back.',
      actions: [PillButton(label: 'Turn everything back on', onSelect: _undoAll)],
      child: _list([
        if (_msg.isNotEmpty) _note(_msg),
        if (!_scanned) _note('Checking what\'s on this TV…'),
        if (home != null)
          _note(home == 2
              ? 'Google\'s home screen and its ads are already off: Foyer is the home screen.'
              : 'Google\'s home screen (where most ads live) is still on. Switch it off in TV tools › Home button.',
              color: home == 2 ? _good : Colors.white70),
        ...rows,
        if (_scanned) ...[
          _heading('Foyer leaves these alone'),
          for (final e in _gtvKeep.entries)
            if (_state.containsKey(e.key)) _note('•  ${e.value}', color: Colors.white54),
          _note(
              'Casting says "untrusted device"? That\'s Google\'s setup app, which has to stay off while Foyer is the home screen on the Streamer. Switching Foyer off in TV tools › Home button brings it back.',
              color: Colors.white54),
        ],
        if (_log.isNotEmpty) ...[
          _heading('What changed'),
          for (final l in _log.reversed.take(12))
            _note(l, color: Colors.white38),
        ],
      ]),
    );
  }
}

// Add a game controller over Bluetooth (PS5 DualSense, PS4, Xbox, Switch Pro, 8BitDo):
// pick the kind, Foyer says which buttons to hold, searches, and pairs the controller
// the moment it shows up. No codes, nothing else to press.
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'screens.dart';
import 'system.dart';

class _Pad {
  const _Pad(this.id, this.name, this.how, this.names, this.icon);
  final String id;
  final String name;
  final String how; // how to put it in pairing mode
  final List<String> names; // what it calls itself over Bluetooth
  final IconData icon;
}

const List<_Pad> _pads = [
  _Pad('ps5', 'PlayStation 5 (DualSense)',
      'Hold the Create button (the small one left of the touchpad) and the PS button together for about 3 seconds, until the light around the touchpad blinks quickly.',
      ['dualsense', 'wireless controller'], Icons.sports_esports_rounded),
  _Pad('ps4', 'PlayStation 4 (DualShock 4)',
      'Hold the Share button and the PS button together for about 3 seconds, until the light bar flashes quickly.',
      ['wireless controller', 'dualshock'], Icons.sports_esports_rounded),
  _Pad('xbox', 'Xbox (Series X|S, One)',
      'Turn it on with the Xbox button, then hold the small pair button on top for 3 seconds, until the Xbox button flashes quickly.',
      ['xbox'], Icons.sports_esports_rounded),
  _Pad('switch', 'Nintendo Switch Pro',
      'Hold the small sync button on top, next to the charging port, until the lights along the bottom run back and forth.',
      ['pro controller'], Icons.sports_esports_rounded),
  _Pad('other', 'Another controller (8BitDo and others)',
      'Put it in Bluetooth pairing mode (check its manual: often Start + a mode button, or a pair button on top).',
      ['8bitdo', 'controller', 'gamepad', 'pad', 'joy'], Icons.videogame_asset_rounded),
];

class ControllerPairScreen extends StatefulWidget {
  const ControllerPairScreen({super.key});
  @override
  State<ControllerPairScreen> createState() => _ControllerPairScreenState();
}

class _ControllerPairScreenState extends State<ControllerPairScreen> {
  _Pad? _pad;
  final Map<String, Map> _found = {};
  String _status = '';
  String _pairing = '';
  bool _done = false;
  Timer? _again;
  DateTime _until = DateTime(2000);

  @override
  void initState() {
    super.initState();
    kSystem.setMethodCallHandler(_onEvent);
  }

  @override
  void dispose() {
    _again?.cancel();
    kSystem.setMethodCallHandler(null);
    kSystem.invokeMethod('btStop').catchError((_) => null);
    super.dispose();
  }

  bool _isPad(Map d) {
    final n = '${d['name']}'.toLowerCase();
    final p = _pad;
    if (p == null) return false;
    if (p.names.any(n.contains)) return true;
    return p.id == 'other' && d['kind'] == 'input';
  }

  Future<dynamic> _onEvent(MethodCall call) async {
    if (!mounted) return null;
    final m = call.arguments is Map ? call.arguments as Map : const {};
    final addr = '${m['address']}';
    if (call.method == 'btFound') {
      if (m['paired'] == true || _done) return null;
      setState(() => _found[addr] = m);
      // the controller we're waiting for: pair it straight away
      if (_pairing.isEmpty && _isPad(m)) _pair(m);
    } else if (call.method == 'btBond') {
      final bond = m['bond'];
      if (bond == 12 && addr == _pairing) {
        _again?.cancel();
        kSystem.invokeMethod('btStop').catchError((_) => null);
        setState(() {
          _done = true;
          _status = '${m['name']} is connected. It works in Foyer and in your games. '
              'Next time, just press its PS (or home) button to wake it.';
        });
      } else if (bond == 10 && addr == _pairing) {
        setState(() {
          _pairing = '';
          _status = 'That didn\'t pair. Put the controller in pairing mode again; Foyer keeps looking.';
        });
      }
    } else if (call.method == 'btDone') {
      // keep searching for two minutes (one search lasts about 12 seconds)
      if (!_done && DateTime.now().isBefore(_until)) {
        _again?.cancel();
        _again = Timer(const Duration(milliseconds: 500), _scanOnce);
      } else if (!_done && mounted) {
        setState(() => _status = 'No controller showed up. Check it\'s in pairing mode (fast blinking), then search again.');
      }
    }
    return null;
  }

  Future<void> _pair(Map d) async {
    final addr = '${d['address']}';
    setState(() {
      _pairing = addr;
      _status = 'Found ${d['name']}. Pairing…';
    });
    final ok = (await kSystem.invokeMethod<bool>('btPair', {'address': addr}).catchError((_) => false)) ?? false;
    if (!ok && mounted) {
      setState(() {
        _pairing = '';
        _status = 'Couldn\'t pair with ${d['name']}. Try putting it in pairing mode again.';
      });
    }
  }

  Future<void> _scanOnce() async {
    await kSystem.invokeMethod<bool>('btScan').catchError((_) => false);
  }

  Future<void> _start(_Pad p) async {
    // Bluetooth must be on, and Foyer allowed to use it (given once over the debugging link)
    var s = await sysCall('btState');
    if (s['allowed'] == false) {
      await adbOut([
        'pm grant com.leclair.leclair_home android.permission.BLUETOOTH_SCAN',
        'pm grant com.leclair.leclair_home android.permission.BLUETOOTH_CONNECT',
      ]);
      s = await sysCall('btState');
    }
    if (s['on'] != true) {
      await adbOut(['cmd bluetooth_manager enable || svc bluetooth enable']);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    setState(() {
      _pad = p;
      _done = false;
      _pairing = '';
      _found.clear();
      _status = 'Searching… ${p.how}';
    });
    _until = DateTime.now().add(const Duration(minutes: 2));
    await _scanOnce();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pad;
    return SettingsPage(
      title: 'Add a controller',
      subtitle: p == null
          ? 'Which controller is it? Foyer shows you which buttons to hold, then pairs it by itself.'
          : p.name,
      actions: [
        if (p != null && !_done) PillButton(label: 'Search again', onSelect: () => _start(p)),
        if (p != null) PillButton(label: 'Another kind', onSelect: () => setState(() => _pad = null)),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p == null)
            for (var i = 0; i < _pads.length; i++)
              SettingRow(
                autofocus: i == 0,
                entry: HubEntry(_pads[i].icon, _pads[i].name, '', () => _start(_pads[i])),
              )
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_done ? Icons.check_circle_rounded : Icons.bluetooth_searching_rounded,
                  size: 64, color: _done ? const Color(0xFF8CE99A) : Colors.white),
              const SizedBox(width: 24),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!_done)
                    Text(p.how, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.35)),
                  const SizedBox(height: 16),
                  Text(_status, style: const TextStyle(fontSize: 26, color: Colors.white70, height: 1.35)),
                ]),
              ),
            ]),
            if (!_done && _found.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Text('Nearby (select one to pair it yourself)',
                  style: TextStyle(fontSize: 24, color: Colors.white54)),
              const SizedBox(height: 12),
              for (final d in _found.values)
                SettingRow(
                  entry: HubEntry(
                    _isPad(d) ? Icons.sports_esports_rounded : Icons.bluetooth_rounded,
                    '${d['name']}',
                    '${d['address']}' == _pairing ? 'Pairing…' : '',
                    () => _pair(d),
                  ),
                ),
            ],
            if (_done) ...[
              const SizedBox(height: 30),
              PillButton(label: 'Done', autofocus: true, onSelect: () => Navigator.of(context).pop()),
            ],
          ],
        ]),
      ),
    );
  }
}

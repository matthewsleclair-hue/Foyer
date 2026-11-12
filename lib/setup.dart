// First-run setup (Foyer 2.0): a guided flow a friend can finish with just the remote.
//   Welcome > Home screen (takeover + tune-up + remote helper, as one checklist) >
//   Wi-Fi (only if offline) > About your home > Make it yours > Your apps > Extras > Done.
// Every choice is saved as it's made. Settings can still open each part on its own.
import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';
import 'remote.dart';
import 'screens.dart';
import 'seasons.dart';
import 'server.dart';
import 'sounds.dart';
import 'system.dart';

enum _Step { welcome, home, wifi, about, look, apps, extras, done }

const Map<_Step, String> _railNames = {
  _Step.welcome: 'Welcome',
  _Step.home: 'Home screen',
  _Step.wifi: 'Wi-Fi',
  _Step.about: 'About your home',
  _Step.look: 'Make it yours',
  _Step.apps: 'Your apps',
  _Step.extras: 'Extras',
  _Step.done: 'All set',
};

const _body = TextStyle(fontSize: 28, color: Colors.white70);
const _small = TextStyle(fontSize: 23, color: Colors.white54);
const _good = Color(0xFF8CE99A);
const _bad = Color(0xFFFFB4A9);

class FirstRunSetup extends StatefulWidget {
  const FirstRunSetup({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<FirstRunSetup> createState() => _FirstRunSetupState();
}

class _FirstRunSetupState extends State<FirstRunSetup> {
  _Step _step = _Step.welcome;
  final Set<_Step> _done = {};

  // home screen checklist
  bool _devOptions = false;
  bool _adbOn = false;
  bool _isHome = false;
  bool _helper = false;
  bool _tunedUp = false;
  bool _busy = false;
  String _homeMsg = '';
  Color _homeMsgColor = Colors.white70;
  Timer? _poll;

  // wi-fi
  String _link = '';
  bool _wifiChecked = false;

  // apps
  List<InstalledApp> _installed = const [];
  bool _appsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // ── moving between steps ──

  List<_Step> get _steps => [
        _Step.welcome,
        _Step.home,
        // Wi-Fi only shows up when the box is offline (the takeover can drop it)
        if (!_wifiChecked || _link == 'none' || _step == _Step.wifi) _Step.wifi,
        _Step.about,
        _Step.look,
        _Step.apps,
        _Step.extras,
        _Step.done,
      ];

  Future<void> _go(_Step s) async {
    _poll?.cancel();
    if (s == _Step.wifi) {
      await _checkLink();
      // online: nothing to do here
      if (_link != 'none') {
        _wifiChecked = true;
        return _go(_Step.about);
      }
    }
    if (!mounted) return;
    setState(() => _step = s);
    if (s == _Step.home) _startHomePoll();
  }

  void _next() {
    _done.add(_step);
    final all = _Step.values;
    final i = all.indexOf(_step);
    if (i < all.length - 1) _go(all[i + 1]);
  }

  void _back() {
    final all = _Step.values;
    var i = all.indexOf(_step) - 1;
    // skip Wi-Fi going back when it wasn't needed
    if (i >= 0 && all[i] == _Step.wifi && _link != 'none') i--;
    if (i >= 0) _go(all[i]);
  }

  void _finish() {
    final s = SettingsScope.read(context);
    s.change(() => s.setupDone = true);
    widget.onDone();
  }

  // ── home screen step ──

  void _startHomePoll() {
    _refreshHome();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshHome());
  }

  Future<void> _refreshHome() async {
    final i = await sysCall('info');
    final home = await loadDevice();
    bool helper = false;
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('homeKeyStatus');
      helper = m?['enabled'] == true;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _devOptions = i['devOptions'] == true;
      _adbOn = i['adbOn'] == true;
      _isHome = home;
      _helper = helper;
    });
  }

  Future<void> _openTv(String page) async {
    try {
      await kChannel.invokeMethod<bool>('openSettings', {'page': page});
    } catch (_) {}
  }

  /// One press does all the technical setup on Google TV.
  Future<void> _takeOver() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _homeMsg = 'Working… If the TV asks to allow debugging, tick "Always allow" and choose Allow.';
      _homeMsgColor = Colors.white70;
    });
    const me = 'com.leclair.leclair_home';
    final err = await adbQuick([
      'pm grant $me android.permission.WRITE_SECURE_SETTINGS',
      'appops set $me ACCESS_RESTRICTED_SETTINGS allow',
      'pm grant $me android.permission.BLUETOOTH_SCAN',
      'pm grant $me android.permission.BLUETOOTH_CONNECT',
      // Google's home and setup app (the setup app can grab Home once Google's home is off)
      'pm disable-user --user 0 com.google.android.apps.tv.launcherx',
      'pm disable-user --user 0 com.google.android.tungsten.setupwraith',
      'cmd package set-home-activity $me/.MainActivity',
      // tune-up: ads, tracking and extras (each one can come back in Settings)
      for (final p in kGtvTuneUpPackages) 'pm disable-user --user 0 $p',
    ]);
    if (err == null) {
      try {
        await kChannel.invokeMethod<bool>('setHomeKey', {'enabled': true});
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await _refreshHome();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) {
        _homeMsg = err;
        _homeMsgColor = _bad;
      } else {
        _tunedUp = true;
        _homeMsg = _isHome
            ? 'All done. The Home button now opens Foyer, and Google\'s ads are off.'
            : 'Almost there. Press Home on the remote; if the TV asks which home app to use, pick Foyer and Always.';
        _homeMsgColor = _isHome ? _good : Colors.white70;
      }
    });
  }

  Future<void> _fireHelper() async {
    bool ok = false;
    try {
      ok = (await kChannel.invokeMethod<bool>('setHomeKey', {'enabled': true})) ?? false;
    } catch (_) {}
    await _refreshHome();
    if (mounted && !ok) {
      setState(() {
        _homeMsg = 'Foyer needs a one-time permission from a computer first. See the guide: '
            'adb shell pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS';
        _homeMsgColor = _bad;
      });
    }
  }

  // ── wi-fi ──

  Future<void> _checkLink() async {
    final i = await sysCall('info');
    _link = '${i['link'] ?? ''}';
  }

  // ── apps ──

  Future<void> _loadApps() async {
    final apps = await fetchInstalledApps();
    if (!mounted) return;
    final s = SettingsScope.read(context);
    setState(() {
      _installed = apps;
      _appsLoaded = true;
    });
    if (s.pinned.isEmpty) {
      final have = apps.map((a) => a.package).toSet();
      s.setPinned(kSuggested.where(have.contains).take(kMaxPinned).toList());
    }
  }

  // ── layout ──

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.welcome) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          const Positioned.fill(child: RepaintBoundary(child: Backdrop(tint: kDefaultTint))),
          Padding(
            padding: const EdgeInsets.fromLTRB(90, 80, 120, 64),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_step != _Step.welcome) ...[
                SizedBox(width: 330, child: _rail()),
                const SizedBox(width: 60),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _footer(),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _rail() {
    final steps = _steps;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Foyer setup', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white54)),
      const SizedBox(height: 28),
      for (final s in steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s == _step ? Colors.white : (_done.contains(s) ? Colors.white24 : Colors.transparent),
                border: Border.all(color: s == _step ? Colors.white : Colors.white38, width: 2),
              ),
              child: _done.contains(s) && s != _step
                  ? const Icon(Icons.check_rounded, size: 22, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 18),
            Flexible(
              child: Text(_railNames[s]!,
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: s == _step ? FontWeight.w700 : FontWeight.w500,
                      color: s == _step ? Colors.white : (_done.contains(s) ? Colors.white70 : Colors.white38))),
            ),
          ]),
        ),
    ]);
  }

  Widget _footer() {
    final homeReady = _isHome || (kIsFireTv && _helper);
    final online = _link.isNotEmpty && _link != 'none';
    // Home screen and Wi-Fi can be skipped until they're done
    final skippable = (_step == _Step.home && !homeReady) || (_step == _Step.wifi && !online);
    Widget primary;
    if (_step == _Step.welcome) {
      primary = PillButton(
          key: const ValueKey('start'), label: 'Let\'s start', primary: true, autofocus: true, onSelect: _next);
    } else if (_step == _Step.done) {
      primary = PillButton(
          key: const ValueKey('finish'),
          label: 'Go to my home screen',
          primary: true,
          autofocus: true,
          onSelect: _finish);
    } else if (skippable) {
      primary = PillButton(key: ValueKey('skip$_step'), label: 'Skip for now', onSelect: _next);
    } else {
      primary = PillButton(
          key: ValueKey('next$_step'),
          label: 'Next',
          primary: true,
          autofocus: (_step == _Step.home && homeReady) || (_step == _Step.wifi && online),
          onSelect: _next);
    }
    return Row(children: [
      if (_step != _Step.welcome) PillButton(key: ValueKey('back$_step'), label: 'Back', onSelect: _back),
      const Spacer(),
      if (_step == _Step.apps)
        Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Text('${SettingsScope.of(context).pinned.length} of $kMaxPinned picked', style: _body),
        ),
      primary,
    ]);
  }

  Widget _title(String t, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700, letterSpacing: -1)),
        const SizedBox(height: 10),
        SizedBox(width: 1150, child: Text(sub, style: _body)),
        const SizedBox(height: 34),
      ]);

  Widget _stepBody() {
    switch (_step) {
      case _Step.welcome:
        return _welcome();
      case _Step.home:
        return kIsFireTv ? _fireHome() : _googleHome();
      case _Step.wifi:
        return _wifi();
      case _Step.about:
        return _about();
      case _Step.look:
        return _look();
      case _Step.apps:
        return _apps();
      case _Step.extras:
        return _extras();
      case _Step.done:
        return _allSet();
    }
  }

  // ── 1. welcome ──

  Widget _welcome() {
    final device = kIsFireTv
        ? 'Fire TV'
        : (kDeviceModel.isEmpty ? 'Google TV' : kDeviceModel);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4C6EF5), Color(0xFF9C36B5)]),
          ),
          child: const Icon(Icons.door_front_door_rounded, size: 92, color: Color(0xFFFFE8CC)),
        ),
        const SizedBox(height: 40),
        const Text('Welcome to Foyer',
            style: TextStyle(fontSize: 84, fontWeight: FontWeight.w700, letterSpacing: -1.5)),
        const SizedBox(height: 16),
        const Text('A calm, ad-free home screen for your TV. Setup takes about 5 minutes.', style: _body),
        const SizedBox(height: 12),
        Text('Setting up: $device', style: _small),
      ]),
    );
  }

  // ── 2. home screen ──

  Widget _check(bool ok, String title, String sub, {bool busy = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? _good : Colors.transparent,
              border: Border.all(color: ok ? _good : Colors.white38, width: 2.5),
            ),
            child: ok
                ? const Icon(Icons.check_rounded, size: 32, color: Colors.black)
                : (busy
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : null),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w700, color: ok ? Colors.white : Colors.white)),
              if (sub.isNotEmpty) Text(sub, style: _small),
            ]),
          ),
        ]),
      );

  Widget _googleHome() {
    final needDev = !_devOptions;
    final needAdb = _devOptions && !_adbOn;
    final ready = _adbOn && !_isHome;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Make Foyer your home screen',
            'This switches off Google\'s home screen and its ads, so the Home button always opens Foyer. '
                'Each line ticks itself off as you go.'),
        _check(_devOptions, 'Developer options on',
            needDev ? 'Open About, then press "Android TV OS build" 7 times until it says you\'re a developer.' : ''),
        _check(_adbOn, 'Debugging on', needAdb ? 'Open Developer options and turn on USB debugging.' : ''),
        _check(_isHome, 'Foyer is the home screen',
            ready ? 'Press the button below. When the TV asks, tick "Always allow" and choose Allow.' : '',
            busy: _busy),
        _check(_tunedUp || _isHome, 'Google\'s ads and tracking off', '', busy: _busy),
        _check(_helper, 'Remote helper on', 'For the star, YouTube and Netflix buttons and the sleep timer',
            busy: _busy),
        const SizedBox(height: 16),
        Wrap(spacing: 18, runSpacing: 18, children: [
          if (needDev) PillButton(label: 'Open About', primary: true, autofocus: true, onSelect: () => _openTv('about')),
          if (needAdb)
            PillButton(
                label: 'Open Developer options', primary: true, autofocus: true, onSelect: () => _openTv('developer')),
          if (!needDev && !needAdb && !(_isHome && _helper))
            PillButton(
                label: _busy ? 'Working…' : 'Make Foyer the home screen',
                primary: true,
                autofocus: true,
                onSelect: _takeOver),
        ]),
        if (_homeMsg.isNotEmpty) ...[
          const SizedBox(height: 22),
          SizedBox(width: 1150, child: Text(_homeMsg, style: _body.copyWith(color: _homeMsgColor))),
        ],
        const SizedBox(height: 26),
        const SizedBox(
          width: 1150,
          child: Text(
              'After this the TV may forget its Wi-Fi once. That\'s normal: the next step lets you pick it again.',
              style: _small),
        ),
      ]),
    );
  }

  Widget _fireHome() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Keep Foyer in front',
            'Amazon doesn\'t allow its home screen to be switched off. Foyer\'s helper catches the Home button '
                'and brings Foyer back instead. Double-press Home for Amazon\'s home when you want it.'),
        _check(_helper, 'Home button helper on', ''),
        const SizedBox(height: 16),
        if (!_helper) PillButton(label: 'Turn on the helper', primary: true, autofocus: true, onSelect: _fireHelper),
        if (_homeMsg.isNotEmpty) ...[
          const SizedBox(height: 22),
          SizedBox(width: 1150, child: Text(_homeMsg, style: _body.copyWith(color: _homeMsgColor))),
        ],
      ]),
    );
  }

  // ── 3. wi-fi ──

  Widget _wifi() {
    final online = _link.isNotEmpty && _link != 'none';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(online ? 'You\'re online' : 'Connect to Wi-Fi',
          online ? 'All good. Choose Next.' : 'The TV isn\'t connected to the internet right now. Pick your network.'),
      if (!online)
        PillButton(
            label: 'Choose a Wi-Fi network',
            primary: true,
            autofocus: true,
            onSelect: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WifiScreen()));
              await _checkLink();
              if (mounted) setState(() {});
            }),
      if (online) const Icon(Icons.wifi_rounded, size: 90, color: _good),
    ]);
  }

  // ── 4. about your home ──

  Widget _about() {
    final s = SettingsScope.of(context);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('About your home', 'Shown in the greeting on your home screen.'),
        Wrap(spacing: 18, runSpacing: 18, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _BigField(
              value: s.name,
              autofocus: true,
              onSelect: () async {
                final v = await askText(context, 'Name your home', s.name, hint: 'Home', maxLength: 24);
                if (v != null && v.isNotEmpty) s.change(() => s.name = v);
              }),
          for (final n in kNameIdeas)
            if (n != s.name) Opt(label: n, selected: false, onSelect: () => s.change(() => s.name = n)),
        ]),
        const SizedBox(height: 34),
        const Text('Clock', style: _small),
        const SizedBox(height: 12),
        Wrap(spacing: 18, children: [
          Opt(label: '12-hour  (8:30)', selected: !s.clock24, onSelect: () => s.change(() => s.clock24 = false)),
          Opt(label: '24-hour  (20:30)', selected: s.clock24, onSelect: () => s.change(() => s.clock24 = true)),
        ]),
        const SizedBox(height: 34),
        const Text('Weather', style: _small),
        const SizedBox(height: 12),
        Opt(
            label: s.weatherCity.isEmpty ? 'Choose your city' : s.weatherCity,
            selected: s.weatherCity.isNotEmpty,
            onSelect: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeatherScreen()))),
      ]),
    );
  }

  // ── 5. make it yours ──

  Widget _look() {
    final s = SettingsScope.of(context);
    Widget row(String label, List<Widget> opts) => Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _small),
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 16, children: opts),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Make it yours', 'The preview on the right changes as you choose.'),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                row('Glass', [
                  Opt(
                      label: 'Simple',
                      selected: !s.liquid,
                      autofocus: true,
                      onSelect: () => s.change(() => s.liquid = false)),
                  Opt(label: 'Liquid', selected: s.liquid, onSelect: () => s.change(() => s.liquid = true)),
                ]),
                row('Wallpaper', [
                  Opt(
                      label: 'Follows the app',
                      selected: s.wallMode == 'glow',
                      onSelect: () => s.change(() {
                            s.wallMode = 'glow';
                            s.wallValue = '';
                          })),
                  for (var i = 0; i < kWallPresets.length && i < 4; i++)
                    Opt(
                        label: kWallPresets[i].name,
                        color: kWallPresets[i].color,
                        selected: s.wallMode == 'preset' && s.wallValue == '$i',
                        onSelect: () => s.change(() {
                              s.wallMode = 'preset';
                              s.wallValue = '$i';
                            })),
                ]),
                row('Holiday themes', [
                  Opt(label: 'On', selected: s.seasonal, onSelect: () => s.change(() => s.seasonal = true)),
                  Opt(label: 'Off', selected: !s.seasonal, onSelect: () => s.change(() => s.seasonal = false)),
                ]),
                row('Sounds', [
                  for (var i = 0; i < kSoundNames.length; i++)
                    Opt(
                        label: kSoundNames[i],
                        selected: s.soundLevel == i,
                        onSelect: () {
                          s.change(() {
                            s.soundLevel = i;
                            kSoundLevel = i;
                          });
                          uiSound('select');
                        }),
                ]),
              ]),
            ),
          ),
          const SizedBox(width: 40),
          const _MiniHome(),
        ]),
      ),
    ]);
  }

  // ── 6. apps ──

  Widget _apps() {
    final s = SettingsScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Your apps', 'These sit along the bottom of your home screen. We picked the usual ones; change anything.'),
      Expanded(
        child: !_appsLoaded
            ? const Text('Looking for your apps…', style: _body)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 20, runSpacing: 20, children: [
                  for (var i = 0; i < _installed.length; i++)
                    Builder(builder: (_) {
                      final a = _installed[i];
                      final order = s.pinned.indexOf(a.package);
                      return AppChip(
                        app: a,
                        autofocus: i == 0,
                        selected: order >= 0,
                        badge: order >= 0
                            ? Text('${order + 1}',
                                style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w700))
                            : null,
                        onSelect: () {
                          if (order >= 0) {
                            s.setPinned(s.pinned.where((p) => p != a.package).toList());
                          } else if (s.pinned.length < kMaxPinned) {
                            s.setPinned([...s.pinned, a.package]);
                          }
                        },
                      );
                    }),
                ]),
              ),
      ),
    ]);
  }

  // ── 7. extras ──

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    if (mounted) setState(() {});
  }

  Widget _extras() {
    final s = SettingsScope.of(context);
    final teams = s.sportsTeams.length;
    final customKeys = s.remoteKeys.values.any((v) => v.isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Extras', 'All optional. Set up any now, or later in Settings.'),
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SysRow(
                icon: Icons.sports_hockey_rounded,
                title: 'Sports scores',
                autofocus: true,
                subtitle: 'Live scores and goal alerts for your teams: NHL, MLB, NBA, NFL, F1',
                value: teams > 0 ? '✓ $teams' : '',
                onSelect: () => _open(const SportsSettingsScreen())),
            SysRow(
                icon: Icons.cloud_sync_rounded,
                title: 'Foyer Drop',
                subtitle: 'Send photos, notes and drawings from your phone, and use it as a remote',
                value: s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty ? '✓ Linked' : '',
                onSelect: () => _open(const ServerScreen())),
            SysRow(
                icon: Icons.settings_remote_rounded,
                title: 'Remote buttons',
                subtitle: 'Choose what the star, YouTube and Netflix buttons open',
                value: customKeys ? '✓ Set' : '',
                onSelect: () => _open(const RemoteButtonsScreen())),
            if (!kIsFireTv && !_tunedUp && !_isHome)
              SysRow(
                  icon: Icons.cleaning_services_rounded,
                  title: 'Tune-up',
                  subtitle: 'Switch off Google\'s ads and tracking',
                  onSelect: () => _open(const GoogleTuneUpScreen())),
          ]),
        ),
      ),
    ]);
  }

  // ── 8. all set ──

  Widget _allSet() {
    final s = SettingsScope.of(context);
    Widget line(bool ok, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 34, color: ok ? _good : Colors.white38),
            const SizedBox(width: 16),
            Text(t, style: TextStyle(fontSize: 28, color: ok ? Colors.white : Colors.white54)),
          ]),
        );
    Widget tip(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Icon(i, size: 34, color: const Color(0xFFB8C4FF)),
            const SizedBox(width: 16),
            Text(t, style: _body),
          ]),
        );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('You\'re all set, ${s.name}', 'Here\'s what\'s ready. Everything can be changed later in Settings.'),
        line(_isHome || (kIsFireTv && _helper), 'Foyer is your home screen'),
        if (!kIsFireTv) line(_tunedUp || _isHome, 'Google\'s ads switched off'),
        line(_helper, 'Remote helper on'),
        line(s.pinned.isNotEmpty, '${s.pinned.length} apps on your home screen'),
        line(s.weatherCity.isNotEmpty, s.weatherCity.isEmpty ? 'Weather (not set)' : 'Weather for ${s.weatherCity}'),
        line(s.sportsTeams.isNotEmpty, s.sportsTeams.isEmpty ? 'Sports scores (none)' : 'Following ${s.sportsTeams.length} teams'),
        line(s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty, 'Foyer Drop'),
        const SizedBox(height: 26),
        const Text('Good to know', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        tip(Icons.nightlight_round, 'The moon button: Goodnight, or a sleep timer'),
        tip(Icons.star_rounded, 'The star button on your remote opens what you chose in Remote buttons'),
        tip(Icons.menu_rounded, 'The Menu button, or the gear in the corner, opens Settings'),
        tip(Icons.touch_app_rounded, 'Hold OK on an app to move it or remove it'),
      ]),
    );
  }
}

/// The name, shown big, with a pencil: select to type a new one.
class _BigField extends StatelessWidget {
  const _BigField({required this.value, required this.onSelect, this.autofocus = false});
  final String value;
  final VoidCallback onSelect;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 560,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: f ? Colors.white : Colors.white.withAlpha(24),
            border: Border.all(color: Colors.white.withAlpha(f ? 255 : 80), width: f ? 3 : 1.5),
          ),
          child: Row(children: [
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w600, color: f ? Colors.black : Colors.white)),
            ),
            Icon(Icons.edit_rounded, size: 36, color: f ? Colors.black54 : Colors.white54),
          ]),
        ),
      );
}

/// A small live copy of the home screen for "Make it yours".
class _MiniHome extends StatelessWidget {
  const _MiniHome();

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final season = activeSeason(s);
    final look = kSeasonLooks[season];
    final tiles = [
      const Color(0xFFE50914),
      const Color(0xFF00A8E1),
      const Color(0xFFFF0000),
      const Color(0xFFE5A00D),
      const Color(0xFF1C7ED6),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 720,
        height: 405,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white38, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 1920,
            height: 1080,
            child: Stack(children: [
              Positioned.fill(child: Wallpaper(tint: tiles[1])),
              Positioned.fill(child: SeasonLayer(season: season, light: true)),
              Positioned(
                left: 72,
                top: 44,
                child: Glass(
                  radius: 40,
                  child: Text(look?.greeting ?? 'Welcome to ${s.name}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
                ),
              ),
              Positioned(
                right: 72,
                top: 44,
                child: Glass(
                  radius: 40,
                  child: Text(s.clock24 ? '20:30' : '8:30',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
                ),
              ),
              Positioned(
                left: 96,
                bottom: 300,
                child: Glass(
                  radius: 48,
                  padding: const EdgeInsets.all(40),
                  child: const SizedBox(
                    width: 620,
                    height: 160,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Netflix', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text('Press OK to open', style: TextStyle(fontSize: 30, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: 300,
                right: 300,
                bottom: 70,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < tiles.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Glass(
                        radius: 34,
                        padding: const EdgeInsets.all(18),
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: tiles[i],
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text('Preview', style: _small),
    ]);
  }
}

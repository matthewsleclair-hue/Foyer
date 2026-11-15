import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'main.dart';
import 'games.dart';
import 'screens.dart';
import 'sync.dart';

/// Talks to your own Foyer Drop server (the Docker app in /server):
/// notes show on the home screen, photos can be used as the screensaver.

class DropNote {
  DropNote(this.id, this.text, this.from);
  final String id, text, from;
}

class DropApi {
  static String _clean(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String clean(String url) => _clean(url);

  static Future<dynamic> _get(String url, String token, String path) {
    if (token.isEmpty) throw const HttpException('not set up');
    return _send(url, path, token: token);
  }

  static Future<dynamic> _send(String url, String path,
      {String token = '', Object? post, int waitSeconds = 10}) async {
    final base = _clean(url);
    if (base.isEmpty) throw const HttpException('not set up');
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse('$base$path');
      final req = await (post == null ? c.getUrl(uri) : c.postUrl(uri)).timeout(const Duration(seconds: 8));
      if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
      if (post != null) {
        final bytes = utf8.encode(jsonEncode(post));
        req.headers.contentType = ContentType.json;
        req.contentLength = bytes.length; // a plain sized upload: some proxies dislike chunked ones
        req.add(bytes);
      }
      final res = await req.close().timeout(Duration(seconds: waitSeconds));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) throw const HttpException('unlinked');
      if (res.statusCode == 429) throw const HttpException('Too many tries. Wait a few minutes.');
      if (res.statusCode != 200) {
        // the server's own plain-English reason, when it gave one
        String? why;
        try {
          final d = jsonDecode(body);
          if (d is Map && d['detail'] is String) why = d['detail'] as String;
        } catch (_) {}
        throw HttpException(why ?? 'Server answered ${res.statusCode}');
      }
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }

  // ── search everything (see search.dart) ──
  static Future<List<Map<String, dynamic>>> search(String url, String token, String q, String lang,
      {String country = 'CA'}) async {
    final j = await _get(url, token,
        '/api/search?q=${Uri.encodeQueryComponent(q)}&lang=$lang&country=$country');
    final l = j is Map ? j['results'] : null;
    return [if (l is List) for (final x in l) if (x is Map) Map<String, dynamic>.from(x)];
  }

  // ── settings that follow you (see sync.dart) ──
  static Future<void> saveSettings(String url, String token, Map<String, dynamic> settings, String platform) =>
      _send(url, '/api/tv/settings',
          token: token, post: {'settings': settings, 'platform': platform}, waitSeconds: 20);

  static Future<List<Map<String, dynamic>>> settingsCopies(String url, String token) async {
    final j = await _get(url, token, '/api/tv/settings');
    final l = j is Map ? j['copies'] : null;
    return [if (l is List) for (final x in l) if (x is Map) Map<String, dynamic>.from(x)];
  }

  static Future<Map<String, dynamic>> settingsCopy(String url, String token, String id) async {
    final j = await _get(url, token, '/api/tv/settings/${Uri.encodeComponent(id)}');
    if (j is! Map || j['settings'] is! Map) throw const HttpException('No settings from that TV');
    return Map<String, dynamic>.from(j);
  }

  /// Returns null when fine, or a plain-English problem.
  static Future<String?> test(String url, String token) async {
    try {
      await _get(url, token, '/api/ping');
      return null;
    } on HttpException catch (e) {
      return e.message == 'unlinked'
          ? 'This TV is no longer linked. Link it again.'
          : 'Could not use that server: ${e.message}';
    } on TimeoutException {
      return 'The server did not answer. Check the address.';
    } catch (_) {
      return 'Could not reach the server. Check the address.';
    }
  }

  /// Asks the server for a short code to show on screen. Returns (code, secret).
  static Future<List<String>> linkStart(String url, String tvName, String device) async {
    final j = await _send(url, '/api/link/start', post: {'name': tvName, 'device': device});
    final code = j is Map ? '${j['code'] ?? ''}' : '';
    final secret = j is Map ? '${j['secret'] ?? ''}' : '';
    if (code.isEmpty || secret.isEmpty) throw const HttpException('That does not look like a Foyer Drop server.');
    return [code, secret];
  }

  /// 'waiting', 'expired', or the (token, account) once someone typed the code.
  static Future<List<String>> linkPoll(String url, String secret) async {
    final j = await _send(url, '/api/link/poll?secret=${Uri.encodeQueryComponent(secret)}');
    if (j is! Map) return ['waiting', '', ''];
    return ['${j['status'] ?? 'waiting'}', '${j['token'] ?? ''}', '${j['account'] ?? ''}'];
  }

  static Future<List<DropNote>> notes(String url, String token) async {
    final j = await _get(url, token, '/api/notes');
    final l = j is Map ? j['notes'] : null;
    final out = <DropNote>[];
    if (l is List) {
      for (final n in l) {
        if (n is Map && '${n['text'] ?? ''}'.isNotEmpty) {
          out.add(DropNote('${n['id']}', '${n['text']}', '${n['from'] ?? ''}'));
        }
      }
    }
    return out;
  }

  /// The newest drawing, or null.
  static Future<DropDrawing?> drawing(String url, String token) async {
    final j = await _get(url, token, '/api/drawings');
    final l = j is Map ? j['drawings'] : null;
    if (l is! List || l.isEmpty || l.first is! Map) return null;
    final d = l.first as Map;
    final id = '${d['id'] ?? ''}';
    if (id.isEmpty) return null;
    return DropDrawing(id, '${d['from'] ?? ''}', '${_clean(url)}/drawings/$id.png', token);
  }

  static Future<List<String>> photoUrls(String url, String token) async {
    final j = await _get(url, token, '/api/photos');
    final l = j is Map ? j['photos'] : null;
    final base = _clean(url);
    return l is List ? [for (final id in l) '$base/photos/$id.jpg'] : const [];
  }
}

class DropDrawing {
  DropDrawing(this.id, this.from, this.url, this.token);
  final String id, from, url, token;
}

class DropFeed {
  final ValueNotifier<List<DropNote>> notes = ValueNotifier(const []);
  final ValueNotifier<DropDrawing?> drawing = ValueNotifier(null);

  /// Changes whenever photos are added or removed, so the screensaver can reload.
  final ValueNotifier<String> photosStamp = ValueNotifier('');
  String _gamesStamp = '';

  /// Set by the home screen: runs "open this app" / "open this link" sent from the phone.
  void Function(String type, String value)? onCommand;

  /// Set by the home screen: the installed apps, so the phone page can list them.
  Future<List<Map<String, String>>> Function()? appsProvider;
  String _appsSentFor = '';
  DateTime? _appsSentAt;

  bool _appsBusy = false;
  bool _appsAgain = false;

  /// Sends the list of shown apps to the server now. One at a time, and always ends with the
  /// newest list, so an older send can never overwrite a newer one.
  /// Returns how many apps the phone page now shows, or a plain-English problem.
  Future<String> sendAppsNow() async {
    final p = appsProvider;
    if (p == null || _sig.isEmpty) return 'This TV is not linked yet.';
    if (_appsBusy) {
      _appsAgain = true;
      return '';
    }
    _appsBusy = true;
    var out = '';
    do {
      _appsAgain = false;
      final sig = _sig;
      try {
        final apps = await p();
        final j = await DropApi._send(_url, '/api/tv/apps',
            token: _token, post: {'apps': apps}, waitSeconds: 30);
        final n = j is Map && j['count'] is num ? (j['count'] as num).toInt() : apps.length;
        _appsSentFor = sig;
        _appsSentAt = DateTime.now();
        out = n == 1 ? 'The phone page now shows 1 app.' : 'The phone page now shows $n apps.';
      } on HttpException catch (e) {
        _appsSentFor = ''; // try again on the next check
        out = e.message == 'unlinked'
            ? 'This TV is no longer linked. Link it again.'
            : 'Could not update the phone page: ${e.message}';
      } on StateError catch (e) {
        _appsSentFor = '';
        out = 'Could not read this TV\'s app list (${e.message}). Try again in a moment.';
      } on TimeoutException {
        _appsSentFor = '';
        out = 'The server took too long to answer. Try again in a moment.';
      } catch (e) {
        _appsSentFor = '';
        // show the real reason so it can be fixed
        final why = '$e';
        out = 'Could not update the phone page: ${why.length > 160 ? why.substring(0, 160) : why}';
      }
    } while (_appsAgain);
    _appsBusy = false;
    return out;
  }

  Future<void> _sendApps(String url, String token, String sig) async {
    final fresh = _appsSentFor == sig &&
        _appsSentAt != null &&
        DateTime.now().difference(_appsSentAt!).inHours < 6;
    if (fresh || _appsBusy) return;
    await sendAppsNow();
  }
  DateTime? _last;
  String _sig = '';
  bool _busy = false;

  // Instant updates: one request stays open and the server answers it the moment something changes.
  bool _listening = false;
  bool _push = false; // true once the server has shown it supports this
  bool _noPush = false; // an older server: stick to regular checks
  int _v = 0;
  String _url = '', _token = '';
  DateTime _asked = DateTime.now();

  Future<void> _listen() async {
    if (_listening || _noPush) return;
    _listening = true;
    final sig = _sig;
    while (sig == _sig && _sig.isNotEmpty) {
      // stop when the home screen has not asked for a while (app in the background)
      if (DateTime.now().difference(_asked).inSeconds > 40) break;
      try {
        final j = await DropApi._send(_url, '/api/wait?v=$_v', token: _token, waitSeconds: 40);
        final v = j is Map && j['v'] is num ? (j['v'] as num).toInt() : 0;
        _push = true;
        if (v != _v) {
          final first = _v == 0;
          _v = v;
          if (!first && sig == _sig) await refresh(_url, _token, force: true);
        }
      } on HttpException catch (e) {
        if (e.message == 'Server answered 404') {
          _noPush = true;
          break;
        }
        _push = false;
        await Future<void>.delayed(const Duration(seconds: 5));
      } catch (_) {
        _push = false;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    _listening = false;
    _push = false;
  }

  bool _toldNative = false;

  /// The phone page's remote is handled natively (it has to work inside other apps too),
  /// so the native side needs to know which server this TV is linked to.
  void _tellNative(String url, String token) {
    _toldNative = true;
    kChannel
        .invokeMethod<bool>('dropConfig', {'url': url, 'token': token})
        .catchError((Object _) => false);
  }

  Future<void> refresh(String url, String token, {bool force = false}) async {
    _asked = DateTime.now();
    if (url.trim().isEmpty || token.isEmpty) {
      if (_sig.isNotEmpty || !_toldNative) _tellNative('', '');
      _sig = '';
      if (notes.value.isNotEmpty) notes.value = const [];
      if (drawing.value != null) drawing.value = null;
      return;
    }
    final sig = '$url|$token';
    final age = _last == null ? 9999 : DateTime.now().difference(_last!).inSeconds;
    if (sig != _sig) {
      _sig = sig;
      _url = url;
      _token = token;
      _v = 0;
      _noPush = false;
      force = true;
      _tellNative(DropApi.clean(url), token);
    }
    if (!_listening) _listen();
    // with instant updates working, the regular check is only a safety net
    if (_busy || !(force || age >= (_push ? 30 : 4))) return;
    _busy = true;
    _last = DateTime.now();
    try {
      List<DropNote> n;
      DropDrawing? d;
      try {
        final j = await DropApi._get(url, token, '/api/feed');
        n = [
          for (final x in (j['notes'] as List? ?? const []))
            if (x is Map && '${x['text'] ?? ''}'.isNotEmpty)
              DropNote('${x['id']}', '${x['text']}', '${x['from'] ?? ''}')
        ];
        final dj = j['drawing'];
        d = dj is Map && '${dj['id'] ?? ''}'.isNotEmpty
            ? DropDrawing('${dj['id']}', '${dj['from'] ?? ''}',
                '${DropApi.clean(url)}/drawings/${dj['id']}.png', token)
            : null;
        final ph = '${j['photos'] ?? ''}';
        if (ph != photosStamp.value) photosStamp.value = ph;
        // games sent from a phone: download them into the Games folder
        final gs = '${j['games'] ?? ''}';
        if (gs != _gamesStamp) {
          _gamesStamp = gs;
          if (gs.isNotEmpty) syncDropGames(DropApi.clean(url), token);
        }
        final cmds = j['commands'];
        if (cmds is List) {
          for (final c in cmds) {
            if (c is Map) onCommand?.call('${c['type']}', '${c['value']}');
          }
        }
        _sendApps(url, token, sig);
      } on HttpException catch (e) {
        if (e.message != 'Server answered 404') rethrow;
        // an older server without the quick feed
        n = await DropApi.notes(url, token);
        d = await DropApi.drawing(url, token);
      }
      final same = n.length == notes.value.length &&
          [for (var i = 0; i < n.length; i++) n[i].id == notes.value[i].id].every((x) => x);
      if (!same) notes.value = n;
      if (d?.id != drawing.value?.id) drawing.value = d;
    } on HttpException catch (e) {
      if (e.message == 'unlinked') {
        // the TV was unlinked from the web page
        notes.value = const [];
        drawing.value = null;
      }
    } catch (_) {
      // keep the last good ones
    }
    _busy = false;
  }
}

final DropFeed kDrop = DropFeed();

/// What sits on the home screen: the newest drawing next to the notes.
class DropCorner extends StatelessWidget {
  const DropCorner({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DropDrawing?>(
        valueListenable: kDrop.drawing,
        builder: (_, d, __) => ValueListenableBuilder<List<DropNote>>(
          valueListenable: kDrop.notes,
          builder: (_, n, __) => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (d != null) _DrawingCard(d: d),
                if (d != null && n.isNotEmpty) const SizedBox(width: 18),
                if (n.isNotEmpty) NotesCard(notes: n),
              ]),
        ),
      );
}

class _DrawingCard extends StatelessWidget {
  const _DrawingCard({required this.d});
  final DropDrawing d;
  @override
  Widget build(BuildContext context) => Glass(
        radius: 28,
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 352,
            height: 220,
            child: Image.network(d.url,
                key: ValueKey(d.id),
                headers: {'Authorization': 'Bearer ${d.token}'},
                fit: BoxFit.contain,
                cacheWidth: 704,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          if (d.from.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text('From ${d.from}', style: const TextStyle(fontSize: 20, color: Colors.white70)),
            ),
        ]),
      );
}

// ───────────────────────── notes card on Home ─────────────────────────

class NotesCard extends StatefulWidget {
  const NotesCard({super.key, required this.notes});
  final List<DropNote> notes;
  @override
  State<NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<NotesCard> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && widget.notes.length > 1) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notes.isEmpty) return const SizedBox.shrink();
    final n = widget.notes[_i % widget.notes.length];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Glass(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Column(
            key: ValueKey(n.id),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sticky_note_2_rounded, size: 26, color: Colors.white70),
                const SizedBox(width: 10),
                Text(n.from.isEmpty ? 'Note' : 'Note from ${n.from}',
                    style: const TextStyle(fontSize: 22, color: Colors.white70)),
              ]),
              const SizedBox(height: 8),
              Text(n.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── settings screen ─────────────────────────

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  String _msg = '';

  Future<bool> _askAddress() async {
    final s = SettingsScope.read(context);
    final v = await askText(context, 'Server address', s.serverUrl,
        hint: 'For example drop.example.com or 192.168.1.50:8080', maxLength: 200);
    if (v == null || v.trim().isEmpty) return false;
    if (v.trim() != s.serverUrl) {
      s.change(() {
        s.serverUrl = v.trim();
        s.serverToken = ''; // a different server needs a fresh link
      });
    }
    if (mounted) setState(() => _msg = '');
    return true;
  }

  Future<void> _link() async {
    final s = SettingsScope.read(context);
    if (s.serverUrl.trim().isEmpty && !await _askAddress()) return;
    if (!mounted) return;
    final account = await Navigator.of(context)
        .push(MaterialPageRoute<String>(builder: (_) => const LinkScreen()));
    if (!mounted || account == null) return;
    setState(() => _msg = 'Linked to $account. Notes and drawings will show on the home screen.');
    kDrop.refresh(s.serverUrl, s.serverToken, force: true);
    // another TV or PC in this household already set up? offer to set this one up the same way
    await offerSettingsCopy(context);
  }

  Future<void> _test() async {
    final s = SettingsScope.read(context);
    setState(() => _msg = 'Testing…');
    final r = await DropApi.test(s.serverUrl, s.serverToken);
    if (!mounted) return;
    setState(() => _msg = r ?? 'Connected and working.');
    if (r == null) kDrop.refresh(s.serverUrl, s.serverToken, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final linked = s.serverUrl.isNotEmpty && s.serverToken.isNotEmpty;
    return SettingsPage(
      title: 'Foyer Drop',
      subtitle:
          'Send notes, drawings and photos to this TV from any phone, and open apps from it.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PillButton(
              label: linked ? 'Linked. Link again' : 'Link this TV',
              primary: !linked,
              autofocus: true,
              onSelect: _link),
          const SizedBox(height: 20),
          PillButton(
              label: s.serverUrl.isEmpty ? 'Set server address' : 'Server: ${s.serverUrl}',
              onSelect: _askAddress),
          if (linked) ...[
            const SizedBox(height: 20),
            PillButton(
                label: s.dropHidden.isEmpty
                    ? 'Apps on the phone page: all'
                    : 'Apps on the phone page: ${s.dropHidden.length} hidden',
                onSelect: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const DropAppsScreen()))),
            const SizedBox(height: 20),
            PillButton(label: 'Test connection', onSelect: _test),
          ],
          if (s.serverUrl.isNotEmpty || s.serverToken.isNotEmpty) ...[
            const SizedBox(height: 20),
            PillButton(
                label: 'Disconnect',
                onSelect: () {
                  s.change(() {
                    s.serverUrl = '';
                    s.serverToken = '';
                    if (s.ssSource == 'drop') s.ssSource = 'colors';
                  });
                  kDrop.refresh('', '');
                  setState(() => _msg = 'Disconnected.');
                }),
          ],
          const SizedBox(height: 28),
          SizedBox(
              width: 1300,
              child: Text(_msg, style: const TextStyle(fontSize: 26, color: Colors.white70))),
        ]),
      ),
    );
  }
}

/// Shows a short code, like Plex does. You type it on the web page and the TV links itself.
class LinkScreen extends StatefulWidget {
  const LinkScreen({super.key});
  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  String _code = '';
  String _secret = '';
  String _msg = 'Getting a code…';
  bool _failed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    final s = SettingsScope.read(context);
    setState(() {
      _code = '';
      _failed = false;
      _msg = 'Getting a code…';
    });
    try {
      final name = s.name.trim().isEmpty ? 'Fire TV' : "${s.name.trim()}'s TV";
      final r = await DropApi.linkStart(s.serverUrl, name, s.clientId);
      if (!mounted) return;
      setState(() {
        _code = r[0];
        _secret = r[1];
        _msg = 'Waiting for you to enter the code…';
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } on HttpException catch (e) {
      _fail(e.message.startsWith('Too many') || e.message.startsWith('That does')
          ? e.message
          : 'That address answered, but not like a Foyer Drop server. Check the address.');
    } catch (_) {
      _fail('Could not reach the server. Go back and check the address.');
    }
  }

  void _fail(String m) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _msg = m;
    });
  }

  Future<void> _check() async {
    final s = SettingsScope.read(context);
    try {
      final r = await DropApi.linkPoll(s.serverUrl, _secret);
      if (!mounted) return;
      if (r[0] == 'linked' && r[1].isNotEmpty) {
        _poll?.cancel();
        s.change(() => s.serverToken = r[1]);
        Navigator.of(context).pop(r[2].isEmpty ? 'your account' : r[2]);
      } else if (r[0] == 'expired') {
        _poll?.cancel();
        _fail('That code ran out. Get a new one.');
      }
    } catch (_) {
      // a hiccup: keep waiting
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final site = DropApi.clean(s.serverUrl).replaceFirst(RegExp(r'^https?://'), '');
    return SettingsPage(
      title: 'Link this TV',
      subtitle: 'No typing on the TV. Use your phone.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _step('1', 'On your phone, open  $site'),
        _step('2', 'Sign in (or create an account), then tap TVs'),
        _step('3', 'Enter this code:'),
        const SizedBox(height: 18),
        if (_code.isNotEmpty)
          Glass(
            radius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 22),
            child: Text(_code.split('').join(' '),
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w700, letterSpacing: 6)),
          ),
        const SizedBox(height: 26),
        SizedBox(
            width: 1300,
            child: Text(_msg, style: const TextStyle(fontSize: 28, color: Colors.white70))),
        const SizedBox(height: 26),
        PillButton(
            label: _failed ? 'Get a new code' : 'Cancel',
            primary: _failed,
            autofocus: true,
            onSelect: _failed ? _start : () => Navigator.of(context).pop()),
      ]),
    );
  }

  Widget _step(String n, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40), shape: BoxShape.circle),
              child: Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          const SizedBox(width: 18),
          Text(t, style: const TextStyle(fontSize: 32)),
        ]),
      );
}

/// Choose which apps the phone page may open. Everything is shown unless you hide it.
class DropAppsScreen extends StatefulWidget {
  const DropAppsScreen({super.key});
  @override
  State<DropAppsScreen> createState() => _DropAppsScreenState();
}

class _DropAppsScreenState extends State<DropAppsScreen> {
  List<InstalledApp>? _apps;
  Timer? _later;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    fetchInstalledApps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  @override
  void dispose() {
    if (_later?.isActive ?? false) {
      _later!.cancel();
      kDrop.sendAppsNow();
    }
    super.dispose();
  }

  void _set(Settings s, List<String> hidden) {
    s.change(() => s.dropHidden = hidden);
    // tell the phone page shortly after the last press
    _later?.cancel();
    _later = Timer(const Duration(milliseconds: 900), () async {
      final r = await kDrop.sendAppsNow();
      if (mounted && r.isNotEmpty) setState(() => _msg = r);
    });
    if (_msg != 'Updating the phone page…') setState(() => _msg = 'Updating the phone page…');
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final apps = _apps;
    final hidden = s.dropHidden.toSet();
    return SettingsPage(
      title: 'Apps on the phone page',
      subtitle: 'Pick the apps that show under "Open on TV". Press an app to show or hide it.',
      child: apps == null
          ? const Text('Loading…', style: TextStyle(fontSize: 28, color: Colors.white70))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 16, runSpacing: 16, children: [
                  PillButton(label: 'Show all', onSelect: () => _set(s, [])),
                  PillButton(
                      label: 'Hide all',
                      onSelect: () => _set(s, [for (final a in apps) a.package])),
                ]),
                const SizedBox(height: 16),
                Text(_msg.isEmpty ? '${apps.length - hidden.length} of ${apps.length} apps shown.' : _msg,
                    style: const TextStyle(fontSize: 24, color: Colors.white70)),
                const SizedBox(height: 20),
                Wrap(spacing: 16, runSpacing: 16, children: [
                  for (var i = 0; i < apps.length; i++)
                    _AppToggle(
                      key: ValueKey(apps[i].package),
                      app: apps[i],
                      shown: !hidden.contains(apps[i].package),
                      autofocus: i == 0,
                      onSelect: () {
                        final h = {...hidden};
                        if (!h.remove(apps[i].package)) h.add(apps[i].package);
                        _set(s, h.toList());
                      },
                    ),
                ]),
              ]),
            ),
    );
  }
}

class _AppToggle extends StatelessWidget {
  const _AppToggle(
      {super.key,
      required this.app,
      required this.shown,
      required this.onSelect,
      this.autofocus = false});
  final InstalledApp app;
  final bool shown;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => FocusButton(
        autofocus: autofocus,
        scrollIntoView: true,
        scale: 1.0,
        onSelect: onSelect,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 400,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: f ? Colors.white : Colors.white.withAlpha(shown ? 40 : 14),
            border: Border.all(color: Colors.white.withAlpha(f ? 255 : (shown ? 150 : 50))),
          ),
          child: Row(children: [
            Opacity(
                opacity: shown ? 1 : 0.35,
                child: Image.memory(app.icon, width: 44, height: 44, gaplessPlayback: true)),
            const SizedBox(width: 14),
            Expanded(
                child: Text(app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 24,
                        color: f ? Colors.black : (shown ? Colors.white : Colors.white54)))),
            Icon(shown ? Icons.check_circle_rounded : Icons.visibility_off_rounded,
                size: 28, color: f ? Colors.black : (shown ? Colors.white : Colors.white38)),
          ]),
        ),
      );
}

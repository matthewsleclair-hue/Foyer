import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';

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

  static Future<dynamic> _get(String url, String token, String path) async {
    final base = _clean(url);
    if (base.isEmpty || token.isEmpty) throw const HttpException('not set up');
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c.getUrl(Uri.parse('$base$path')).timeout(const Duration(seconds: 8));
      req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) throw const HttpException('Wrong token');
      if (res.statusCode != 200) throw HttpException('Server answered ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      c.close(force: true);
    }
  }

  /// Returns null when fine, or a plain-English problem.
  static Future<String?> test(String url, String token) async {
    try {
      await _get(url, token, '/api/ping');
      return null;
    } on HttpException catch (e) {
      return e.message == 'Wrong token'
          ? 'The server answered, but the token is wrong.'
          : 'Could not use that server: ${e.message}';
    } on TimeoutException {
      return 'The server did not answer. Check the address and that the TV is on the same network.';
    } catch (_) {
      return 'Could not reach the server. Check the address (for example 192.168.1.50:8080).';
    }
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

  static Future<List<String>> photoUrls(String url, String token) async {
    final j = await _get(url, token, '/api/photos');
    final l = j is Map ? j['photos'] : null;
    final base = _clean(url);
    return l is List ? [for (final id in l) '$base/photos/$id.jpg'] : const [];
  }
}

class DropFeed {
  final ValueNotifier<List<DropNote>> notes = ValueNotifier(const []);
  DateTime? _last;
  String _sig = '';
  bool _busy = false;

  Future<void> refresh(String url, String token, {bool force = false}) async {
    if (url.trim().isEmpty || token.isEmpty) {
      _sig = '';
      if (notes.value.isNotEmpty) notes.value = const [];
      return;
    }
    final sig = '$url|$token';
    final age = _last == null ? 9999 : DateTime.now().difference(_last!).inSeconds;
    if (_busy || !(force || sig != _sig || age >= 60)) return;
    _busy = true;
    _sig = sig;
    _last = DateTime.now();
    try {
      notes.value = await DropApi.notes(url, token);
    } catch (_) {
      // keep the last good notes
    }
    _busy = false;
  }
}

final DropFeed kDrop = DropFeed();

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
      constraints: const BoxConstraints(maxWidth: 760),
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

  Future<void> _ask(bool isUrl) async {
    final s = SettingsScope.read(context);
    final v = await askText(
        context,
        isUrl ? 'Server address' : 'Server token',
        isUrl ? s.serverUrl : s.serverToken,
        hint: isUrl ? 'For example 192.168.1.50:8080' : 'The FOYER_TOKEN you set on the server',
        maxLength: 200);
    if (v == null) return;
    s.change(() {
      if (isUrl) {
        s.serverUrl = v.trim();
      } else {
        s.serverToken = v.trim();
      }
    });
    if (mounted) setState(() => _msg = '');
  }

  Future<void> _test() async {
    final s = SettingsScope.read(context);
    setState(() => _msg = 'Testing…');
    final r = await DropApi.test(s.serverUrl, s.serverToken);
    if (!mounted) return;
    setState(() => _msg = r ?? 'Connected. Notes you send will show on the home screen.');
    if (r == null) kDrop.refresh(s.serverUrl, s.serverToken, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'Photo and note drop',
      subtitle:
          'Connect to your own Foyer Drop server. Send notes and photos from any phone and they show up here.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PillButton(
              label: s.serverUrl.isEmpty ? 'Set server address' : 'Address: ${s.serverUrl}',
              primary: s.serverUrl.isEmpty,
              onSelect: () => _ask(true)),
          const SizedBox(height: 20),
          PillButton(
              label: s.serverToken.isEmpty ? 'Set token' : 'Token: set (change)',
              primary: s.serverToken.isEmpty,
              onSelect: () => _ask(false)),
          const SizedBox(height: 20),
          PillButton(label: 'Test connection', onSelect: _test),
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
              child: Text(_msg,
                  style: const TextStyle(fontSize: 26, color: Colors.white70))),
        ]),
      ),
    );
  }
}

// Foyer for PC updates itself: it checks your Foyer Drop server (or the GitHub repo, with
// a token), downloads the new Foyer-PC zip, and a small helper swaps the files in after
// Foyer closes, then opens the new Foyer. Settings stay (they live in %APPDATA%\Foyer).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart';
import '../screens.dart';
import '../update.dart';
import 'bridge.dart';

/// Checks for a newer Foyer for PC. Null when up to date. Throws if it can't check.
Future<UpdateInfo?> checkPcUpdate(Settings s) async {
  final src = s.updateUrl.trim();
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    if (src.isEmpty || src == UpdateApi.dropSource) {
      if (s.serverUrl.isEmpty || s.serverToken.isEmpty) {
        throw const FormatException('Link Foyer Drop first (Settings › Home screen › Foyer Drop). Updates come from there.');
      }
      final base = s.serverUrl.replaceAll(RegExp(r'/+$'), '');
      final req = await c.getUrl(Uri.parse('$base/api/update/pc'));
      req.headers.set('Authorization', 'Bearer ${s.serverToken}');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null; // nothing published there yet
      if (res.statusCode >= 400) throw HttpException('Foyer Drop HTTP ${res.statusCode}');
      final j = jsonDecode(body) as Map;
      final build = (j['build'] as num?)?.toInt() ?? 0;
      if (build <= kPcBuild) return null;
      return UpdateInfo('${j['version'] ?? ''}', build, '$base/api/update/pc/zip', '${j['notes'] ?? ''}');
    }
    // GitHub: the newest "Foyer for PC" release (tags pc-v1.2.3+N)
    final repo = UpdateApi.githubRepo(src);
    if (repo == null) throw const FormatException('Updates come from Foyer Drop or a GitHub repo');
    final req = await c.getUrl(Uri.https('api.github.com', '/repos/$repo/releases', {'per_page': '30'}));
    req.headers.set('Accept', 'application/vnd.github+json');
    final tok = UpdateApi.cleanToken(s.updateToken);
    if (tok.isNotEmpty) req.headers.set('Authorization', 'Bearer $tok');
    final res = await req.close().timeout(const Duration(seconds: 12));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
    for (final r in (jsonDecode(body) as List)) {
      if (r is! Map) continue;
      final m = RegExp(r'^pc-v(\d+\.\d+\.\d+)\+(\d+)$').firstMatch('${r['tag_name']}');
      if (m == null) continue;
      final build = int.parse(m.group(2)!);
      if (build <= kPcBuild) return null;
      for (final a in (r['assets'] as List? ?? const [])) {
        if (a is Map && '${a['name']}'.toLowerCase().endsWith('.zip')) {
          final url = tok.isNotEmpty ? '${a['url']}' : '${a['browser_download_url']}';
          return UpdateInfo(m.group(1)!, build, url, '${r['body'] ?? ''}');
        }
      }
    }
    return null;
  } finally {
    c.close(force: true);
  }
}

/// Checks now and then in the background; a new version lights up the gear and shows a note.
void startPcUpdateChecks() {
  Future<void> run() async {
    final ctx = kNavKey.currentContext;
    if (ctx == null) return;
    try {
      kUpdate.value = await checkPcUpdate(SettingsScope.read(ctx));
    } catch (_) {}
  }

  Timer(const Duration(seconds: 25), run);
  Timer.periodic(const Duration(hours: 6), (_) => run());
}

/// Downloads the zip, then hands over to a helper that swaps the files and reopens Foyer.
Future<void> installPcUpdate(UpdateInfo u, Settings s, void Function(double) onProgress) async {
  final dir = Directory('${Platform.environment['TEMP'] ?? Directory.systemTemp.path}\\FoyerUpdate');
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final zip = '${dir.path}\\Foyer-PC.zip';
  final token = u.url.contains('api.github.com') ? s.updateToken : s.serverToken;
  await UpdateApi.download(u.url, zip, token, onProgress);
  final appDir = File(Platform.resolvedExecutable).parent.path;
  final script = File('${dir.path}\\update.ps1');
  await script.writeAsString(r'''
param([string]$Zip, [string]$Dest, [string]$Exe, [int]$ProcId)
try { Wait-Process -Id $ProcId -Timeout 20 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 500
$tmp = Join-Path (Split-Path $Zip) 'x'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
Expand-Archive -Path $Zip -DestinationPath $tmp -Force
$src = (Get-ChildItem -Path $tmp -Recurse -Filter 'foyer.exe' | Select-Object -First 1).DirectoryName
if ($src) { Copy-Item -Path (Join-Path $src '*') -Destination $Dest -Recurse -Force }
Start-Process -FilePath $Exe
''');
  await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-Zip',
        zip,
        '-Dest',
        appDir,
        '-Exe',
        Platform.resolvedExecutable,
        '-ProcId',
        '$pid',
      ],
      mode: ProcessStartMode.detached);
  // close the streaming windows too, then let the helper do its job
  await closeWebApps();
  exit(0);
}

class PcUpdateScreen extends StatefulWidget {
  const PcUpdateScreen({super.key});
  @override
  State<PcUpdateScreen> createState() => _PcUpdateScreenState();
}

class _PcUpdateScreenState extends State<PcUpdateScreen> {
  UpdateInfo? _found = kUpdate.value;
  String _msg = '';
  bool _busy = false;
  double? _prog;

  @override
  void initState() {
    super.initState();
    if (_found == null) WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = 'Checking…';
    });
    try {
      final u = await checkPcUpdate(SettingsScope.read(context));
      kUpdate.value = u;
      if (!mounted) return;
      setState(() {
        _found = u;
        _msg = u == null
            ? 'You\'re up to date.'
            : 'Version ${u.version} is ready.${u.notes.trim().isEmpty ? '' : '\n\n${plainNotes(u.notes)}'}';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Could not check: ${UpdateApi.friendly(e)}');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _install() async {
    final u = _found;
    if (u == null || _busy) return;
    setState(() {
      _busy = true;
      _prog = 0;
      _msg = 'Downloading…';
    });
    try {
      await installPcUpdate(u, SettingsScope.read(context), (p) {
        if (mounted) setState(() => _prog = p);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _prog = null;
          _msg = 'Could not update: ${UpdateApi.friendly(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final fromDrop = s.updateUrl.trim().isEmpty || s.updateUrl.trim() == UpdateApi.dropSource;
    return SettingsPage(
      title: 'Updates',
      subtitle: 'Foyer for PC updates itself: it downloads the new version, closes for a moment and opens again. '
          'Your settings and sign-ins stay.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This is Foyer for PC $kPcVersion (build $kPcBuild)',
              style: const TextStyle(fontSize: 28, color: Colors.white70)),
          const SizedBox(height: 6),
          Text(fromDrop ? 'Updates come from your Foyer Drop server.' : 'Updates come from GitHub.',
              style: const TextStyle(fontSize: 24, color: Colors.white54)),
          const SizedBox(height: 26),
          PillButton(
            label: _prog != null
                ? 'Downloading… ${((_prog ?? 0) * 100).round()}%'
                : (_busy ? 'Checking…' : (_found != null ? 'Download and install ${_found!.version}' : 'Check now')),
            primary: true,
            autofocus: true,
            onSelect: () => _found != null ? _install() : _check(),
          ),
          if (_prog != null) ...[
            const SizedBox(height: 22),
            SizedBox(
                width: 700,
                child: LinearProgressIndicator(value: _prog, minHeight: 10, borderRadius: BorderRadius.circular(6))),
          ],
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                  width: 1400,
                  child: Text(_msg,
                      maxLines: 16,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 24, height: 1.4, color: Colors.white70))),
            ),
        ]),
      ),
    );
  }
}

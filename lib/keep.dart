// Keep watching and people (ideas from couch-tv, github.com/Seagey/couch-tv, MIT).
//
// Keep watching: the shows you're part way through, from Android's own Watch Next list
// (what Netflix, Disney+, Prime, YouTube and the rest keep for the TV), with how far in
// you are. OK opens the show right where you were.
//
// People: each person who watches this TV has their own apps and teams. The names sit
// at the top left of the home screen; pick one to switch.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens.dart';
import 'plex.dart';

class KeepItem {
  KeepItem(this.id, this.package, this.app, this.title, this.subtitle, this.progress, this.image,
      {this.imageUrl = '', this.plex, this.at = 0});
  final int id; // Watch Next row (-1 for Plex)
  final String package;
  final String app;
  final String title;
  final String subtitle;
  final double? progress;
  final Uint8List? image;
  final String imageUrl; // Plex artwork, loaded from your server
  final PlexItem? plex;
  final int at; // last watched, ms since 1970
}

/// The Keep watching cards, refreshed while the home screen is open.
final ValueNotifier<List<KeepItem>> kKeep = ValueNotifier(const []);
DateTime _keepAt = DateTime(2000);

/// Fills Keep watching from two places: your Plex server's Continue Watching (Plex doesn't
/// share it with the TV), and the TV's Watch Next list for every other app. Newest first.
Future<void> refreshKeepWatching({bool force = false}) async {
  if (!force && DateTime.now().difference(_keepAt) < const Duration(seconds: 45)) return;
  _keepAt = DateTime.now();
  final ctx = kNavKey.currentContext;
  final s = ctx == null ? null : SettingsScope.read(ctx);
  final results = await Future.wait([
    _fromPlex(s),
    _fromTv(skipPlex: s != null && s.plexUrl.isNotEmpty && s.plexToken.isNotEmpty),
  ]);
  final all = [...results[0], ...results[1]]..sort((a, b) => b.at.compareTo(a.at));
  kKeep.value = all;
}

Future<List<KeepItem>> _fromPlex(Settings? s) async {
  if (s == null || s.plexUrl.isEmpty || s.plexToken.isEmpty) return const [];
  try {
    final items = await PlexApi(s.clientId)
        .onDeck(PlexServer(s.plexName, s.plexUrl, s.plexToken))
        .timeout(const Duration(seconds: 12));
    return [
      for (final it in items)
        KeepItem(-1, kPlexPackage, 'Plex', it.title, it.subtitle, it.progress, null,
            imageUrl: it.imageUrl, plex: it, at: it.viewedAt * 1000),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<KeepItem>> _fromTv({bool skipPlex = false}) async {
  try {
    final r = await kChannel.invokeMapMethod<String, dynamic>(
        'watchNext', {'max': 6, 'skip': skipPlex ? const [kPlexPackage] : const <String>[]});
    if (r?['ok'] != true) return const [];
    final out = <KeepItem>[];
    for (final x in (r?['items'] as List? ?? const [])) {
      if (x is! Map) continue;
      final season = '${x['season'] ?? ''}'.trim();
      final ep = '${x['episode'] ?? ''}'.trim();
      final epTitle = '${x['episodeTitle'] ?? ''}'.trim();
      var sub = '';
      if (season.isNotEmpty && ep.isNotEmpty) {
        sub = 'S$season E$ep';
      } else if (ep.isNotEmpty) {
        sub = 'Episode $ep';
      }
      if (epTitle.isNotEmpty && epTitle != '${x['title']}') sub = sub.isEmpty ? epTitle : '$sub · $epTitle';
      final img = x['image'];
      out.add(KeepItem(
        (x['id'] as num?)?.toInt() ?? -1,
        '${x['package']}',
        '${x['app']}',
        '${x['title']}',
        sub,
        (x['progress'] as num?)?.toDouble(),
        img is Uint8List ? img : null,
        at: (x['engaged'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<void> openKeepItem(KeepItem k) async {
  final p = k.plex;
  if (p != null) {
    // the episode or movie's own page in Plex; the Plex app if that doesn't open
    final link = p.type == 'season' ? p.showLink : p.plexLink;
    var ok = false;
    if (link.isNotEmpty) {
      try {
        ok = (await kChannel.invokeMethod<bool>('openLink', {'url': link, 'package': kPlexPackage})) ?? false;
      } catch (_) {}
    }
    if (!ok) await launchPackage(kPlexPackage);
    return;
  }
  try {
    await kChannel.invokeMethod<bool>('openWatchNext', {'id': k.id});
  } catch (_) {}
}

/// "Keep watching" and a row of cards. Shows nothing when the list is empty.
class KeepWatchingRow extends StatelessWidget {
  const KeepWatchingRow({super.key, required this.onOpen});
  final ValueChanged<KeepItem> onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<KeepItem>>(
        valueListenable: kKeep,
        builder: (_, items, __) {
          if (items.isEmpty) return const SizedBox.shrink();
          final shown = items.take(3).toList();
          return FocusTraversalGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 14),
                child: Text('Keep watching',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Color(0x99000000), blurRadius: 16)])),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < shown.length; i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 22),
                    child: _KeepCard(item: shown[i], onOpen: () => onOpen(shown[i])),
                  ),
              ]),
            ]),
          );
        },
      );
}

class _KeepCard extends StatelessWidget {
  const _KeepCard({required this.item, required this.onOpen});
  final KeepItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => FocusButton(
        onSelect: onOpen,
        scale: 1.04,
        builder: (_, f) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 430,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: f ? Colors.white.withAlpha(60) : Colors.black.withAlpha(90),
            border: Border.all(color: Colors.white.withAlpha(f ? 230 : 50), width: f ? 3 : 1.5),
            boxShadow: f ? const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))] : null,
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 150,
                height: 84,
                child: item.image != null
                    ? Image.memory(item.image!, fit: BoxFit.cover, gaplessPlayback: true)
                    : item.imageUrl.isNotEmpty
                    ? Image.network(item.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => ColoredBox(color: Colors.white.withAlpha(30)))
                    : ColoredBox(
                        color: Colors.white.withAlpha(30),
                        child: const Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.app.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, letterSpacing: 1.2, color: Colors.white60)),
                const SizedBox(height: 4),
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700)),
                if (item.subtitle.isNotEmpty)
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, color: Colors.white70)),
                if (item.progress != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 5,
                      backgroundColor: Colors.white.withAlpha(50),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      );
}

// ───────────────────────── who's watching ─────────────────────────

/// "Matthew | Sarah" under the greeting on the home screen. Only shown with two or more people.
class ProfilePills extends StatelessWidget {
  const ProfilePills({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    if (s.profiles.length < 2) return const SizedBox.shrink();
    return FocusTraversalGroup(
      child: Glass(
        radius: 40,
        padding: const EdgeInsets.all(6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < s.profiles.length; i++)
            FocusButton(
              scale: 1.0,
              onSelect: () => s.switchProfile(i),
              builder: (_, f) {
                final on = i == s.activeProfile;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    color: f ? Colors.white : (on ? Colors.white.withAlpha(215) : Colors.transparent),
                    border: f ? Border.all(color: Colors.white, width: 3) : null,
                  ),
                  child: Text(s.profiles[i].name,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: on || f ? FontWeight.w700 : FontWeight.w500,
                          color: on || f ? Colors.black : Colors.white70)),
                );
              },
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── settings ─────────────────────────

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  Future<void> _add(BuildContext context, Settings s) async {
    var first = 'Me';
    if (s.profiles.isEmpty) {
      final me = await askText(context, 'First, what\'s your name?', '', hint: 'You keep your apps and teams', maxLength: 16);
      if (me == null || me.trim().isEmpty || !context.mounted) return;
      first = me.trim();
    }
    final n = await askText(context, 'Who else watches?', '', hint: 'Their name', maxLength: 16);
    if (n == null || n.trim().isEmpty) return;
    s.addPerson(n.trim(), firstName: first);
  }

  void _menu(BuildContext context, Settings s, int i) {
    final n = s.profiles.length;
    showMenu2(context, s.profiles[i].name, [
      if (i != s.activeProfile) MenuChoice('Switch to ${s.profiles[i].name}', () => s.switchProfile(i)),
      MenuChoice('Rename', () async {
        final v = await askText(context, 'New name', s.profiles[i].name, maxLength: 16);
        if (v != null && v.trim().isNotEmpty) s.renamePerson(i, v.trim());
      }),
      if (i > 0) MenuChoice('Move left', () => s.movePerson(i, -1)),
      if (i < n - 1) MenuChoice('Move right', () => s.movePerson(i, 1)),
      MenuChoice('Remove ${s.profiles[i].name}', () {
        showMenu2(context, 'Remove ${s.profiles[i].name}?', [
          MenuChoice('Their apps and teams are forgotten. Nothing in the apps themselves changes.', null),
          MenuChoice('Remove', () => s.removePerson(i)),
          MenuChoice('Cancel', () {}),
        ]);
      }),
      MenuChoice('Cancel', () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    return SettingsPage(
      title: 'People',
      subtitle: 'Everyone who watches gets their own apps along the bottom and their own sports teams. '
          'Their names sit at the top left of the home screen, under the greeting: pick one to switch.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < s.profiles.length; i++)
            SettingRow(
              autofocus: i == 0,
              entry: HubEntry(
                Icons.person_rounded,
                s.profiles[i].name,
                '${(i == s.activeProfile ? s.pinned : s.profiles[i].pinned).length} apps · '
                    '${(i == s.activeProfile ? s.sportsTeams : s.profiles[i].teams).length} teams',
                () => _menu(context, s, i),
                value: i == s.activeProfile ? 'Watching now' : '',
              ),
            ),
          SettingRow(
            autofocus: s.profiles.isEmpty,
            entry: HubEntry(Icons.person_add_alt_1_rounded, 'Add a person',
                s.profiles.isEmpty ? 'Right now this TV is set up for one person' : 'Starts with the same apps as you',
                () => _add(context, s)),
          ),
        ]),
      ),
    );
  }
}

/// Keeps the cards fresh while the home screen is showing.
class KeepWatchingTicker {
  Timer? _t;
  void start() {
    _t?.cancel();
    refreshKeepWatching(force: true);
    _t = Timer.periodic(const Duration(minutes: 1), (_) => refreshKeepWatching());
  }

  void stop() => _t?.cancel();
}

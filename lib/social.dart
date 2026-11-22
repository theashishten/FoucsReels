import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _ch = MethodChannel('focus_reels');

/// Only HTTPS, or plain HTTP to a local development server reached over USB or the emulator host.
bool validBase(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return false;
  if (u.scheme == 'https') return true;
  return u.scheme == 'http' && const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(u.host);
}

/// Minimal JSON-over-HTTP client for the Focus Reels server.
class Api {
  Api(this.base, this.token);
  final String base, token;

  Future<Map<String, dynamic>> call(String method, String path,
      [Map<String, dynamic>? body]) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await c.openUrl(method, Uri.parse('$base$path'));
      if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 8));
      final text = await res.transform(utf8.decoder).join();
      final m = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode >= 400) throw (m['error'] ?? 'error ${res.statusCode}').toString();
      return m;
    } finally {
      c.close(force: true);
    }
  }
}

/// Holds friends/duel/buddy state and the actions on it. Rebuilds the UI through [notify].
class SocialCtl {
  SocialCtl(this.notify, this.ctx, this.social, this.config, this.saveConfig, this.localDays);
  final VoidCallback notify;
  final BuildContext Function() ctx;
  final Map<String, dynamic> Function() social;
  final Map<String, dynamic> Function() config;
  final Future<void> Function(Map<String, dynamic>) saveConfig;
  final Map<String, int> Function() localDays;

  Map<String, dynamic>? net; // {me, friends, incoming, info}
  String error = '';

  bool get joined => (social()['token'] ?? '').toString().isNotEmpty;
  bool get remoteBuddy => config()['remoteBuddy'] == true && joined;
  Api? get api => joined ? Api(social()['url'] as String, social()['token'] as String) : null;

  void _toast(String m) {
    final c = ctx();
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> refresh() async {
    final a = api;
    if (a == null) {
      net = null;
      error = '';
      return;
    }
    try {
      final days = localDays();
      await a.call('POST', '/sync', {'days': days});
      final today = (days.keys.toList()..sort()).last;
      final info = await a.call('GET', '/me');
      final fr = await a.call('GET', '/friends?day=$today');
      final inc = await a.call('GET', '/requests/incoming');
      net = {'info': info, 'me': fr['me'], 'friends': fr['friends'], 'incoming': inc['requests']};
      error = '';
      // Keep the app's "needs buddy approval" switch in step with the server.
      final hasBuddy = (info['buddyId'] ?? '').toString().isNotEmpty;
      if (hasBuddy != (config()['remoteBuddy'] == true)) {
        await saveConfig({...config(), 'remoteBuddy': hasBuddy});
      }
    } catch (e) {
      error = 'Could not reach the server: $e';
    }
    notify();
  }

  Future<void> join(String url, String name) async {
    final u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!validBase(u)) {
      _toast('Use an https:// address (http:// only works for 127.0.0.1)');
      return;
    }
    if (name.trim().isEmpty) {
      _toast('Pick a display name');
      return;
    }
    try {
      final r = await Api(u, '').call('POST', '/register', {'name': name.trim()});
      await _ch.invokeMethod('setSocial', jsonEncode({
        'url': u, 'token': r['token'], 'userId': r['userId'], 'name': r['name'], 'code': r['code'],
      }));
      await refresh();
    } catch (e) {
      _toast('Could not join: $e');
    }
  }

  Future<void> addFriend(String code) async {
    try {
      final r = await api!.call('POST', '/invite/accept', {'code': code.trim()});
      _toast('Added ${(r['friend'] as Map)['name']}');
      await refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> removeFriend(String id) async {
    try {
      await api!.call('POST', '/friends/remove', {'friendId': id});
      await refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> setBuddy(String? id) async {
    try {
      await api!.call('POST', '/buddy', {'friendId': id});
      await refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> decide(String requestId, bool approve) async {
    try {
      await api!.call('POST', '/requests/$requestId/decision', {'approve': approve});
      await refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> disconnect() async {
    await _ch.invokeMethod('setSocial', jsonEncode({}));
    await saveConfig({...config(), 'remoteBuddy': false});
    net = null;
    notify();
  }

  /// Asks the buddy to approve [what] and waits for the answer (up to 5 minutes). Fails closed.
  Future<bool> approval(String what) async {
    final a = api;
    if (a == null) return false;
    String id;
    try {
      id = (await a.call('POST', '/requests', {'kind': 'change', 'note': what}))['id'] as String;
    } catch (e) {
      _toast('Could not reach your buddy\'s server, so this is not allowed right now.');
      return false;
    }
    var open = true;
    var ok = false;
    final c = ctx();
    if (!c.mounted) return false;
    final nav = Navigator.of(c);
    unawaited(showDialog<void>(
      context: c,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Waiting for your buddy'),
        content: Text('Asked them to approve: $what'),
        actions: [
          TextButton(
            onPressed: () {
              open = false;
              Navigator.pop(d);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));
    for (var i = 0; i < 100 && open; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!open) break;
      try {
        final r = await a.call('GET', '/requests/mine');
        final m = (r['requests'] as List).cast<Map>().where((x) => x['id'] == id).toList();
        if (m.isNotEmpty && m.first['status'] != 'pending') {
          ok = m.first['status'] == 'approved';
          break;
        }
      } catch (_) {}
    }
    if (open) nav.pop();
    if (!ok) _toast('Not approved');
    return ok;
  }
}

class FriendsPage extends StatefulWidget {
  const FriendsPage(this.soc, {super.key});
  final SocialCtl soc;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final url = TextEditingController(text: 'http://127.0.0.1:8787');
  final name = TextEditingController();
  final code = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final soc = widget.soc;
    if (!soc.joined) return _joinCard(soc);
    final net = soc.net;
    final cs = Theme.of(context).colorScheme;
    final info = (net?['info'] as Map?) ?? {};
    final me = (net?['me'] as Map?) ?? {};
    final friends = ((net?['friends'] as List?) ?? []).cast<Map>();
    final incoming = ((net?['incoming'] as List?) ?? []).cast<Map>();
    final buddyId = (info['buddyId'] ?? '').toString();
    final myCode = (soc.social()['code'] ?? '').toString();
    final myName = (soc.social()['name'] ?? '').toString();
    final myWeek = (me['week'] ?? 0) as int;

    return ListView(padding: const EdgeInsets.all(16), children: glassify([
      if (soc.error.isNotEmpty)
        Card(color: cs.errorContainer, child: ListTile(title: Text(soc.error))),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person),
          title: Text(myName),
          subtitle: Text('Your invite code: $myCode'),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: myCode));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Code copied')));
              }
            },
          ),
        ),
      ),
      if (incoming.isNotEmpty) ...[
        Text('Buddy requests', style: Theme.of(context).textTheme.titleMedium),
        for (final r in incoming)
          Card(
            color: cs.tertiaryContainer,
            child: ListTile(
              title: Text('${r['fromName']} wants to: ${r['note']}'),
              trailing: Wrap(children: [
                IconButton(
                    icon: const Icon(Icons.check_circle),
                    onPressed: () => soc.decide(r['id'] as String, true)),
                IconButton(
                    icon: const Icon(Icons.cancel),
                    onPressed: () => soc.decide(r['id'] as String, false)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 8),
      Text('Add a friend', style: Theme.of(context).textTheme.titleMedium),
      Row(children: [
        Expanded(
          child: TextField(
            controller: code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Friend\'s invite code'),
          ),
        ),
        TextButton(
          onPressed: () async {
            await soc.addFriend(code.text);
            code.clear();
          },
          child: const Text('Add'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('Weekly duel (fewest reels wins)',
          style: Theme.of(context).textTheme.titleMedium),
      if (friends.isEmpty) const Padding(
          padding: EdgeInsets.all(12), child: Text('No friends yet. Share your code.')),
      for (final f in friends) _friendCard(context, soc, f, myWeek, buddyId),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.shield),
          title: Text(buddyId.isEmpty ? 'No accountability buddy' : 'Buddy approval is ON'),
          subtitle: Text(buddyId.isEmpty
              ? 'Pick a friend below. They must approve before you can pause or loosen your rules.'
              : 'Your buddy must approve pausing, loosening rules, resetting blocks and leaving.'),
          trailing: buddyId.isEmpty
              ? null
              : TextButton(
                  onPressed: () async {
                    if (await soc.approval('remove me as their buddy')) await soc.setBuddy(null);
                  },
                  child: const Text('Remove'),
                ),
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Disconnect from server'),
        onPressed: () async {
          if (soc.remoteBuddy && !await soc.approval('disconnect from the server')) return;
          await soc.disconnect();
        },
      ),
      const Text(
          'Shared with friends: your display name and your daily reel totals. Nothing else leaves your phone.',
          style: TextStyle(fontSize: 12)),
    ]));
  }

  Widget _friendCard(BuildContext context, SocialCtl soc, Map f, int myWeek, String buddyId) {
    final theirWeek = (f['week'] ?? 0) as int;
    final winning = myWeek < theirWeek;
    final tie = myWeek == theirWeek;
    final isBuddy = f['userId'] == buddyId;
    final total = (myWeek + theirWeek).clamp(1, 1 << 30);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${f['name']}${isBuddy ? '  (buddy)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('today ${f['today']}'),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: myWeek / total, minHeight: 8),
          const SizedBox(height: 4),
          Text('You $myWeek  vs  ${f['name']} $theirWeek  •  '
              '${tie ? 'Tied' : (winning ? 'You are winning' : '${f['name']} is winning')}'),
          Wrap(spacing: 8, children: [
            if (!isBuddy && buddyId.isEmpty)
              TextButton(
                  onPressed: () => soc.setBuddy(f['userId'] as String),
                  child: const Text('Make buddy')),
            TextButton(
                onPressed: () => soc.removeFriend(f['userId'] as String),
                child: const Text('Remove')),
          ]),
        ]),
      ),
    );
  }

  Widget _joinCard(SocialCtl soc) => ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Friends, weekly duels and a remote accountability buddy need a Focus Reels server. '
            'Only your display name and daily reel totals are shared.'),
        const SizedBox(height: 16),
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Server address (https://…)'),
        ),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => soc.join(url.text, name.text), child: const Text('Join')),
      ]);
}

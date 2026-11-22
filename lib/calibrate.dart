import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'main.dart' show apps, promptText;
import 'theme.dart';

const _ch = MethodChannel('focus_reels');

/// Detection rules: the view ids that tell Focus Reels "a reel is on screen" in each app. Built-in ids ship with
/// the app; if an app update breaks counting you can capture the screen and add a new id here, no update needed.
class CalibratePage extends StatefulWidget {
  const CalibratePage({super.key});
  @override
  State<CalibratePage> createState() => _CalibratePageState();
}

class _CalibratePageState extends State<CalibratePage> with WidgetsBindingObserver {
  Map<String, List<String>> defaults = {};
  Map<String, List<String>> custom = {};
  String lastPkg = '';
  List<(String, bool)> seen = []; // (view id, scrollable)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    final raw = await _ch.invokeMethod<String>('getDetectors');
    if (raw == null || !mounted) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    Map<String, List<String>> conv(Map m) =>
        {for (final e in m.entries) e.key as String: [for (final x in e.value as List) x as String]};
    final ids = (j['lastIds'] ?? '') as String;
    final pkg = ids.contains(': ') ? ids.substring(0, ids.indexOf(': ')) : '';
    final body = pkg.isEmpty ? '' : ids.substring(ids.indexOf(': ') + 2);
    final found = <(String, bool)>[];
    final seenIds = <String>{};
    for (final tok in body.split(',')) {
      final m = RegExp(r'^([A-Za-z0-9_]+)(\*?)').firstMatch(tok.trim());
      if (m == null || m.group(1) == '-') continue;
      if (seenIds.add(m.group(1)!)) found.add((m.group(1)!, m.group(2) == '*'));
    }
    setState(() {
      defaults = conv(j['defaults'] as Map);
      custom = conv(j['custom'] as Map);
      lastPkg = pkg;
      seen = found;
    });
  }

  Future<void> save() async {
    await _ch.invokeMethod('setDetectors', jsonEncode(custom));
    setState(() {});
  }

  void add(String pkg, String id) {
    final l = [...(custom[pkg] ?? <String>[])];
    if (id.isEmpty || l.contains(id) || (defaults[pkg] ?? []).contains(id)) return;
    l.add(id);
    custom[pkg] = l;
    save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('Detection rules')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Glass(
          tint: cs.tertiaryContainer,
          child: Text(
            'If counting or blocking stops working after an app update, open the reel screen in that app, come back here and tap a view id from the list below to use it as the "reel screen" marker.',
            style: TextStyle(color: cs.onTertiaryContainer, height: 1.4),
          ),
        ),
        Section('Last screen seen', [
          if (lastPkg.isEmpty)
            const Tile(
              icon: Icons.touch_app_outlined,
              title: 'Nothing captured yet',
              subtitle: 'Open a reel app and scroll a little, then come back here.',
            )
          else ...[
            Tile(
              leading: AppIcon(lastPkg, size: 40),
              title: apps[lastPkg] ?? lastPkg,
              subtitle: '${seen.length} view ids on that screen. Tap one to use it as the reel marker.',
              trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: load),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (id, scroll) in seen.take(40))
                  ActionChip(
                    avatar: scroll ? const Icon(Icons.swap_vert, size: 16) : null,
                    label: Text(id, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      add(lastPkg, id);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Added "$id" for ${apps[lastPkg] ?? lastPkg}')));
                    },
                  ),
              ]),
            ),
          ],
        ], footer: 'A swap icon marks a scrolling container, which is usually the reel pager.'),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Text('Per app', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.3)),
        ),
        for (final e in apps.entries) _appCard(context, e.key, e.value),
      ]),
    );
  }

  Widget _appCard(BuildContext context, String pkg, String name) {
    final cs = context.cs;
    final def = defaults[pkg] ?? [];
    final cus = custom[pkg] ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppIcon(pkg, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
            if (cus.isNotEmpty)
              TextButton(
                onPressed: () {
                  custom.remove(pkg);
                  save();
                },
                child: const Text('Reset'),
              ),
          ]),
          const SizedBox(height: 10),
          if (def.isEmpty && cus.isEmpty)
            Text(
              pkg == 'com.netflix.mediaclient'
                  ? 'Netflix uses its own screen-label detector, no ids needed.'
                  : 'No built-in ids. A scrolling full-screen view is used instead; add an id to be exact.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
            ),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final id in def)
              Chip(label: Text(id, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
            for (final id in cus)
              InputChip(
                label: Text(id, style: const TextStyle(fontSize: 12)),
                backgroundColor: cs.primaryContainer,
                onDeleted: () {
                  custom[pkg] = [...cus]..remove(id);
                  save();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Add id'),
              onPressed: () async {
                final v = await promptText(context, 'View id for $name', 'e.g. clips_viewer_view_pager');
                if (v != null) add(pkg, v.trim());
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

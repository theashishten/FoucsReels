import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _ch = MethodChannel('focus_reels');

const _timerChoices = [15, 30, 45, 60, 90, 120, 180];

String _dk(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _dur(int ms) {
  final m = (ms / 60000).round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// Screen time for every app (from Android's usage log), by day, week or month, kept permanently.
class AppsPage extends StatefulWidget {
  const AppsPage(this.cfg, this.save, {super.key});
  final Map<String, dynamic> cfg;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> with WidgetsBindingObserver {
  Map<String, dynamic> days = {};
  bool access = true, loaded = false;
  int unlocks = 0;
  final Map<String, Uint8List> icons = {};
  int span = 0; // 0 day, 1 week, 2 month
  int offset = 0; // periods back from now

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
    final raw = await _ch.invokeMethod<String>('getAppUsage');
    if (raw == null || !mounted) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      days = Map<String, dynamic>.from(j['days'] as Map);
      access = j['access'] == true;
      unlocks = (j['unlocks'] ?? 0) as int;
      loaded = true;
    });
  }

  Future<void> loadIcons() async {
    final want = <String>{};
    for (final d in days.values) {
      for (final p in (d as Map).keys) {
        if (!icons.containsKey(p)) want.add(p as String);
      }
    }
    if (want.isEmpty) return;
    final raw = await _ch.invokeMethod<String>('getIcons', want.toList());
    if (raw == null || !mounted) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      for (final e in m.entries) {
        icons[e.key] = base64Decode(e.value as String);
      }
    });
  }

  Map<String, dynamic> get timers =>
      Map<String, dynamic>.from((widget.cfg['appTimers'] ?? {}) as Map);

  Future<void> pickTimer(String pkg, String name) async {
    final cur = (timers[pkg] ?? 0) as int;
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Daily timer: $name'),
        children: [
          for (final m in _timerChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Text(m < 60 ? '$m minutes' : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}',
                  style: TextStyle(fontWeight: m == cur ? FontWeight.bold : FontWeight.normal)),
            ),
          if (cur > 0)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 0),
              child: const Text('No timer'),
            ),
        ],
      ),
    );
    if (v == null) return;
    final t = timers;
    if (v == 0) {
      t.remove(pkg);
    } else {
      t[pkg] = v;
    }
    await widget.save({...widget.cfg, 'appTimers': t});
  }

  /// First and last day (inclusive) of the shown period.
  (DateTime, DateTime) get range {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    if (span == 0) {
      final d = today.subtract(Duration(days: offset));
      return (d, d);
    }
    if (span == 1) {
      final end = today.subtract(Duration(days: 7 * offset));
      return (end.subtract(const Duration(days: 6)), end);
    }
    final first = DateTime(n.year, n.month - offset, 1);
    final last = DateTime(first.year, first.month + 1, 0);
    return (first, last);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (!access) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apps, size: 48),
            const SizedBox(height: 12),
            const Text('Allow usage access to see how long you spend in every app.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _ch.invokeMethod('openUsageSettings'),
              child: const Text('Grant usage access'),
            ),
          ]),
        ),
      );
    }
    final (from, to) = range;
    final perApp = <String, int>{};
    final labels = <String, String>{};
    final perDay = <String, int>{};
    var recorded = 0;
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      final rec = days[_dk(d)] as Map?;
      if (rec == null) continue;
      recorded++;
      rec.forEach((p, v) {
        final ms = ((v['ms'] ?? 0) as num).toInt();
        perApp[p] = (perApp[p] ?? 0) + ms;
        labels[p] = (v['label'] ?? p) as String;
        perDay[_dk(d)] = (perDay[_dk(d)] ?? 0) + ms;
      });
    }
    final total = perApp.values.fold<int>(0, (a, b) => a + b);
    final list = perApp.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = list.isEmpty ? 1 : list.first.value;
    String title() {
      String m(DateTime d) => '${d.day}/${d.month}';
      if (span == 0) return offset == 0 ? 'Today' : (offset == 1 ? 'Yesterday' : m(from));
      if (span == 1) return '${m(from)} - ${m(to)}';
      const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${names[from.month - 1]} ${from.year}';
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        PillTabs<int>(
          items: const {0: 'Day', 1: 'Week', 2: 'Month'},
          value: span,
          onChanged: (v) => setState(() {
            span = v;
            offset = 0;
          }),
        ),
        PeriodNav(
          label: title(),
          onPrev: () => setState(() => offset++),
          onNext: offset == 0 ? null : () => setState(() => offset--),
        ),
        Center(
          child: Text(_dur(total), style: Theme.of(context).textTheme.displaySmall),
        ),
        Center(
          child: Text(
            span == 0 || recorded == 0
                ? 'screen time in all apps  -  $unlocks ${unlocks == 1 ? 'unlock' : 'unlocks'} today'
                : 'avg ${_dur((total / recorded).round())} per day (${recorded} days recorded)',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No usage recorded for this period.', textAlign: TextAlign.center),
          ),
        for (final e in list.take(40))
          AppRow(
            pkg: e.key,
            name: labels[e.key] ?? e.key,
            value: _dur(e.value),
            fraction: e.value / top,
            onTap: () => pickTimer(e.key, labels[e.key] ?? e.key),
            badge: (timers[e.key] ?? 0) as int > 0
                ? Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.timer, size: 14),
                    label: Text('${timers[e.key]}m'),
                  )
                : null,
          ),
        if (span != 0 && perDay.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('By day', style: Theme.of(context).textTheme.titleMedium),
          for (final k in (perDay.keys.toList()..sort()).reversed)
            ListTile(dense: true, title: Text(k), trailing: Text(_dur(perDay[k]!))),
        ],
        const SizedBox(height: 8),
        Text(
          'Tap an app to set a daily timer: when it runs out the app is closed for the rest of the day. Android only keeps about a week of usage, so Focus Reels saves each day here as it goes.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ]),
    );
  }
}

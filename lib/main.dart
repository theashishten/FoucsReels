import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'apps_usage.dart';
import 'calibrate.dart';
import 'position.dart';
import 'insights.dart';
import 'setup.dart';
import 'social.dart';
import 'theme.dart';
import 'updater.dart';
import 'counter_style.dart';

void main() => runApp(const FocusReelsApp());

const _ch = MethodChannel('focus_reels');

/// Browsers whose Shorts/Reels are counted (when "Count Shorts in browsers" is on).
const webApps = <String, String>{
  'com.android.chrome': 'Chrome (web Shorts)',
  'com.sec.android.app.sbrowser': 'Samsung Internet (web Shorts)',
  'com.brave.browser': 'Brave (web Shorts)',
  'com.microsoft.emmx': 'Edge (web Shorts)',
  'org.mozilla.firefox': 'Firefox (web Shorts)',
  'com.opera.browser': 'Opera (web Shorts)',
};

String appName(String pkg) => apps[pkg] ?? webApps[pkg] ?? pkg;

const apps = <String, String>{
  'com.instagram.android': 'Instagram Reels',
  'com.google.android.youtube': 'YouTube Shorts',
  'com.zhiliaoapp.musically': 'TikTok',
  'com.ss.android.ugc.trill': 'TikTok (alt)',
  'com.snapchat.android': 'Snapchat Spotlight',
  'com.facebook.katana': 'Facebook Reels (not supported yet)',
  'com.netflix.mediaclient': 'Netflix clips',
};

class FocusReelsApp extends StatelessWidget {
  const FocusReelsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Focus Reels',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Shell(),
      );
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Snapshot of native state, parsed from the JSON the Android side returns.
class AppState {
  AppState(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get config => Map<String, dynamic>.from(raw['config']);
  Map<String, dynamic> get today => Map<String, dynamic>.from(raw['today']);
  Map<String, dynamic> get status => Map<String, dynamic>.from(raw['status']);
  Map<String, dynamic> get history => Map<String, dynamic>.from(raw['history']);

  /// Per-day detail (per-app, hourly, watch time) for every past day, kept forever.
  Map<String, dynamic> get daily => Map<String, dynamic>.from(raw['daily'] ?? {});
  bool get a11y => raw['a11y'] == true;
  bool get usage => raw['usage'] == true;
  Map<String, dynamic> get social => Map<String, dynamic>.from(raw['social'] ?? {});
  int get estimated => (today['estimated'] ?? 0) as int;
  String get lastEvent => raw['lastEvent'] as String? ?? '';
  String get firstDay => raw['firstDay'] as String? ?? '';
  int get now => raw['now'] as int;
  int get total => (today['total'] ?? 0) as int;
  /// Track-only is the default: just count reels, never limit or block on its own.
  bool get trackOnly => config['trackOnly'] != false;
  int get limit => (trackOnly || plan != 'limits') ? 0 : (config['dailyLimit'] ?? 0) as int;

  /// Average reels per day over the last 7 days (only days since the app was first used).
  double get avg7 {
    final first = DateTime.tryParse(firstDay);
    var n = 0, sum = 0;
    for (var i = 0; i < 7; i++) {
      final d = nowDate.subtract(Duration(days: i));
      if (first != null && DateTime(d.year, d.month, d.day).isBefore(first)) break;
      sum += totalOn(d);
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }
  int get skimmed => (today['skimmed'] ?? 0) as int;
  int get blocks => (today['blocks'] ?? 0) as int;
  int get watchMin => (((today['watchMs'] ?? 0) as num) / 60000).round();
  String get pin => (config['buddyPin'] ?? '') as String;

  /// Current plan: track, limits (your own rules), blockAll, oneReel, curious or paused.
  String get plan {
    final p = (config['plan'] ?? 'none') as String;
    if (p == 'paused') return 'paused';
    if (trackOnly) return 'track';
    return p == 'none' ? 'limits' : p;
  }

  /// Every block that happened, oldest first: {t, pkg, why, act}.
  List<Map<String, dynamic>> get blockLog {
    try {
      final l = jsonDecode((raw['blockLog'] ?? '[]') as String) as List;
      return [for (final e in l) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }
  List<int> get hourly =>
      ((today['hourly'] ?? List.filled(24, 0)) as List).cast<int>();
  List<int> get peakHours {
    final a = (raw['agg'] as Map?)?['hours'];
    return a == null ? List.filled(24, 0) : (a as List).cast<int>();
  }

  /// Today's screen time and scroll bursts per app, busiest first: (label, minutes, scrolls).
  List<(String, int, int)> get screenApps {
    final apps = (raw['screen'] as Map?)?['apps'] as Map? ?? {};
    final l = <(String, int, int)>[
      for (final v in apps.values)
        ((v['label'] ?? '') as String, (((v['ms'] ?? 0) as num) / 60000).round(), (v['scrolls'] ?? 0) as int)
    ];
    l.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : b.$3.compareTo(a.$3));
    return l;
  }

  Map<String, dynamic> get perApp =>
      Map<String, dynamic>.from(today['perApp'] ?? {});

  int remainingMs(String key) {
    final until = (status[key] ?? 0) as int;
    return until > now ? until - now : 0;
  }

  DateTime get nowDate => DateTime.fromMillisecondsSinceEpoch(now);

  int totalOn(DateTime d) {
    if (dayKey(d) == dayKey(nowDate)) return total;
    return (history[dayKey(d)] ?? 0) as int;
  }

  /// Consecutive days (ending today) at or under the daily limit, back to the first day of use.
  int get streak {
    if (limit <= 0 || firstDay.isEmpty) return 0;
    final first = DateTime.tryParse(firstDay);
    if (first == null) return 0;
    var n = 0;
    for (var i = 0; i < 365; i++) {
      final d = nowDate.subtract(Duration(days: i));
      if (DateTime(d.year, d.month, d.day).isBefore(first)) break;
      if (totalOn(d) > limit) break;
      n++;
    }
    return n;
  }
}

String fmt(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

Future<String?> promptText(BuildContext c, String title, String hint) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  AppState? s;
  Perms? perms;
  bool showSetup = false;
  int tab = 0;
  Timer? _timer;
  Timer? _netTimer;
  late final SocialCtl soc = SocialCtl(
    () {
      if (mounted) setState(() {});
    },
    () => context,
    () => s?.social ?? {},
    () => s?.config ?? {},
    saveConfig,
    _localDays,
  );

  /// Last 7 days of totals (history plus today) in the shape the server expects.
  Map<String, int> _localDays() {
    final st = s;
    if (st == null) return {};
    final out = <String, int>{};
    for (var i = 0; i < 7; i++) {
      final d = st.nowDate.subtract(Duration(days: i));
      out[dayKey(d)] = st.totalOn(d);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh().then((_) => soc.refresh());
    // Look for a new version once per launch (can be switched off in Health).
    Updates.loadCurrent().then((_) async {
      await refresh();
      if (s?.config['autoUpdate'] != false) Updates.check(api: (s?.config['updateApi'] ?? defaultUpdateApi) as String);
    });
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    _netTimer = Timer.periodic(const Duration(seconds: 10), (_) => soc.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _netTimer?.cancel();
    super.dispose();
  }

  /// Asks for whatever protection is active: the remote buddy's approval, else the PIN, else allows.
  Future<bool> guard(String what) async {
    if (soc.remoteBuddy) return soc.approval(what);
    return pinOk();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    final j = await _ch.invokeMethod<String>('getState');
    if (!mounted || j == null) return;
    final p = await Perms.load();
    if (!mounted) return;
    setState(() {
      s = AppState(jsonDecode(j) as Map<String, dynamic>);
      perms = p;
    });
  }

  /// True if no buddy PIN is set, or the user enters it correctly.
  Future<bool> pinOk() async {
    final pin = s?.pin ?? '';
    if (pin.isEmpty) return true;
    final got = await promptText(context, 'Buddy PIN', 'Ask your buddy for the PIN');
    if (got == pin) return true;
    if (got != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wrong PIN')));
    }
    return false;
  }

  /// A change "weakens" the rules if it makes blocking easier to avoid.
  bool weakens(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Switching from "Limit & block" to "Track only" turns every limit off.
    if (a['trackOnly'] == false && b['trackOnly'] != false) return true;
    final la = (a['dailyLimit'] ?? 0) as int, lb = (b['dailyLimit'] ?? 0) as int;
    if (la > 0 && (lb == 0 || lb > la)) return true;
    if (a['blockEnabled'] == true && b['blockEnabled'] != true) return true;
    if (a['strict'] == true && b['strict'] != true) return true;
    // Moving to a plan that blocks less (for example Block all to Paused) loosens the rules.
    int strength(Map<String, dynamic> c) {
      if (c['plan'] == 'paused') return -1;
      if (c['trackOnly'] != false) return 0;
      switch (c['plan']) {
        case 'blockAll':
          return 4;
        case 'oneReel':
          return 3;
        case 'curious':
          return 2;
        default:
          return 1;
      }
    }

    if (strength(a) > 0 && strength(b) < strength(a)) return true;
    if (a['blockBrowser'] == true && b['blockBrowser'] != true) return true;
    // Turning off "always block" or "hide tab" for an app loosens it.
    final aa = Map<String, dynamic>.from((a['apps'] ?? {}) as Map);
    final ab = Map<String, dynamic>.from((b['apps'] ?? {}) as Map);
    for (final e in aa.entries) {
      final x = Map<String, dynamic>.from(e.value as Map);
      final y = Map<String, dynamic>.from((ab[e.key] ?? {}) as Map);
      for (final k in ['alwaysBlock', 'hideTab']) {
        if (x[k] == true && y[k] != true) return true;
      }
    }
    // Removing or raising an app timer loosens it too.
    final ta = Map<String, dynamic>.from((a['appTimers'] ?? {}) as Map);
    final tb = Map<String, dynamic>.from((b['appTimers'] ?? {}) as Map);
    for (final e in ta.entries) {
      final nv = (tb[e.key] ?? 0) as int;
      if ((e.value as int) > 0 && (nv == 0 || nv > (e.value as int))) return true;
    }
    final sa = (a['schedules'] ?? []) as List, sb = (b['schedules'] ?? []) as List;
    if (sb.length < sa.length) return true;
    for (var i = 0; i < sa.length && i < sb.length; i++) {
      if (sa[i]['on'] == true && sb[i]['on'] != true) return true;
    }
    return false;
  }

  Future<void> saveConfig(Map<String, dynamic> cfg) async {
    final cur = s;
    if (cur != null && weakens(cur.config, cfg) && !await guard('loosen their blocking rules')) {
      await refresh();
      return;
    }
    await _ch.invokeMethod('setConfig', jsonEncode(cfg));
    await refresh();
  }

  List<String> _titles(bool friends) =>
      ['Today', 'Stats', 'Apps', if (friends) 'Friends', 'Rules', 'Health'];

  @override
  Widget build(BuildContext context) {
    final st = s;
    if (st == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pm = perms;
    final skipped = st.config['setupSkipped'] == true;
    if (pm != null && !pm.ready && (!skipped || showSetup)) {
      return Scaffold(
        body: SetupPage(
          onDone: () => setState(() => showSetup = false),
          onSkip: () async {
            setState(() => showSetup = false);
            await saveConfig({...st.config, 'setupSkipped': true});
          },
        ),
      );
    }
    if (showSetup) {
      return Scaffold(
        body: SetupPage(onDone: () => setState(() => showSetup = false), onSkip: () => setState(() => showSetup = false)),
      );
    }
    // Friends, duels and the remote buddy need a server, so the tab is hidden unless switched on in Health.
    final showFriends = st.config['friends'] == true;
    final pages = [
      TodayPage(st, refresh, () => guard('pause blocking for 5 minutes'), saveConfig,
          soc.remoteBuddy),
      InsightsPage(st),
      AppsPage(st.config, saveConfig),
      if (showFriends) FriendsPage(soc),
      RulesPage(st, saveConfig, refresh, () => guard('remove the PIN')),
      HealthPage(st, refresh, saveConfig, () => guard('reset today\'s blocks'), perms),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 24,
        title: Text(_titles(showFriends)[tab.clamp(0, pages.length - 1)]),
      ),
      body: Column(children: [
        ValueListenableBuilder<UpdateInfo?>(
          valueListenable: Updates.available,
          builder: (context, u, _) => u == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => showUpdateDialog(context, u),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: context.cs.secondaryContainer,
                      ),
                      child: Row(children: [
                        Icon(Icons.system_update, color: context.cs.onSecondaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Update available: ${u.version}',
                              style: TextStyle(color: context.cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                        ),
                        Text('Update', style: TextStyle(color: context.cs.onSecondaryContainer, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
        ),
        if (pm != null && !pm.ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() => showSetup = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: context.cs.primaryContainer,
                ),
                child: Row(children: [
                  Icon(Icons.shield_outlined, color: context.cs.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Finish setup - ${pm.missing} permission${pm.missing == 1 ? '' : 's'} left',
                        style: TextStyle(color: context.cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.chevron_right, color: context.cs.onPrimaryContainer),
                ]),
              ),
            ),
          ),
        Expanded(child: pages[tab.clamp(0, pages.length - 1)]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.clamp(0, pages.length - 1),
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Today'),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Apps'),
          if (showFriends)
            const NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Friends'),
          const NavigationDestination(icon: Icon(Icons.tune), label: 'Rules'),
          const NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Health'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Today

class TodayPage extends StatelessWidget {
  const TodayPage(this.s, this.refresh, this.pinOk, this.save, this.remote, {super.key});
  final bool remote;
  final AppState s;
  final Future<void> Function() refresh;
  final Future<bool> Function() pinOk;
  final Future<void> Function(Map<String, dynamic>) save;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final over = s.limit > 0 && s.total >= s.limit;
    final progress = s.limit == 0 ? 0.0 : (s.total / s.limit).clamp(0.0, 1.0);
    final hard = s.remainingMs('hardBlockUntil');
    final cool = s.remainingMs('blockedUntil');
    final paused = s.remainingMs('pausedUntil');
    final streak = s.streak;
    final tint = [cs.primary, cs.tertiary, cs.secondary, cs.outline, cs.error];
    final shown = [
      for (final k in [...apps.keys, ...webApps.keys])
        if (((s.perApp[k] ?? 0) as num) > 0) k
    ]..sort((a, b) => ((s.perApp[b] ?? 0) as num).compareTo((s.perApp[a] ?? 0) as num));
    Color colorOf(String pkg) => tint[shown.indexOf(pkg).clamp(0, tint.length - 1)];
    final totalApps = shown.fold<num>(0, (a, p) => a + (s.perApp[p] as num));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Glass(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(children: [
          GradientRing(
            size: 230,
            stroke: 26,
            value: progress,
            colors: [over ? cs.error : cs.primary],
            segments: s.limit == 0 && totalApps > 0
                ? [for (final p in shown) ((s.perApp[p] as num) / totalApps, colorOf(p))]
                : null,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${s.total}',
                  style: (s.total >= 1000
                          ? Theme.of(context).textTheme.displayMedium
                          : Theme.of(context).textTheme.displayLarge)
                      ?.copyWith(color: cs.onSurface)),
              Text(s.limit == 0 ? 'reels today' : 'of ${s.limit} reels',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 6, children: [
              for (final p in shown)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(p), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(appName(p), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ]),
            ]),
          ],
          if (streak > 0 || s.estimated > 0 || s.blocks > 0) ...[
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
              if (streak > 0)
                Chip(
                    avatar: Icon(Icons.local_fire_department, size: 18, color: cs.primary),
                    label: Text('$streak day streak')),
              if (s.estimated > 0)
                Chip(avatar: const Icon(Icons.auto_graph, size: 18), label: Text('~${s.estimated} estimated')),
              if (s.blocks > 0)
                Chip(avatar: Icon(Icons.block, size: 18, color: cs.error), label: Text('${s.blocks} blocked')),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      _planCard(context),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: StatTile(icon: Icons.timer_outlined, value: '${s.watchMin}m', label: 'watched', color: cs.primary)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.show_chart, value: '${s.avg7.round()}', label: 'avg / day', color: cs.secondary)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.fast_forward, value: '${s.skimmed}', label: 'skimmed', color: cs.tertiary)),
      ]),
      const SizedBox(height: 10),
      Glass(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final days = [for (var i = 6; i >= 0; i--) s.nowDate.subtract(Duration(days: i))];
            final vals = [for (final d in days) s.totalOn(d)];
            final top = vals.fold<int>(1, (a, b) => b > a ? b : a);
            const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
            return SizedBox(
              height: 120,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(vals[i] > 0 ? '${vals[i]}' : '',
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        height: 6 + 70 * vals[i] / top,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: i == 6 ? cs.primary : cs.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(letters[days[i].weekday - 1],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w400,
                              color: i == 6 ? cs.onSurface : cs.onSurfaceVariant)),
                    ]),
                  ),
              ]),
            );
          }),
        ]),
      ),
      const SizedBox(height: 10),
      Glass(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('By app', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final p in shown)
            AppRow(
              pkg: p,
              name: appName(p),
              value: '${s.perApp[p]}',
              fraction: ((s.perApp[p] as num) / (s.total == 0 ? 1 : s.total)).toDouble(),
              color: colorOf(p),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No reels counted yet today.', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        if (!s.trackOnly) ...[
        Expanded(child: OutlinedButton.icon(
          icon: const Icon(Icons.pause_circle_outline),
          label: const Text('Pause 5 min'),
          onPressed: () async {
            if (!await pinOk()) return;
            // A buddy-approved pause is allowed even in strict mode or during a hard block.
            final ok = remote
                ? await _ch
                    .invokeMethod('forcePause', {'minutes': 5})
                    .then((_) => true)
                : await _ch.invokeMethod<bool>('pause', {'minutes': 5});
            if (ok != true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Pausing is disabled (strict mode or hard block).')));
            }
            refresh();
          },
        )),
        const SizedBox(width: 10),
        ],
        Expanded(child: GradButton(
          icon: Icons.lock_outline,
          label: 'Hard block 30 min',
          onPressed: () async {
            await _ch.invokeMethod('hardBlock', {'minutes': 30});
            refresh();
          },
        )),
      ]),
      const SizedBox(height: 16),
    ]);
  }

  static const _plans = <(String, String, IconData, String)>[
    ('track', 'Track only', Icons.insights, 'Just count your reels. Nothing is blocked.'),
    ('limits', 'My limits', Icons.tune, 'Block using the daily limit, schedules and window set in Rules.'),
    ('blockAll', 'Block all', Icons.block, 'Reels and Shorts close the moment you open them.'),
    ('oneReel', 'One reel', Icons.looks_one_outlined, 'Watch one reel, then reels close for a break.'),
    ('curious', 'Curious', Icons.timer_outlined, 'Watch for a few minutes, then reels close for a break.'),
    ('paused', 'Paused', Icons.pause_circle_outline, 'Blocking is off for now. Reels are still counted.'),
  ];

  void _setPlan(String p) {
    final c = {...s.config};
    switch (p) {
      case 'track':
        c['trackOnly'] = true;
        c['plan'] = 'none';
      case 'limits':
        c['trackOnly'] = false;
        c['plan'] = 'none';
        c['blockEnabled'] = true;
        if (((c['dailyLimit'] ?? 0) as int) == 0) c['dailyLimit'] = 100;
      case 'paused':
        c['plan'] = 'paused';
      default:
        c['trackOnly'] = false;
        c['plan'] = p;
        c['blockEnabled'] = true;
    }
    save(c);
  }

  Widget _planCard(BuildContext context) {
    final cs = context.cs;
    final cur = s.plan;
    final info = _plans.firstWhere((e) => e.$1 == cur);
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Plan', style: Theme.of(context).textTheme.titleMedium),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in _plans)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(p.$3, size: 18, color: cur == p.$1 ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                  label: Text(p.$2),
                  selected: cur == p.$1,
                  showCheckmark: false,
                  selectedColor: cs.secondaryContainer,
                  onSelected: (_) => _setPlan(p.$1),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(info.$4, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
        ),
      ]),
    );
  }

  Widget _status(IconData i, String t, Color col) => Card(
        child: ListTile(leading: Icon(i, color: col), title: Text(t)),
      );

  Widget _suggestion(BuildContext context) {
    final next = (s.limit * 0.9).round().clamp(5, s.limit - 1);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.trending_down),
        title: Text('Nice streak! Try a limit of $next?'),
        subtitle: Text('You have stayed under ${s.limit} for ${s.streak} days.'),
        trailing: TextButton(
          onPressed: () => save({...s.config, 'dailyLimit': next}),
          child: const Text('Apply'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Rules

class RulesPage extends StatelessWidget {
  const RulesPage(this.s, this.save, this.refresh, this.pinOk, {super.key});
  final AppState s;
  final Future<void> Function(Map<String, dynamic>) save;
  final Future<void> Function() refresh;
  final Future<bool> Function() pinOk;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final cfg = s.config;
    final schedules = ((cfg['schedules'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    final appCfg = Map<String, dynamic>.from(cfg['apps'] ?? {});
    void set(String k, Object v) => save({...cfg, k: v});
    int num(String k, int d) => (cfg[k] ?? d) as int;
    final track = s.trackOnly;

    void setMode(bool toTrack) {
      // Moving to "Limit & block" with no limit set would limit nothing, so start from a sensible number.
      final dl = (cfg['dailyLimit'] ?? 0) as int;
      save({
        ...cfg,
        'trackOnly': toTrack,
        if (!toTrack && dl == 0) 'dailyLimit': 100,
        if (!toTrack) 'blockEnabled': true,
      });
    }

    Future<void> addSchedule(int a, int b) async =>
        set('schedules', [...schedules, {'start': a, 'end': b, 'days': 127, 'on': true}]);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ChoiceCard(
          icon: Icons.insights,
          title: 'Track only',
          body: 'Just count your reels. Nothing is blocked.',
          selected: track,
          onTap: () => setMode(true),
        ),
        const SizedBox(width: 10),
        ChoiceCard(
          icon: Icons.shield_outlined,
          title: 'Limit & block',
          body: 'Set your own limits and block reels.',
          selected: !track,
          onTap: () => setMode(false),
        ),
      ]),
      if (!track) ...[
        _limitCard(context, num('dailyLimit', 100), (v) => set('dailyLimit', v)),
        if (cfg['plan'] == 'curious')
          Section('Curious plan', [
            SliderTile(
              icon: Icons.timer_outlined,
              title: 'Watch for',
              value: num('curiousOn', 5),
              min: 1,
              max: 30,
              unit: ' min',
              onEnd: (v) => set('curiousOn', v),
            ),
            SliderTile(
              title: 'Then a break of',
              value: num('curiousOff', 30),
              min: 5,
              max: 180,
              unit: ' min',
              onEnd: (v) => set('curiousOff', v),
            ),
          ], footer: 'The timer starts with your first reel after a quiet spell.'),
        if (cfg['plan'] == 'oneReel')
          Section('One reel plan', [
            SliderTile(
              icon: Icons.looks_one_outlined,
              title: 'Break after your reel',
              value: num('planCooldown', 30),
              min: 5,
              max: 180,
              unit: ' min',
              onEnd: (v) => set('planCooldown', v),
            ),
          ]),
        Section('Blocking', [
          SwitchTile(
            icon: Icons.block,
            title: 'Blocking enabled',
            subtitle: 'Master switch for every block below',
            value: cfg['blockEnabled'] == true,
            onChanged: (v) => set('blockEnabled', v),
          ),
          SwitchTile(
            icon: Icons.lock_outline,
            title: 'Strict mode',
            subtitle: 'No pausing while a block is active',
            value: cfg['strict'] == true,
            onChanged: (v) => set('strict', v),
          ),
        ]),
        Section('Allowance window', [
          SliderTile(
            icon: Icons.local_cafe_outlined,
            title: 'Reels per window',
            value: num('windowAllowed', 0),
            min: 0,
            max: 30,
            zero: 'Off',
            onEnd: (v) => set('windowAllowed', v),
          ),
          SliderTile(
            title: 'Window length',
            value: num('windowMinutes', 5),
            min: 1,
            max: 60,
            unit: ' min',
            onEnd: (v) => set('windowMinutes', v),
          ),
          SliderTile(
            title: 'Cooldown after going over',
            value: num('cooldownMinutes', 30),
            min: 1,
            max: 240,
            unit: ' min',
            onEnd: (v) => set('cooldownMinutes', v),
          ),
        ], footer: 'Allow a few reels per window; going over starts a cooldown. Reels per window "Off" turns this off.'),
        Section('Scheduled blocks', [
          for (var i = 0; i < schedules.length; i++)
            _scheduleTile(context, i, schedules, (l) => set('schedules', l)),
          Tile(
            icon: Icons.bedtime_outlined,
            bg: cs.tertiaryContainer,
            fg: cs.onTertiaryContainer,
            title: 'Bedtime 11 pm - 7 am',
            subtitle: 'Add a ready-made overnight block',
            trailing: Icon(Icons.add, color: cs.onSurfaceVariant),
            onTap: () => addSchedule(23 * 60, 7 * 60),
          ),
          Tile(
            icon: Icons.schedule,
            bg: cs.tertiaryContainer,
            fg: cs.onTertiaryContainer,
            title: 'Custom time',
            subtitle: 'Pick when reels are blocked',
            trailing: Icon(Icons.add, color: cs.onSurfaceVariant),
            onTap: () async {
              final a = await showTimePicker(
                  context: context, initialTime: const TimeOfDay(hour: 22, minute: 0), helpText: 'Block from');
              if (a == null || !context.mounted) return;
              final b = await showTimePicker(
                  context: context, initialTime: const TimeOfDay(hour: 7, minute: 0), helpText: 'Block until');
              if (b == null) return;
              addSchedule(a.hour * 60 + a.minute, b.hour * 60 + b.minute);
            },
          ),
        ]),
        Section('Accountability buddy', [
          s.pin.isEmpty
              ? Tile(
                  icon: Icons.lock_outline,
                  title: 'Set a buddy PIN',
                  subtitle: 'Have a friend choose it, so you cannot loosen your own rules',
                  trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  onTap: () async {
                    final a = await promptText(context, 'New PIN (4+ digits)', 'PIN');
                    if (a == null || a.length < 4 || !context.mounted) return;
                    final b = await promptText(context, 'Repeat the PIN', 'PIN');
                    if (b == a) {
                      set('buddyPin', a);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('PINs did not match')));
                    }
                  },
                )
              : Tile(
                  icon: Icons.lock_open,
                  bg: cs.errorContainer,
                  fg: cs.onErrorContainer,
                  title: 'Remove the buddy PIN',
                  subtitle: 'Needs the current PIN',
                  trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  onTap: () async {
                    if (await pinOk()) set('buddyPin', '');
                  },
                ),
        ], footer: 'Without the PIN you cannot pause, switch blocking off, raise limits or remove schedules.'),
      ],
      Section('Counting', [
        SwitchTile(
          icon: Icons.history,
          title: 'Count reels you go back to',
          subtitle: 'Off: swiping back to a reel you already saw does not add to the count (Instagram, YouTube, Snapchat, Netflix)',
          value: cfg['countBack'] == true,
          onChanged: (v) => set('countBack', v),
        ),
        Tile(
          icon: Icons.palette_outlined,
          title: 'Counter style',
          subtitle: 'Dark, light, glass, transparent or colour. Size and opacity too',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CounterStylePage(cfg: cfg, save: save))),
        ),
        Tile(
          icon: Icons.open_with,
          title: 'Counter position',
          subtitle: 'Or press and hold the counter while you watch, then drag it',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CounterPositionPage(cfg: cfg, save: save))),
        ),
      ]),
      Section('Mindfulness', [
        SliderTile(
          icon: Icons.self_improvement,
          title: 'Pause before reels',
          value: num('frictionSeconds', 0),
          min: 0,
          max: 30,
          zero: 'Off',
          unit: ' sec',
          onEnd: (v) => set('frictionSeconds', v),
        ),
        SwitchTile(
          icon: Icons.pin_drop_outlined,
          title: 'Live counter',
          subtitle: 'A small count over the reel app. Press and hold it to move it',
          value: cfg['bubble'] != false,
          onChanged: (v) => set('bubble', v),
        ),
        SwitchTile(
          icon: Icons.psychology_alt_outlined,
          title: 'Reflect after long sessions',
          subtitle: 'Name 3 reels after 10 or more in a row',
          value: cfg['reflect'] != false,
          onChanged: (v) => set('reflect', v),
        ),
        SwitchTile(
          icon: Icons.summarize_outlined,
          title: 'Daily recap at 9 pm',
          subtitle: 'Reels, screen time and unlocks',
          value: cfg['summary'] != false,
          onChanged: (v) => set('summary', v),
        ),
      ], footer: 'After 5 or more minutes away from reels, "Pause before reels" makes you wait before scrolling again.'),
      Section('When a block happens', [
        Tile(
          icon: Icons.exit_to_app,
          title: 'Default action',
          subtitle: 'What Focus Reels does to a reel app when it blocks it',
          trailing: Text(actionLabel(cfg['blockAction'] as String?),
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
          onTap: () async {
            final v = await pickAction(context, (cfg['blockAction'] ?? 'back') as String, allowDefault: false);
            if (v != null) set('blockAction', v);
          },
        ),
      ], footer: 'Each app below can use its own action instead.'),
      Section('Browsers', [
        SwitchTile(
          icon: Icons.analytics_outlined,
          title: 'Count Shorts & Reels in browsers',
          subtitle: 'Each new YouTube Short you open in Chrome and other browsers adds to your count',
          value: cfg['countBrowser'] == true,
          onChanged: (v) => set('countBrowser', v),
        ),
        SwitchTile(
          icon: Icons.language,
          title: 'Block Shorts & Reels in browsers',
          subtitle: 'YouTube Shorts and Instagram Reels opened on the web',
          value: cfg['blockBrowser'] == true,
          onChanged: (v) => set('blockBrowser', v),
        ),
      ], footer: 'Only while one of these is on, Focus Reels reads the address bar of Chrome, Samsung Internet, Brave, Edge, Firefox and Opera to spot a Shorts or Reels link. Nothing is stored or sent.'),
      Section('Detection', [
        Tile(
          icon: Icons.build_circle_outlined,
          title: 'Detection rules',
          subtitle: 'Fix counting if an app update breaks it',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalibratePage())),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 8),
        child: Text('Apps',
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.3)),
      ),
      for (final e in apps.entries) _appCard(context, e.key, e.value, appCfg, (m) => set('apps', m), limits: !track),
    ]);
  }

  /// Big number and slider for the daily limit, with one-tap presets.
  Widget _limitCard(BuildContext context, int limit, void Function(int) onEnd) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: _LimitBody(limit: limit, onEnd: onEnd),
      ),
    );
  }

  String _t(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Widget _scheduleTile(BuildContext c, int i, List<Map<String, dynamic>> all,
      void Function(List<Map<String, dynamic>>) put) {
    final cs = c.cs;
    final sc = all[i];
    const names = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: cs.tertiaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.bedtime_outlined, size: 20, color: cs.onTertiaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text('${_t(sc['start'] as int)} - ${_t(sc['end'] as int)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          ),
          Switch(
            value: sc['on'] == true,
            onChanged: (v) => put([for (var j = 0; j < all.length; j++) j == i ? {...sc, 'on': v} : all[j]]),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
            onPressed: () => put([for (var j = 0; j < all.length; j++) if (j != i) all[j]]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var d = 0; d < 7; d++)
            GestureDetector(
              onTap: () => put([
                for (var j = 0; j < all.length; j++) j == i ? {...sc, 'days': (sc['days'] as int) ^ (1 << d)} : all[j]
              ]),
              child: Container(
                width: 38, height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ((sc['days'] as int) & (1 << d)) != 0 ? cs.primary : cs.surfaceContainerHighest,
                ),
                child: Text(names[d],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: ((sc['days'] as int) & (1 << d)) != 0 ? cs.onPrimary : cs.onSurfaceVariant,
                    )),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _appCard(BuildContext c, String pkg, String name, Map<String, dynamic> appCfg,
      void Function(Map<String, dynamic>) put,
      {bool limits = true}) {
    final cs = c.cs;
    final a = Map<String, dynamic>.from(appCfg[pkg] ?? {});
    final enabled = a['enabled'] != false;
    final limit = (a['limit'] ?? 0) as int;
    final always = a['alwaysBlock'] == true;
    final hasTab = pkg == 'com.instagram.android' || pkg == 'com.google.android.youtube';
    void setA(String k, Object v) => put({...appCfg, pkg: {...a, k: v}});
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Section(null, [
        Tile(
          leading: AppIcon(pkg, size: 40),
          title: name,
          subtitle: enabled ? 'Counting reels' : 'Not counted',
          trailing: Switch(value: enabled, onChanged: (v) => setA('enabled', v)),
          onTap: () => setA('enabled', !enabled),
        ),
        if (enabled) ...[
          SwitchTile(
            icon: Icons.block,
            bg: cs.errorContainer,
            fg: cs.onErrorContainer,
            title: 'Always block reels',
            subtitle: 'They close the moment you open them',
            value: always,
            onChanged: (v) => setA('alwaysBlock', v),
          ),
          Tile(
            icon: Icons.exit_to_app,
            title: 'When blocked',
            subtitle: 'What happens to this app',
            trailing: Text(actionLabel(a['blockAction'] as String?, fallback: 'Default'),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            onTap: () async {
              final v = await pickAction(c, (a['blockAction'] ?? '') as String, allowDefault: true);
              if (v != null) setA('blockAction', v);
            },
          ),
          if (hasTab)
            SwitchTile(
              icon: Icons.visibility_off_outlined,
              title: 'Hide the ${pkg.endsWith('youtube') ? 'Shorts' : 'Reels'} tab',
              subtitle: 'Covers the tab button so it cannot be tapped',
              value: a['hideTab'] == true,
              onChanged: (v) => setA('hideTab', v),
            ),
          if (hasTab)
            SwitchTile(
              icon: Icons.home_outlined,
              title: 'Open to a safe page',
              subtitle: pkg.endsWith('youtube')
                  ? 'Start YouTube on your Subscriptions, not the home feed'
                  : 'Start Instagram on your messages, not the feed',
              value: a['safeLaunch'] == true,
              onChanged: (v) => setA('safeLaunch', v),
            ),
          if (limits && !always)
            SliderTile(
              icon: Icons.speed,
              title: 'Daily limit for this app',
              value: limit,
              min: 0,
              max: 500,
              zero: 'None',
              onEnd: (v) => setA('limit', v),
            ),
        ],
      ]),
    );
  }
}

class _LimitBody extends StatefulWidget {
  const _LimitBody({required this.limit, required this.onEnd});
  final int limit;
  final void Function(int) onEnd;

  @override
  State<_LimitBody> createState() => _LimitBodyState();
}

class _LimitBodyState extends State<_LimitBody> {
  late double cur = widget.limit.toDouble();

  @override
  void didUpdateWidget(_LimitBody old) {
    super.didUpdateWidget(old);
    if (old.limit != widget.limit) cur = widget.limit.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(children: [
      Text('Daily limit', style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text(cur.round() == 0 ? 'Off' : '${cur.round()}', style: Theme.of(context).textTheme.displayMedium),
      Text(cur.round() == 0 ? 'no daily limit' : 'reels per day', style: TextStyle(color: cs.onSurfaceVariant)),
      Slider(
        value: cur.clamp(0, 1000),
        min: 0,
        max: 1000,
        onChanged: (x) => setState(() => cur = x),
        onChangeEnd: (x) => widget.onEnd(x.round()),
      ),
      Wrap(spacing: 8, children: [
        for (final p in const [0, 25, 50, 100, 200, 300])
          ChoiceChip(
            label: Text(p == 0 ? 'Off' : '$p'),
            selected: cur.round() == p,
            onSelected: (_) {
              setState(() => cur = p.toDouble());
              widget.onEnd(p);
            },
          ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- Health

class HealthPage extends StatelessWidget {
  const HealthPage(this.s, this.refresh, this.save, this.pinOk, this.perms, {super.key});
  final AppState s;
  final Perms? perms;
  final Future<void> Function() refresh;
  final Future<void> Function(Map<String, dynamic>) save;
  final Future<bool> Function() pinOk;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    void toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    final p = perms;
    final missing = p?.missing ?? (s.a11y ? 0 : 1);
    final healthy = missing == 0 && s.a11y;

    Widget status(bool ok, VoidCallback fix) => ok
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(100)),
            child: Text('On', style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
          )
        : FilledButton.tonal(
            onPressed: fix,
            style: FilledButton.styleFrom(minimumSize: const Size(72, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Allow'),
          );

    Tile perm(IconData icon, String title, String sub, bool ok, String method) => Tile(
          icon: icon,
          bg: ok ? cs.secondaryContainer : cs.errorContainer,
          fg: ok ? cs.onSecondaryContainer : cs.onErrorContainer,
          title: title,
          subtitle: sub,
          trailing: status(ok, () => _ch.invokeMethod(method)),
          onTap: ok ? null : () => _ch.invokeMethod(method),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: healthy ? cs.secondaryContainer : cs.errorContainer,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: healthy ? cs.secondary : cs.error, shape: BoxShape.circle),
            child: Icon(healthy ? Icons.verified_user : Icons.warning_amber_rounded,
                color: healthy ? cs.onSecondary : cs.onError, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(healthy ? 'Everything is running' : '$missing thing${missing == 1 ? '' : 's'} need attention',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: healthy ? cs.onSecondaryContainer : cs.onErrorContainer)),
              const SizedBox(height: 4),
              Text(
                  healthy
                      ? 'Reels are being counted in the background.'
                      : 'Allow the items below so counting never stops.',
                  style: TextStyle(
                      height: 1.35,
                      color: (healthy ? cs.onSecondaryContainer : cs.onErrorContainer).withValues(alpha: 0.8))),
            ]),
          ),
        ]),
      ),
      Section('Permissions', [
        perm(Icons.accessibility_new, 'Accessibility', 'Sees when a reel is on screen', s.a11y, 'openAccessibilitySettings'),
        perm(Icons.layers_outlined, 'Display over other apps', 'Live counter and block screen',
            p?.overlay ?? true, 'openOverlaySettings'),
        perm(Icons.notifications_outlined, 'Notifications', 'Limit warnings and your daily recap',
            p?.notifications ?? true, 'requestNotifications'),
        perm(Icons.battery_charging_full, 'Run in the background', 'Stops the phone putting the app to sleep',
            p?.battery ?? true, 'requestBattery'),
        perm(Icons.data_usage, 'Usage access', 'Screen time for all apps and the backup counter', s.usage,
            'openUsageSettings'),
      ]),
      Section('Backup counter', [
        SwitchTile(
          icon: Icons.mic_none,
          title: 'Use the backup counter',
          subtitle: 'Estimates reels from time with a reel app open and audio playing',
          value: s.config['fallback'] == true,
          onChanged: (v) async {
            await _ch.invokeMethod('setFallback', {'on': v});
            refresh();
          },
        ),
        if (s.config['fallback'] == true)
          SliderTile(
            title: 'Seconds per reel',
            value: (s.config['estSeconds'] ?? 25) as int,
            min: 10,
            max: 60,
            unit: ' s',
            onEnd: (v) => save({...s.config, 'estSeconds': v}),
          ),
      ], footer: 'It cannot block anything, and it stands down whenever Accessibility is on.'),
      Section('Features', [
        SwitchTile(
          icon: Icons.group_outlined,
          title: 'Friends, duels and remote buddy',
          subtitle: 'Needs a server you host. Off by default',
          value: s.config['friends'] == true,
          onChanged: (v) => save({...s.config, 'friends': v}),
        ),
        const Tile(
          icon: Icons.dashboard_customize_outlined,
          title: 'Quick Settings tile',
          subtitle: 'Swipe down twice, tap the pencil and add "Block reels 30m" for a one-tap hard block',
        ),
        Tile(
          icon: Icons.notifications_active_outlined,
          title: 'Send a test recap',
          subtitle: 'Shows the evening recap notification now',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () => _ch.invokeMethod('testSummary'),
        ),
      ]),
      Section('App updates', [
        Tile(
          icon: Icons.system_update_alt,
          title: 'Version ${Updates.current.isEmpty ? '...' : Updates.current}',
          subtitle: 'Tap to check for a newer version',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () async {
            toast('Checking...');
            String? why;
            final u = await Updates.check(api: (s.config['updateApi'] ?? defaultUpdateApi) as String, error: (m) => why = m);
            if (!context.mounted) return;
            if (u != null) {
              showUpdateDialog(context, u);
            } else {
              toast(why ?? 'You have the latest version.');
            }
          },
        ),
        SwitchTile(
          icon: Icons.autorenew,
          title: 'Check automatically',
          subtitle: 'Looks for a new version when the app opens',
          value: s.config['autoUpdate'] != false,
          onChanged: (v) => save({...s.config, 'autoUpdate': v}),
        ),
      ], footer: 'New versions come from the Releases page of the project on GitHub. Android always asks you to confirm the install.'),
      Section('Your data', [
        Tile(
          icon: Icons.upload_outlined,
          title: 'Copy a backup',
          subtitle: 'Settings, history and daily detail to the clipboard',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () async {
            await Clipboard.setData(ClipboardData(
                text: jsonEncode({'config': s.config, 'history': s.history, 'daily': s.daily})));
            toast('Backup copied to clipboard');
          },
        ),
        Tile(
          icon: Icons.download_outlined,
          title: 'Restore from clipboard',
          subtitle: 'Paste a backup you copied earlier',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () async {
            try {
              final t = (await Clipboard.getData('text/plain'))?.text ?? '';
              final m = jsonDecode(t) as Map<String, dynamic>;
              await _ch.invokeMethod('importHistory', jsonEncode(m['history'] ?? {}));
              await _ch.invokeMethod('importDaily', jsonEncode(m['daily'] ?? {}));
              await save(Map<String, dynamic>.from(m['config'] as Map));
              toast('Backup restored');
            } catch (_) {
              toast('Clipboard does not hold a valid backup');
            }
          },
        ),
      ]),
      Section('Troubleshooting', [
        Tile(
          icon: Icons.lock_open,
          title: 'Clear active blocks',
          subtitle: 'Ends any running block. All your counts stay',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () async {
            // Ending a block loosens your rules, so it needs the buddy PIN / approval when one is set.
            if (!await pinOk()) return;
            await _ch.invokeMethod('clearBlocks');
            refresh();
            toast('Active blocks cleared. Your counts are untouched.');
          },
        ),
        Tile(
          icon: Icons.bug_report_outlined,
          title: 'Last event seen',
          subtitle: s.lastEvent.isEmpty
              ? 'No reel-app events yet. Open a reel app and check "surface=true" appears here.'
              : s.lastEvent,
        ),
        Tile(
          icon: Icons.delete_forever_outlined,
          bg: cs.errorContainer,
          fg: cs.onErrorContainer,
          title: 'Erase all data',
          titleColor: cs.error,
          subtitle: 'Permanently deletes your reel history. Settings stay',
          onTap: () async {
            final sure = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Erase all data?'),
                content: const Text(
                    'This permanently deletes every day of reel history on this phone. Your settings stay. This cannot be undone. Use "Copy a backup" first if you might want it back.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep my data')),
                  TextButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: Text('Erase everything', style: TextStyle(color: Theme.of(d).colorScheme.error)),
                  ),
                ],
              ),
            );
            if (sure != true || !await pinOk()) return;
            await _ch.invokeMethod('eraseAll');
            refresh();
            toast('All data erased');
          },
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Glass(
          tint: cs.tertiaryContainer,
          child: Row(children: [
            Icon(Icons.workspace_premium_outlined, color: cs.onTertiaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Everything is unlocked. Strict mode, schedules, per-app limits, timers and stats are all free, with no account, payments or ads.',
                style: TextStyle(color: cs.onTertiaryContainer, height: 1.4),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}


String actionLabel(String? a, {String fallback = 'Go back'}) => switch (a) {
      'home' => 'Go home',
      'lock' => 'Lock screen',
      'back' => 'Go back',
      _ => fallback,
    };

/// Asks what to do when a block fires. Returns the chosen action ("" means use the default).
Future<String?> pickAction(BuildContext context, String current, {required bool allowDefault}) {
  Widget opt(BuildContext c, String v, String title, String sub) => SimpleDialogOption(
        onPressed: () => Navigator.pop(c, v),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(current == v ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: c.cs.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Text(sub, style: TextStyle(fontSize: 12.5, color: c.cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      );
  return showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('When a block happens'),
      children: [
        if (allowDefault) opt(c, '', 'Use the default', 'Follow the setting in Rules'),
        opt(c, 'back', 'Go back', 'Leaves the reel screen, stays in the app'),
        opt(c, 'home', 'Go home', 'Sends you to the home screen'),
        opt(c, 'lock', 'Lock the screen', 'Turns the screen off (Android 9 or newer)'),
      ],
    ),
  );
}

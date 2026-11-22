import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

import 'main.dart';

enum Span { day, week, month, year }

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// One day's numbers. Per-app and hourly detail exists for days recorded since detailed history was added.
class DayData {
  DayData(this.date, this.total, this.perApp, this.hourly, this.watchMs, this.skimmed);
  final DateTime date;
  final int total;
  final Map<String, int> perApp;
  final List<int>? hourly;
  final int watchMs;
  final int skimmed;
}

DayData dayData(AppState s, DateTime date) {
  final key = dayKey(date);
  Map<String, dynamic>? m;
  if (key == dayKey(s.nowDate)) {
    m = s.today;
  } else if (s.daily[key] is Map) {
    m = Map<String, dynamic>.from(s.daily[key] as Map);
  }
  final total = key == dayKey(s.nowDate) ? s.total : ((s.history[key] ?? m?['total'] ?? 0) as num).toInt();
  final per = <String, int>{};
  ((m?['perApp'] ?? {}) as Map).forEach((k, v) => per[k.toString()] = (v as num).toInt());
  final h = m?['hourly'];
  return DayData(
    date,
    total,
    per,
    h is List ? h.map((e) => (e as num).toInt()).toList() : null,
    ((m?['watchMs'] ?? 0) as num).toInt(),
    ((m?['skimmed'] ?? 0) as num).toInt(),
  );
}

class Range {
  Range(this.start, this.end);
  final DateTime start, end;
  Iterable<DateTime> get days sync* {
    var d = start;
    var n = 0;
    while (!d.isAfter(end) && n++ < 400) {
      yield d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
  }
}

Range rangeFor(Span span, int offset, DateTime today) {
  switch (span) {
    case Span.day:
      final d = DateTime(today.year, today.month, today.day - offset);
      return Range(d, d);
    case Span.week:
      final end = DateTime(today.year, today.month, today.day - 7 * offset);
      return Range(DateTime(end.year, end.month, end.day - 6), end);
    case Span.month:
      final first = DateTime(today.year, today.month - offset, 1);
      return Range(first, DateTime(first.year, first.month + 1, 0));
    case Span.year:
      final y = today.year - offset;
      return Range(DateTime(y, 1, 1), DateTime(y, 12, 31));
  }
}

String rangeLabel(Span span, Range r) {
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  switch (span) {
    case Span.day:
      return '${r.start.day} ${mon[r.start.month - 1]} ${r.start.year}';
    case Span.week:
      return '${r.start.day} ${mon[r.start.month - 1]} – ${r.end.day} ${mon[r.end.month - 1]}';
    case Span.month:
      return '${mon[r.start.month - 1]} ${r.start.year}';
    case Span.year:
      return '${r.start.year}';
  }
}

class InsightsPage extends StatefulWidget {
  const InsightsPage(this.s, {super.key});
  final AppState s;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  Span span = Span.week;
  int offset = 0;

  AppState get s => widget.s;

  /// Days in [r] that fall between the first day of use and today (the only days that can hold data).
  List<DayData> _days(Range r) {
    final first = DateTime.tryParse(s.firstDay);
    final today = _d(s.nowDate);
    return [
      for (final d in r.days)
        if (!d.isAfter(today) && (first == null || !d.isBefore(_d(first)))) dayData(s, d)
    ];
  }

  @override
  Widget build(BuildContext context) {
    final today = _d(s.nowDate);
    final r = rangeFor(span, offset, today);
    final prev = rangeFor(span, offset + 1, today);
    final days = _days(r);
    final prevDays = _days(prev);
    final total = days.fold<int>(0, (a, b) => a + b.total);
    final prevTotal = prevDays.fold<int>(0, (a, b) => a + b.total);
    final n = days.isEmpty ? 1 : days.length;
    final watchMin = (days.fold<int>(0, (a, b) => a + b.watchMs) / 60000).round();
    final skimmed = days.fold<int>(0, (a, b) => a + b.skimmed);
    final busiest = days.isEmpty ? null : days.reduce((a, b) => a.total >= b.total ? a : b);
    // Today is still in progress, so it is left out of "lightest day" whenever there are complete days.
    final complete = days.where((d) => dayKey(d.date) != dayKey(today)).toList();
    final lightPool = complete.isEmpty ? days : complete;
    final lightest = lightPool.isEmpty ? null : lightPool.reduce((a, b) => a.total <= b.total ? a : b);

    final per = <String, int>{};
    final hours = List<int>.filled(24, 0);
    var haveHours = false;
    for (final d in days) {
      d.perApp.forEach((k, v) => per[k] = (per[k] ?? 0) + v);
      final h = d.hourly;
      if (h != null && h.length == 24) {
        haveHours = true;
        for (var i = 0; i < 24; i++) {
          hours[i] += h[i];
        }
      }
    }

    final bars = _bars(r, days);
    final cs = Theme.of(context).colorScheme;
    final change = prevTotal == 0 ? null : ((total - prevTotal) * 100 / prevTotal);
    final allTime = s.history.values.fold<int>(0, (a, b) => a + (b as num).toInt()) +
        (s.history.containsKey(dayKey(s.nowDate)) ? 0 : s.total);

    final peak = haveHours ? hours.indexOf(hours.reduce((a, b) => a > b ? a : b)) : null;
    String hm(int m) => m >= 120 ? '${(m / 60).toStringAsFixed(1)} h' : '$m min';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      PillTabs<Span>(
        items: const {Span.day: 'Day', Span.week: 'Week', Span.month: 'Month', Span.year: 'Year'},
        value: span,
        onChanged: (v) => setState(() {
          span = v;
          offset = 0;
        }),
      ),
      PeriodNav(
        label: rangeLabel(span, r),
        onPrev: () => setState(() => offset++),
        onNext: offset == 0 ? null : () => setState(() => offset--),
      ),
      Glass(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$total', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('reels', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            ),
            const Spacer(),
            if (change != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: change > 0 ? cs.errorContainer : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(change > 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16, color: change > 0 ? cs.onErrorContainer : cs.onSecondaryContainer),
                  const SizedBox(width: 4),
                  Text('${change.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: change > 0 ? cs.onErrorContainer : cs.onSecondaryContainer)),
                ]),
              ),
          ]),
          Text(
            change != null
                ? 'vs $prevTotal in the previous ${span.name}'
                : (prevDays.isEmpty ? 'No earlier data to compare' : 'Previous ${span.name}: $prevTotal'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          if (span == Span.day && !haveHours)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No hourly detail for this day (recorded before detailed history existed).',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else
            _chart(context, span == Span.day ? hours : bars.values, span == Span.day ? _hourLabels() : bars.labels),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: StatTile(icon: Icons.show_chart, value: (total / n).toStringAsFixed(1), label: 'avg / day', color: cs.secondary)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.timer_outlined, value: hm(watchMin), label: 'watch time', color: cs.tertiary)),
        const SizedBox(width: 10),
        Expanded(child: StatTile(icon: Icons.fast_forward, value: '$skimmed', label: 'skimmed', color: cs.primary)),
      ]),
      Section('Highlights', [
        if (span != Span.day && busiest != null)
          Tile(
            icon: Icons.local_fire_department_outlined,
            bg: cs.errorContainer,
            fg: cs.onErrorContainer,
            title: 'Busiest day',
            subtitle: dayKey(busiest.date),
            trailing: Text('${busiest.total}', style: Theme.of(context).textTheme.titleLarge),
          ),
        if (span != Span.day && lightest != null)
          Tile(
            icon: Icons.spa_outlined,
            title: 'Lightest day',
            subtitle: dayKey(lightest.date),
            trailing: Text('${lightest.total}', style: Theme.of(context).textTheme.titleLarge),
          ),
        if (peak != null)
          Tile(
            icon: Icons.schedule,
            bg: cs.tertiaryContainer,
            fg: cs.onTertiaryContainer,
            title: 'Peak hour',
            subtitle: 'When you watch the most',
            trailing: Text('${peak.toString().padLeft(2, '0')}:00', style: Theme.of(context).textTheme.titleLarge),
          ),
        Tile(
          icon: Icons.all_inclusive,
          title: 'All time',
          subtitle: 'Every reel counted since you started',
          trailing: Text('$allTime', style: Theme.of(context).textTheme.titleLarge),
        ),
      ]),
      if (span != Span.day && haveHours) ...[
        const SizedBox(height: 14),
        Glass(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Busiest hours', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _chart(context, hours, _hourLabels()),
          ]),
        ),
      ],
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
        child: Text('By app',
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.3)),
      ),
      Glass(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: per.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No per-app detail for this period yet.', style: TextStyle(color: cs.onSurfaceVariant)),
              )
            : Column(children: [
                for (final e in (per.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  AppRow(
                    pkg: e.key,
                    name: appName(e.key),
                    value: '${e.value}',
                    fraction: total == 0 ? 0 : e.value / total,
                  ),
              ]),
      ),
      Builder(builder: (context) {
        final from = DateTime(r.start.year, r.start.month, r.start.day).millisecondsSinceEpoch;
        final to = DateTime(r.end.year, r.end.month, r.end.day + 1).millisecondsSinceEpoch;
        final log = [
          for (final b in s.blockLog)
            if (((b['t'] ?? 0) as num) >= from && ((b['t'] ?? 0) as num) < to) b
        ];
        const why = {
          'always': 'Always block',
          'plan': 'Plan',
          'hard': 'Hard block',
          'cooldown': 'Break',
          'schedule': 'Schedule',
          'limit': 'Daily limit',
          'applimit': 'App limit',
          'apptimer': 'App timer',
          'browser': 'Browser',
        };
        String hhmm(int ms) {
          final d = DateTime.fromMillisecondsSinceEpoch(ms);
          return '${d.day}/${d.month}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        }

        final top = <String, int>{};
        for (final b in log) {
          top[(b['why'] ?? '') as String] = (top[(b['why'] ?? '') as String] ?? 0) + 1;
        }
        final topWhy = top.entries.isEmpty ? null : (top.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
        return Section('Blocks', [
          Tile(
            icon: Icons.shield_outlined,
            bg: cs.errorContainer,
            fg: cs.onErrorContainer,
            title: 'Blocked ${log.length} time${log.length == 1 ? '' : 's'}',
            subtitle: log.isEmpty
                ? 'Nothing was blocked in this period'
                : 'Against $total reels watched${topWhy == null ? '' : '. Most often: ${why[topWhy.key] ?? topWhy.key}'}',
          ),
          for (final b in log.reversed.take(6))
            Tile(
              leading: AppIcon((b['pkg'] ?? '') as String, size: 40),
              title: apps[(b['pkg'] ?? '') as String] ?? webApps[(b['pkg'] ?? '') as String] ?? (b['why'] == 'browser' ? 'Browser' : 'Reel app'),
              subtitle: '${why[b['why']] ?? b['why']}  -  ${hhmm((b['t'] as num).toInt())}',
              trailing: Text(actionLabel(b['act'] as String?),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
        ], footer: log.isEmpty ? null : 'The 6 most recent blocks in this period. Every block is kept in your history.');
      }),
      Section('Export', [
        Tile(
          icon: Icons.table_chart_outlined,
          title: 'Copy all data as CSV',
          subtitle: 'Paste it into a spreadsheet',
          trailing: Icon(Icons.copy, size: 20, color: cs.onSurfaceVariant),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: _csv()));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('CSV copied. Paste it into a spreadsheet.')));
            }
          },
        ),
        Tile(
          icon: Icons.description_outlined,
          title: 'Copy this report',
          subtitle: 'A short summary of ${rangeLabel(span, r)}',
          trailing: Icon(Icons.copy, size: 20, color: cs.onSurfaceVariant),
          onTap: () async {
            final text = 'Focus Reels ${span.name} report (${rangeLabel(span, r)})\n'
                'Total reels: $total (avg ${(total / n).toStringAsFixed(1)}/day)\n'
                'Watch time: about $watchMin min\n'
                '${change == null ? '' : '${change >= 0 ? 'Up' : 'Down'} ${change.abs().toStringAsFixed(0)}% vs previous ${span.name}\n'}'
                '${per.entries.map((e) => '${apps[e.key] ?? e.key}: ${e.value}').join('\n')}';
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied')));
            }
          },
        ),
      ], footer: 'Every day is kept for good, including per-app and hourly detail. Nothing is deleted unless you erase it in Health.'),
    ]);
  }

  List<String> _hourLabels() => List.generate(24, (i) => i % 6 == 0 ? '$i' : '');

  ({List<int> values, List<String> labels}) _bars(Range r, List<DayData> days) {
    final byDate = {for (final d in days) dayKey(d.date): d.total};
    switch (span) {
      case Span.day:
        return (values: const <int>[], labels: const <String>[]);
      case Span.week:
        const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        final ds = r.days.toList();
        return (
          values: [for (final d in ds) byDate[dayKey(d)] ?? 0],
          labels: [for (final d in ds) '${wd[d.weekday - 1]}\n${d.day}'],
        );
      case Span.month:
        final ds = r.days.toList();
        return (
          values: [for (final d in ds) byDate[dayKey(d)] ?? 0],
          labels: [for (final d in ds) (d.day == 1 || d.day % 5 == 0) ? '${d.day}' : ''],
        );
      case Span.year:
        final m = List<int>.filled(12, 0);
        for (final d in days) {
          m[d.date.month - 1] += d.total;
        }
        return (values: m, labels: const ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']);
    }
  }

  Widget _chart(BuildContext c, List<int> v, List<String> labels) {
    if (v.isEmpty) return const SizedBox.shrink();
    final cs = c.cs;
    final m = v.fold<int>(1, (a, b) => b > a ? b : a);
    final top = v.indexOf(m);
    final dense = v.length > 24;
    return SizedBox(
      height: 168,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < v.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              SizedBox(
                height: 16,
                child: i == top && m > 0
                    ? OverflowBox(
                        maxWidth: 60,
                        child: Text('${v[i]}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                      )
                    : null,
              ),
              Container(
                margin: EdgeInsets.symmetric(horizontal: dense ? 0.6 : (v.length > 12 ? 2 : 5)),
                height: 3 + 104 * v[i] / m,
                decoration: BoxDecoration(
                  color: i == top && m > 0 ? cs.primary : cs.primary.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(dense ? 2 : 8),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                child: Text(i < labels.length ? labels[i] : '',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, height: 1.2, color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
      ]),
    );
  }

  /// One row per day from the first day of use to today, with a column per app.
  String _csv() {
    final first = DateTime.tryParse(s.firstDay) ?? _d(s.nowDate);
    final today = _d(s.nowDate);
    final keys = apps.keys.toList();
    final b = StringBuffer('date,total,${keys.map((k) => apps[k]!.replaceAll(',', ' ')).join(',')},watch_minutes,skimmed\n');
    for (final d in Range(_d(first), today).days) {
      final x = dayData(s, d);
      b.writeln('${dayKey(d)},${x.total},${keys.map((k) => x.perApp[k] ?? 0).join(',')},'
          '${(x.watchMs / 60000).round()},${x.skimmed}');
    }
    return b.toString();
  }
}

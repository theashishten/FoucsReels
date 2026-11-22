import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Flat, tonal Material 3 look: warm neutral surfaces, one coral accent with sage and sky companions.
/// Light and dark both follow the phone's setting.
extension Cs on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
}

ColorScheme _scheme(Brightness b) {
  if (b == Brightness.dark) {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFB59F),
      onPrimary: Color(0xFF5A1503),
      primaryContainer: Color(0xFF6A2410),
      onPrimaryContainer: Color(0xFFFFDAD0),
      secondary: Color(0xFFA9D3B2),
      onSecondary: Color(0xFF123822),
      secondaryContainer: Color(0xFF2F4A37),
      onSecondaryContainer: Color(0xFFC4EFCD),
      tertiary: Color(0xFFA5C8F8),
      onTertiary: Color(0xFF0B305A),
      tertiaryContainer: Color(0xFF1F4474),
      onTertiaryContainer: Color(0xFFD3E4FF),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF151110),
      onSurface: Color(0xFFEDE0D8),
      onSurfaceVariant: Color(0xFFB5A89E),
      surfaceContainerLowest: Color(0xFF100C0B),
      surfaceContainerLow: Color(0xFF1B1614),
      surfaceContainer: Color(0xFF221C19),
      surfaceContainerHigh: Color(0xFF2C2420),
      surfaceContainerHighest: Color(0xFF362D28),
      outline: Color(0xFF857A71),
      outlineVariant: Color(0xFF3A312B),
    );
  }
  return const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFC4482C),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDAD0),
    onPrimaryContainer: Color(0xFF3F0D00),
    secondary: Color(0xFF3F7A55),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCDEBD3),
    onSecondaryContainer: Color(0xFF082613),
    tertiary: Color(0xFF2F65A7),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD2E4FF),
    onTertiaryContainer: Color(0xFF001C39),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFBF8F4),
    onSurface: Color(0xFF201A15),
    onSurfaceVariant: Color(0xFF6E645B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F1EA),
    surfaceContainer: Color(0xFFF1EAE1),
    surfaceContainerHigh: Color(0xFFEAE1D6),
    surfaceContainerHighest: Color(0xFFE3D9CD),
    outline: Color(0xFF8C8178),
    outlineVariant: Color(0xFFE2D8CC),
  );
}

ThemeData buildTheme(Brightness b) {
  final cs = _scheme(b);
  final base = ThemeData(colorScheme: cs, useMaterial3: true, brightness: b);
  final t = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    canvasColor: cs.surface,
    textTheme: t.copyWith(
      displayLarge: t.displayLarge?.copyWith(fontWeight: FontWeight.w400, letterSpacing: -1.5),
      displayMedium: t.displayMedium?.copyWith(fontWeight: FontWeight.w400, letterSpacing: -1),
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w400, letterSpacing: -0.5),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w500),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w500),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      color: cs.surfaceContainer,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      iconColor: cs.onSurfaceVariant,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 76,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          )),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? cs.secondaryContainer : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? cs.onSecondaryContainer : cs.onSurfaceVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: cs.outlineVariant),
        foregroundColor: cs.primary,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.primary : cs.surfaceContainerHighest),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : cs.outline),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.surfaceContainerHighest,
      thumbColor: cs.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
  );
}

/// No decoration: kept so existing screens that wrap everything in Aurora keep working.
class Aurora extends StatelessWidget {
  const Aurora({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Flat tonal card (the Digital Wellbeing look): a soft container colour, big radius, no border or shadow.
class Glass extends StatelessWidget {
  const Glass({required this.child, this.padding = const EdgeInsets.all(20), this.tint, super.key});
  final Widget child;
  final EdgeInsets padding;
  /// Optional container colour; defaults to the standard card colour.
  final Color? tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: tint ?? context.cs.surfaceContainer,
        ),
        child: child,
      );
}

/// Donut chart: either one progress arc, or several coloured segments (share per app).
class GradientRing extends StatelessWidget {
  const GradientRing({
    required this.value,
    required this.colors,
    required this.size,
    this.stroke = 22,
    this.segments,
    this.track,
    this.child,
    super.key,
  });
  /// Progress 0..1 when [segments] is null.
  final double value;
  final List<Color> colors;
  final double size, stroke;
  /// (fraction, colour) pairs summing to <= 1.
  final List<(double, Color)>? segments;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: CustomPaint(
          painter: _RingPainter(value, colors.first, stroke, segments, track ?? context.cs.surfaceContainerHighest),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.stroke, this.segments, this.track);
  final double value, stroke;
  final Color color, track;
  final List<(double, Color)>? segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    final segs = segments ?? [(value.clamp(0.0, 1.0), color)];
    // Several segments get flat ends with small gaps; a single progress arc keeps rounded ends.
    final multi = segs.length > 1;
    p.strokeCap = multi ? StrokeCap.butt : StrokeCap.round;
    final gap = multi ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (final (f, c) in segs) {
      if (f <= 0) continue;
      final sweep = math.max(0.0, math.pi * 2 * f - gap);
      if (sweep <= 0.001) continue;
      canvas.drawArc(rect, start + gap / 2, sweep, false, p..color = c);
      start += math.pi * 2 * f;
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => true;
}

/// Small stat tile: icon, big number, caption, on a tonal container colour.
class StatTile extends StatelessWidget {
  const StatTile({required this.icon, required this.value, required this.label, this.color, super.key});
  final IconData icon;
  final String value, label;
  /// Accent role colour (primary, secondary or tertiary of the scheme); picks the matching container.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (bg, fg) = color == cs.secondary
        ? (cs.secondaryContainer, cs.onSecondaryContainer)
        : color == cs.tertiary
            ? (cs.tertiaryContainer, cs.onTertiaryContainer)
            : (cs.primaryContainer, cs.onPrimaryContainer);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: fg),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: fg)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
      ]),
    );
  }
}

/// Wraps settings rows in flat rounded tiles with a little space between them.
List<Widget> glassify(List<Widget> items) {
  const rows = {'ListTile', 'SwitchListTile', 'CheckboxListTile', 'RadioListTile', '_SliderRow'};
  return [
    for (final w in items)
      if (rows.contains(w.runtimeType.toString()))
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Material(
              color: context.cs.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: w,
            ),
          ),
        )
      else
        w,
  ];
}

/// Flat progress bar with rounded ends.
class GradBar extends StatelessWidget {
  const GradBar({required this.value, this.height = 8, this.colors, super.key});
  final double value, height;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: [
        Container(height: height, color: cs.surfaceContainerHighest),
        FractionallySizedBox(
          widthFactor: value.clamp(0.02, 1.0),
          child: Container(height: height, color: colors?.first ?? cs.primary),
        ),
      ]),
    );
  }
}

/// Primary action button: a flat filled pill.
class GradButton extends StatelessWidget {
  const GradButton({required this.label, required this.onPressed, this.icon, this.colors, super.key});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final bg = colors?.first;
    return FilledButton(
      style: bg == null ? null : FilledButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white),
      onPressed: onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// App icon fetched once from Android and cached.
class AppIcon extends StatefulWidget {
  const AppIcon(this.pkg, {this.size = 40, super.key});
  final String pkg;
  final double size;

  static final Map<String, Uint8List?> _cache = {};
  static const _ch = MethodChannel('focus_reels');

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  @override
  void initState() {
    super.initState();
    if (!AppIcon._cache.containsKey(widget.pkg)) _load();
  }

  Future<void> _load() async {
    AppIcon._cache[widget.pkg] = null;
    try {
      final raw = await AppIcon._ch.invokeMethod<String>('getIcons', [widget.pkg]);
      final m = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      final b = m[widget.pkg] as String?;
      if (b != null) AppIcon._cache[widget.pkg] = base64Decode(b);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = AppIcon._cache[widget.pkg];
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.28),
      child: bytes == null
          ? Container(
              width: widget.size,
              height: widget.size,
              color: context.cs.surfaceContainerHighest,
              child: Icon(Icons.smart_display_outlined, size: widget.size * 0.5, color: context.cs.onSurfaceVariant),
            )
          : Image.memory(bytes, width: widget.size, height: widget.size, gaplessPlayback: true),
    );
  }
}

/// One app in a list: icon, name, a value on the right and an optional bar. Used everywhere an app is
/// listed so every screen looks the same.
class AppRow extends StatelessWidget {
  const AppRow({
    required this.pkg,
    required this.name,
    required this.value,
    this.fraction,
    this.color,
    this.onTap,
    this.badge,
    super.key,
  });
  final String pkg, name, value;
  final double? fraction;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            AppIcon(pkg, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                  if (badge != null) ...[badge!, const SizedBox(width: 8)],
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ]),
                if (fraction != null) ...[
                  const SizedBox(height: 8),
                  GradBar(value: fraction!, colors: color == null ? null : [color!]),
                ],
              ]),
            ),
          ]),
        ),
      );
}

// ------------------------------------------------------------------ settings-style building blocks

/// A titled group of rows inside one rounded card, like Digital Wellbeing's settings.
class Section extends StatelessWidget {
  const Section(this.title, this.children, {this.footer, super.key});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
            child: Text(title!,
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.3)),
          ),
        Material(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: 72, color: cs.outlineVariant.withValues(alpha: 0.5)),
              children[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(footer!, style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

/// One row: tonal icon circle, title, optional subtitle and a trailing widget.
class Tile extends StatelessWidget {
  const Tile({
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.bg,
    this.fg,
    this.titleColor,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final Color? bg, fg, titleColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final lead = leading ??
        (icon == null
            ? null
            : Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: bg ?? cs.secondaryContainer, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: fg ?? cs.onSecondaryContainer),
              ));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: 16)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: titleColor ?? cs.onSurface)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurfaceVariant)),
                ),
            ]),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(left: 12), child: trailing),
        ]),
      ),
    );
  }
}

class SwitchTile extends StatelessWidget {
  const SwitchTile({required this.title, required this.value, required this.onChanged, this.subtitle, this.icon, this.leading, this.bg, this.fg, super.key});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Color? bg, fg;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        leading: leading,
        bg: bg,
        fg: fg,
        trailing: Switch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );
}

/// A labelled slider row; the current value is shown on the right in the accent colour.
class SliderTile extends StatefulWidget {
  const SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onEnd,
    this.zero = '',
    this.unit = '',
    this.icon,
    super.key,
  });
  final String title, zero, unit;
  final int value, min, max;
  final IconData? icon;
  final void Function(int) onEnd;

  @override
  State<SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<SliderTile> {
  late double cur = widget.value.toDouble();

  @override
  void didUpdateWidget(SliderTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) cur = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final shown = cur.round() == 0 && widget.zero.isNotEmpty ? widget.zero : '${cur.round()}${widget.unit}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(children: [
        Row(children: [
          if (widget.icon != null) ...[
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
              child: Icon(widget.icon, size: 20, color: cs.onSecondaryContainer),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
          Text(shown, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        Slider(
          value: cur.clamp(widget.min.toDouble(), widget.max.toDouble()),
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          onChanged: (x) => setState(() => cur = x),
          onChangeEnd: (x) => widget.onEnd(x.round()),
        ),
      ]),
    );
  }
}

/// Rounded pill tabs (Day / Week / Month ...), the Digital Wellbeing way of switching a time range.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({required this.items, required this.value, required this.onChanged, super.key});
  final Map<T, String> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(100)),
      child: Row(children: [
        for (final e in items.entries)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: e.key == value ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(e.value,
                    style: TextStyle(
                      fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500,
                      color: e.key == value ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                    )),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Previous / title / next row used above every period chart.
class PeriodNav extends StatelessWidget {
  const PeriodNav({required this.label, required this.onPrev, this.onNext, super.key});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    Widget btn(IconData i, VoidCallback? f) => IconButton.filledTonal(
          onPressed: f,
          icon: Icon(i),
          style: IconButton.styleFrom(
            backgroundColor: cs.surfaceContainer,
            foregroundColor: cs.onSurface,
            disabledBackgroundColor: cs.surfaceContainer.withValues(alpha: 0.5),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        btn(Icons.chevron_left, onPrev),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        btn(Icons.chevron_right, onNext),
      ]),
    );
  }
}

/// A big selectable card (used for the Track only / Limit & block choice).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({required this.icon, required this.title, required this.body, required this.selected, required this.onTap, super.key});
  final IconData icon;
  final String title, body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainer;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
              const Spacer(),
              if (selected) Icon(Icons.check_circle, color: cs.primary, size: 22),
            ]),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(fontSize: 13, height: 1.35, color: fg.withValues(alpha: 0.75))),
          ]),
        ),
      ),
    );
  }
}

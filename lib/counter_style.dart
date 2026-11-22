import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Lets the user restyle the live counter shown over Instagram, YouTube and the other reel apps.
class CounterStylePage extends StatefulWidget {
  const CounterStylePage({required this.cfg, required this.save, super.key});
  final Map<String, dynamic> cfg;
  final Future<void> Function(Map<String, dynamic>) save;

  @override
  State<CounterStylePage> createState() => _CounterStylePageState();
}

const _styles = <String, List<String>>{
  'liquid': ['Liquid glass', 'Frosted glass with a bright edge. Easy to read on any video'],
  'dark': ['Dark', 'Solid dark pill'],
  'light': ['Light', 'Solid white pill'],
  'glass': ['Glass', 'Smoky see-through pill'],
  'clear': ['Transparent', 'No background, text with a dark outline'],
  'colour': ['Colour', 'Filled with the ring colour'],
};

class _CounterStylePageState extends State<CounterStylePage> {
  late String style = (widget.cfg['counterStyle'] ?? 'dark').toString();
  late double opacity = ((widget.cfg['counterOpacity'] ?? 92) as num).toDouble();
  late double size = ((widget.cfg['counterSize'] ?? 100) as num).toDouble();
  late bool label = widget.cfg['counterLabel'] != false;
  late bool ring = widget.cfg['counterRing'] != false;

  Future<void> commit() => widget.save({
        ...widget.cfg,
        'counterStyle': style,
        'counterOpacity': opacity.round(),
        'counterSize': size.round(),
        'counterLabel': label,
        'counterRing': ring,
      });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('Counter style')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text('This is how the live counter looks over Instagram, YouTube and the other reel apps.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 14),
        _preview(),
        Section('Style', [
          for (final e in _styles.entries)
            Tile(
              icon: style == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              title: e.value[0],
              subtitle: e.value[1],
              onTap: () {
                setState(() => style = e.key);
                commit();
              },
            ),
        ]),
        Section('Adjust', [
          SliderTile(
            icon: Icons.opacity,
            title: 'Opacity',
            value: opacity.round(),
            min: 20,
            max: 100,
            zero: '',
            unit: '%',
            onEnd: (v) {
              setState(() => opacity = v.toDouble());
              commit();
            },
          ),
          SliderTile(
            icon: Icons.format_size,
            title: 'Size',
            value: size.round(),
            min: 70,
            max: 150,
            zero: '',
            unit: '%',
            onEnd: (v) {
              setState(() => size = v.toDouble());
              commit();
            },
          ),
          SwitchTile(
            icon: Icons.donut_large,
            title: 'Progress ring',
            subtitle: 'Off shows just the number',
            value: ring,
            onChanged: (v) {
              setState(() => ring = v);
              commit();
            },
          ),
          SwitchTile(
            icon: Icons.short_text,
            title: 'Caption',
            subtitle: 'The "8 left" or "today" text',
            value: label,
            onChanged: (v) {
              setState(() => label = v);
              commit();
            },
          ),
        ]),
        TextButton(
          onPressed: () {
            setState(() {
              style = 'dark';
              opacity = 92;
              size = 100;
              label = true;
              ring = true;
            });
            commit();
          },
          child: const Text('Reset to default'),
        ),
      ]),
    );
  }

  Widget _preview() {
    final scale = size / 100;
    final a = opacity / 100;
    Color fill = const Color(0xFF151114);
    Color text = Colors.white, sub = const Color(0xFFCFC4BD), track = const Color(0x2EFFFFFF);
    Color? edge = const Color(0x33FFFFFF);
    const accent = Color(0xFF7FDDB0);
    switch (style) {
      case 'light':
        fill = Colors.white;
        text = const Color(0xFF1B1B1F);
        sub = const Color(0xFF5F5A63);
        track = const Color(0x1F000000);
        edge = const Color(0x22000000);
        break;
      case 'glass':
        fill = const Color(0x66181820);
        sub = const Color(0xFFF2F2F7);
        edge = const Color(0x66FFFFFF);
        break;
      case 'liquid':
        fill = const Color(0x7A0E0E12);
        sub = const Color(0xFFF2F2F7);
        edge = const Color(0xBFFFFFFF);
        break;
      case 'clear':
        fill = const Color(0x00000000);
        sub = Colors.white;
        edge = null;
        break;
      case 'colour':
        fill = accent;
        text = const Color(0xFF151110);
        sub = const Color(0xFF2B2220);
        track = const Color(0x33000000);
        edge = null;
        break;
    }
    Color fade(Color c) => c.withValues(alpha: c.a * a);
    final shadow = style == 'clear'
        ? const [Shadow(blurRadius: 5, color: Color(0xFF000000), offset: Offset(0, 1)), Shadow(blurRadius: 5, color: Color(0xFF000000), offset: Offset(0, 1))]
        : (style == 'glass' || style == 'liquid')
            ? const [Shadow(blurRadius: 2.5, color: Color(0xFF000000), offset: Offset(0, 1))]
            : null;
    final ringSize = 32.0 * scale;
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A5A8C), Color(0xFFB4638A), Color(0xFFE9A15B)],
        ),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 22),
      child: Container(
        height: ringSize + 10 * scale,
        padding: EdgeInsets.only(left: 5 * scale, right: 11 * scale),
        decoration: BoxDecoration(
          color: fade(fill),
          borderRadius: BorderRadius.circular(100),
          border: edge == null ? null : Border.all(color: fade(edge)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(alignment: Alignment.center, children: [
              if (ring) ...[
                SizedBox.expand(
                  child: Padding(
                    padding: EdgeInsets.all(2 * scale),
                    child: CircularProgressIndicator(value: 1, strokeWidth: 3 * scale, color: track),
                  ),
                ),
                SizedBox.expand(
                  child: Padding(
                    padding: EdgeInsets.all(2 * scale),
                    child: CircularProgressIndicator(
                      value: 0.4,
                      strokeWidth: 3 * scale,
                      strokeCap: StrokeCap.round,
                      color: style == 'colour' ? text : accent,
                    ),
                  ),
                ),
              ],
              Text('42',
                  style: TextStyle(
                      color: text,
                      fontSize: (ring ? 13 : 17) * scale,
                      fontWeight: FontWeight.w700,
                      shadows: shadow)),
            ]),
          ),
          if (label) ...[
            SizedBox(width: 8 * scale),
            Text('8 left', style: TextStyle(color: sub, fontSize: 12 * scale, shadows: shadow)),
          ],
        ]),
      ),
    );
  }
}

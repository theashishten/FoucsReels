import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Drag the little counter to where you want it over the reel apps. Position is saved as fractions of the
/// screen, so it lands in the same place on any phone.
class CounterPositionPage extends StatefulWidget {
  const CounterPositionPage({required this.cfg, required this.save, super.key});
  final Map<String, dynamic> cfg;
  final Future<void> Function(Map<String, dynamic>) save;

  @override
  State<CounterPositionPage> createState() => _CounterPositionPageState();
}

class _CounterPositionPageState extends State<CounterPositionPage> {
  // Defaults match the native side: centred, near the top.
  static const defX = 0.5, defY = 0.036;
  late double x = ((widget.cfg['bubbleX'] ?? defX) as num).toDouble();
  late double y = ((widget.cfg['bubbleY'] ?? defY) as num).toDouble();
  bool dragging = false;

  Future<void> commit() => widget.save({...widget.cfg, 'bubbleX': x, 'bubbleY': y});

  void preset(double nx, double ny) {
    setState(() {
      x = nx;
      y = ny;
    });
    commit();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(title: const Text('Counter position')),
      body: ListView(
          physics: dragging ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text(
          'Drag the counter to where you want it. It stays there over Instagram, YouTube and the other reel apps.',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: AspectRatio(
            aspectRatio: 9 / 18,
            child: LayoutBuilder(builder: (context, c) {
              const pillW = 128.0, pillH = 38.0;
              final w = c.maxWidth, h = c.maxHeight;
              final left = (x * w - pillW / 2).clamp(0.0, w - pillW);
              final top = (y * h).clamp(0.0, h - pillH);
              return Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: cs.outlineVariant, width: 3),
                ),
                child: Stack(children: [
                  Center(
                    child: Icon(Icons.play_circle_outline, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    // Raw pointer events: a normal drag would lose to the list's own vertical scrolling.
                    child: Listener(
                      onPointerDown: (_) => setState(() => dragging = true),
                      onPointerMove: (e) => setState(() {
                        x = ((left + e.delta.dx + pillW / 2) / w).clamp(0.05, 0.95);
                        y = ((top + e.delta.dy) / h).clamp(0.0, 0.93);
                      }),
                      onPointerUp: (_) {
                        setState(() => dragging = false);
                        commit();
                      },
                      onPointerCancel: (_) => setState(() => dragging = false),
                      child: Container(
                        width: pillW,
                        height: pillH,
                        decoration: BoxDecoration(
                          color: const Color(0xEB151114),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(left: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFFB59F), width: 3),
                            ),
                            child: const Text('42',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          const Text('today', style: TextStyle(color: Color(0xFFCFC4BD), fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
          ),
        ),
        Section('Quick positions', [
          Tile(
            icon: Icons.vertical_align_top,
            title: 'Top centre',
            subtitle: 'The default',
            onTap: () => preset(defX, defY),
          ),
          Tile(
            icon: Icons.north_west,
            title: 'Top left',
            onTap: () => preset(0.22, defY),
          ),
          Tile(
            icon: Icons.north_east,
            title: 'Top right',
            onTap: () => preset(0.78, defY),
          ),
          Tile(
            icon: Icons.vertical_align_bottom,
            title: 'Bottom centre',
            subtitle: 'Above the navigation bar',
            onTap: () => preset(0.5, 0.82),
          ),
        ]),
      ]),
    );
  }
}

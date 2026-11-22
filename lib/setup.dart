import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _ch = MethodChannel('focus_reels');

/// Permission state as reported by the Android side.
class Perms {
  Perms(this.m);
  final Map<String, dynamic> m;
  bool get accessibility => m['accessibility'] == true;
  bool get overlay => m['overlay'] == true;
  bool get notifications => m['notifications'] == true;
  bool get battery => m['battery'] == true;
  bool get usage => m['usage'] == true;

  /// The four every reel counter needs to keep working in the background.
  int get missing => [accessibility, overlay, notifications, battery].where((b) => !b).length;
  bool get ready => missing == 0;

  static Future<Perms> load() async {
    final raw = await _ch.invokeMethod<String>('getPermissions');
    return Perms(raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }
}

class _Step {
  const _Step(this.icon, this.title, this.why, this.method, this.colors);
  final IconData icon;
  final String title, why, method;
  final List<Color> colors;
}

const _steps = <String, _Step>{
  'accessibility': _Step(
    Icons.accessibility_new,
    'Accessibility',
    'Lets Focus Reels see when a reel is on screen so it can count each one. It reads nothing else.',
    'openAccessibilitySettings',
    [Color(0xFF7B5CFF), Color(0xFFB14CFF)],
  ),
  'overlay': _Step(
    Icons.layers_outlined,
    'Display over other apps',
    'Shows the small live counter and the block screen on top of Instagram, YouTube and the rest.',
    'openOverlaySettings',
    [Color(0xFF22D3EE), Color(0xFF5EEAD4)],
  ),
  'notifications': _Step(
    Icons.notifications_active_outlined,
    'Notifications',
    'For limit warnings, session reminders and your evening recap.',
    'requestNotifications',
    [Color(0xFFFFB347), Color(0xFFFF7A90)],
  ),
  'battery': _Step(
    Icons.battery_charging_full,
    'Run in the background',
    'Stops the phone from putting Focus Reels to sleep, so counting never silently stops.',
    'requestBattery',
    [Color(0xFF34D399), Color(0xFF5EEAD4)],
  ),
};

/// First-run (and "finish setup") screen asking for the permissions a reel counter needs.
class SetupPage extends StatefulWidget {
  const SetupPage({required this.onDone, required this.onSkip, super.key});
  final VoidCallback onDone, onSkip;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with WidgetsBindingObserver {
  Perms? p;

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
    final n = await Perms.load();
    if (mounted) setState(() => p = n);
  }

  bool _granted(String k) => switch (k) {
        'accessibility' => p!.accessibility,
        'overlay' => p!.overlay,
        'notifications' => p!.notifications,
        _ => p!.battery,
      };

  @override
  Widget build(BuildContext context) {
    final pr = p;
    if (pr == null) return const Center(child: CircularProgressIndicator());
    final done = 4 - pr.missing;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 56, height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: context.cs.primary,
            ),
            child: Icon(Icons.bolt, color: context.cs.onPrimary, size: 30),
          ),
        ),
        const SizedBox(height: 20),
        Text('Set up Focus Reels', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Four quick permissions so counting works in the background, like a proper wellbeing app. Nothing leaves your phone.',
          style: TextStyle(color: context.cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: GradBar(value: done / 4, height: 8)),
          const SizedBox(width: 12),
          Text('$done of 4', style: TextStyle(color: context.cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 16),
        for (final e in _steps.entries) _card(e.key, e.value),
        const SizedBox(height: 12),
        if (pr.ready)
          GradButton(label: 'All set  -  continue', icon: Icons.check_circle_outline, onPressed: widget.onDone)
        else
          TextButton(onPressed: widget.onSkip, child: const Text('Skip for now')),
      ]),
    );
  }

  /// Android 13+ greys out Accessibility for apps installed from a file. This explains the one-time unlock.
  Future<void> _restrictedHelp() async {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Accessibility is greyed out?'),
        content: const SingleChildScrollView(
          child: Text(
            'Android blocks Accessibility for apps installed from a file, with the message "Restricted setting". '
            'Unlock it once:\n\n'
            '1. Tap "Open App info" below.\n'
            '2. Tap the three dots at the top right.\n'
            '3. Tap "Allow restricted settings" and confirm with your PIN or fingerprint.\n'
            '4. Come back and tap Allow again, then switch on Focus Reels in Accessibility.\n\n'
            'No three dots? Open the app once, then go Settings > Apps > Focus Reels > the three dots.',
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              _ch.invokeMethod('openAppInfo');
            },
            child: const Text('Open App info'),
          ),
        ],
      ),
    );
  }

  Widget _card(String key, _Step st) {
    final ok = _granted(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Glass(
        padding: const EdgeInsets.all(18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: st.colors.first,
            ),
            child: Icon(st.icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(st.why, style: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 13, height: 1.35)),
              const SizedBox(height: 12),
              if (ok)
                Row(children: [
                  Icon(Icons.check_circle, color: context.cs.secondary, size: 18),
                  const SizedBox(width: 6),
                  Text('Allowed', style: TextStyle(color: context.cs.secondary, fontWeight: FontWeight.w600)),
                ])
              else
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 150,
                  child: GradButton(
                    label: 'Allow',
                    onPressed: () async {
                      await _ch.invokeMethod(st.method);
                      // The notification dialog returns quickly; the others come back via resume.
                      if (key == 'notifications') {
                        await Future<void>.delayed(const Duration(milliseconds: 800));
                        load();
                      }
                    },
                  ),
                ),
                if (key == 'accessibility')
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                    onPressed: () => _restrictedHelp(),
                    child: const Text("Can't turn it on? Tap for help"),
                  ),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

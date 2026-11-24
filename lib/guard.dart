import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _ch = MethodChannel('focus_reels');
const _adbCommand = 'adb shell pm grant com.example.focus_reels android.permission.WRITE_SECURE_SETTINGS';

/// Banking apps refuse to open while an Accessibility service is on. This section pauses counting while one is open.
class BankGuardSection extends StatefulWidget {
  const BankGuardSection({required this.cfg, required this.save, super.key});
  final Map<String, dynamic> cfg;
  final Future<void> Function(Map<String, dynamic>) save;

  @override
  State<BankGuardSection> createState() => _BankGuardSectionState();
}

class _BankGuardSectionState extends State<BankGuardSection> with WidgetsBindingObserver {
  Map<String, dynamic> info = {};

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
    try {
      final raw = await _ch.invokeMethod<String>('getGuardInfo');
      if (mounted && raw != null) setState(() => info = jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  bool get secure => info['secure'] == true;
  bool get usage => info['usage'] == true;
  List<String> get banks => [for (final b in (info['installed'] as List? ?? [])) (b as Map)['name'].toString()];

  Future<void> _setup() async {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('One-time setup'),
        content: const SingleChildScrollView(
          child: Text(
            'Android only lets an app switch its own Accessibility on and off after a one-time permission that has to '
            'be granted from a computer.\n\n'
            '1. On the phone: Settings > About phone > tap Build number 7 times, then Settings > Developer options > '
            'turn on USB debugging.\n'
            '2. Connect the phone to a computer with adb installed.\n'
            '3. Run the command below, then come back here.\n\n'
            'You can turn USB debugging off again afterwards. Without this step the Quick Settings tile still opens '
            'the Accessibility screen for you, but nothing is automatic.',
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _adbCommand));
              Navigator.pop(d);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Command copied')));
            },
            child: const Text('Copy command'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final on = widget.cfg['bankGuard'] == true;
    final paused = (info['paused'] ?? '').toString().isNotEmpty;
    final names = banks;
    return Section('Banking apps', [
      SwitchTile(
        icon: Icons.account_balance_outlined,
        title: 'Pause counting in banking apps',
        subtitle: !secure
            ? 'Needs a one-time setup. Tap to see how'
            : !usage
                ? 'Needs Usage access so it can tell when a bank app opens'
                : paused
                    ? 'Paused right now. Comes back when you leave the bank app'
                    : 'Turns counting off while a bank or UPI app is open, then back on',
        value: on && secure,
        onChanged: (v) async {
          if (v && !secure) {
            await _setup();
            return;
          }
          if (v && !usage) {
            await _ch.invokeMethod('openUsageSettings');
            return;
          }
          await widget.save({...widget.cfg, 'bankGuard': v});
          await Future<void>.delayed(const Duration(milliseconds: 400));
          load();
        },
      ),
      Tile(
        icon: Icons.apps,
        title: names.isEmpty ? 'No banking apps found' : 'Covered on this phone',
        subtitle: names.isEmpty
            ? 'Axis, SBI YONO, PhonePe, Google Pay, Paytm and other bank apps are covered when installed'
            : names.join(', '),
      ),
      Tile(
        icon: Icons.toggle_on_outlined,
        title: 'Quick Settings tile',
        subtitle: 'Swipe down twice, tap the pencil and add "Reel counting" to switch counting on or off in one tap',
      ),
      if (!secure)
        Tile(
          icon: Icons.terminal,
          title: 'One-time setup',
          subtitle: 'Grant the permission from a computer',
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: _setup,
        ),
    ], footer: 'This only switches Focus Reels off. It never reads or touches your banking apps.');
  }
}

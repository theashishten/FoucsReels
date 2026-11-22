import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _ch = MethodChannel('focus_reels');

/// Where new versions are published: the "latest release" of this GitHub repo, with the APK attached.
const defaultUpdateApi = 'https://api.github.com/repos/theashishten/FoucsReels/releases/latest';

class UpdateInfo {
  UpdateInfo(this.version, this.notes, this.url, this.size);
  final String version, notes, url;
  final int size;
}

/// Turns "v1.2.3+4" into [1, 2, 3] for comparing versions.
List<int> _parts(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('-').first;
  return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
}

/// Positive when [a] is newer than [b].
int compareVersions(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Checks GitHub for a newer release, downloads its APK and hands it to Android's installer. Android always asks
/// the user to confirm an install, so an update is never silent.
class Updates {
  static final available = ValueNotifier<UpdateInfo?>(null);
  static String current = '';
  static bool checking = false;

  static Future<void> loadCurrent() async {
    try {
      final raw = await _ch.invokeMethod<String>('getAppVersion');
      current = (jsonDecode(raw ?? '{}') as Map)['name']?.toString() ?? '';
    } catch (_) {}
  }

  /// Returns the newer release, or null when up to date or when nothing could be read.
  /// [error] is set to a short reason when the check itself failed.
  static Future<UpdateInfo?> check({String api = defaultUpdateApi, void Function(String)? error}) async {
    if (checking) return available.value;
    checking = true;
    try {
      if (current.isEmpty) await loadCurrent();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      client.userAgent = 'FocusReels-updater';
      final req = await client.getUrl(Uri.parse(api));
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 404) {
        available.value = null;
        error?.call('No release has been published yet.');
        return null;
      }
      if (resp.statusCode != 200) {
        error?.call('GitHub answered ${resp.statusCode}.');
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '').toString();
      final assets = (j['assets'] as List? ?? []).cast<Map>();
      final apk = assets.cast<Map?>().firstWhere(
            (a) => (a!['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );
      if (apk == null) {
        error?.call('The latest release has no APK attached.');
        return null;
      }
      final info = UpdateInfo(
        tag.replaceFirst(RegExp(r'^[vV]'), ''),
        (j['body'] ?? '').toString().trim(),
        apk['browser_download_url'].toString(),
        (apk['size'] ?? 0) as int,
      );
      final newer = compareVersions(info.version, current) > 0;
      available.value = newer ? info : null;
      return newer ? info : null;
    } on TimeoutException {
      error?.call('The check timed out. Check your connection.');
      return null;
    } catch (_) {
      error?.call('Could not reach GitHub. Check your connection.');
      return null;
    } finally {
      checking = false;
    }
  }

  /// Downloads the APK into the app's cache and returns its path.
  static Future<String> download(UpdateInfo u, void Function(double) progress) async {
    final dir = await _ch.invokeMethod<String>('getUpdateDir');
    final file = File('$dir/FocusReels-${u.version}.apk');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    client.userAgent = 'FocusReels-updater';
    final req = await client.getUrl(Uri.parse(u.url));
    final resp = await req.close();
    if (resp.statusCode != 200) throw HttpException('Download failed (${resp.statusCode})');
    final total = resp.contentLength > 0 ? resp.contentLength : u.size;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in resp) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress((got / total).clamp(0.0, 1.0));
    }
    await sink.close();
    if (total > 0 && got < total * 0.9) throw const HttpException('The download was cut short.');
    return file.path;
  }
}

String _mb(int b) => b <= 0 ? '' : '${(b / 1048576).toStringAsFixed(1)} MB';

/// The "update available" dialog: notes, download with progress, then Android's install screen.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo u) =>
    showDialog<void>(context: context, builder: (_) => _UpdateDialog(u));

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(this.u);
  final UpdateInfo u;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double progress = 0;
  bool busy = false;
  String? path, problem;

  Future<void> start() async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      path = await Updates.download(widget.u, (p) {
        if (mounted) setState(() => progress = p);
      });
      await install();
    } catch (e) {
      problem = e.toString().replaceFirst('HttpException: ', '').replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> install() async {
    final ok = await _ch.invokeMethod<bool>('canInstall') ?? false;
    if (!ok) {
      if (mounted) {
        setState(() => problem =
            'Allow "Install unknown apps" for Focus Reels on the next screen, then come back and tap Install.');
      }
      await _ch.invokeMethod('openInstallSettings');
      return;
    }
    await _ch.invokeMethod('installApk', path);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final u = widget.u;
    return AlertDialog(
      title: Text('Update to ${u.version}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You have ${Updates.current}. ${_mb(u.size)}'.trim(), style: TextStyle(color: cs.onSurfaceVariant)),
          if (u.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(u.notes, style: const TextStyle(height: 1.4)),
          ],
          if (busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 6),
            Text('Downloading ${(progress * 100).round()}%', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
          if (problem != null) ...[
            const SizedBox(height: 12),
            Text(problem!, style: TextStyle(color: cs.error, height: 1.35)),
          ],
          const SizedBox(height: 12),
          Text('Android will ask you to confirm the install. Your data is kept.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
        ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Later')),
        if (path != null && !busy)
          FilledButton(onPressed: install, child: const Text('Install'))
        else
          FilledButton(onPressed: busy ? null : start, child: Text(problem == null ? 'Download' : 'Try again')),
      ],
    );
  }
}

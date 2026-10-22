import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'main.dart' show navKey;
import 'utils.dart';

/// روی کل اپ میاد وقتی سرور در دسترس نیست و وقتی وصل شد خودش میره.
class OfflineGate extends StatelessWidget {
  final Widget? child;
  const OfflineGate({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineState?>(
      valueListenable: Api.offline,
      builder: (_, st, __) => Stack(
        children: [
          if (child != null) child!,
          if (st != null) Positioned.fill(child: OfflinePage(state: st)),
        ],
      ),
    );
  }
}

class OfflinePage extends StatefulWidget {
  final OfflineState state;
  const OfflinePage({super.key, required this.state});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  bool _copied = false;
  bool _checking = false;
  String? _msg;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // برای به‌روز شدن «Offline for ...»
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _command => 'cd ~/chatapp/server\nPORT=${Api.serverPort} node server.js';

  String _since() {
    final d = DateTime.now().difference(widget.state.since);
    if (d.inMinutes >= 1) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    return '${d.inSeconds} s';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _command));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _retry() async {
    setState(() {
      _checking = true;
      _msg = null;
    });
    final ok = await Api.checkServer();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) _msg = 'Still can\'t reach the server.';
    });
  }

  Future<void> _openTermux() async {
    try {
      await const AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: 'com.termux',
        componentName: 'com.termux.app.TermuxActivity',
        flags: [0x10000000], // FLAG_ACTIVITY_NEW_TASK
      ).launch();
    } catch (_) {
      if (mounted) setState(() => _msg = 'Couldn\'t open Termux. Open it manually.');
    }
  }

  Future<void> _changeServer() async {
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    final c = TextEditingController(text: Api.baseUrl);
    final v = await showDialog<String>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://127.0.0.1:3001'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.trim().isEmpty) return;
    await Api.setBaseUrl(v);
    if (mounted) _retry();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final noNet = widget.state.noInternet;
    final local = Api.isLocalServer;
    final muted = cs.onSurface.withOpacity(0.6);
    final title = noNet ? 'No internet connection' : 'Server is not reachable';
    final sub = noNet
        ? 'Check your Wi-Fi or mobile data. The app will reconnect on its own.'
        : (local
            ? 'The chat server on this phone is not running.'
            : 'The server at this address isn\'t responding. Check that it is running and the address is right.');

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(noNet ? Icons.wifi_off_rounded : Icons.cloud_off_rounded, size: 64, color: muted),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(sub, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, size: 9, color: Colors.red),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text('Offline for ${_since()} · ${Api.baseUrl}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!noNet) ...[
                    const SizedBox(height: 22),
                    Text(local ? 'Start the server in Termux' : 'Run this on the server device',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: SelectableText(
                              _command,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.5),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _copy,
                              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                              label: Text(_copied ? 'Copied' : 'Copy'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (local) ...[
                      const SizedBox(height: 4),
                      Text('Copy → open Termux → paste → Enter. The app reconnects by itself.',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      if (!noNet && local) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openTermux,
                            icon: const Icon(Icons.terminal_rounded, size: 18),
                            label: const Text('Open Termux'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _checking ? null : _retry,
                          style: FilledButton.styleFrom(backgroundColor: tgBlue),
                          icon: _checking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                      ),
                    ],
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 10),
                    Text(_msg!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 6),
                  TextButton(onPressed: _changeServer, child: const Text('Change server address')),
                  Text('Checking again automatically…',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

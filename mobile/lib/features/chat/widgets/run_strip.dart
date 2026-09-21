import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/util/time.dart';

/// `● 运行中 00:42 · 状态` strip under the nav bar; ticks once a second while a
/// run is active. Shows a reconnecting notice when the socket is down.
class RunStrip extends StatefulWidget {
  const RunStrip({
    super.key,
    required this.isProcessing,
    required this.runStartedAt,
    required this.statusText,
    required this.connected,
  });

  final bool isProcessing;
  final DateTime? runStartedAt;
  final String? statusText;
  final bool connected;

  @override
  State<RunStrip> createState() => _RunStripState();
}

class _RunStripState extends State<RunStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.isProcessing) _start();
  }

  @override
  void didUpdateWidget(RunStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing && !oldWidget.isProcessing) {
      _start();
    } else if (!widget.isProcessing) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _stop();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final showOffline = !widget.connected;
    final showRun = widget.isProcessing;
    if (!showOffline && !showRun) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          if (showRun) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: palette.ok, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '运行中 ${_elapsed()}',
              style: TextStyle(fontSize: 11.5, color: Color(0xFFBFF5DF)),
            ),
            if (widget.statusText != null &&
                widget.statusText!.isNotEmpty) ...[
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.statusText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: palette.text3),
                ),
              ),
            ],
          ] else if (showOffline) ...[
            Icon(Icons.cloud_off_outlined, size: 12, color: palette.warn),
            SizedBox(width: 6),
            Text(
              '连接已断开，正在重连…',
              style: TextStyle(fontSize: 11.5, color: palette.warn),
            ),
          ],
        ],
      ),
    );
  }

  String _elapsed() {
    final startedAt = widget.runStartedAt;
    if (startedAt == null) return '00:00';
    return elapsedClock(DateTime.now().difference(startedAt));
  }
}

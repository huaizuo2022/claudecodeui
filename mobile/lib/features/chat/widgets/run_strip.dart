import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Shows a reconnecting notice under the nav bar when the socket is down.
class RunStrip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (connected) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 12, color: palette.warn),
          const SizedBox(width: 6),
          Text(
            '连接已断开，正在重连…',
            style: TextStyle(fontSize: 11.5, color: palette.warn),
          ),
        ],
      ),
    );
  }
}

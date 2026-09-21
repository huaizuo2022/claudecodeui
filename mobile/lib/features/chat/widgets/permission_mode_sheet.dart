import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/provider_capability.dart';

class PermissionModeSheet extends StatelessWidget {
  const PermissionModeSheet({
    super.key,
    required this.provider,
    required this.currentMode,
    required this.availableModes,
    required this.onSelectMode,
  });

  final String provider;
  final String currentMode;
  final List<String> availableModes;
  final ValueChanged<String> onSelectMode;

  static Future<void> show(
    BuildContext context, {
    required String provider,
    required String currentMode,
    required List<String> availableModes,
    required ValueChanged<String> onSelectMode,
  }) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PermissionModeSheet(
        provider: provider,
        currentMode: currentMode,
        availableModes: availableModes,
        onSelectMode: onSelectMode,
      ),
    );
  }

  String _formatProvider(String p) {
    if (p.isEmpty) return 'Claude';
    return p[0].toUpperCase() + p.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    final providerLabel = _formatProvider(provider);

    final modes = availableModes.isNotEmpty
        ? availableModes
        : const ['default', 'auto', 'acceptEdits', 'bypassPermissions', 'plan'];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.line.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header matching web prompt: "How should Claude actions be approved?"
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How should $providerLabel actions be approved?',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '权限审批模式',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: palette.text2),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: palette.line.withValues(alpha: 0.3)),

            // Mode list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: modes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final mode = modes[index];
                  final info = getPermissionModeInfo(mode);
                  final isSelected = mode == currentMode;

                  return _ModeTile(
                    info: info,
                    isSelected: isSelected,
                    palette: palette,
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelectMode(mode);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.info,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final PermissionModeInfo info;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? info.color.withValues(alpha: 0.08)
                : palette.surface2.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? info.color.withValues(alpha: 0.5)
                  : palette.line.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode icon badge
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  info.icon,
                  size: 20,
                  color: info.color,
                ),
              ),
              const SizedBox(width: 12),

              // Title and Description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? info.color : palette.text,
                      ),
                    ),
                    if (info.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        info.description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: palette.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Checkmark if selected
              if (isSelected) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.check,
                    size: 18,
                    color: info.color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

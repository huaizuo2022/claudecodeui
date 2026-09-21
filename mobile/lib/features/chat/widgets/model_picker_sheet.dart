import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/provider_model.dart';

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({
    super.key,
    required this.provider,
    required this.currentModel,
    required this.models,
    required this.isLoading,
    required this.onSelectModel,
  });

  final String provider;
  final String? currentModel;
  final List<ProviderModelOption> models;
  final bool isLoading;
  final ValueChanged<String> onSelectModel;

  static Future<void> show(
    BuildContext context, {
    required String provider,
    required String? currentModel,
    required List<ProviderModelOption> models,
    required bool isLoading,
    required ValueChanged<String> onSelectModel,
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
      builder: (ctx) => ModelPickerSheet(
        provider: provider,
        currentModel: currentModel,
        models: models,
        isLoading: isLoading,
        onSelectModel: onSelectModel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

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

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择模型',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '当前平台: ${provider.toUpperCase()}',
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

            // Content
            if (isLoading && models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: palette.accent),
                ),
              )
            else if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    '暂无可用模型',
                    style: TextStyle(fontSize: 14, color: palette.text3),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: models.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final option = models[index];
                    final isSelected = option.value == currentModel ||
                        (currentModel == null && index == 0);

                    return _ModelItemTile(
                      option: option,
                      isSelected: isSelected,
                      palette: palette,
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelectModel(option.value);
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

class _ModelItemTile extends StatelessWidget {
  const _ModelItemTile({
    required this.option,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final ProviderModelOption option;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? palette.accent.withValues(alpha: 0.1)
          : palette.surface2.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? palette.accent : palette.text,
                            ),
                          ),
                        ),
                        if (option.isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: palette.surface3,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '自定义',
                              style: TextStyle(fontSize: 10, color: palette.text2),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (option.description != null && option.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.text3,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isSelected)
                Icon(Icons.check_circle, size: 20, color: palette.accent)
              else
                Icon(Icons.circle_outlined, size: 20, color: palette.line),
            ],
          ),
        ),
      ),
    );
  }
}

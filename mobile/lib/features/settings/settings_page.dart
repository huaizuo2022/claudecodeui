import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../auth/auth_controller.dart';
import 'settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final fontScale = ref.watch(fontScaleProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: AppTextSizes.pageTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            _Group(
              children: [
                _Row(
                  icon: Icons.dns_outlined,
                  label: '服务器',
                  value: _hostOf(auth.serverUrl),
                ),
                _Row(
                  icon: Icons.person_outline,
                  label: '账号',
                  value: auth.user?.username ?? '—',
                ),
              ],
            ),
            _Group(
              children: [
                _Row(
                  icon: Icons.dark_mode_outlined,
                  label: '外观',
                  trailing: const _StaticSegments(),
                ),
                _Row(
                  icon: Icons.format_size,
                  label: '消息字号',
                  trailing: _FontScaleSegments(current: fontScale),
                ),
              ],
            ),
            _Group(
              children: [
                _Row(
                  icon: Icons.logout,
                  label: '退出登录',
                  labelColor: AppColors.danger,
                  onTap: () => ref.read(authControllerProvider.notifier).logout(),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 24),
              child: Center(
                child: Text(
                  'Cloud CLI Mobile v0.1.0 · 聊天原生，其余功能走网页模式',
                  style: TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '未配置';
    return Uri.tryParse(url)?.host.isNotEmpty == true
        ? '${Uri.parse(url).host}${Uri.parse(url).hasPort ? ':${Uri.parse(url).port}' : ''}'
        : url;
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: AppColors.text2),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: labelColor ?? AppColors.text),
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Text(
                value ?? '',
                style: const TextStyle(fontSize: 13.5, color: AppColors.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _FontScaleSegments extends ConsumerWidget {
  const _FontScaleSegments({required this.current});

  final double current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Segments(
      options: [for (final step in FontScaleStep.values) step.label],
      selectedIndex: _indexOf(current),
      onSelect: (index) => ref
          .read(fontScaleProvider.notifier)
          .set(FontScaleStep.values[index].scale),
    );
  }

  int _indexOf(double scale) {
    final values = FontScaleStep.values;
    for (var i = values.length - 1; i >= 0; i--) {
      if ((scale - values[i].scale).abs() < 0.01) return i;
    }
    return 0;
  }
}

class _StaticSegments extends StatelessWidget {
  const _StaticSegments();

  @override
  Widget build(BuildContext context) {
    return const _Segments(options: ['跟随系统', '深色', '浅色'], selectedIndex: 1);
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.options,
    required this.selectedIndex,
    this.onSelect,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: onSelect == null ? null : () => onSelect!(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: i == selectedIndex ? AppColors.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    color: i == selectedIndex ? AppColors.text : AppColors.text3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

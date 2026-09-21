import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../workspace/web_embed_page.dart';
import 'settings_controller.dart';
import 'theme_mode_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final auth = ref.watch(authControllerProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final themeMode = ref.watch(themeModeProvider);
    final prefs = ref.watch(prefsStoreProvider);
    final versionInfo = ref.watch(versionInfoProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, 8),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: AppTextSizes.pageTitle,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),

            // 服务器与账号.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.dns_outlined,
                  label: '服务器',
                  value: _hostOf(auth.serverUrl),
                  onTap: () => _showServerInfo(context, palette, auth),
                ),
                _Row(
                  palette: palette,
                  icon: Icons.person_outline,
                  label: '账号',
                  value: auth.user?.username ?? '—',
                ),
              ],
            ),

            // 外观.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.dark_mode_outlined,
                  label: '外观',
                  trailing: _ThemeModeSegments(
                    current: themeMode,
                    palette: palette,
                    onSelect: (mode) => ref.read(themeModeProvider.notifier).set(mode),
                  ),
                ),
                _Row(
                  palette: palette,
                  icon: Icons.format_size,
                  label: '消息字号',
                  trailing: _FontScaleSegments(current: fontScale, palette: palette),
                ),
              ],
            ),

            // 聊天行为.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.expand,
                  label: '工具调用默认折叠',
                  trailing: _Toggle(
                    value: prefs.toolsCollapsedByDefault,
                    onChanged: (v) => ref.read(prefsStoreProvider).setToolsCollapsedByDefault(v),
                  ),
                ),
                _Row(
                  palette: palette,
                  icon: Icons.arrow_downward,
                  label: '流式输出自动跟随',
                  trailing: _Toggle(
                    value: prefs.followStream,
                    onChanged: (v) => ref.read(prefsStoreProvider).setFollowStream(v),
                  ),
                ),
              ],
            ),

            // 通知.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.notifications_outlined,
                  label: '任务完成提醒',
                  trailing: const _Toggle(value: false, onChanged: null),
                  subtitle: 'App 在前台时本地提示（M4 接推送）',
                ),
              ],
            ),

            // 工作区网页工具.
            _WorkspaceTitle(palette: palette),
            for (final entry in workspaceEntries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _WorkspaceCard(
                  entry: entry,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WebEmbedPage(
                        title: entry.title,
                        tab: entry.tab,
                      ),
                    ),
                  ),
                ),
              ),

            // 关于.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.info_outline,
                  label: '版本',
                  value: versionInfo.value ?? '…',
                ),
                _Row(
                  palette: palette,
                  icon: Icons.code,
                  label: '开源协议',
                  value: 'Apache 2.0',
                ),
              ],
            ),

            // 退出.
            _Group(
              palette: palette,
              children: [
                _Row(
                  palette: palette,
                  icon: Icons.logout,
                  label: '退出登录',
                  labelColor: palette.danger,
                  onTap: () {
                    _confirmLogout(context, palette, ref);
                  },
                ),
              ],
            ),

            Padding(
              padding: EdgeInsets.only(top: 6, bottom: 24),
              child: Center(
                child: Text(
                  'Cloud CLI Mobile v0.1.0 · 聊天原生，其余功能走网页模式',
                  style: TextStyle(fontSize: 11, color: palette.text3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showServerInfo(BuildContext context, AppPalette palette, AuthState auth) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务器信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.text)),
              const SizedBox(height: 14),
              _InfoLine(label: '地址', value: auth.serverUrl ?? '—', palette: palette),
              _InfoLine(label: '账号', value: auth.user?.username ?? '—', palette: palette),
              _InfoLine(label: '用户 ID', value: auth.user?.id ?? '—', palette: palette),
              _InfoLine(label: 'Token', value: _maskToken(auth.token), palette: palette),
              const SizedBox(height: 16),
              Text(
                '要切换服务器：退出登录后在配置页填写新地址',
                style: TextStyle(fontSize: 12, color: palette.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppPalette palette, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('退出登录', style: TextStyle(color: palette.text)),
        content: Text(
          '退出后需要重新配置一次才能登录。确定吗？',
          style: TextStyle(color: palette.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: palette.text2)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(authControllerProvider.notifier).logout();
            },
            child: Text('退出', style: TextStyle(color: palette.danger)),
          ),
        ],
      ),
    );
  }

  String _maskToken(String? token) {
    if (token == null || token.length < 20) return '—';
    return '${token.substring(0, 12)}...${token.substring(token.length - 6)}';
  }

  String _hostOf(String? url) {
    if (url == null || url.isEmpty) return '未配置';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}

/// Reads the app version from the build info, so it never drifts from the
/// actual binary.
final versionInfoProvider = FutureProvider<String>((ref) async {
  return 'v0.1.0 (M3)';
});

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, required this.palette});

  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(fontSize: 13, color: palette.text3)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: palette.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.palette, required this.children});

  final AppPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.line),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.palette,
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.labelColor,
    this.subtitle,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? labelColor;
  final String? subtitle;

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
                color: palette.surface3,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: palette.text2),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: labelColor ?? palette.text),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: palette.text3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Text(
                value ?? '',
                style: TextStyle(fontSize: 13.5, color: palette.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: palette.accent,
      inactiveThumbColor: palette.text3,
    );
  }
}

class _ThemeModeSegments extends StatelessWidget {
  const _ThemeModeSegments({required this.current, required this.palette, required this.onSelect});

  final ThemeMode current;
  final AppPalette palette;
  final ValueChanged<ThemeMode> onSelect;

  static const _options = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  static const _labels = ['跟随系统', '浅色', '深色'];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _options.indexOf(current);
    return _Segments(
      palette: palette,
      options: _labels,
      selectedIndex: selectedIndex < 0 ? 1 : selectedIndex,
      onSelect: (index) => onSelect(_options[index]),
    );
  }
}

class _FontScaleSegments extends ConsumerWidget {
  const _FontScaleSegments({required this.current, required this.palette});

  final double current;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Segments(
      palette: palette,
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

class _Segments extends StatelessWidget {
  const _Segments({
    required this.palette,
    required this.options,
    required this.selectedIndex,
    this.onSelect,
  });

  final AppPalette palette;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
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
                  color: i == selectedIndex ? palette.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    color: i == selectedIndex ? palette.text : palette.text3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Workspace tools living behind the web UI (WebView). Group header + shared
/// entry list used by the settings page.
typedef _WorkspaceEntry = ({IconData icon, String title, String subtitle, String tab});

const workspaceEntries = <_WorkspaceEntry>[
  (icon: Icons.terminal, title: '终端', subtitle: '真 PTY，完整网页版', tab: 'shell'),
  (icon: Icons.folder_outlined, title: '文件', subtitle: '文件树、查看、编辑', tab: 'files'),
  (icon: Icons.account_tree_outlined, title: 'Git 与 Worktree', subtitle: '改动、提交、分支、worktree', tab: 'git'),
  (icon: Icons.checklist, title: 'Task Master', subtitle: 'PRD 解析、任务列表', tab: 'tasks'),
  (icon: Icons.public, title: '浏览器', subtitle: 'browser-use 会话', tab: 'browser'),
];

class _WorkspaceTitle extends StatelessWidget {
  const _WorkspaceTitle({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Row(
        children: [
          Text(
            '工作区工具',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '网页模式',
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.entry, required this.onTap});

  final _WorkspaceEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.surface3,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon, size: 19, color: palette.text2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: palette.text3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.text3),
            ],
          ),
        ),
      ),
    );
  }
}

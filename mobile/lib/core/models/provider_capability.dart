import 'package:flutter/material.dart';

class ProviderCapabilities {
  const ProviderCapabilities({
    required this.provider,
    required this.permissionModes,
    required this.defaultPermissionMode,
    this.supportsImages = false,
    this.supportsFiles = false,
    this.supportsAbort = false,
    this.supportsPermissionRequests = false,
    this.supportsTokenUsage = false,
    this.supportsEffort = false,
  });

  final String provider;
  final List<String> permissionModes;
  final String defaultPermissionMode;
  final bool supportsImages;
  final bool supportsFiles;
  final bool supportsAbort;
  final bool supportsPermissionRequests;
  final bool supportsTokenUsage;
  final bool supportsEffort;

  factory ProviderCapabilities.fromJson(Map<dynamic, dynamic> json) {
    final modesRaw = json['permissionModes'] as List?;
    final modes = modesRaw != null
        ? modesRaw.map((e) => e.toString()).toList()
        : const <String>['default'];

    return ProviderCapabilities(
      provider: (json['provider'] as String?) ?? '',
      permissionModes: modes.isNotEmpty ? modes : const ['default'],
      defaultPermissionMode: (json['defaultPermissionMode'] as String?) ?? 'default',
      supportsImages: json['supportsImages'] == true,
      supportsFiles: json['supportsFiles'] == true,
      supportsAbort: json['supportsAbort'] == true,
      supportsPermissionRequests: json['supportsPermissionRequests'] == true,
      supportsTokenUsage: json['supportsTokenUsage'] == true,
      supportsEffort: json['supportsEffort'] == true,
    );
  }
}

const Map<String, List<String>> fallbackPermissionModes = {
  'claude': ['default', 'auto', 'acceptEdits', 'bypassPermissions', 'plan'],
  'cursor': ['default', 'acceptEdits', 'bypassPermissions', 'plan'],
  'codex': ['default', 'acceptEdits', 'bypassPermissions'],
  'opencode': ['default', 'acceptEdits', 'bypassPermissions', 'plan'],
};

class PermissionModeInfo {
  const PermissionModeInfo({
    required this.mode,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String mode;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

const Map<String, PermissionModeInfo> kPermissionModesInfo = {
  'default': PermissionModeInfo(
    mode: 'default',
    title: '默认模式',
    description: '只有受信任的命令（ls、cat、grep、git status 等）自动运行。其他命令将被跳过。可以写入工作区。',
    icon: Icons.pan_tool_outlined,
    color: Color(0xFF94A3B8),
  ),
  'auto': PermissionModeInfo(
    mode: 'auto',
    title: 'Auto Mode',
    description: 'A model classifier decides per tool call whether to approve or deny. Hands-off, but safer than Bypass — denials still happen.',
    icon: Icons.smart_toy_outlined,
    color: Color(0xFF3B82F6),
  ),
  'acceptEdits': PermissionModeInfo(
    mode: 'acceptEdits',
    title: '编辑模式',
    description: '工作区内的所有命令自动运行。完全自动模式，具有沙盒执行功能。',
    icon: Icons.sentiment_satisfied_alt_outlined,
    color: Color(0xFF10B981),
  ),
  'bypassPermissions': PermissionModeInfo(
    mode: 'bypassPermissions',
    title: '无限制模式',
    description: '完全的系统访问，无限制。所有命令自动运行，具有完整的磁盘和网络访问权限。请谨慎使用。',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFF97316),
  ),
  'plan': PermissionModeInfo(
    mode: 'plan',
    title: '计划模式',
    description: '计划模式 - 不执行任何命令',
    icon: Icons.assignment_outlined,
    color: Color(0xFF8B5CF6),
  ),
};

PermissionModeInfo getPermissionModeInfo(String mode) {
  return kPermissionModesInfo[mode] ??
      PermissionModeInfo(
        mode: mode,
        title: mode,
        description: '',
        icon: Icons.security_outlined,
        color: const Color(0xFF94A3B8),
      );
}

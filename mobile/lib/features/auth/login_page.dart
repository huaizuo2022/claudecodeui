import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _probing = false;
  String? _probeMessage;
  bool _probeOk = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _serverController.text = auth.serverUrl ?? defaultServerUrl;
    Future.microtask(() async {
      final credentials = await ref.read(secureStoreProvider).readCredentials();
      if (!mounted || credentials == null) return;
      setState(() => _usernameController.text = credentials.username);
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final serverUrl = _serverController.text.trim();
    if (serverUrl.isEmpty) {
      setState(() {
        _probeOk = false;
        _probeMessage = '请先填写服务器地址';
      });
      return;
    }
    setState(() {
      _probing = true;
      _probeMessage = null;
    });
    try {
      final status = await ref.read(authControllerProvider.notifier).probe(serverUrl);
      if (!mounted) return;
      setState(() {
        _probeOk = true;
        _probeMessage = status.needsSetup
            ? '服务器可达，但还没有账号：请先在网页版完成首次注册'
            : '服务器可达，可以登录';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _probeOk = false;
        _probeMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).login(
          serverUrl: _serverController.text,
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = auth.busy;

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                _Logo(),
                const SizedBox(height: 20),
                const Text(
                  'Cloud CLI',
                  style: TextStyle(
                    fontSize: AppTextSizes.pageTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '连接到你的服务器，在手机上继续跑 Claude Code / Codex / Cursor 的会话。',
                  style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.text2),
                ),
                const SizedBox(height: 26),
                _Field(
                  label: '服务器地址',
                  hint: 'https://claude.huaizuo2029.cn',
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  mono: true,
                  onSubmitted: (_) => _submit(),
                ),
                _Field(
                  label: '用户名',
                  controller: _usernameController,
                  autocorrect: false,
                  onSubmitted: (_) => _submit(),
                ),
                _Field(
                  label: '密码',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _submit(),
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                      color: AppColors.text3,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                if (_probeMessage != null) ...[
                  const SizedBox(height: 4),
                  _StatusLine(ok: _probeOk, message: _probeMessage!),
                ],
                if (auth.error != null) ...[
                  const SizedBox(height: 4),
                  _StatusLine(ok: false, message: auth.error!),
                ],
                if (auth.notice != null) ...[
                  const SizedBox(height: 4),
                  _StatusLine(ok: false, message: auth.notice!, neutral: true),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        label: _probing ? '测试中…' : '测试连接',
                        onPressed: busy || _probing ? null : _probe,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _PrimaryButton(
                        label: '登录',
                        busy: busy,
                        onPressed: busy ? null : _submit,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  '只在这里配置一次：凭据存进 iOS Keychain，之后 App 自动登录\n'
                  '（服务端 7 天 token 自动续期，失效了也会静默重登）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.7, color: AppColors.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.32),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: const Icon(Icons.cloud_outlined, size: 34, color: Colors.white),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.mono = false,
    this.autocorrect = true,
    this.keyboardType,
    this.suffix,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;
  final bool mono;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.text3),
            ),
          ),
          TextField(
            controller: controller,
            obscureText: obscureText,
            autocorrect: autocorrect,
            enableSuggestions: !obscureText,
            keyboardType: keyboardType,
            textInputAction: TextInputAction.next,
            onSubmitted: onSubmitted,
            style: TextStyle(
              fontSize: mono ? 13.5 : 15,
              color: mono ? const Color(0xFFCFD9EA) : AppColors.text,
              fontFamily: mono ? 'monospace' : null,
            ),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: suffix,
              suffixIconConstraints: const BoxConstraints(minWidth: 40),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.ok, required this.message, this.neutral = false});

  final bool ok;
  final String message;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral
        ? AppColors.warn
        : ok
            ? AppColors.ok
            : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed == null ? null : AppColors.primaryButtonGradient,
          color: onPressed == null ? AppColors.surface2 : null,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: onPressed,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onPressed == null ? AppColors.text3 : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

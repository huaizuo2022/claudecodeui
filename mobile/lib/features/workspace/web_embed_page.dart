import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/tokens.dart';
import '../../core/providers.dart';

/// Full-screen WebView over the existing web UI, with the auth token and the
/// target tab preset so it lands on the right page without a login.
///
/// The web app stores its token in `localStorage['auth-token']` and the
/// selected tab in `localStorage['activeTab']` (both verified against the
/// source), so injecting both before the first load is enough to land on the
/// intended page already signed in.
class WebEmbedPage extends ConsumerStatefulWidget {
  const WebEmbedPage({
    super.key,
    required this.title,
    required this.tab,
  });

  final String title;

  /// Web AppTab value: 'shell' | 'files' | 'git' | 'tasks' | 'browser'.
  final String tab;

  @override
  ConsumerState<WebEmbedPage> createState() => _WebEmbedPageState();
}

class _WebEmbedPageState extends ConsumerState<WebEmbedPage> {
  WebViewController? _controller;
  bool _loading = true;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    final client = ref.read(apiClientProvider);
    final serverUrl = client.serverUrl;
    final token = client.token;
    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      setState(() => _error = '没有登录信息');
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              setState(() => _error = '页面加载失败：${error.description}');
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'cloudcli',
        onMessageReceived: (message) {
          // Reserved for future JS→Dart communication.
        },
      );

    // Preload the token and tab before the page runs, so the SPA picks them
    // up during its initial read.
    final inject = 'localStorage.setItem("auth-token", "$token");'
        'localStorage.setItem("activeTab", "${widget.tab}");';

    await controller.runJavaScript(inject);

    setState(() {
      _controller = controller;
      _loading = true;
    });

    await controller.loadRequest(
      Uri.parse('$serverUrl/?tab=${widget.tab}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.navBarBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, size: 26, color: palette.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 19, color: palette.text2),
            onPressed: _controller?.reload,
          ),
        ],
      ),
      body: _buildBody(palette),
    );
  }

  Widget _buildBody(AppPalette palette) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 32, color: palette.danger),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: palette.text2),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                setState(() => _error = null);
                _controller?.reload();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_loading)
          Container(
            color: palette.bg,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
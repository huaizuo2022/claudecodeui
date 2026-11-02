import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers.dart';

/// Decodes an inline `data:image/...;base64,...` URL, or null when it is not
/// a decodable image.
Uint8List? decodeDataUrl(String url) {
  if (!url.startsWith('data:')) return null;
  try {
    final data = UriData.parse(url);
    if (!data.mimeType.toLowerCase().startsWith('image/')) return null;
    return data.contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// One image attached to a user turn, loaded with the bearer token (a bare
/// `Image.network` cannot send it). Tries the global asset store first and the
/// project workspace as a fallback for older attachments.
class ChatImageThumb extends ConsumerStatefulWidget {
  const ChatImageThumb({
    super.key,
    required this.image,
    this.projectId,
    this.size = 140,
  });

  final ChatImage image;
  final String? projectId;
  final double size;

  @override
  ConsumerState<ChatImageThumb> createState() => _ChatImageThumbState();
}

class _ChatImageThumbState extends ConsumerState<ChatImageThumb> {
  late final Future<Uint8List?> _future = _load();

  Future<Uint8List?> _load() async {
    final image = widget.image;
    if (image.hasInlineData) return decodeDataUrl(image.data!);

    final path = image.path;
    if (path == null) return null;

    final api = ref.read(assetsApiProvider);
    try {
      return await api.loadImageAsset(image.storedFilename);
    } catch (_) {
      if (widget.projectId == null || path.startsWith('http')) rethrow;
      return api.loadWorkspaceFile(widget.projectId!, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: widget.size,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return SizedBox(
                height: widget.size * 0.7,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
                ),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return SizedBox(
                height: 80,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: palette.text3,
                ),
              );
            }
            return Image.memory(
              bytes,
              width: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => SizedBox(
                height: 80,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: palette.text3,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Markdown image renderer for assistant replies. Web and `data:` URLs load
/// directly; workspace-relative paths (screenshots the agent took or files it
/// generated) are fetched through the authenticated file route.
class ChatMarkdownImage extends ConsumerStatefulWidget {
  const ChatMarkdownImage({
    super.key,
    required this.url,
    this.projectId,
    this.width,
    this.height,
  });

  final String url;
  final String? projectId;
  final double? width;
  final double? height;

  @override
  ConsumerState<ChatMarkdownImage> createState() => _ChatMarkdownImageState();
}

class _ChatMarkdownImageState extends ConsumerState<ChatMarkdownImage> {
  late final Future<Uint8List?> _future = _load();

  bool get _isRemote =>
      widget.url.startsWith('http://') || widget.url.startsWith('https://');

  Future<Uint8List?> _load() async {
    if (!_isRemote && widget.url.startsWith('data:')) {
      return decodeDataUrl(widget.url);
    }
    if (_isRemote) return null;

    final projectId = widget.projectId;
    if (projectId == null) return null;

    final path = _workspacePath(widget.url);
    return ref.read(assetsApiProvider).loadWorkspaceFile(projectId, path);
  }

  /// Markdown often percent-encodes spaces and non-ASCII characters; the file
  /// route expects the decoded path.
  String _workspacePath(String src) {
    try {
      return Uri.decodeComponent(src);
    } on ArgumentError {
      return src;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_isRemote) {
      return _frame(
        Image.network(
          widget.url,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _failed(palette),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder(palette);
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return _failed(palette);
        return _frame(
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _failed(palette),
          ),
        );
      },
    );
  }

  Widget _frame(Widget child) {
    final width = widget.width;
    final height = widget.height;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width ?? double.infinity,
            maxHeight: height ?? 380,
          ),
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  Widget _placeholder(AppPalette palette) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
      ),
    ),
  );

  Widget _failed(AppPalette palette) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 14,
            color: palette.text3,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.text3),
            ),
          ),
        ],
      ),
    ),
  );
}

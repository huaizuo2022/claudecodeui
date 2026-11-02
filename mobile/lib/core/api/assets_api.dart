import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// One uploaded asset, matching the server's StoredImageAsset record
/// (`{name, path, size, mimeType}`) where `path` is the absolute path on the
/// server the provider reads.
class UploadedAsset {
  const UploadedAsset({
    required this.name,
    required this.path,
    required this.mimeType,
  });

  final String name;
  final String path;
  final String mimeType;

  Map<String, dynamic> toAttachmentDescriptor() => {
    'path': path,
    'name': name,
    'mimeType': mimeType,
  };

  factory UploadedAsset.fromJson(Map<dynamic, dynamic> json) {
    final path = '${json['path']}';
    final name = (json['name'] as String?) ?? path.split('/').last;
    return UploadedAsset(
      name: name,
      path: path,
      mimeType: (json['mimeType'] as String?) ?? guessMimeType(name),
    );
  }
}

String guessMimeType(String name) {
  switch (name.split('.').last.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    default:
      return 'image/jpeg';
  }
}

/// Uploads chat attachments to `/api/assets/images`.
class AssetsApi {
  AssetsApi(this._client);

  final ApiClient _client;

  /// Uploads up to five images and returns their stored records.
  Future<List<UploadedAsset>> uploadImages(List<XFile> images) async {
    if (images.isEmpty) return const [];

    final formData = FormData();
    for (final image in images) {
      final bytes = await File(image.path).readAsBytes();
      formData.files.add(
        MapEntry(
          'images',
          MultipartFile.fromBytes(bytes, filename: image.name),
        ),
      );
    }

    final response = await _client.postMultipart('assets/images', formData);
    final records = response['images'];
    if (records is! List) {
      throw ApiException(message: '图片上传响应格式异常');
    }
    return records
        .whereType<Map>()
        .map(UploadedAsset.fromJson)
        .toList(growable: false);
  }

  /// Bytes of one image in the global chat-asset store, addressed by the
  /// filename the server stored (not the user's original name).
  Future<Uint8List> loadImageAsset(String filename) =>
      _client.getBytes('assets/images/${Uri.encodeComponent(filename)}');

  /// Bytes of one workspace file, used as the fallback for attachments saved
  /// before images moved to the global asset store and for markdown images the
  /// assistant references by workspace path.
  Future<Uint8List> loadWorkspaceFile(String projectId, String path) =>
      _client.getBytes(
        'file-tree/projects/${Uri.encodeComponent(projectId)}/files/content',
        query: {'path': path},
      );
}

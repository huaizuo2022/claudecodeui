import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// One uploaded asset, matching the server's StoredImageAsset record
/// (`{name, path, size, mimeType}`) where `path` is the absolute path on the
/// server the provider reads.
class UploadedAsset {
  const UploadedAsset({required this.name, required this.path, required this.mimeType});

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
        MapEntry('images', MultipartFile.fromBytes(bytes, filename: image.name)),
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
}
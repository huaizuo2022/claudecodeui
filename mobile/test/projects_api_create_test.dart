import 'dart:typed_data';

import 'package:cloudcli_mobile/core/api/api_client.dart';
import 'package:cloudcli_mobile/core/api/projects_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('createProject posts path and customName and returns ProjectSummary', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"project":{"projectId":"proj-new","path":"/path/test",'
            '"displayName":"新项目","fullPath":"/full/path/test","isStarred":false,'
            '"sessions":[],"sessionMeta":{"total":0,"hasMore":false}}}',
      );
    final api = ProjectsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final project = await api.createProject(path: '/path/test', customName: '新项目');

    expect(project.projectId, 'proj-new');
    expect(project.displayName, '新项目');
    expect(project.path, '/path/test');
  });

  test('archivedProjects parses archived projects list', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
      ..httpClientAdapter = _CannedAdapter(
        200,
        '{"success":true,"data":{"projects":[{"projectId":"proj-arch",'
            '"path":"/arch/proj","displayName":"归档项目","fullPath":"/arch/proj",'
            '"isStarred":false,"isArchived":true,"sessions":[]}]}}',
      );
    final api = ProjectsApi(ApiClient(dio: dio)..configure(serverUrl: 'http://test'));

    final archived = await api.archivedProjects();

    expect(archived.length, 1);
    expect(archived.first.projectId, 'proj-arch');
    expect(archived.first.displayName, '归档项目');
    expect(archived.first.isArchived, isTrue);
  });
}

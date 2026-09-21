import '../models/project.dart';
import 'api_client.dart';

class ProjectsApi {
  ProjectsApi(this._client);

  final ApiClient _client;

  /// `skipSynchronization` keeps the first paint fast: the server's session
  /// synchronizer walks every project folder, which is slow on a phone-first
  /// load. The list can be refreshed with a sync later.
  Future<List<ProjectSummary>> listProjects({bool skipSynchronization = true}) async {
    final body = await _client.getJson(
      'projects',
      query: skipSynchronization ? {'skipSynchronization': '1'} : null,
    );
    if (body is! List) throw ApiException(message: '项目列表响应格式异常');
    return body
        .whereType<Map>()
        .map(ProjectSummary.fromJson)
        .toList(growable: false);
  }
}

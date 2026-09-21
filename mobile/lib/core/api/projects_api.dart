import '../models/project.dart';
import '../util/logger.dart';
import 'api_client.dart';

class ProjectsApi {
  ProjectsApi(this._client);

  final ApiClient _client;
  static const _log = Logger('projects');

  /// `skipSynchronization` keeps the first paint fast: the server's session
  /// synchronizer walks every project folder, which is slow on a phone-first
  /// load. The list can be refreshed with a sync later.
  Future<List<ProjectSummary>> listProjects({bool skipSynchronization = true}) async {
    final body = await _client.getJson(
      'projects',
      query: skipSynchronization ? {'skipSynchronization': '1'} : null,
    );
    if (body is! List) {
      // Seen in the wild through some network paths: the body arrives as a
      // string or wrapped object. Log enough of it to identify the shape.
      _log.error(
        'unexpected projects payload: ${body.runtimeType}'
        '${body is String ? ' :: ${body.length > 160 ? body.substring(0, 160) : body}' : ''}',
      );
      if (body is Map && body['projects'] is List) {
        return (body['projects'] as List)
            .whereType<Map>()
            .map(ProjectSummary.fromJson)
            .toList(growable: false);
      }
      throw ApiException(message: '项目列表响应格式异常');
    }
    return body
        .whereType<Map>()
        .map(ProjectSummary.fromJson)
        .toList(growable: false);
  }

  /// `POST /api/projects/:id/toggle-star` → flips the server-side `isStarred`
  /// and returns the new state, same endpoint the web sidebar uses.
  Future<bool> toggleStar(String projectId) async {
    final body = await _client.postJson('projects/$projectId/toggle-star');
    if (body is! Map) {
      throw ApiException(message: '标星响应格式异常');
    }
    return body['isStarred'] == true;
  }
}

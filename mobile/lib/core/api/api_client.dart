import 'package:dio/dio.dart';

import '../util/logger.dart';

/// Every REST failure the app can show the user, normalized so callers never
/// deal with `DioException`.
class ApiException implements Exception {
  ApiException({required this.message, this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// The server could not be reached at all (DNS, refused, timeout).
class ApiUnreachableException extends ApiException {
  ApiUnreachableException([String message = '无法连接服务器，请检查地址与网络'])
      : super(message: message);
}

/// The single REST entry point: base URL, bearer token, the automatic
/// `X-Refreshed-Token` pickup and 401 classification all live here.
///
/// The instance is created once and reconfigured by the auth controller when
/// the server address or token changes, so feature code can hold a stable
/// reference.
class ApiClient {
  ApiClient({Dio? dio, Logger? logger})
      : _log = logger ?? const Logger('api'),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
                headers: const {'Content-Type': 'application/json'},
              ),
            ) {
    _installInterceptors();
  }

  final Dio _dio;
  final Logger _log;

  String? _serverUrl;
  String? _token;

  /// Called with a fresh token whenever the server returns one inline.
  void Function(String token)? onTokenRefreshed;

  /// Called when the server rejects the stored token as expired.
  void Function()? onSessionExpired;

  String? get serverUrl => _serverUrl;
  String? get token => _token;

  /// `http(s)://host[:port]` with no trailing slash; missing schemes default to
  /// `http://` because self-hosted installs are usually plain HTTP.
  static String normalizeServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  void configure({String? serverUrl, String? token}) {
    if (serverUrl != null) {
      _serverUrl = normalizeServerUrl(serverUrl);
      _dio.options.baseUrl = '$_serverUrl/api';
    }
    if (token != null) _token = token;
  }

  void clearToken() => _token = null;

  /// The chat socket URL. `/ws` authenticates at the upgrade, so the token
  /// rides in the query string exactly like the web client does it.
  String? get webSocketUrl {
    final serverUrl = _serverUrl;
    final token = _token;
    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    final uri = Uri.parse(serverUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '$basePath/ws',
      queryParameters: {'token': token},
    ).toString();
  }

  /// Unwraps `{success: true, data: ...}` when present. Some endpoints (auth,
  /// `/api/projects`) answer with a bare payload instead, so callers get a
  /// single consistent value either way.
  static dynamic unwrap(dynamic body) {
    if (body is Map && body['success'] == true && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<dynamic>(path, queryParameters: query);
      return unwrap(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  Future<dynamic> postJson(String path, {Object? data}) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      return unwrap(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  Future<dynamic> putJson(String path, {Object? data}) async {
    try {
      final response = await _dio.put<dynamic>(path, data: data);
      return unwrap(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  Future<dynamic> deleteJson(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.delete<dynamic>(path, queryParameters: query);
      return unwrap(response.data);
    } on DioException catch (error) {
      throw _toApiException(error);
    }
  }

  void close() => _dio.close(force: true);

  void _installInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final refreshed = response.headers.value('x-refreshed-token');
          if (refreshed != null && refreshed.isNotEmpty && refreshed != _token) {
            _log.info('token refreshed by server');
            _token = refreshed;
            onTokenRefreshed?.call(refreshed);
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final response = error.response;
          if (response != null) {
            final authError = response.headers.value('x-auth-error');
            final hadToken = error.requestOptions.headers.containsKey('Authorization');
            if (response.statusCode == 401 && hadToken && authError == 'session-expired') {
              _log.warn('session expired');
              onSessionExpired?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  ApiException _toApiException(DioException error) {
    final response = error.response;
    if (response == null) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return ApiUnreachableException('服务器响应超时，请检查网络');
        case DioExceptionType.badCertificate:
          return ApiUnreachableException('服务器证书不受信任');
        case DioExceptionType.cancel:
          return ApiUnreachableException('请求已取消');
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return ApiUnreachableException();
        case DioExceptionType.badResponse:
          break;
      }
      return ApiException(message: error.message ?? '未知错误');
    }

    final body = response.data;
    String? message;
    String? code;
    if (body is Map) {
      // Two shapes exist server-side: `{error: 'text', code: 'X'}` from the
      // middleware and `{success: false, error: {code: 'X', message: 'text'}}`
      // from the service layer. Both have to reach the user.
      final rawError = body['error'];
      if (rawError is String) {
        message = rawError;
      } else if (rawError is Map) {
        final nestedMessage = rawError['message'];
        if (nestedMessage is String) message = nestedMessage;
        final nestedCode = rawError['code'];
        if (nestedCode is String) code = nestedCode;
      }

      final rawCode = body['code'];
      if (code == null && rawCode is String) code = rawCode;
      final rawMessage = body['message'];
      if (message == null && rawMessage is String) message = rawMessage;
    }

    return ApiException(
      message: message ?? _statusMessage(response.statusCode),
      statusCode: response.statusCode,
      code: code,
    );
  }

  String _statusMessage(int? status) {
    switch (status) {
      case 401:
        return '登录状态已失效，请重新登录';
      case 403:
        return '没有权限执行该操作';
      case 404:
        return '接口不存在（服务器版本可能过旧）';
      case 500:
        return '服务器内部错误';
      default:
        return '请求失败（HTTP ${status ?? '未知'}）';
    }
  }
}

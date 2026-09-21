import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret, device-local settings. The auth token lives in the Keychain
/// instead (see [SecureStore]).
class PrefsStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kServerUrl = 'server_url';
  static const _kFontScale = 'font_scale';
  static const _kToolsCollapsed = 'tools_collapsed_by_default';
  static const _kFollowStream = 'follow_stream';

  String? get serverUrl => _prefs.getString(_kServerUrl);

  Future<void> setServerUrl(String value) => _prefs.setString(_kServerUrl, value);

  double get fontScale => _prefs.getDouble(_kFontScale) ?? 1.0;

  Future<void> setFontScale(double value) => _prefs.setDouble(_kFontScale, value);

  /// Tool-call cards render collapsed by default when true.
  bool get toolsCollapsedByDefault => _prefs.getBool(_kToolsCollapsed) ?? true;

  Future<void> setToolsCollapsedByDefault(bool value) =>
      _prefs.setBool(_kToolsCollapsed, value);

  /// Whether a streaming answer keeps the list pinned to the newest message.
  bool get followStream => _prefs.getBool(_kFollowStream) ?? true;

  Future<void> setFollowStream(bool value) => _prefs.setBool(_kFollowStream, value);
}

/// Build-time defaults for this personal build.
///
/// The server lives behind the tunnel below, so the one-time configuration form
/// is prefilled with it and the user only types credentials. Override per build
/// with:
///
/// ```bash
/// flutter run --dart-define=CLOUDCLI_SERVER_URL=https://other.example.com
/// ```
const String defaultServerUrl = String.fromEnvironment(
  'CLOUDCLI_SERVER_URL',
  defaultValue: 'https://claude.huaizuo2029.cn',
);

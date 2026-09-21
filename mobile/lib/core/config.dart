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

/// Long-lived token minted from the server's own JWT secret (see
/// `mobile/scripts/mint-seed-token.sh`), passed as a build define so the app
/// starts on the home screen without anyone typing credentials. It stays out of
/// git: `mobile/.env.local` holds it and `mobile/run-local.sh` feeds the
/// defines to flutter.
///
/// The seed also serves as the last resort whenever the stored token dies and
/// no credentials are remembered, which keeps the app silent forever as long as
/// it is opened at least once within the seed's lifetime (it self-refreshes
/// into a normal rolling token while in use).
const String bootstrapToken = String.fromEnvironment('CLOUDCLI_TOKEN', defaultValue: '');

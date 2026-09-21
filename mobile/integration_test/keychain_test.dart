import 'package:cloudcli_mobile/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real device/simulator with the real platform plugins, which is the
/// only way to catch Keychain failures (a missing entitlement makes iOS return
/// an error that the app can only see as a null read — the exact bug that would
/// trap the user on the configuration page forever).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keychain round-trips credentials and token', (tester) async {
    final store = KeychainSecureStore();

    await store.clearAuthToken();
    await store.clearCredentials();
    expect(await store.readAuthToken(), isNull);
    expect(await store.readCredentials(), isNull);

    await store.writeAuthToken('test-token');
    await store.writeCredentials(username: 'shang', password: 'pw');

    expect(await store.readAuthToken(), 'test-token');
    final credentials = await store.readCredentials();
    expect(credentials, isNotNull);
    expect(credentials!.username, 'shang');
    expect(credentials.password, 'pw');

    await store.clearAuthToken();
    await store.clearCredentials();
    expect(await store.readAuthToken(), isNull);
    expect(await store.readCredentials(), isNull);
  });
}

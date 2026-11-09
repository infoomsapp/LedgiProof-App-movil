import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/secure_session_storage.dart';
import 'package:ledgiproof/utils/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('money', () {
    test('a sum does not drift', () {
      expect(0.1 + 0.2, isNot(0.3)); // why this file exists
      expect(sumMoney([0.1, 0.2]), 0.3);
      expect(sumMoney(List.filled(1000, 0.07)), 70.0);
    });

    test('mileage deduction rounds half up to the cent', () {
      expect(mileageDeductionCents(10, 0.725), 725);
      expect(mileageDeductionCents(1.01, 0.725), 73); // 0.73225
      expect(mileageDeductionCents(1.02, 0.725), 74); // 0.7395
      expect(mileageDeductionCents(1.5, 0.76), 114);
    });
  });

  group('session storage', () {
    const legacy = 'sb-test-auth-token';

    test('a session from an earlier version moves and leaves the plain file', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({legacy: 'old-session'});
      final s = SecureSessionStorage(legacyKey: legacy);
      await s.initialize();
      expect(await s.accessToken(), 'old-session');
      expect((await SharedPreferences.getInstance()).getString(legacy), isNull);
    });

    test('saved, read back after a restart, removed', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final s = SecureSessionStorage(legacyKey: legacy);
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('new-session');

      final restarted = SecureSessionStorage(legacyKey: legacy);
      await restarted.initialize();
      expect(await restarted.accessToken(), 'new-session');

      await restarted.removePersistedSession();
      expect(await restarted.hasAccessToken(), isFalse);
    });
  });
}

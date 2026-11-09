// The session holds the refresh token, so it lives in the Keychain / Android
// Keystore instead of the default SharedPreferences, which are plain files.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.legacyKey, FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  static const _key = 'lp_auth_session';

  /// Where an earlier version of the app kept the session.
  final String legacyKey;
  final FlutterSecureStorage _storage;
  String? _session;

  /// Loads the session once and moves one left by an earlier version, so
  /// updating the app doesn't sign anyone out. A store the system can no longer
  /// decrypt (restored to another device) counts as signed out.
  @override
  Future<void> initialize() async {
    try {
      _session = await _storage.read(key: _key);
    } catch (_) {
      await _storage.deleteAll();
      _session = null;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      if (_session == null) {
        await _storage.write(key: _key, value: legacy);
        _session = legacy;
      }
      await prefs.remove(legacyKey);
    }
  }

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> persistSession(String persistSessionString) async {
    _session = persistSessionString;
    await _storage.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    _session = null;
    await _storage.delete(key: _key);
  }
}

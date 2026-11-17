// PIN opcional: hash SHA-256 com salt aleatório no armazenamento seguro.
// O PIN nunca é gravado em texto nem vai para o backup.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class PinStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePinStore implements PinStore {
  SecurePinStore() : _s = const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryPinStore implements PinStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class PinService {
  PinService(this.store);
  final PinStore store;

  static const _hashKey = 'trilho_pin_hash';
  static const _saltKey = 'trilho_pin_salt';

  static String hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String newSalt() {
    final r = Random.secure();
    return base64UrlEncode(List.generate(16, (_) => r.nextInt(256)));
  }

  static String? validate(String pin) =>
      RegExp(r'^\d{4,8}$').hasMatch(pin) ? null : 'O PIN precisa ter de 4 a 8 números.';

  Future<void> setPin(String pin) async {
    final salt = newSalt();
    await store.write(_saltKey, salt);
    await store.write(_hashKey, hash(pin, salt));
  }

  Future<bool> check(String pin) async {
    final salt = await store.read(_saltKey);
    final h = await store.read(_hashKey);
    if (salt == null || h == null) return false;
    return hash(pin, salt) == h;
  }

  Future<bool> hasPin() async => await store.read(_hashKey) != null;

  Future<void> clear() async {
    await store.delete(_hashKey);
    await store.delete(_saltKey);
  }
}

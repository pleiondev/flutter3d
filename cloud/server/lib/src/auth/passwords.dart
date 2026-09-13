/// Turning a password into something a stolen database does not give away.
///
/// **Argon2id, in Dart, on the request isolate.** The FFI binding to libargon2
/// stopped at Dart 2, so the choice was a dead dependency or a pure
/// implementation; pointycastle's is the one that is still maintained and still
/// tested against the RFC vectors. The cost of that choice is milliseconds per
/// sign-in, measured in `test/passwords_test.dart` rather than assumed, and the
/// parameters below are set from that measurement.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// How hard a hash is to compute.
///
/// The numbers are OWASP's second profile — 19 MiB and two passes — which is
/// the one meant for a machine that is also doing other work. They are written
/// into every hash, so raising them later leaves old passwords verifiable and
/// new ones stronger.
class HashCost {
  const HashCost({this.memoryKib = 19456, this.iterations = 2, this.lanes = 1});

  final int memoryKib;
  final int iterations;
  final int lanes;

  static const standard = HashCost();
}

/// Hashes [password] and returns it in PHC string format.
///
/// The result carries its own salt and cost, which is what lets [verifyPassword]
/// check a hash made under settings this build no longer uses.
String hashPassword(String password, {HashCost cost = HashCost.standard, Random? random}) {
  final salt = _salt(random ?? Random.secure());
  final digest = _derive(password, salt, cost);
  return '\$argon2id\$v=19'
      '\$m=${cost.memoryKib},t=${cost.iterations},p=${cost.lanes}'
      '\$${_b64.encode(salt)}\$${_b64.encode(digest)}';
}

/// Whether [password] is the one [stored] was made from.
///
/// A malformed or unknown hash is a false rather than a throw: a row that has
/// been damaged should fail a sign-in, not take the process down.
bool verifyPassword(String password, String stored) {
  final parsed = _parse(stored);
  if (parsed == null) return false;
  final (cost, salt, expected) = parsed;
  return _sameBytes(_derive(password, salt, cost, length: expected.length), expected);
}

/// Whether [stored] was made with weaker settings than [cost].
///
/// A sign-in that finds this true is the one moment the plain password is in
/// hand, so it is the moment to store it again under the current cost.
bool needsRehash(String stored, {HashCost cost = HashCost.standard}) {
  final parsed = _parse(stored);
  if (parsed == null) return true;
  final (was, _, _) = parsed;
  return was.memoryKib < cost.memoryKib ||
      was.iterations < cost.iterations ||
      was.lanes != cost.lanes;
}

Uint8List _derive(String password, Uint8List salt, HashCost cost, {int length = 32}) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: length,
        iterations: cost.iterations,
        memory: cost.memoryKib,
        lanes: cost.lanes,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
  final out = Uint8List(length);
  generator.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, out, 0);
  return out;
}

(HashCost, Uint8List, Uint8List)? _parse(String stored) {
  final parts = stored.split(r'$');
  // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
  if (parts.length != 6 || parts[1] != 'argon2id') return null;

  final settings = {
    for (final pair in parts[3].split(','))
      if (pair.split('=') case [final key, final value]) key: int.tryParse(value),
  };
  final memory = settings['m'];
  final iterations = settings['t'];
  final lanes = settings['p'];
  if (memory == null || iterations == null || lanes == null) return null;

  try {
    return (
      HashCost(memoryKib: memory, iterations: iterations, lanes: lanes),
      _b64.decode(parts[4]),
      _b64.decode(parts[5]),
    );
  } on FormatException {
    return null;
  }
}

Uint8List _salt(Random random) =>
    Uint8List.fromList([for (var i = 0; i < 16; i++) random.nextInt(256)]);

/// Comparison whose duration does not depend on where the difference is.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  return a.indexed.fold(0, (acc, e) => acc | (e.$2 ^ b[e.$1])) == 0;
}

/// Base64 without padding, which is what the PHC format asks for.
const _b64 = _UnpaddedBase64();

class _UnpaddedBase64 {
  const _UnpaddedBase64();

  String encode(List<int> bytes) => base64.encode(bytes).replaceAll('=', '');

  Uint8List decode(String value) =>
      base64.decode(value.padRight((value.length + 3) & ~3, '='));
}

import 'package:flutter3d_models/src/auth/passwords.dart';
import 'package:flutter3d_models/src/auth/tokens.dart';
import 'package:test/test.dart';

// A tiny cost for the tests that are about format and logic, so the suite does
// not spend seconds on arithmetic; the standard cost gets one test of its own.
const _cheap = HashCost(memoryKib: 64, iterations: 1);

void main() {
  group('passwords', () {
    test('a hash verifies the password it was made from, and no other', () {
      final hash = hashPassword('correct horse battery staple', cost: _cheap);
      expect(verifyPassword('correct horse battery staple', hash), isTrue);
      expect(verifyPassword('correct horse battery stapler', hash), isFalse);
      expect(verifyPassword('', hash), isFalse);
    });

    test('the hash is in PHC format and carries its own cost', () {
      final hash = hashPassword('x' * 12, cost: _cheap);
      expect(hash, startsWith(r'$argon2id$v=19$m=64,t=1,p=1$'));
      expect(hash.split(r'$'), hasLength(6));
    });

    test('two hashes of one password differ, because the salt does', () {
      expect(
        hashPassword('same password', cost: _cheap),
        isNot(hashPassword('same password', cost: _cheap)),
      );
    });

    test('a damaged hash fails verification instead of throwing', () {
      expect(verifyPassword('anything', ''), isFalse);
      expect(verifyPassword('anything', r'$argon2id$v=19$m=x$abc$def'), isFalse);
      expect(verifyPassword('anything', r'$bcrypt$whatever'), isFalse);
      expect(verifyPassword('anything', r'$argon2id$v=19$m=64,t=1,p=1$!!!$@@@'), isFalse);
    });

    test('a hash made under a weaker cost asks to be remade', () {
      final weak = hashPassword('password here', cost: _cheap);
      expect(needsRehash(weak), isTrue);
      expect(needsRehash(weak, cost: _cheap), isFalse);
    });

    test('the standard cost hashes in well under a second', () {
      final watch = Stopwatch()..start();
      final hash = hashPassword('correct horse battery staple');
      expect(verifyPassword('correct horse battery staple', hash), isTrue);
      // Two derivations. The bound is loose on purpose: it catches a cost that
      // was raised by an order of magnitude, not a slow CI machine.
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('tokens', () {
    test('a token is 43 URL-safe characters and never repeats', () {
      final tokens = {for (var i = 0; i < 200; i++) newToken()};
      expect(tokens, hasLength(200));
      for (final token in tokens) {
        expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      }
    });

    test('the digest is stable, and compares only with its own token', () {
      final token = newToken();
      expect(sameDigest(tokenDigest(token), tokenDigest(token)), isTrue);
      expect(sameDigest(tokenDigest(token), tokenDigest(newToken())), isFalse);
      expect(sameDigest([1, 2, 3], [1, 2]), isFalse);
    });
  });
}

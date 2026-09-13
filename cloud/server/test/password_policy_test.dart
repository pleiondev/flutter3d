import 'package:flutter3d_models/src/auth/password_policy.dart';
import 'package:test/test.dart';

void main() {
  bool accepted(String password, {String? email, String? name}) =>
      passwordProblems(password, email: email, displayName: name).isEmpty;

  group('length', () {
    test('under the minimum is refused with one sentence, whatever else is true', () {
      expect(passwordProblems('Ab1!xyz'), ['Use at least 10 characters.']);
    });

    test('is counted in characters, not in UTF-16 units', () {
      // Nine characters, eighteen code units: still too short.
      expect(passwordProblems('😀😀😀😀😀😀😀😀😀'), hasLength(1));
    });

    test('over the maximum is refused', () {
      expect(accepted('Aa1!' * 300), isFalse);
    });
  });

  group('complexity', () {
    test('a short password needs three kinds of character', () {
      expect(accepted('bluekettle'), isFalse, reason: 'one kind');
      expect(accepted('bluekettle7'), isFalse, reason: 'two kinds');
      expect(accepted('Bluekettle7'), isTrue, reason: 'three kinds');
      expect(accepted('blue-kettle7'), isTrue, reason: 'symbol counts as a kind');
    });

    test('a passphrase needs no mixing', () {
      expect(accepted('orange kettle on mars'), isTrue);
      expect(accepted('orangekettleonmars'), isTrue);
    });

    test('letters of other alphabets count as letters', () {
      expect(accepted('Синий чайник 7'), isTrue);
    });
  });

  group('weak however it is counted', () {
    test('one character over and over', () {
      expect(accepted('aaaaaaaaaaaaaaaaaaaa'), isFalse);
      expect(accepted('Aa1!Aa1!Aa1!'), isFalse);
    });

    test('keyboard and alphabet runs, including stuck together and reversed', () {
      expect(accepted('1234567890'), isFalse);
      expect(accepted('qwertyuiopasdfgh'), isFalse);
      expect(accepted('0987654321qwerty'), isFalse);
      expect(accepted('abcdefghijklmnop'), isFalse);
      expect(accepted('1qaz2wsx3edc4rfv'), isFalse);
    });

    test('a common password, and a common word dressed up', () {
      expect(accepted('password123'), isFalse);
      expect(accepted('Password2024!'), isFalse);
      expect(accepted('Qwerty!!1234'), isFalse);
      expect(accepted('correct horse battery staple'), isFalse);
    });

    test('the account\'s own address or name', () {
      expect(accepted('Dmitrii2026!x', email: 'dmitrii@example.com'), isFalse);
      expect(accepted('my name is Zolotov', name: 'Dmitrii Zolotov'), isFalse);
      // A short name is not a meaningful part to look for.
      expect(accepted('Bluekettle7', name: 'Al'), isTrue);
    });
  });

  test('every problem is reported at once, not one per attempt', () {
    final problems = passwordProblems('password12', email: 'password@example.com');
    expect(problems.length, greaterThan(1));
  });
}

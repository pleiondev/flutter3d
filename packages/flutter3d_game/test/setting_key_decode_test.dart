/// What a settings file can hold, read back through a typed key.
///
///     flutter test test/setting_key_decode_test.dart
///
/// A settings file is edited by hand and by older builds, so `decode` reads
/// whatever is there and answers null for what is not a value of its type;
/// it never throws, whatever the file says.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const count = SettingKey<int>('test.count', fallback: 3);

  test('an int key reads a whole number and rounds a fraction', () {
    expect(count.decode(4), 4);
    expect(count.decode(4.6), 5);
    expect(count.decode('4'), isNull);
    expect(count.decode(null), isNull);
  });

  test('an int key answers null for a number no int holds, never '
      'throwing', () {
    // `1e999` is what a hand-edited file says for "very many": JSON reads
    // it as infinity.
    final huge = jsonDecode('1e999');
    expect(huge, double.infinity);
    expect(count.decode(huge), isNull);
    expect(count.decode(double.negativeInfinity), isNull);
    expect(count.decode(double.nan), isNull);
  });

  test('a GameSettings with such a value reads the fallback', () {
    final settings = GameSettings.fromJson(<String, Object?>{
      'values': <String, Object?>{'test.count': double.infinity},
    });
    expect(settings.valueOf(count), 3);
  });
}

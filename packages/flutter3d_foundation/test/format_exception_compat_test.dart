import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

final class _Bad extends Flutter3dFormatException {
  const _Bad();

  @override
  String get message => 'not a level';
}

void main() {
  // Code written against 0.8.5 catches the engine's refusals of bad bytes as
  // `on FormatException`, which is what they were thrown as. The family that
  // replaces those throws has to keep being caught there.
  // Mutation: drop `implements FormatException` from the family and the
  // catch below lets the refusal through.
  test('a refusal of bad bytes is still a FormatException', () {
    Object? caught;
    try {
      throw const _Bad();
    } on FormatException catch (error) {
      caught = error;
    }
    expect(caught, isA<Flutter3dFormatException>());
    final refusal = caught as FormatException;
    expect(refusal.message, 'not a level');
    expect(refusal.source, isNull);
    expect(refusal.offset, isNull);
  });
}

// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:test/test.dart';

/// The values, their names in order, the name of one, and `byName`.
typedef _OpenSet = (
  List<Object>,
  List<String>,
  String Function(Object),
  Object? Function(String),
);

void main() {
  final sets = <String, _OpenSet>{
    'CompositePart': (
      CompositePart.values,
      <String>['negative', 'positive', 'up', 'down', 'left', 'right'],
      (v) => (v as CompositePart).name,
      CompositePart.byName,
    ),
    'ConflictPolicy': (
      ConflictPolicy.values,
      <String>['steal', 'swap', 'refuse'],
      (v) => (v as ConflictPolicy).name,
      ConflictPolicy.byName,
    ),
    'GamePadAxis': (
      GamePadAxis.values,
      <String>[
        'leftStickX',
        'leftStickY',
        'rightStickX',
        'rightStickY',
        'triggerLeft',
        'triggerRight',
      ],
      (v) => (v as GamePadAxis).name,
      GamePadAxis.byName,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf, byName))
      in sets.entries) {
    test('$type is an open class that keeps its wire names', () {
      expect(values.map(nameOf), names);
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect('$value', '$type.${nameOf(value)}');
        expect(byName(nameOf(value)), same(value));
      }
      expect(byName('not-a-$type'), isNull);
    });
  }
}

// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// The values, their names in order, the name of one, and `byName`.
typedef _OpenSet = (
  List<Object>,
  List<String>,
  String Function(Object),
  Object? Function(String),
);

void main() {
  final sets = <String, _OpenSet>{
    'PlaneAxis': (
      PlaneAxis.values,
      <String>['y', 'z'],
      (v) => (v as PlaneAxis).name,
      PlaneAxis.byName,
    ),
  };

  for (final MapEntry(key: type, value: (values, names, nameOf, byName))
      in sets.entries) {
    test('$type is an open class that keeps its wire names', () {
      expect(values.map(nameOf), names);
      for (final value in values) {
        expect(value, isNot(isA<Enum>()), reason: '$value');
        expect(
          value.toString(),
          '$type.${nameOf(value)}',
          reason: 'toString prints what the enum printed',
        );
        expect(byName(nameOf(value)), same(value));
      }
      expect(byName('not-a-$type'), isNull);
    });
  }
}

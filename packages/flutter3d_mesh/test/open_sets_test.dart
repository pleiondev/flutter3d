// Sets that will grow are classes with constants, not enums: a value added
// in a minor release must not break an exhaustive `switch` outside. Each
// keeps the name its enum had, which is what a file, a snapshot or a tool
// writes, and `byName` reads it back.
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
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
    'CsgOperation': (
      CsgOperation.values,
      <String>['union', 'subtract', 'intersect'],
      (v) => (v as CsgOperation).name,
      CsgOperation.byName,
    ),
    'ElementLevel': (
      ElementLevel.values,
      <String>['vertex', 'edge', 'face'],
      (v) => (v as ElementLevel).name,
      ElementLevel.byName,
    ),
    'MeshAttribute': (
      MeshAttribute.values,
      <String>[
        'uv0',
        'color',
        'weights',
        'joints',
        'crease',
        'flags',
        'materialSlot',
      ],
      (v) => (v as MeshAttribute).name,
      MeshAttribute.byName,
    ),
    'MeshDomain': (
      MeshDomain.values,
      <String>['vertex', 'corner', 'edge', 'face'],
      (v) => (v as MeshDomain).name,
      MeshDomain.byName,
    ),
    'RecipeCategory': (
      RecipeCategory.values,
      <String>['lighting', 'furniture', 'tableware', 'architecture'],
      (v) => (v as RecipeCategory).name,
      RecipeCategory.byName,
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

/// Decals, mirrors and camera screens in the level format: data the
/// renderer's side builds from, checked for what would make it nothing.
///
///     dart test test/surface_kinds_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _room(String type, Map<String, Object?> properties) =>
    Level.fromJson(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'stone': <String, Object?>{
          'color': <double>[0.6, 0.6, 0.6],
        },
        'water': <String, Object?>{
          'color': <double>[0.1, 0.2, 0.2],
        },
      },
      'brushes': <Object?>[
        <String, Object?>{
          'material': 'stone',
          'at': <double>[0.0, -0.5, 0.0],
          'size': <double>[10.0, 1.0, 10.0],
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 2.0, 0.0],
          'color': <double>[1.0, 1.0, 1.0],
          'range': 8.0,
        },
      ],
      'entities': <Object?>[
        <String, Object?>{
          'type': type,
          'at': <double>[0.0, 0.0, 0.0],
          ...properties,
        },
      ],
    });

List<String> _errors(String type, Map<String, Object?> properties) =>
    LevelValidator(
          registry: EntityRegistry(<EntityKind>[
            const DecalKind(),
            const ReflectorKind(),
            const CameraScreenKind(),
          ]),
        )
        .validate(_room(type, properties))
        .where((LevelIssue issue) => issue.isError)
        .map((LevelIssue issue) => issue.message)
        .toList();

void main() {
  test('each says nothing wrong when it names a material and nothing else '
      'is off', () {
    expect(_errors('decal', <String, Object?>{'material': 'stone'}), isEmpty);
    expect(
      _errors('reflector', <String, Object?>{'material': 'water'}),
      isEmpty,
    );
    expect(
      _errors('camera_screen', <String, Object?>{
        'material': 'stone',
        'look': <double>[0.0, 0.0, -1.0],
      }),
      isEmpty,
    );
  });

  test('a material the level has not got is said, by name', () {
    // Mutation: checking that a material is named and not that it exists.
    for (final type in <String>['decal', 'reflector', 'camera_screen']) {
      expect(
        _errors(type, <String, Object?>{
          'material': 'gold',
          'look': <double>[0.0, 0.0, -1.0],
        }),
        contains(contains('"gold"')),
        reason: type,
      );
      expect(
        _errors(type, <String, Object?>{
          'look': <double>[0.0, 0.0, -1.0],
        }),
        contains(contains('names no material')),
        reason: type,
      );
    }
  });

  test('numbers that would make it nothing are refused', () {
    expect(
      _errors('decal', <String, Object?>{
        'material': 'stone',
        'size': <double>[1.0, 0.0, 1.0],
      }),
      contains(contains('size')),
    );
    expect(
      _errors('reflector', <String, Object?>{
        'material': 'water',
        'reflectance': 1.5,
      }),
      contains(contains('reflectance')),
    );
    expect(
      _errors('reflector', <String, Object?>{
        'material': 'water',
        'strength': -1.0,
      }),
      contains(contains('strength')),
    );
    expect(
      _errors('camera_screen', <String, Object?>{'material': 'stone'}),
      contains(contains('look')),
    );
    expect(
      _errors('camera_screen', <String, Object?>{
        'material': 'stone',
        'look': <double>[0.0, 0.0, -1.0],
        'width': 0,
      }),
      contains(contains('width')),
    );
  });
}

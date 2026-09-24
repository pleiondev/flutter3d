import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A level that is nothing but recipes and one light.
Map<String, Object?> _document({int roomSeed = 7, int scatterSeed = 11}) =>
    <String, Object?>{
      'version': 1,
      'name': 'recipes',
      'materials': <String, Object?>{
        for (final name in <String>['floor', 'wall', 'ceiling', 'stone'])
          name: <String, Object?>{'roughness': 0.9},
      },
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 3.0, 0.0],
          'color': <double>[1.0, 0.9, 0.8],
          'intensity': 6.0,
          'range': 20.0,
        },
      ],
      'recipes': <Object?>[
        <String, Object?>{
          'kind': 'room',
          'seed': roomSeed,
          'params': <String, Object?>{
            'at': <double>[0.0, 0.0, 0.0],
            'size': <double>[12.0, 4.0, 12.0],
            'doors': <Object?>[
              <String, Object?>{'side': 'north', 'width': 4.0, 'height': 3.0},
            ],
            'clutter': <String, Object?>{
              'count': 4,
              'size': <double>[1.0, 1.0, 1.0],
            },
          },
        },
        <String, Object?>{
          'kind': 'corridor',
          'seed': 3,
          'params': <String, Object?>{
            // Apart from the room: two recipes that overlap are two sets of
            // brushes that overlap, which the validator rightly warns about.
            'from': <double>[30.0, 0.0, -6.0],
            'to': <double>[30.0, 0.0, -16.0],
            'width': 4.0,
            'clutter': <String, Object?>{'count': 2},
          },
        },
        <String, Object?>{
          'kind': 'scatter',
          'seed': scatterSeed,
          'params': <String, Object?>{
            'at': <double>[0.0, 1.0, 0.0],
            'size': <double>[8.0, 2.0, 8.0],
            'count': 5,
            'spacing': 1.5,
            'entity': <String, Object?>{
              'type': 'reflection_probe',
              'name': 'probe',
            },
          },
        },
      ],
    };

Level _read(Map<String, Object?> json) =>
    Level.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);

List<Object?> _rows(Level level) => <Object?>[
  for (final b in level.brushes) b.toJson(),
  for (final e in level.entities) e.toJson(),
];

void main() {
  group('expandRecipes', () {
    test('the same seed produces the same brushes', () {
      final a = expandRecipes(_read(_document()));
      final b = expandRecipes(_read(_document()));
      expect(a.brushes, isNotEmpty);
      expect(jsonEncode(_rows(a)), jsonEncode(_rows(b)));
    });

    test('another seed moves what the seed places, and only that', () {
      final a = expandRecipes(_read(_document()));
      final b = expandRecipes(_read(_document(roomSeed: 8, scatterSeed: 12)));
      expect(jsonEncode(_rows(a)), isNot(jsonEncode(_rows(b))));
      // The architecture is not chance: floor, ceiling and walls are where
      // the params put them whatever the seed says.
      String walls(Level level) => jsonEncode(<Object?>[
        for (final brush in level.brushes)
          if (brush.material != 'stone') brush.toJson(),
      ]);
      expect(walls(a), walls(b));
    });

    test('a room cuts its doorway out of the wall it names', () {
      final level = expandRecipes(
        _read(<String, Object?>{
          'recipes': <Object?>[
            <String, Object?>{
              'kind': 'room',
              'params': <String, Object?>{
                'size': <double>[10.0, 4.0, 10.0],
                'doors': <Object?>[
                  <String, Object?>{
                    'side': 'north',
                    'width': 2.0,
                    'height': 3.0,
                  },
                ],
              },
            },
          ],
        }),
      );
      // Floor, ceiling, east and west walls whole; the north wall in three:
      // left of the door, right of it, and the lintel over it.
      expect(level.brushes, hasLength(4 + 1 + 3));
      final lintel = level.brushes.singleWhere(
        (Brush b) => b.material == 'wall' && b.size.y < 1.5,
      );
      expect(lintel.centre.y, closeTo(3.5, 1e-6));
      expect(lintel.size.x, closeTo(2.0, 1e-6));
      expect(lintel.shadowCasting, ShadowCasting.doubleSided);
      // A room reflects itself: one probe, half way up.
      expect(level.ofType('reflection_probe').single.position.y, 2.0);
    });

    test('scattered things stand apart and inside their box', () {
      final level = expandRecipes(_read(_document()));
      final probes = level.entities
          .where((EntityDef e) => e.name?.startsWith('probe') ?? false)
          .toList();
      expect(probes, hasLength(5));
      expect(probes.map((EntityDef e) => e.name), <String>[
        'probe 1',
        'probe 2',
        'probe 3',
        'probe 4',
        'probe 5',
      ]);
      for (final (i, p) in probes.indexed) {
        expect(p.position.x.abs(), lessThanOrEqualTo(4.0));
        expect(p.position.z.abs(), lessThanOrEqualTo(4.0));
        expect(p.position.y, 0.0);
        for (final q in probes.skip(i + 1)) {
          final dx = p.position.x - q.position.x;
          final dz = p.position.z - q.position.z;
          expect(dx * dx + dz * dz, greaterThanOrEqualTo(1.5 * 1.5 - 1e-3));
        }
      }
    });

    test('a level with no recipes comes back as itself', () {
      final level = Level(name: 'plain');
      expect(identical(expandRecipes(level), level), isTrue);
    });

    test('an unknown kind is refused by name', () {
      final level = _read(<String, Object?>{
        'recipes': <Object?>[
          <String, Object?>{'kind': 'volcano'},
        ],
      });
      expect(
        () => expandRecipes(level),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.message,
            'message',
            contains('volcano'),
          ),
        ),
      );
    });
  });

  group('a level with recipes', () {
    test('writes its recipes back rather than what they expand to', () {
      final level = _read(_document());
      final written = level.toJson();
      expect(written['recipes'], hasLength(3));
      expect(written.containsKey('brushes'), isFalse);
      expect(jsonEncode(Level.fromJson(written).toJson()), jsonEncode(written));
    });

    test('validates', () {
      final issues = LevelValidator(
        registry: EntityRegistry(<EntityKind>[const ReflectionProbeKind()]),
      ).validate(_read(_document()));
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('a recipe that cannot be expanded is a validation error', () {
      final issues =
          LevelValidator(
            registry: EntityRegistry(const <EntityKind>[]),
          ).validate(
            _read(<String, Object?>{
              'recipes': <Object?>[
                <String, Object?>{
                  'kind': 'corridor',
                  'params': <String, Object?>{
                    'from': <double>[0.0, 0.0, 0.0],
                    'to': <double>[4.0, 0.0, 4.0],
                  },
                },
              ],
            }),
          );
      expect(issues.single.isError, isTrue);
      expect(issues.single.message, contains('not straight'));
    });

    test('its visibility hash covers what the recipes expand to', () {
      final a = LevelVisibility.hashBrushes(_read(_document()));
      final same = LevelVisibility.hashBrushes(_read(_document()));
      final moved = LevelVisibility.hashBrushes(_read(_document(roomSeed: 9)));
      expect(a, same);
      expect(a, isNot(moved));
      expect(a, LevelVisibility.hashBrushes(expandRecipes(_read(_document()))));
      // Mutation: hash `authored.brushes` in `hashBrushes` and every seed
      // hashes the empty list — `moved` equals `a`. So does seeding
      // `_clutter` from a constant: only the room's seed differs here.
    });

    test('its walls are in the collision world', () {
      final world = CollisionWorld();
      _read(_document()).addTo(world);
      world.update();
      expect(
        world.colliderCount,
        expandRecipes(_read(_document())).brushes.length,
      );
    });
  });

  group('roundDecimal', () {
    test('decides on the exact value and breaks true ties to even', () {
      // The reference values are what the generators that wrote the shipped
      // level documents produced for the same inputs.
      expect(roundDecimal(0.0625, 3), 0.062);
      expect(roundDecimal(0.1875, 3), 0.188);
      expect(roundDecimal(2.675, 2), 2.67);
      expect(roundDecimal(1.0005, 3), 1.0);
      expect(roundDecimal(0.0005, 3), 0.001);
      expect(roundDecimal(-2.5e-4, 3), -0.0);
      expect(roundDecimal(-2.5e-4, 3).isNegative, isTrue);
      expect(roundDecimal(123456.78949999, 3), 123456.789);
      expect(roundDecimal(12.0, 3), 12.0);
      // Mutation: `(value * 1000).round() / 1000` gives 0.063 for the first.
    });
  });
}

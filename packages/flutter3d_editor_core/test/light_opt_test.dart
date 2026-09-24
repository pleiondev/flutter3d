/// The light optimizer: fewer lights, judged by the pictures they make.
///
///     dart test test/light_opt_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A closed room six metres square and three high, grey, with [lights] in it
/// and a player standing in one corner.
Map<String, Object?> _room(List<Map<String, Object?>> lights) =>
    <String, Object?>{
      'version': 1,
      'name': 'room',
      'materials': <String, Object?>{
        'stone': <String, Object?>{
          'baseColor': <double>[0.6, 0.6, 0.6, 1.0],
          'roughness': 0.9,
        },
      },
      'brushes': <Object?>[
        _box(<double>[0.0, -0.25, 0.0], <double>[7.0, 0.5, 7.0]),
        _box(<double>[0.0, 3.25, 0.0], <double>[7.0, 0.5, 7.0]),
        _box(<double>[-3.25, 1.5, 0.0], <double>[0.5, 3.0, 7.0]),
        _box(<double>[3.25, 1.5, 0.0], <double>[0.5, 3.0, 7.0]),
        _box(<double>[0.0, 1.5, -3.25], <double>[6.0, 3.0, 0.5]),
        _box(<double>[0.0, 1.5, 3.25], <double>[6.0, 3.0, 0.5]),
      ],
      'lights': lights,
      'entities': <Object?>[
        <String, Object?>{
          'type': 'player_spawn',
          'at': <double>[2.0, 0.0, 2.0],
          'yaw': 0.8,
        },
      ],
    };

Map<String, Object?> _box(List<double> at, List<double> size) =>
    <String, Object?>{'at': at, 'size': size, 'material': 'stone'};

Map<String, Object?> _point(List<double> at, {double intensity = 3.0}) =>
    <String, Object?>{
      'type': 'point',
      'at': at,
      'intensity': intensity,
      'range': 10.0,
    };

Level _level(List<Map<String, Object?>> lights) => Level.fromJson(
  jsonDecode(jsonEncode(_room(lights))) as Map<String, Object?>,
);

/// Two views from the spawn, across the room each way, so the lamp's pool
/// on the floor and on two walls is in the pictures.
final List<LightView> _views = <LightView>[
  (from: Vector3(2.0, 1.6, 2.0), at: Vector3(-1.0, 0.8, -1.0)),
  (from: Vector3(-2.0, 1.6, 2.0), at: Vector3(1.0, 0.8, -1.5)),
];

void main() {
  group('a level drawn in linear light', () {
    test('is its lights added together', () {
      // What the whole optimizer stands on: with visibility frozen, the
      // picture under two lights is the unlit picture plus each light's own.
      //
      // Mutation: leave `tonemap` at its default in `LightShading.settings`.
      // The tone curve rolls the sum off and the two pictures part.
      final a = LevelLight.fromJson(_point(<double>[-1.0, 2.5, 0.0]));
      final b = LevelLight.fromJson(_point(<double>[1.5, 2.0, 1.0]));
      final shading = LightShading.of(_level(const []), width: 64, height: 40);
      final view = _views.first;
      final unlit = shading.render(view, const <LevelLight>[]);
      final both = shading.render(view, <LevelLight>[a, b]);
      final first = shading.render(view, <LevelLight>[a]);
      final second = shading.render(view, <LevelLight>[b]);
      var worst = 0.0;
      var brightest = 0.0;
      for (var i = 0; i < both.length; i++) {
        final sum = first[i] + second[i] - unlit[i];
        final off = (both[i] - sum).abs();
        if (off > worst) worst = off;
        if (both[i] > brightest) brightest = both[i];
      }
      expect(brightest, greaterThan(0.2), reason: 'the room was not lit');
      expect(worst, lessThan(brightest * 1e-3));
    });
  });

  group('the optimizer', () {
    test('three coincident lights collapse to one within the bound', () {
      // The synthetic room the plan asks for: three lamps in one place are
      // one lamp three times as strong, and the pictures cannot tell.
      //
      // Mutation: make `_Problem.retune` a no-op (return the set as it came)
      // and let the merge loop try no pair. Removing a lamp then leaves the
      // room two thirds as bright, the difference passes the bound, and all
      // three stay. (With merges left on, two merges find the same answer —
      // one lamp standing for three is exactly what a merge makes.)
      final level = _level(<Map<String, Object?>>[
        _point(<double>[0.0, 2.5, 0.0]),
        _point(<double>[0.0, 2.5, 0.0]),
        _point(<double>[0.0, 2.5, 0.0]),
      ]);
      const optimizer = LightOptimizer(width: 80, height: 50);
      final plan = optimizer.optimize(level, views: _views);

      expect(plan.before, hasLength(3));
      expect(plan.after, hasLength(1));
      expect(plan.after.single.intensity, closeTo(9.0, 0.05));
      expect(plan.after.single.position, Vector3(0.0, 2.5, 0.0));
      expect(plan.difference, lessThan(optimizer.maxDifference));
      expect(plan.underLit, lessThanOrEqualTo(optimizer.maxUnderLit));
      expect(plan.costAfter, closeTo(plan.costBefore / 3.0, 1.0));
      expect(plan.overlapBefore, greaterThan(0.6));
      expect(plan.overlapAfter, 0.0);
      expect(plan.moves, hasLength(greaterThanOrEqualTo(2)));
      expect(plan.holds, isTrue);
      expect(plan.changes, isTrue);
      expect(level.lights, hasLength(3), reason: 'the level was changed');
    });

    test('a set that misses the bounds once drawn changes nothing', () {
      // The search judges moves on the lights' pictures added together; the
      // drawn set is judged again, and a miss there is not a plan to take.
      // Mutation: drop `&& holds` from `LightPlan.changes` and the command
      // line, the agent's tool and the editor's button all apply it.
      final plan = LightPlan(
        before: const <LevelLight>[],
        after: const <LevelLight>[],
        moves: const <String>['removed a lamp'],
        costBefore: 2.0,
        costAfter: 1.0,
        overlapBefore: 0.5,
        overlapAfter: 0.0,
        difference: 0.2,
        underLit: 0.3,
        holds: false,
        width: 1,
        height: 1,
        previewBefore: Uint8List(4),
        previewAfter: Uint8List(4),
      );

      expect(plan.changes, isFalse);
      expect(plan.says, contains('misses the bounds'));
    });

    test('keeps a lamp nothing else stands in for', () {
      // Two lamps at the two ends of the room each light a half the other
      // barely reaches: either one gone is a dark half, which the
      // under-illumination bound refuses.
      //
      // Mutation: set `maxUnderLit` and `maxDifference` to 1 here. Both
      // bounds open, a lamp goes, and the count is one.
      final level = _level(<Map<String, Object?>>[
        _point(<double>[-2.4, 1.0, -2.4], intensity: 1.5)..['range'] = 3.0,
        _point(<double>[2.4, 1.0, 2.4], intensity: 1.5)..['range'] = 3.0,
      ]);
      const optimizer = LightOptimizer(width: 80, height: 50);
      final plan = optimizer.optimize(
        level,
        views: <LightView>[
          (from: Vector3(0.0, 1.6, 0.0), at: Vector3(-2.0, 0.5, -2.0)),
          (from: Vector3(0.0, 1.6, 0.0), at: Vector3(2.0, 0.5, 2.0)),
        ],
      );
      expect(plan.after, hasLength(2));
    });

    test('a merge stands one lamp where two were close together', () {
      // Two lamps forty centimetres apart are one lamp to anybody looking,
      // but neither alone is in the right place for both: removing one and
      // doubling the other shifts the pool past the bound, a lamp between
      // them does not.
      //
      // Mutation: make the merge loop in `optimize` try no pair
      // (`_mergeable(...).take(0)`). Removal alone is refused and both stay.
      final level = _level(<Map<String, Object?>>[
        _point(<double>[-0.2, 2.5, 0.0]),
        _point(<double>[0.2, 2.5, 0.0]),
      ]);
      const optimizer = LightOptimizer(width: 80, height: 50);
      final plan = optimizer.optimize(level, views: _views);
      expect(plan.after, hasLength(1));
      expect(plan.moves.first, startsWith('merged light 0 and light 1'));
      expect(plan.after.single.position.x, closeTo(0.0, 0.01));
      expect(plan.after.single.intensity, closeTo(6.0, 0.3));
      expect(plan.difference, lessThan(optimizer.maxDifference));
    });

    test('says what it did and what it bought', () {
      final plan = const LightOptimizer(width: 40, height: 25).optimize(
        _level(<Map<String, Object?>>[
          _point(<double>[0.0, 2.5, 0.0]),
          _point(<double>[0.0, 2.5, 0.0]),
        ]),
        views: _views,
      );
      expect(plan.says, startsWith('2 → 1 lights, shading cost 50.0% lower'));
      expect(plan.previewBefore, hasLength(40 * 25 * 4));
      expect(plan.pngs.after.sublist(1, 4), utf8.encode('PNG'));
    });
  });

  group('against several lighting states', () {
    // A lamp the noon sun drowns out is a lamp nobody misses at noon, and
    // the only light in the room at night. The sun here is a bright light
    // the state adds and the optimizer may not touch.
    final level = _level(<Map<String, Object?>>[
      _point(<double>[1.5, 1.0, -1.5], intensity: 0.6)..['range'] = 4.0,
    ]);
    final noon = LightingState(
      'noon',
      lights: <LevelLight>[
        LevelLight.fromJson(_point(<double>[0.0, 2.5, 0.0], intensity: 60.0)),
      ],
    );
    const night = LightingState('night');
    const optimizer = LightOptimizer(width: 80, height: 50);

    test('drops the lamp when only noon is asked about', () {
      final plan = optimizer.optimize(
        level,
        views: _views,
        states: <LightingState>[noon],
      );
      expect(plan.after, isEmpty);
    });

    test('keeps it when night is asked about too', () {
      // The second state is the whole difference. Mutation: build the frames
      // in `optimize` from `states.first` alone. Night is never looked at
      // and the lamp goes.
      final plan = optimizer.optimize(
        level,
        views: _views,
        states: <LightingState>[noon, night],
      );
      expect(plan.after, hasLength(1));
      expect(plan.difference, lessThan(optimizer.maxDifference));
    });
  });

  group('views', () {
    test('are taken along the path a player walked, at eye height', () {
      final poses = <Pose>[
        for (var i = 0; i < 20; i++)
          Pose(time: i / 15.0, yaw: 0.0)..position.setValues(i * 0.5, 0.0, 0.0),
      ];
      final views = viewsAlong(poses, count: 3);
      expect(views, hasLength(3));
      expect(views.first.from, Vector3(0.0, lightViewEyeHeight, 0.0));
      expect(views.last.from, Vector3(9.5, lightViewEyeHeight, 0.0));
      // Yaw nought looks down -Z.
      expect(views.first.at.z, lessThan(views.first.from.z));
    });

    test('fall back to the spawn, four ways round', () {
      final views = defaultLightViews(_level(const []));
      expect(views, hasLength(4));
      expect(views.first.from, Vector3(2.0, lightViewEyeHeight, 2.0));
    });
  });

  group('applied to the document', () {
    test('is one step, and undo puts every light back', () {
      final editing = Editing.parse(
        jsonEncode(
          _room(<Map<String, Object?>>[
            _point(<double>[0.0, 2.5, 0.0]),
            _point(<double>[0.0, 2.5, 0.0]),
            _point(<double>[0.0, 2.5, 0.0]),
          ]),
        ),
        path: '/levels/room.json',
      );
      final before = jsonEncode(editing.level.toJson());
      final plan = const LightOptimizer(
        width: 40,
        height: 25,
      ).optimize(editing.level, views: _views);

      // Mutation: drop `_remember` from `Editing.setLights`. The change is
      // made and nothing records it, so undo has nothing to put back.
      final did = editing.history.run(SetLights(plan.after, why: plan.says));
      expect(did, isTrue);
      expect(editing.level.lights, hasLength(1));
      expect(editing.history.undoSays, plan.says);

      editing.history.undo();
      expect(jsonEncode(editing.level.toJson()), before);
      editing.history.redo();
      expect(editing.level.lights, hasLength(1));
      expect(editing.level.lights.single.intensity, closeTo(9.0, 0.05));
    });
  });
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_build/src/convert/report.dart';
import 'package:flutter3d_build/src/convert/scene.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('placement', () {
    test('a turn about Y is all yaw and no tilt', () {
      final p = placementOf(
        Matrix4.compose(
          Vector3(1, 2, 3),
          Quaternion.axisAngle(Vector3(0, 1, 0), 0.7),
          Vector3.all(1),
        ),
      );
      expect(p.yaw, closeTo(0.7, 1e-6));
      expect(placementJson(p).containsKey('tilt'), isFalse);
      expect(placementJson(p)['at'], <double>[1.0, 2.0, 3.0]);
    });

    test('yaw then tilt gives the rotation back', () {
      final q =
          Quaternion.axisAngle(Vector3(1, 0, 0), 0.4) *
          Quaternion.axisAngle(Vector3(0, 1, 0), -1.1);
      final p = placementOf(Matrix4.compose(Vector3.zero(), q, Vector3.all(1)));
      final back = Quaternion.axisAngle(Vector3(0, 1, 0), p.yaw) * p.tilt;
      final v = Vector3(0.3, -0.2, 0.9);
      final a = q.rotated(v);
      final b = back.rotated(v);
      expect((a - b).length, lessThan(1e-6));
    });

    test('numbers are rounded, and negative zero is zero', () {
      expect(roundNumber(-1e-12), 0.0);
      expect(roundNumber(0.1234567), 0.123457);
    });
  });

  group('the level document', () {
    ScenePrefab inner() => ScenePrefab('post', <SceneItem>[
      SceneItem(name: 'pole', asset: 'models/pole.f3d'),
    ]);

    Map<String, Object?> write(
      List<ScenePrefab> prefabs,
      ConvertReport report,
    ) =>
        jsonDecode(
              levelDocument(
                name: prefabs.first.id,
                prefabs: prefabs,
                materials: <SceneMaterial>[
                  SceneMaterial(
                    'steel',
                    'materials/steel.fmat',
                    SurfaceMaterial(),
                  ),
                ],
                prefix: 'assets/imported',
                report: report,
              ),
            )
            as Map<String, Object?>;

    test('a turned instance stays an instance, at version 2, generated', () {
      final report = ConvertReport('x', 'test');
      final json = write(<ScenePrefab>[
        ScenePrefab('yard', <SceneItem>[
          SceneItem(
            name: 'gate',
            local: Matrix4.compose(
              Vector3(4, 0, 0),
              Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2),
              Vector3.all(1),
            ),
            instance: const NestedInstance('post'),
          ),
        ]),
        inner(),
      ], report);
      expect(json['version'], 2);
      expect(json['generatedBy'], 'flutter3d convert');
      expect(
        (json['materials']! as Map<String, Object?>)['steel'],
        containsPair('fmat', 'assets/imported/materials/steel.fmat'),
      );
      final level = Level.fromJson(json);
      final gate = level.prefabs['yard']!.entities.single;
      expect(gate.type, EntityTypes.prefab);
      expect(gate.yaw, closeTo(math.pi / 2, 1e-5));
      final expanded = expandPrefabs(level).entities.single;
      expect(expanded.string('asset'), 'assets/imported/models/pole.f3d');
      expect(expanded.position.x, closeTo(4, 1e-5));
      expect(report.warnings, isEmpty);
    });

    test('a scaled instance is written as its rows, with a warning', () {
      final report = ConvertReport('x', 'test');
      final json = write(<ScenePrefab>[
        ScenePrefab('yard', <SceneItem>[
          SceneItem(
            name: 'gate',
            local: Matrix4.diagonal3Values(2, 2, 2),
            instance: const NestedInstance('post'),
          ),
        ]),
        inner(),
      ], report);
      final rows = Level.fromJson(json).prefabs['yard']!.entities;
      expect(rows.single.type, kModelEntityType);
      expect(rows.single.vector('scale'), Vector3.all(2));
      expect(report.warnings.single, contains('rows'));
    });

    test('a prefab that contains itself is dropped, not looped on', () {
      final report = ConvertReport('x', 'test');
      write(<ScenePrefab>[
        ScenePrefab('loop', <SceneItem>[
          SceneItem(
            name: 'me',
            local: Matrix4.diagonal3Values(2, 2, 2),
            instance: const NestedInstance('loop'),
          ),
        ]),
      ], report);
      expect(report.dropped.single, contains('contains itself'));
    });

    test('a box takes its scale into its size', () {
      final report = ConvertReport('x', 'test');
      final json = write(<ScenePrefab>[
        ScenePrefab('room', <SceneItem>[
          SceneItem(
            name: 'floor',
            local: Matrix4.diagonal3Values(4, 0.5, 2),
            shape: PrimitiveShape.box(Vector3.all(1)),
          ),
        ]),
      ], report);
      final floor = Level.fromJson(json).prefabs['room']!.entities.single;
      expect(floor.type, kPropEntityType);
      expect(floor.vector('size'), Vector3(4, 0.5, 2));
      expect(floor.properties.containsKey('scale'), isFalse);
    });
  });
}

/// Which command a rail button stands for.
///
///     flutter test test/tool_commands_test.dart
library;

import 'dart:math';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/tool_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('commandFor', () {
    test('object.add is always a box primitive, whether or not anything is '
        'selected', () {
      expect(
        commandFor('object.add', activeObject: null, editMesh: null),
        isA<AddPrimitive>().having((c) => c.kind, 'kind', 'box'),
      );
    });

    test('object.bake with nothing selected only arms — no command', () {
      expect(
        commandFor('object.bake', activeObject: null, editMesh: null),
        isNull,
      );
    });

    test('object.bake with an object held bakes that object', () {
      final command = commandFor(
        'object.bake',
        activeObject: 7,
        editMesh: null,
      );
      expect(command, isA<BakeToMesh>().having((c) => c.id, 'id', 7));
    });

    test('object.origin with an object held sets its origin to the bounds '
        'bottom', () {
      final command = commandFor(
        'object.origin',
        activeObject: 3,
        editMesh: null,
      );
      expect(
        command,
        isA<SetOrigin>()
            .having((c) => c.id, 'id', 3)
            .having((c) => c.to, 'to', OriginPlacement.boundsBottom),
      );
    });

    test('object.apply with an object held applies that object\'s '
        'transform', () {
      final command = commandFor(
        'object.apply',
        activeObject: 4,
        editMesh: null,
      );
      expect(command, isA<ApplyTransform>().having((c) => c.id, 'id', 4));
    });

    test('mesh.extrude with no mesh being edited steps by a tenth of a '
        'metre', () {
      final command = commandFor(
        'mesh.extrude',
        activeObject: null,
        editMesh: null,
      );
      expect(
        command,
        isA<Extrude>().having((c) => c.distance, 'distance', 0.1),
      );
    });

    test('mesh.extrude with a mesh being edited steps by a tenth of its '
        'span', () {
      final mesh = EditMesh.cuboid(size: Vector3(2, 2, 2));
      final command = commandFor(
        'mesh.extrude',
        activeObject: null,
        editMesh: mesh,
      );
      expect(
        command,
        isA<Extrude>().having(
          (c) => c.distance,
          'distance',
          closeTo(2 * sqrt(3) * 0.1, 1e-9),
        ),
      );
    });

    test('mesh.bevel with no mesh being edited widens by half a tenth of a '
        'metre', () {
      final command = commandFor(
        'mesh.bevel',
        activeObject: null,
        editMesh: null,
      );
      expect(command, isA<BevelEdges>().having((c) => c.width, 'width', 0.05));
    });

    test('mesh.bevel with a mesh being edited widens by half a tenth of its '
        'span', () {
      final mesh = EditMesh.cuboid(size: Vector3(2, 2, 2));
      final command = commandFor(
        'mesh.bevel',
        activeObject: null,
        editMesh: mesh,
      );
      expect(
        command,
        isA<BevelEdges>().having(
          (c) => c.width,
          'width',
          closeTo(2 * sqrt(3) * 0.1 * 0.5, 1e-9),
        ),
      );
    });

    test('an unknown id only arms — no command', () {
      expect(
        commandFor('object.frobnicate', activeObject: null, editMesh: null),
        isNull,
      );
    });
  });

  group('stepOf', () {
    test('defaults to a tenth of a metre with no mesh at all', () {
      expect(stepOf(null), 0.1);
    });

    test('defaults to a tenth of a metre when the mesh has no live '
        'vertices', () {
      final builder = EditMeshBuilder();
      final mesh = builder.build();
      expect(stepOf(mesh), 0.1);
    });

    test('is a tenth of the live vertices\' diagonal span', () {
      final mesh = EditMesh.cuboid(size: Vector3(4, 0, 0));
      expect(stepOf(mesh), closeTo(4 * 0.1, 1e-9));
    });
  });
}

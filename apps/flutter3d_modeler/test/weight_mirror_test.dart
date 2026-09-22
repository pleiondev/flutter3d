/// `jointMirrorMapByName`: the `PaintMirror.jointMirror` a skeleton's own
/// `.L`/`.R` naming already implies — `ui/weight_paint_panel.dart`'s own
/// "Mirror" flag, wired without a person drawing the map by hand.
///
///     flutter test test/weight_mirror_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/weight_mirror.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject _joint(int id, String name) => ModelObject(
  id: id,
  name: name,
  geometry: const SocketGeometry(),
  transform: Matrix4.identity(),
);

void main() {
  test('a .L/.R pair mirrors onto each other, both ways', () {
    final project = ModelProject(
      objects: <ModelObject>[_joint(1, 'Бедро.L'), _joint(2, 'Бедро.R')],
    );
    final skeleton = ProjectSkeleton(
      joints: <int>[1, 2],
      inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
    );

    expect(jointMirrorMapByName(project, skeleton), <int, int>{0: 1, 1: 0});
  });

  test('a joint straddling the plane is left out of the map entirely', () {
    final project = ModelProject(
      objects: <ModelObject>[
        _joint(1, 'Бедро.L'),
        _joint(2, 'Бедро.R'),
        _joint(3, 'Таз'),
      ],
    );
    final skeleton = ProjectSkeleton(
      joints: <int>[1, 2, 3],
      inverseBindMatrices: <Matrix4>[
        Matrix4.identity(),
        Matrix4.identity(),
        Matrix4.identity(),
      ],
    );

    // Mutation: name the spine to itself. `mirrorWeights` already treats a
    // missing entry as "stays itself", so naming it explicitly changes
    // nothing about the result and only invites a second bug the day the
    // convention changes.
    expect(jointMirrorMapByName(project, skeleton).containsKey(2), isFalse);
    expect(jointMirrorMapByName(project, skeleton), <int, int>{0: 1, 1: 0});
  });

  test('a .L with no .R counterpart in this skeleton mirrors nothing', () {
    final project = ModelProject(objects: <ModelObject>[_joint(1, 'Хвост.L')]);
    final skeleton = ProjectSkeleton(
      joints: <int>[1],
      inverseBindMatrices: <Matrix4>[Matrix4.identity()],
    );

    expect(jointMirrorMapByName(project, skeleton), isEmpty);
  });

  test('an empty skeleton mirrors nothing', () {
    expect(
      jointMirrorMapByName(
        const ModelProject(),
        ProjectSkeleton(
          joints: const <int>[],
          inverseBindMatrices: const <Matrix4>[],
        ),
      ),
      isEmpty,
    );
  });

  test(
    'another naming convention (no .L/.R suffix at all) mirrors nothing',
    () {
      final project = ModelProject(
        objects: <ModelObject>[_joint(1, 'Hip_Left'), _joint(2, 'Hip_Right')],
      );
      final skeleton = ProjectSkeleton(
        joints: <int>[1, 2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      );

      expect(jointMirrorMapByName(project, skeleton), isEmpty);
    },
  );
}

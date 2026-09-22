/// `ux-13`'s own second switch, where it actually matters: what the file
/// holds.
///
///     dart test test/modifier_export_test.dart
///
/// **The export did not fold modifiers at all before this row.** A mirror or
/// an array was in the viewport and not in the GLB: the only way to get the
/// modified mesh out was "Apply", which drops the stack and cannot be undone
/// once the file is saved.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject _cubeWith(List<ModifierSlot> slots) => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
    modifiers: slots,
  ),
);

ModifierSlot _array({
  bool enabled = true,
  bool inExport = true,
  int count = 3,
}) => ModifierSlot(
  modifier: ArrayModifier(count: count, offset: Vector3(3, 0, 0)),
  enabled: enabled,
  inExport: inExport,
);

int _trianglesOf(ModelDocument document) =>
    document.surfaces.fold(0, (int sum, ModelSurface it) {
      return sum + it.mesh.triangleCount;
    });

void main() {
  group('ux-13: what the export folds', () {
    test('a modifier in the export is in the file', () {
      final ModelDocument plain = toModelDocument(
        _cubeWith(const <ModifierSlot>[]),
      );
      final ModelDocument folded = toModelDocument(
        _cubeWith(<ModifierSlot>[_array()]),
      );

      // Mutation: write the raw geometry, which is what this did. The
      // viewport shows a row of three cubes and the GLB holds one, and
      // nothing anywhere says so.
      expect(_trianglesOf(folded), _trianglesOf(plain) * 3);
    });

    test('and one kept out of it is not', () {
      final ModelDocument plain = toModelDocument(
        _cubeWith(const <ModifierSlot>[]),
      );
      final ModelDocument folded = toModelDocument(
        _cubeWith(<ModifierSlot>[_array(inExport: false)]),
      );

      // The acceptance this row states, from the file's side.
      expect(_trianglesOf(folded), _trianglesOf(plain));
    });

    test('the viewport switch does not decide what the file holds', () {
      final ModelDocument plain = toModelDocument(
        _cubeWith(const <ModifierSlot>[]),
      );
      // Off in the viewport, on for the file — a subdivision somebody keeps
      // out of their way while they work.
      final ModelDocument folded = toModelDocument(
        _cubeWith(<ModifierSlot>[_array(enabled: false)]),
      );

      // Mutation: read `enabled` in the export path. The two switches then
      // mean one thing, and the whole reason for the second one is gone.
      expect(_trianglesOf(folded), _trianglesOf(plain) * 3);
    });
  });

  group('ux-13: the flag itself', () {
    test('is true by default, which is what an old file says', () {
      expect(
        ModifierSlot.fromJson(<String, Object?>{
          'modifier': MirrorModifier(normal: Vector3(1, 0, 0)).toJson(),
          'enabled': true,
        })?.inExport,
        isTrue,
      );
    });

    test('and survives a round trip when it is false', () {
      final ModifierSlot slot = _array(inExport: false);
      final ModifierSlot? read = ModifierSlot.fromJson(slot.toJson());

      // Mutation: write it always, or read it as `== true`. A slot written
      // before this existed carries no key at all, so `== true` reads every
      // one of them as "leave it out of the export" — which silently empties
      // every modifier out of every file anybody had already saved.
      expect(read?.inExport, isFalse);
      expect(ModifierSlot.fromJson(_array().toJson())?.inExport, isTrue);
    });
  });
}

/// `mat-24`'s own multi-asset acceptance: two imports into one project, the
/// second one moved, exported as one GLB-bound `ModelDocument` with two
/// nodes at different matrices and one `SurfaceMaterial` for the material
/// they share.
///
///     flutter test test/scene_multi_asset_export_test.dart
///
/// **Three seams already built for other rows, proven here as one chain.**
/// `ImportInto` (`doc-11a-n`) merges a second document into a project and
/// dedupes materials by content; `MoveBy` inside `ModelHistory.transaction`
/// (`view-12`) moves the selected object as one undo step; `toModelDocument`
/// writes a project's own materials table across whole rather than
/// flattening it per surface. None of that is new — this file's own claim
/// is that the three already agree with each other and with `mat-24`'s own
/// acceptance without anything further being built: `ImportInto`'s dedup
/// happens once, at merge time, so by the time `toModelDocument` walks the
/// merged project there is already only one matching `SurfaceMaterial` in
/// its table for it to write.
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Doc extends ModelDocument {
  _Doc({
    required this.surfaces,
    required this.nodes,
    required this.roots,
    this.materials = const <SurfaceMaterial>[],
  });

  @override
  final List<ModelSurface> surfaces;
  @override
  final List<ModelNode> nodes;
  @override
  final List<int> roots;
  @override
  final List<SurfaceMaterial> materials;
  @override
  final List<EncodedImage> images = const <EncodedImage>[];
  @override
  final List<String> warnings = const <String>[];
}

/// A single-cube, single-material document — the same steel `oneCube` gives
/// `import_into_test.dart`, restated here rather than shared across the two
/// files because `_Doc` is file-private in both.
// ignore: library_private_types_in_public_api
_Doc oneCube({String name = 'cube'}) => _Doc(
  surfaces: <ModelSurface>[
    ModelSurface(
      name: name,
      mesh: EditMesh.cuboid().toMeshData(),
      transform: Matrix4.identity(),
      materialIndex: 0,
    ),
  ],
  nodes: <ModelNode>[
    ModelNode(
      name: name,
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, 1, 1),
      surfaces: <int>[0],
    ),
  ],
  roots: <int>[0],
  materials: <SurfaceMaterial>[
    SurfaceMaterial(
      name: 'steel',
      baseColor: Vector4(0.2, 0.3, 0.4, 1.0),
      metallic: 1.0,
      roughness: 0.25,
    ),
  ],
);

void main() {
  test(
    'two assets imported into one project, the second one moved, export '
    'as two nodes at different matrices sharing one material',
    () {
      // "Импортировать в сцену" — two calls to `importInto`, each one asset,
      // merged into the same growing project rather than each opened on its
      // own.
      final firstImport = importInto(const ModelProject(), oneCube(name: 'A'));
      final secondImport = importInto(firstImport.project, oneCube(name: 'B'));

      // Both assets use `oneCube`'s own identical steel — an equivalent
      // `SurfaceMaterial` in a second document is what `ImportInto`'s dedup
      // is about, and this is `mat-24`'s own acceptance clause for it: two
      // imports, one material once exported.
      expect(secondImport.project.materials, hasLength(1));
      expect(secondImport.project.objects, hasLength(2));

      final int objectB = secondImport.project.objects[1].id;

      // "Перемещение объектов гизмо view-12": a project's own history,
      // moving the selected object by a `MoveBy` inside one transaction —
      // the identical shape a gizmo drag leaves behind, per
      // `transform_gizmo.dart`'s own `GizmoDrag` doc comment.
      final history = ModelHistory(secondImport.project)
        ..selection = ProjectSelection(objects: <int>[objectB]);
      final String? refusal = history.transaction(
        () => history.run(MoveBy(Vector3(2.0, 0.0, 0.0))),
      );
      expect(refusal, isNull);

      // "экспорт сцены одним GLB через toModelDocument() (все объекты как
      // узлы)".
      final ModelDocument exported = toModelDocument(history.project);

      expect(exported.surfaces, hasLength(2));
      // Mutation: import the two assets and never actually apply `MoveBy`
      // (or apply it to the wrong object) — the two surfaces would then
      // carry the identical placement, and the acceptance's own "разными
      // матрицами" would be false.
      expect(
        exported.surfaces[0].transform,
        isNot(equals(exported.surfaces[1].transform)),
      );
      // The moved object is B, so only its own surface should have shifted
      // by the move — A's own placement is untouched.
      expect(exported.surfaces[0].transform, Matrix4.identity());
      expect(
        exported.surfaces[1].transform,
        Matrix4.translation(Vector3(2.0, 0.0, 0.0)),
      );

      // The acceptance's own "один SurfaceMaterial на общий материал":
      // `toModelDocument` writes the project's own table across whole, and
      // that table was already deduped at import time — nothing here
      // re-derives it a second time.
      expect(exported.materials, hasLength(1));
      expect(exported.surfaces[0].materialIndex, 0);
      expect(exported.surfaces[1].materialIndex, 0);
    },
  );

  test(
    'materials that genuinely differ between the two imports stay two '
    'materials in the export, not merged just because they came in '
    'through the same project',
    () {
      final a = importInto(const ModelProject(), oneCube(name: 'A'));
      final differentSteel = _Doc(
        surfaces: <ModelSurface>[
          ModelSurface(
            name: 'B',
            mesh: EditMesh.cuboid().toMeshData(),
            transform: Matrix4.identity(),
            materialIndex: 0,
          ),
        ],
        nodes: <ModelNode>[
          ModelNode(
            name: 'B',
            translation: Vector3.zero(),
            rotation: Quaternion.identity(),
            scale: Vector3(1, 1, 1),
            surfaces: <int>[0],
          ),
        ],
        roots: <int>[0],
        materials: <SurfaceMaterial>[
          SurfaceMaterial(
            name: 'brass',
            baseColor: Vector4(0.8, 0.6, 0.1, 1.0),
            metallic: 1.0,
            roughness: 0.4,
          ),
        ],
      );
      final b = importInto(a.project, differentSteel);

      final exported = toModelDocument(b.project);

      expect(exported.materials, hasLength(2));
    },
  );
}

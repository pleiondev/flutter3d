/// Taking the document out, and reading it back with somebody else's reader.
///
///     flutter test test/exporting_test.dart
///
/// **The round trip is the test and the rest are its corners.** A writer that
/// dropped a surface, mangled a float or wound a face the other way produces a
/// file that still parses; asserting on the bytes proves only that the bytes are
/// well formed. Reading it back with `ObjLoader` and comparing through
/// `compareModelDocuments` puts both halves in the same sentence.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/exporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A cube and a lathed vase: an edited mesh and a shape that still knows its
/// parameters, which are the two geometries an export has to build differently.
ModelProject workshop() => const ModelProject()
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.translationValues(2, 0, 0),
      ),
    )
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'vase',
        geometry: ParametricGeometry(const ParametricCylinder(segments: 12)),
        transform: Matrix4.identity(),
      ),
    );

/// A project holding one object with no faces at all, which readiness calls an
/// error: some loaders refuse an empty mesh and the rest draw nothing.
ModelProject withEmptyObject() => workshop().added(
  (int id) => ModelObject(
    id: id,
    name: 'ghost',
    geometry: EditedGeometry(EditMesh.empty()),
    transform: Matrix4.identity(),
  ),
);

/// A textured project: an 8×8 opaque checkerboard PNG, built with this
/// package's own [encodePng] rather than a fixture file, bound as one
/// material's base-colour texture — mat-30's own worked example.
ModelProject texturedProject() {
  final pixels = Uint8List(8 * 8 * 4);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final on = (x + y).isEven ? 220 : 40;
      final at = (y * 8 + x) * 4;
      pixels[at] = on;
      pixels[at + 1] = on;
      pixels[at + 2] = on;
      pixels[at + 3] = 255;
    }
  }
  return ModelProject(
    images: <EncodedImage>[
      EncodedImage(
        bytes: encodeCompressedPng(8, 8, pixels),
        name: 'checker',
        mimeType: 'image/png',
      ),
    ],
    materials: <ProjectMaterial>[
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'checker',
          baseColorTexture: const TextureBinding(imageIndex: 0),
        ),
      ),
    ],
  ).added(
    (int id) => ModelObject(
      id: id,
      name: 'panel',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
      materialSlots: const <int>[0],
    ),
  );
}

ExportWritten written(ExportResult result) {
  expect(result, isA<ExportWritten>(), reason: '$result');
  return result as ExportWritten;
}

/// [files] read back by the loader that reads OBJ, with the `.mtl` handed over
/// as the sibling it asks for.
Future<ModelDocument> readBack(List<ExportFile> files) {
  final byName = <String, Uint8List>{
    for (final ExportFile file in files) file.name: file.bytes,
  };
  return ObjLoader().load(
    files.first.bytes,
    resolveUri: (AssetRequest request) async {
      final found = byName[request.uri];
      if (found == null) {
        fail('the .obj asked for "${request.uri}" and it was not written');
      }
      return found;
    },
  );
}

void main() {
  group('OBJ, out and back', () {
    test('the shape comes back where it was and the size it was', () async {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;

      final source = toModelDocument(project);
      final back = await readBack(files);

      // **Not `compareModelDocuments` with zero differences, and the reason is
      // worth writing down.** That check is for a format that promises the same
      // buffers back; OBJ promises the same *shape* and changes the buffers on
      // purpose, twice. It has no node tree, so `ObjWriter` bakes each surface's
      // world matrix into its vertices — the cube at x=2 goes out at 1.5 rather
      // than −0.5. And it addresses positions, texcoords and normals as three
      // independent streams, so the writer deduplicates and the loader rebuilds:
      // the cylinder's 78 vertices come back as 76 with the same 288 indices.
      // Both are lossless in shape and neither is expressible as a tolerance.
      //
      // What OBJ does promise is the world-space geometry, so that is what is
      // asserted: the bounds a game engine would frame a camera on.
      final a = source.computeBounds();
      final b = back.computeBounds();
      expect(b.min.x, closeTo(a.min.x, 1e-4));
      expect(b.min.y, closeTo(a.min.y, 1e-4));
      expect(b.min.z, closeTo(a.min.z, 1e-4));
      expect(b.max.x, closeTo(a.max.x, 1e-4));
      expect(b.max.y, closeTo(a.max.y, 1e-4));
      expect(b.max.z, closeTo(a.max.z, 1e-4));

      // Mutation: drop the bake and write local vertices. Every surface comes
      // back at the origin, the bounds collapse to one object's box, and a
      // model of forty props opens as forty props in the same place.
      expect(a.max.x, greaterThan(2.0), reason: 'the cube is placed at x=2');
    });

    test('the triangles and the surfaces both survive', () async {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;

      final back = await readBack(files);

      // Against the project rather than a written-down number, so that changing
      // the fixture cannot leave this passing about the wrong shape.
      expect(back.triangleCount, project.triangleCount);
      expect(back.surfaces, hasLength(project.objects.length));
    });

    test('a lathed vase comes out as triangles, and that is the point', () {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;
      final text = utf8.decode(files.first.bytes);

      // A cylinder of twelve segments is built on the way out —
      // `ParametricShape.drawn` — so it exports as well as any mesh does.
      // Mutation: have the converter answer an empty mesh for a parametric
      // shape and the vase leaves the file entirely, silently.
      expect(text, contains('o vase'));
      expect(text, contains('o cube'));
    });

    test('the material library is written and the obj names it', () {
      final painted =
          ModelProject(
            materials: <ProjectMaterial>[
              ProjectMaterial(
                surface: SurfaceMaterial(
                  name: 'brass',
                  baseColor: Vector4(0.8, 0.6, 0.2, 1),
                ),
              ),
            ],
          ).added(
            (int id) => ModelObject(
              id: id,
              name: 'bolt',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.identity(),
              materialSlots: const <int>[0],
            ),
          );

      final files = written(
        planExport(painted, format: ExportFormat.obj, name: 'thing'),
      ).files;

      // Two files, and the first names the second. Mutation: write only the
      // `.obj` and the `mtllib` line points at a file nobody saved, so the
      // model opens grey wherever it is taken.
      expect(files, hasLength(2));
      expect(files[0].name, 'thing.obj');
      expect(files[1].name, 'thing.mtl');
      expect(utf8.decode(files[0].bytes), contains('mtllib thing.mtl'));
      expect(utf8.decode(files[1].bytes), contains('brass'));
    });
  });

  group('the engine container', () {
    test('a project exports and reads back as the same geometry', () {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.f3d),
      ).files;

      expect(files, hasLength(1));
      expect(files.single.name, 'model.f3d');

      final back = F3dDocument.parse(files.single.bytes);

      // `.f3d` is binary and holds the floats exactly, so this one is held to
      // the bytes rather than to a tolerance — which is the difference the
      // parameter exists to express.
      expect(compareModelDocuments(toModelDocument(project), back), isEmpty);
      expect(back.nodes, hasLength(project.objects.length));
    });

    test('mat-30: the KTX2 texture-encoding option writes a KTX2 image '
        'that loads back without warnings', () {
      final project = texturedProject();
      final files = written(
        planExport(
          project,
          format: ExportFormat.f3d,
          textureEncoding: TextureEncoding.ktx2,
        ),
      ).files;

      final back = F3dDocument.parse(files.single.bytes);
      expect(back.warnings, isEmpty);
      expect(back.images, hasLength(1));

      final imageBytes = back.images.single.bytes;
      expect(
        isKtx2File(imageBytes),
        isTrue,
        reason: 'the option should have replaced the PNG with a KTX2 file',
      );
      // `Ktx2Texture.parse` throws `Ktx2FormatException` on anything it
      // cannot make sense of — this not throwing, and reporting the
      // checkerboard's own (pre-padding) size back, is the literal
      // "loads without warnings" acceptance mat-30's row asks for.
      final texture = Ktx2Texture.parse(imageBytes);
      expect(texture.pixelWidth, 8);
      expect(texture.pixelHeight, 8);
      // Fully opaque source: BC1, not BC3.
      expect(texture.vkFormat, VkFormat.bc1RgbaUNormBlock);
      expect(back.images.single.mimeType, 'image/ktx2');
    });

    test('the default texture encoding keeps writing PNG, unchanged', () {
      final project = texturedProject();
      final files = written(
        planExport(project, format: ExportFormat.f3d),
      ).files;

      final back = F3dDocument.parse(files.single.bytes);
      expect(isKtx2File(back.images.single.bytes), isFalse);
      expect(back.images.single.bytes, project.images.single.bytes);
    });
  });

  group('GLB, out and back', () {
    test('a cube and a lathed vase come back with the same meshes and '
        'triangles — ui-17\'s own worked example', () async {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.glb),
      ).files;

      expect(files, hasLength(1));
      expect(files.single.name, 'model.glb');

      final source = toModelDocument(project);
      final back = await GltfLoader().load(files.single.bytes);

      expect(back.surfaces, hasLength(source.surfaces.length));
      expect(back.triangleCount, source.triangleCount);
      // Unlike OBJ, glTF keeps a node tree — each object's own transform
      // travels as a node rather than being baked into its vertices, so the
      // round trip is held to the same zero-tolerance geometry check `fmt-06`
      // is measured against everywhere else.
      expect(compareModelDocuments(source, back), isEmpty);
    });

    test('an object with no faces still blocks a GLB export, the same as '
        'any other format', () {
      final result = planExport(withEmptyObject(), format: ExportFormat.glb);
      expect(result, isA<ExportBlocked>());
    });

    test('mat-30: the KTX2 texture-encoding option is ignored — glTF keeps '
        'PNG', () async {
      final project = texturedProject();
      final files = written(
        planExport(
          project,
          format: ExportFormat.glb,
          textureEncoding: TextureEncoding.ktx2,
        ),
      ).files;

      final back = await GltfLoader().load(files.single.bytes);
      expect(back.images, hasLength(1));
      expect(
        isKtx2File(back.images.single.bytes),
        isFalse,
        reason: 'the option names only .f3d — GltfWriter never sees it',
      );
    });
  });

  group('what stops an export', () {
    test('an empty project is refused, not written empty', () {
      final result = planExport(const ModelProject(), format: ExportFormat.obj);

      // `ObjWriter` writes an empty file on purpose and says why — a format has
      // to be able to represent nothing. A person pressing Export on an empty
      // document has made a mistake, and that is a different question.
      expect(result, isA<ExportRefused>());
      expect((result as ExportRefused).because, contains('nothing in this'));
    });

    test('an object with no faces blocks, and says how many', () {
      final result = planExport(withEmptyObject(), format: ExportFormat.obj);

      // Mutation: let errors through as warnings. The file is written with an
      // empty mesh in it, which some loaders refuse outright and the rest draw
      // as nothing — and nobody was asked.
      expect(result, isA<ExportBlocked>());
      final blocked = result as ExportBlocked;
      expect(blocked.issues, hasLength(1));
      expect(blocked.issues.single.object?.name, 'ghost');
      expect(blocked.says, contains('One thing'));
    });

    test('force writes it anyway and still says what is wrong', () {
      final result = planExport(
        withEmptyObject(),
        format: ExportFormat.obj,
        force: true,
      );

      // "I know" is an answer to a question, not a reason to stop asking:
      // the warnings ride along with the bytes. Mutation: drop them when forced
      // and the export goes quiet exactly when it has most to say.
      final ok = written(result);
      expect(ok.files, isNotEmpty);
      expect(ok.warnings.any((String w) => w.contains('ghost')), isTrue);
    });

    test('a warning does not block, and comes back with the bytes', () {
      // A quad is a warning: the writer cuts it, so the file loads, and it may
      // not cut it the way somebody would have.
      final quads = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'box',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );

      final ok = written(planExport(quads, format: ExportFormat.obj));

      expect(ok.files, isNotEmpty);
      expect(
        ok.warnings.any((String w) => w.contains('three sides')),
        isTrue,
        reason: 'the cuboid is six quads',
      );
    });

    test("ui-17's own bake-transforms flag: a GLB node carries the identity "
        'once its own transform is baked into the mesh instead', () async {
      final project = workshop();
      final cube = project.objects.first;
      expect(
        cube.transform,
        isNot(Matrix4.identity()),
        reason: "workshop()'s own cube sits at x=2, not the origin",
      );

      final files = written(
        planExport(project, format: ExportFormat.glb, bakeTransforms: true),
      ).files;
      final back = await GltfLoader().load(files.single.bytes);

      // Every surviving node carries the identity — `bakeAllTransforms`
      // moved what used to be the node's own placement into its mesh's
      // own vertices instead. Mutation: skip the bake for objects past
      // the first and the vase's own node keeps its placement.
      for (final ModelSurface surface in back.surfaces) {
        expect(
          surface.transform,
          Matrix4.identity(),
          reason: '${surface.name} should have been baked to the origin',
        );
      }

      // The shape itself is unmoved — baking a transform into geometry
      // changes where the numbers live, not what they describe.
      final unbaked = toModelDocument(project);
      expect(
        back.computeBounds().min.x,
        closeTo(unbaked.computeBounds().min.x, 1e-4),
      );
    });

    test('bakeAllTransforms leaves what it cannot bake exactly as it was', () {
      // The vase is still parametric, which `ApplyTransform` itself
      // refuses to touch (`_editableObject`'s own rule) — its transform
      // rides through unbaked rather than the whole pass failing.
      final project = workshop();
      final vase = project.objects.last;
      expect(vase.geometry, isA<ParametricGeometry>());

      final baked = bakeAllTransforms(project);
      final bakedVase = baked[vase.id]!;
      expect(bakedVase.transform, vase.transform);

      // The cube, an ordinary EditedGeometry object, is the one this
      // reaches: identity transform, geometry moved to match.
      final cube = project.objects.first;
      final bakedCube = baked[cube.id]!;
      expect(bakedCube.transform, Matrix4.identity());
    });

    test('a flattened hierarchy is said out loud for OBJ and not for f3d', () {
      final rigged = workshop();
      final child = rigged.objects.last;
      final withParent = rigged.withObject(
        child.copyWith(parent: rigged.objects.first.id),
      );

      final obj = written(planExport(withParent, format: ExportFormat.obj));
      final f3d = written(planExport(withParent, format: ExportFormat.f3d));

      // OBJ has no node tree at all, so a rig comes back as one level. `.f3d`
      // keeps it. Mutation: warn for both and the sentence stops meaning
      // anything, because it is not true of the container.
      expect(
        obj.warnings.any((String w) => w.contains('no node tree')),
        isTrue,
      );
      expect(
        f3d.warnings.any((String w) => w.contains('no node tree')),
        isFalse,
      );
    });
  });

  group("ux-18: what the one export screen can now ask for", () {
    /// The cube, the vase, and a bolt parented to the cube — three objects
    /// and one parent link, which is the least that can tell "only this one"
    /// apart from "this one and its family".
    (ModelProject, int cube, int vase, int bolt) assembly() {
      final base = workshop();
      final int cube = base.objects.first.id;
      final int vase = base.objects.last.id;
      final ModelProject withBolt = base.added(
        (int id) => ModelObject(
          id: id,
          name: 'bolt',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
          parent: cube,
        ),
      );
      return (withBolt, cube, vase, withBolt.objects.last.id);
    }

    test('selection only writes the picked object and leaves the rest', () {
      final (ModelProject project, _, int vase, _) = assembly();

      final ok = written(
        planExport(project, format: ExportFormat.f3d, only: <int>{vase}),
      );
      final back = F3dDocument.parse(ok.files.single.bytes);

      // Mutation: pass `only` through and narrow nothing, and the whole room
      // comes out of a request for one chair.
      expect(back.surfaces.map((ModelSurface it) => it.name), <String>['vase']);
    });

    test('a child comes with its parent, and a parent with its child', () {
      final (ModelProject project, int cube, _, int bolt) = assembly();

      final fromParent = written(
        planExport(project, format: ExportFormat.f3d, only: <int>{cube}),
      );
      final fromChild = written(
        planExport(project, format: ExportFormat.f3d, only: <int>{bolt}),
      );

      // Down, because a chair without its own legs is a worse answer than
      // refusing; up, because a node whose parent is missing comes back at
      // the origin rather than where it sits.
      expect(
        F3dDocument.parse(
          fromParent.files.single.bytes,
        ).surfaces.map((ModelSurface it) => it.name).toSet(),
        <String>{'cube', 'bolt'},
      );
      expect(
        F3dDocument.parse(
          fromChild.files.single.bytes,
        ).surfaces.map((ModelSurface it) => it.name).toSet(),
        <String>{'cube', 'bolt'},
      );
    });

    test('an empty selection still means everything', () {
      final (ModelProject project, _, _, _) = assembly();

      final ok = written(planExport(project, format: ExportFormat.f3d));

      // The default has to stay what Export has always meant, or every
      // caller that does not know about this option changes behaviour.
      expect(F3dDocument.parse(ok.files.single.bytes).surfaces, hasLength(3));
    });

    test('applyModifiers off writes the base mesh, on writes what is seen', () {
      final mirrored = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'half',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.translationValues(1, 0, 0),
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );

      final folded = written(
        planExport(mirrored, format: ExportFormat.f3d, force: true),
      );
      final bare = written(
        planExport(
          mirrored,
          format: ExportFormat.f3d,
          force: true,
          applyModifiers: false,
        ),
      );

      final int foldedTriangles = F3dDocument.parse(
        folded.files.single.bytes,
      ).triangleCount;
      final int bareTriangles = F3dDocument.parse(
        bare.files.single.bytes,
      ).triangleCount;

      // A mirror doubles the geometry. Mutation: ignore the flag and both
      // numbers agree, which is the bug — somebody taking a model into a
      // tool with its own mirror gets it applied twice.
      expect(foldedTriangles, greaterThan(bareTriangles));
      expect(foldedTriangles, bareTriangles * 2);
    });

    test('the project being edited keeps its modifiers either way', () {
      final mirrored = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'half',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );

      planExport(
        mirrored,
        format: ExportFormat.f3d,
        force: true,
        applyModifiers: false,
      );

      // An export option is not an edit: the copy handed to the writer is
      // the only thing the stacks come off.
      expect(mirrored.objects.single.modifiers, hasLength(1));
    });

    test('every registered writer is a format the screen offers', () {
      // The row's own acceptance. `builtInModelWriters` had STL and USDZ in
      // it long before this menu did, so somebody with a 3D printer opened
      // the one screen that writes files and could not choose the one format
      // they came for. Mutation: drop a member from `ExportFormat` and the
      // writer goes back to being unreachable from the interface.
      final Set<String> offered = <String>{
        for (final ExportFormat format in ExportFormat.values)
          format.writer.name,
      };
      final Set<String> registered = <String>{
        for (final ModelWriter writer in builtInModelWriters) writer.name,
      };
      expect(offered, containsAll(registered));
      // And the other way round, which is the half that catches a member
      // kept here after its writer was withdrawn: a button that writes a
      // format nothing in the repository still reads.
      expect(registered, containsAll(offered));
    });

    test('no two formats are offered under the same name', () {
      // Binary and ASCII STL write the same `.stl` extension, so a picker
      // built on `suffix` alone shows two identical buttons. Mutation: make
      // `label` return `suffix` and this is the test that says why not.
      final List<String> labels = <String>[
        for (final ExportFormat format in ExportFormat.values) format.label,
      ];
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('STL and USDZ are formats the screen can offer', () {
      // `ux-18` asks for one export dialog, which means the dialog has to be
      // able to reach every format the application writes.
      for (final ExportFormat format in <ExportFormat>[
        ExportFormat.stl,
        ExportFormat.stlAscii,
        ExportFormat.usdz,
      ]) {
        final ok = written(planExport(workshop(), format: format));
        expect(ok.files, isNotEmpty, reason: '${format.name} wrote nothing');
        expect(ok.files.single.bytes, isNotEmpty);
      }
    });
  });
}

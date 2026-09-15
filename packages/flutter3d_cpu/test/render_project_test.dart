/// `renderProject` (`flutter3d_model_core`), drawn on a real [CpuDevice] and
/// checked pixel by pixel — the half of `mcp-05n`'s own acceptance that
/// `flutter3d_model_core` itself cannot test, since a real [GraphicsDevice]
/// means a real backend and that package may not depend on one. See
/// `flutter3d_model_core/lib/src/render_project.dart`'s own doc comment, and
/// this package's own pubspec, for why the dependency runs this direction
/// instead.
///
///     dart test test/render_project_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A unit cube centred at [center] rather than at the origin — a modifier's
/// own mirror or array runs in the mesh's *local* space, through the
/// origin, so a cube already straddling it would not show a visible
/// difference in the picture at all.
EditMesh _offsetCuboid(Vector3 center) {
  final half = Vector3(0.5, 0.5, 0.5);
  Vector3 at(double sx, double sy, double sz) =>
      center + Vector3(sx * half.x, sy * half.y, sz * half.z);
  return EditMesh.fromFaces(
    <Vector3>[
      at(-1, -1, -1),
      at(1, -1, -1),
      at(1, 1, -1),
      at(-1, 1, -1),
      at(-1, -1, 1),
      at(1, -1, 1),
      at(1, 1, 1),
      at(-1, 1, 1),
    ],
    <List<int>>[
      <int>[4, 5, 6, 7],
      <int>[1, 0, 3, 2],
      <int>[5, 1, 2, 6],
      <int>[0, 4, 7, 3],
      <int>[3, 7, 6, 2],
      <int>[0, 1, 5, 4],
    ],
  );
}

/// A project with one red, edited (not parametric — a modifier stack only
/// runs over an [EditedGeometry]) cube offset from the origin, and
/// [modifiers] on it.
ModelProject _editedCubeProject({
  List<ModifierSlot> modifiers = const <ModifierSlot>[],
}) {
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(_offsetCuboid(Vector3(1.2, 0, 0))),
      transform: Matrix4.identity(),
      materialSlots: const <int>[0],
      modifiers: modifiers,
    ),
  );
  return ModelProject(
    profile: project.profile,
    objects: project.objects,
    materials: <ProjectMaterial>[
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'red',
          baseColor: Vector4(0.9, 0.1, 0.1, 1.0),
          roughness: 0.8,
        ),
      ),
    ],
    images: project.images,
    nextId: project.nextId,
    skeletons: project.skeletons,
    clips: project.clips,
    lighting: project.lighting,
  );
}

int _differingPixels(Rgba8Image a, Rgba8Image b) {
  var differing = 0;
  for (var i = 0; i < a.pixels.length; i += 4) {
    final dr = (a.pixels[i] - b.pixels[i]).abs();
    final dg = (a.pixels[i + 1] - b.pixels[i + 1]).abs();
    final db = (a.pixels[i + 2] - b.pixels[i + 2]).abs();
    if (dr + dg + db > 30) differing++;
  }
  return differing;
}

/// A project with one cuboid, red, centred at the origin.
ModelProject _cubeProject() {
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: ParametricGeometry(ParametricCuboid(size: Vector3(2, 2, 2))),
      transform: Matrix4.identity(),
      materialSlots: const <int>[0],
    ),
  );
  return ModelProject(
    profile: project.profile,
    objects: project.objects,
    materials: <ProjectMaterial>[
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'red',
          baseColor: Vector4(0.9, 0.1, 0.1, 1.0),
          roughness: 0.8,
        ),
      ),
    ],
    images: project.images,
    nextId: project.nextId,
    skeletons: project.skeletons,
    clips: project.clips,
    lighting: project.lighting,
  );
}

int _litPixels(Rgba8Image image, {int threshold = 60}) {
  var lit = 0;
  for (var i = 0; i < image.pixels.length; i += 4) {
    if (image.pixels[i] + image.pixels[i + 1] + image.pixels[i + 2] >
        threshold) {
      lit++;
    }
  }
  return lit;
}

void main() {
  group('renderProject on a real CpuDevice', () {
    test(
      'draws a cube: the picture is not just the empty background',
      () async {
        final png = await renderProject(
          RenderRequest(project: _cubeProject(), width: 64, height: 64),
          deviceFactory: _cpuDevice,
        );
        final decoded = await decodeImagePure(png);
        expect(decoded, isNotNull);
        expect(decoded!.width, 64);
        expect(decoded.height, 64);
        expect(
          _litPixels(decoded),
          greaterThan(64 * 64 ~/ 20),
          reason:
              'a 2×2×2 cube framed by renderProject should cover a real '
              'fraction of a 64×64 picture, not a speck',
        );
      },
    );

    test('every named view actually points at the cube', () async {
      for (final view in RenderProjectView.values) {
        final png = await renderProject(
          RenderRequest(
            project: _cubeProject(),
            view: view,
            width: 48,
            height: 48,
          ),
          deviceFactory: _cpuDevice,
        );
        final decoded = await decodeImagePure(png);
        expect(
          _litPixels(decoded!),
          greaterThan(0),
          reason: '$view framed nothing — the camera missed the cube',
        );
      }
    });

    test(
      'normals shading draws a visibly different picture than material',
      () async {
        final material = await renderProject(
          RenderRequest(project: _cubeProject(), width: 48, height: 48),
          deviceFactory: _cpuDevice,
        );
        final normals = await renderProject(
          RenderRequest(
            project: _cubeProject(),
            width: 48,
            height: 48,
            shading: RenderShading.normals,
          ),
          deviceFactory: _cpuDevice,
        );
        final decodedMaterial = (await decodeImagePure(material))!;
        final decodedNormals = (await decodeImagePure(normals))!;

        var differingPixels = 0;
        for (var i = 0; i < decodedMaterial.pixels.length; i += 4) {
          final dr = (decodedMaterial.pixels[i] - decodedNormals.pixels[i])
              .abs();
          final dg =
              (decodedMaterial.pixels[i + 1] - decodedNormals.pixels[i + 1])
                  .abs();
          final db =
              (decodedMaterial.pixels[i + 2] - decodedNormals.pixels[i + 2])
                  .abs();
          if (dr + dg + db > 30) differingPixels++;
        }
        expect(
          differingPixels,
          greaterThan(0),
          reason:
              'a red PBR cube and a normals-shaded one should not read '
              'as the same picture',
        );
      },
    );

    test(
      'a selected object is drawn differently than an unselected one',
      () async {
        final a = const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'a',
            geometry: ParametricGeometry(
              ParametricCuboid(size: Vector3(1, 1, 1)),
            ),
            transform: Matrix4.translation(Vector3(-0.7, 0.0, 0.0)),
            materialSlots: const <int>[0],
          ),
        );
        final withB = a.added(
          (int id) => ModelObject(
            id: id,
            name: 'b',
            geometry: ParametricGeometry(
              ParametricCuboid(size: Vector3(1, 1, 1)),
            ),
            transform: Matrix4.translation(Vector3(0.7, 0.0, 0.0)),
            materialSlots: const <int>[0],
          ),
        );
        // Dark and rough, so under this file's two bright directional lights
        // neither cube's own base colour clips to white in either render — a
        // highlight blended over 255 would be invisible in the 8-bit output.
        final project = ModelProject(
          profile: withB.profile,
          objects: withB.objects,
          materials: <ProjectMaterial>[
            ProjectMaterial(
              surface: SurfaceMaterial(
                baseColor: Vector4(0.15, 0.15, 0.15, 1.0),
                roughness: 0.9,
              ),
            ),
          ],
          images: withB.images,
          nextId: withB.nextId,
          skeletons: withB.skeletons,
          clips: withB.clips,
          lighting: withB.lighting,
        );

        final plain = await decodeImagePure(
          await renderProject(
            RenderRequest(project: project, width: 64, height: 64),
            deviceFactory: _cpuDevice,
          ),
        );
        final highlighted = await decodeImagePure(
          await renderProject(
            RenderRequest(
              project: project,
              width: 64,
              height: 64,
              selection: <int>{project.objects.first.id},
            ),
            deviceFactory: _cpuDevice,
          ),
        );

        var differingPixels = 0;
        for (var i = 0; i < plain!.pixels.length; i += 4) {
          if ((plain.pixels[i] - highlighted!.pixels[i]).abs() > 10) {
            differingPixels++;
          }
        }
        expect(
          differingPixels,
          greaterThan(0),
          reason: 'selecting one object should change how that object draws',
        );
      },
    );

    test('an empty project draws the background, not a crash', () async {
      final png = await renderProject(
        RenderRequest(project: const ModelProject(), width: 16, height: 16),
        deviceFactory: _cpuDevice,
      );
      final decoded = await decodeImagePure(png);
      expect(decoded, isNotNull);
      expect(decoded!.width, 16);
      expect(decoded.height, 16);
    });
  });

  group('tut-22 — renderProject is deterministic', () {
    // `tut-22`'s own investigation (`doc/modeler-tutorial-gaps.md`): four
    // committed tutorial reference PNGs were found to differ from a clean
    // regenerate of the same, unmodified HEAD. That turned out to have
    // nothing to do with `renderProject` itself — the real cause was
    // `tut-07`'s own legitimate default change (`RenderSettings.bloom`/
    // `.shadows` now follow `SceneLighting`'s own defaults, which do not
    // match `RenderSettings`'s bare ones, for a project that never touches
    // its own lighting) reaching two tutorial cases' own reference pictures
    // that were never regenerated for it — not a source of nondeterminism
    // anywhere in the render path. This group is what actually rules that
    // out, rather than leaving it assumed: the same project, rendered twice,
    // must come back byte-identical, in one process and across two.
    test(
      'the same project, rendered twice in one process, is byte-identical',
      () async {
        // A shape close to the two cases this row's own investigation named:
        // an edited mesh under a modifier, no explicit `SceneLighting` at
        // all — exactly the combination that made `tut-07`'s default change
        // invisible to every test that only ever compared *within* one run.
        final project = _editedCubeProject(
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        );
        final request = RenderRequest(
          project: project,
          view: RenderProjectView.front,
          width: 64,
          height: 64,
        );
        final first = await renderProject(request, deviceFactory: _cpuDevice);
        final second = await renderProject(request, deviceFactory: _cpuDevice);
        expect(
          second,
          orderedEquals(first),
          reason:
              'renderProject has no clock, no random seed and no unordered '
              'Set/Map on its own render path — two calls with the same '
              'RenderRequest must produce the same bytes',
        );
      },
    );

    test(
      'the same project, rendered in two fresh CpuDevices, is byte-identical',
      () async {
        // `_cpuDevice` builds a brand-new `CpuDevice` per call, the same
        // shape `tool/make_caseN_fixtures.dart` uses from a fresh `dart run`
        // process each time it is invoked by hand — so this is the closer
        // analogue of "two fresh processes" than the test above, without
        // actually paying for a second process.
        final project = _cubeProject();
        final request = RenderRequest(
          project: project,
          view: RenderProjectView.iso,
          width: 48,
          height: 48,
        );
        final a = await renderProject(
          request,
          deviceFactory: (w, h) => CpuDevice(
            width: w,
            height: h,
            shaders: CpuShaderLibrary(builtinCpuShaders()),
          ),
        );
        final b = await renderProject(
          request,
          deviceFactory: (w, h) => CpuDevice(
            width: w,
            height: h,
            shaders: CpuShaderLibrary(builtinCpuShaders()),
          ),
        );
        expect(b, orderedEquals(a));
      },
    );
  });

  group('tut-06 — modifiers read at render time', () {
    Future<Rgba8Image> render(ModelProject project) async =>
        (await decodeImagePure(
          await renderProject(
            RenderRequest(
              project: project,
              view: RenderProjectView.front,
              width: 64,
              height: 64,
            ),
            deviceFactory: _cpuDevice,
          ),
        ))!;

    test('a mirror modifier changes the picture, with no Apply', () async {
      final bare = await render(_editedCubeProject());
      final mirrored = await render(
        _editedCubeProject(
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
          ],
        ),
      );

      // Mutation: read `object.geometry` straight through regardless of
      // `object.modifiers`, the way `renderProject` did before `tut-06` —
      // the two pictures would then be pixel-for-pixel identical.
      expect(
        _differingPixels(bare, mirrored),
        greaterThan(0),
        reason:
            'a mirror modifier should be visible in a headless render '
            'without Apply ever being called',
      );
    });

    test('an array modifier changes the picture, with no Apply', () async {
      final bare = await render(_editedCubeProject());
      final arrayed = await render(
        _editedCubeProject(
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: ArrayModifier(count: 3, offset: Vector3(0, 0, 2.4)),
            ),
          ],
        ),
      );

      expect(
        _differingPixels(bare, arrayed),
        greaterThan(0),
        reason:
            'an array modifier should be visible in a headless render '
            'without Apply ever being called',
      );
    });

    test(
      'Apply bakes exactly the picture the live stack already drew',
      () async {
        final project = _editedCubeProject(
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
            ModifierSlot(
              modifier: ArrayModifier(count: 2, offset: Vector3(0, 0, 2.4)),
            ),
          ],
        );
        final before = await render(project);

        final history = ModelHistory(project);
        expect(history.run(const ApplyModifier(id: 1, index: 1)), isNull);
        expect(history.project[1]!.modifiers, isEmpty);

        final after = await render(history.project);

        // Apply bakes the stack into the base mesh and drops it — it must
        // not change what was already visible, only how it is stored.
        expect(_differingPixels(before, after), 0);
      },
    );
  });

  group("tut-07 — a project's own lighting reaches the picture", () {
    Future<Rgba8Image> render(ModelProject project) async =>
        (await decodeImagePure(
          await renderProject(
            RenderRequest(project: project, width: 64, height: 64),
            deviceFactory: _cpuDevice,
          ),
        ))!;

    int brightnessSum(Rgba8Image image) {
      var sum = 0;
      for (var i = 0; i < image.pixels.length; i += 4) {
        sum += image.pixels[i] + image.pixels[i + 1] + image.pixels[i + 2];
      }
      return sum;
    }

    ModelProject relit(ModelProject base, SceneLighting lighting) =>
        ModelProject(
          profile: base.profile,
          objects: base.objects,
          materials: base.materials,
          images: base.images,
          nextId: base.nextId,
          skeletons: base.skeletons,
          clips: base.clips,
          lighting: lighting,
        );

    test("a project's own point light brightens the picture, on top of the "
        'fixed key/fill pair', () async {
      final base = _cubeProject();
      final unlit = await render(base);
      final lit = await render(
        relit(
          base,
          SceneLighting(
            lights: <ProjectLight>[
              ProjectLight(
                type: ProjectLightType.point,
                intensity: 80.0,
                transform: Matrix4.translation(Vector3(1.5, 1.5, 1.5)),
              ),
            ],
          ),
        ),
      );

      // Mutation: build `renderProject`'s own scene from the two fixed
      // lights alone, the way it did before `tut-07` — the two pictures
      // would then be identical, since nothing reads `project.lighting`
      // at all.
      expect(
        _differingPixels(unlit, lit),
        greaterThan(0),
        reason:
            "a project's own AddLight should reach a headless render, "
            'not only the live viewport',
      );
      expect(
        brightnessSum(lit),
        greaterThan(brightnessSum(unlit)),
        reason: 'an added point light should brighten the picture',
      );
    });

    test("the scene's own exposure reaches the picture too", () async {
      final base = _cubeProject();
      final normal = await render(base);
      final dim = await render(relit(base, const SceneLighting(exposure: 0.3)));

      expect(
        brightnessSum(dim),
        lessThan(brightnessSum(normal)),
        reason:
            "SetSceneLightingField('exposure', ...) should darken a "
            'headless render, the same way it darkens the live viewport',
      );
    });
  });

  group('tut-10 — a posed, skinned, morphed character', () {
    Future<Rgba8Image> render(ModelProject project) async =>
        (await decodeImagePure(
          await renderProject(
            RenderRequest(
              project: project,
              view: RenderProjectView.front,
              width: 64,
              height: 64,
            ),
            deviceFactory: _cpuDevice,
          ),
        ))!;

    /// A flat quad, small enough that a modest joint move carries it well
    /// clear of where it started.
    EditMesh buildQuad() => EditMesh.fromFaces(
      <Vector3>[
        Vector3(-0.5, -0.5, 0),
        Vector3(0.5, -0.5, 0),
        Vector3(0.5, 0.5, 0),
        Vector3(-0.5, 0.5, 0),
      ],
      <List<int>>[
        <int>[0, 1, 2, 3],
      ],
    );

    /// A project with one quad, wholly weighted to one joint sitting at
    /// [jointTransform] — bind pose is always the joint at the identity, so
    /// [jointTransform] alone is what a `PoseJoint`/`RotateBy` pair would
    /// have moved it to.
    ModelProject skinnedQuadProject(Matrix4 jointTransform) {
      var project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'joint',
          geometry: const SocketGeometry(),
          transform: jointTransform,
        ),
      );
      final int jointId = project.objects.single.id;

      final mesh = buildQuad();
      mesh.beginStep();
      assignSelection(
        mesh,
        <int>[for (var v = 0; v < mesh.vertexSlotCount; v++) v],
        0,
        1.0,
      );
      mesh.endStep();
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'mesh',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
          materialSlots: const <int>[0],
          skeletonIndex: 0,
        ),
      );

      return ModelProject(
        profile: project.profile,
        objects: project.objects,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(
              baseColor: Vector4(0.9, 0.1, 0.1, 1.0),
              roughness: 0.8,
            ),
          ),
        ],
        images: project.images,
        nextId: project.nextId,
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[jointId],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
        clips: project.clips,
        lighting: project.lighting,
      );
    }

    test("a posed joint moves the mesh it skins — renderProject draws the "
        'pose, not the bind pose', () async {
      // A rotation, not a translation: `_frame`'s own camera re-fits to
      // wherever a lone skinned object ends up, so a pure translation
      // reads as the identical picture either way — moved, then framed
      // right back to the middle. Turning the flat quad edge-on to the
      // camera instead changes its own *silhouette*, which framing cannot
      // hide.
      final rest = await render(skinnedQuadProject(Matrix4.identity()));
      final posed = await render(
        skinnedQuadProject(Matrix4.rotationY(math.pi / 2)),
      );

      // Mutation: read `object.geometry` at raw bind pose regardless of
      // `skeletonIndex`, the way `renderProject` did before `tut-10` —
      // `restLit` and `posedLit` would then be equal, since nothing about
      // the mesh object's own transform ever changed.
      final int restLit = _litPixels(rest, threshold: 30);
      final int posedLit = _litPixels(posed, threshold: 30);
      expect(
        posedLit,
        lessThan(restLit ~/ 3),
        reason:
            'a quad turned edge-on by its own joint should cover far '
            'fewer pixels face-on than one left at bind pose — '
            'rest=$restLit posed=$posedLit',
      );
    });

    test("a shape key's own weight blends into the render", () async {
      final quad = buildQuad();
      final puffed = Float32List(quad.vertexSlotCount * 3);
      for (var v = 0; v < quad.vertexSlotCount; v++) {
        final p = quad.positionOf(v);
        puffed[v * 3] = p.x * 2.4;
        puffed[v * 3 + 1] = p.y * 2.4;
        puffed[v * 3 + 2] = p.z * 2.4;
      }
      final key = ShapeKey('puff', puffed);

      ModelProject projectAt(double weight) {
        final base = const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'mesh',
            geometry: EditedGeometry(quad),
            transform: Matrix4.identity(),
            materialSlots: const <int>[0],
            shapeSet: ShapeSet(
              keys: <ShapeKey>[key],
              weights: <double>[weight],
            ),
          ),
        );
        return ModelProject(
          profile: base.profile,
          objects: base.objects,
          materials: <ProjectMaterial>[
            ProjectMaterial(
              surface: SurfaceMaterial(
                baseColor: Vector4(0.9, 0.1, 0.1, 1.0),
                roughness: 0.8,
              ),
            ),
          ],
          images: base.images,
          nextId: base.nextId,
          skeletons: base.skeletons,
          clips: base.clips,
          lighting: base.lighting,
        );
      }

      final flat = await render(projectAt(0.0));
      final blended = await render(projectAt(1.0));

      // Mutation: never read `object.shapeSet` at all, the way
      // `renderProject` did before `tut-10` — the two pictures would
      // then be identical regardless of the weight.
      expect(
        _differingPixels(flat, blended),
        greaterThan(0),
        reason:
            "a shape key's own weight should blend into a headless "
            'render — case 4\'s own chest-puff morph',
      );
    });
  });

  group('tut-11 — the weight-paint gradient render mode', () {
    /// A ten-vertex strip along X, half of it weighted 1.0 to the one
    /// joint and half left at 0.0 — two known, well-separated regions to
    /// sample the gradient at.
    ModelProject weightStripProject() {
      const int columns = 10;
      final points = <Vector3>[];
      for (var x = 0; x <= columns; x++) {
        final u = x / columns - 0.5;
        points
          ..add(Vector3(u, -0.5, 0))
          ..add(Vector3(u, 0.5, 0));
      }
      final faces = <List<int>>[
        for (var x = 0; x < columns; x++)
          <int>[x * 2, x * 2 + 2, x * 2 + 3, x * 2 + 1],
      ];
      final mesh = EditMesh.fromFaces(points, faces);
      mesh.beginStep();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        final onJoint = mesh.positionOf(v).x >= 0;
        if (onJoint) assignSelection(mesh, <int>[v], 0, 1.0);
      }
      mesh.endStep();

      final joint = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'joint',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      final int jointId = joint.objects.single.id;
      final withMesh = joint.added(
        (int id) => ModelObject(
          id: id,
          name: 'mesh',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
          materialSlots: const <int>[0],
          skeletonIndex: 0,
        ),
      );
      return ModelProject(
        profile: withMesh.profile,
        objects: withMesh.objects,
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial()),
        ],
        images: withMesh.images,
        nextId: withMesh.nextId,
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[jointId],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
        clips: withMesh.clips,
        lighting: withMesh.lighting,
      );
    }

    test('the half painted onto the joint reads warmer than the half left at '
        'zero', () async {
      final project = weightStripProject();
      final jointId = project.objects
          .firstWhere((ModelObject o) => o.name == 'joint')
          .id;
      final decoded = (await decodeImagePure(
        await renderProject(
          RenderRequest(
            project: project,
            view: RenderProjectView.front,
            width: 64,
            height: 64,
            shading: RenderShading.weights,
            weightsJoint: jointId,
          ),
          deviceFactory: _cpuDevice,
        ),
      ))!;

      // Searched over the whole picture rather than sampled at a fixed
      // coordinate: `_frame`'s own fit (margin, aspect, the socket
      // joint's own degenerate bounds folded into the box) is real
      // arithmetic this test has no business duplicating just to guess
      // a pixel address — what it can assert directly is that both of
      // `weight_gradient_colors.dart`'s own extreme stops actually
      // appear somewhere in the picture.
      bool hasPixelNear(int r, int g, int b, {int tolerance = 40}) {
        for (var i = 0; i < decoded.pixels.length; i += 4) {
          final dr = (decoded.pixels[i] - r).abs();
          final dg = (decoded.pixels[i + 1] - g).abs();
          final db = (decoded.pixels[i + 2] - b).abs();
          if (dr <= tolerance && dg <= tolerance && db <= tolerance) {
            return true;
          }
        }
        return false;
      }

      // Mutation: paint every vertex the same colour (or draw `material`
      // regardless of `shading`) and neither of these is found.
      expect(
        hasPixelNear(0x2A, 0x3A, 0x7A),
        isTrue,
        reason:
            'the untouched half should read as the gradient\'s own '
            'no-influence stop, #2A3A7A',
      );
      expect(
        hasPixelNear(0xFF, 0x3B, 0x5C),
        isTrue,
        reason:
            'the joint half should read as the gradient\'s own '
            'full-influence stop, #FF3B5C',
      );
    });

    test('an object not bound to the requested joint falls back to material, '
        'not a blank mesh', () async {
      final unbound = _cubeProject();
      final decoded = (await decodeImagePure(
        await renderProject(
          RenderRequest(
            project: unbound,
            width: 48,
            height: 48,
            shading: RenderShading.weights,
            weightsJoint: 999,
          ),
          deviceFactory: _cpuDevice,
        ),
      ))!;
      expect(
        _litPixels(decoded),
        greaterThan(0),
        reason:
            'an unskinned object under `weights` mode should still draw '
            'its own material rather than nothing at all',
      );
    });
  });
}

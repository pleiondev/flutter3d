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

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
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
}

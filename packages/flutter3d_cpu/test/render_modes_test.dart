/// `mcp-08n`'s own acceptance: `normals` on an inverted shell differs from
/// `material` by more than 20% of pixels — checked against a real
/// `CpuDevice`, since the point is what actually lands on screen.
///
///     dart test test/render_modes_test.dart
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

void main() {
  test('normals on an inverted shell differs from material by more than 20% '
      'of pixels', () async {
    final shell = EditMesh.cuboid(size: Vector3(2, 2, 2))
      ..beginStep()
      ..flipNormals()
      ..endStep();
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'shell',
        geometry: EditedGeometry(shell),
        transform: Matrix4.identity(),
      ),
    );

    final material = await renderProject(
      RenderRequest(project: project, width: 64, height: 64),
      deviceFactory: _cpuDevice,
    );
    final normals = await renderProject(
      RenderRequest(
        project: project,
        width: 64,
        height: 64,
        shading: RenderShading.normals,
      ),
      deviceFactory: _cpuDevice,
    );

    final decodedMaterial = (await decodeImagePure(material))!;
    final decodedNormals = (await decodeImagePure(normals))!;

    var differingPixels = 0;
    final pixelCount = decodedMaterial.width * decodedMaterial.height;
    for (var i = 0; i < decodedMaterial.pixels.length; i += 4) {
      var differs = false;
      for (var c = 0; c < 3; c++) {
        if ((decodedMaterial.pixels[i + c] - decodedNormals.pixels[i + c])
                .abs() >
            8) {
          differs = true;
          break;
        }
      }
      if (differs) differingPixels++;
    }

    expect(
      differingPixels / pixelCount,
      greaterThan(0.2),
      reason:
          'material and normals shading of an inverted shell should '
          'read as visibly different pictures across most of the frame, '
          'not just at a seam',
    );
  });
}

/// The quality table is measured the way its rows say — `N2`.
///
/// A small lit scene on the software device, one frame of each setting: full
/// quality judged against itself is nought and costs one, a smaller picture
/// looks different from the full one, and the generated source carries the
/// rows `QualityTable.of` reads.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 32;

({Scene scene, RenderView view, RenderSettings settings}) _crates(
  GraphicsDevice device,
) {
  final camera = CameraNode()
    ..setPosition(0.0, 1.5, 3.0)
    ..lookAt(Vector3(0.0, 0.3, 0.0));
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(6, 0.1, 6)).build(),
        ),
        Material(baseColor: Vector4(0.6, 0.6, 0.6, 1.0)),
      )..setPosition(0.0, -0.05, 0.0),
    )
    ..add(
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(baseColor: Vector4(0.8, 0.3, 0.1, 1.0)),
        )
        ..setPosition(0.0, 0.5, 0.0)
        ..setRotationYawPitchRoll(0.6, 0.0, 0.0),
    )
    ..add(
      LightNode(intensity: 3.0)
        ..setPosition(2.0, 4.0, 3.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(camera);
  return (
    scene: scene,
    view: RenderView(camera: camera),
    settings: const RenderSettings(
      ambientOcclusion: AmbientOcclusionSettings(enabled: true),
    ),
  );
}

void main() {
  test('each setting is measured against full quality', () async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final rows = await measureQualityTable(
      device: device,
      width: _width,
      height: _height,
      scenes: <QualityScene>[_crates],
      settle: 1,
      samples: 1,
    );
    expect(rows.map((r) => r.setting), QualitySetting.grid);
    expect(rows.first.cost, 1.0);
    expect(rows.first.flip, 0.0);

    final half = rows.firstWhere(
      (r) => r.setting == const QualitySetting(renderScale: 0.5, tier: 0),
    );
    // Drawn at a quarter of the pixels and stretched back: it looks
    // different. Mutation: compare every row against its own picture.
    expect(half.flip, greaterThan(0.01));
    final fewerSamples = rows.firstWhere(
      (r) => r.setting == const QualitySetting(renderScale: 1.0, tier: 3),
    );
    // A quarter of the occlusion's samples moves the corners, a little.
    expect(fewerSamples.flip, greaterThan(0.0));
    expect(fewerSamples.flip, lessThan(half.flip));

    final source = qualityTablesSource(
      <DeviceClass, ({List<QualityMeasurement> rows, bool measured})>{
        for (final c in DeviceClass.values) c: (rows: rows, measured: false),
      },
    );
    expect(
      source,
      contains(
        'const List<bool> qualityMeasured = <bool>[false, false, false];',
      ),
    );
    expect(
      source,
      contains(
        '  <double>[${rows.map((r) => r.flip.toStringAsFixed(4)).join(', ')}],',
      ),
    );
  });
}

/// Writes `flutter3d_core`'s quality tables — `N2`.
///
///     dart run tool/quality_table.dart
///
/// **What this writes today is a stand-in, and the file says so.** The costs
/// a device class needs are that class's frame times, measured with H2's
/// timing on a phone, a desktop and a browser; this machine has none of them
/// to hand a `dart run`. So the rows here are measured on the software
/// rasteriser, whose cost is the arithmetic the shaders do and whose
/// pictures are the ones every backend's goldens are held to, and all three
/// classes get the same rows with `measured` false. The FLIP column is
/// already the real one; the cost column is right in shape (a pixel costs
/// what a pixel costs) and wrong in proportion wherever a GPU's bottleneck
/// is not arithmetic. `AdaptiveQuality` corrects each row it visits on the
/// device either way.
///
/// A measured table comes from calling `measureQualityTable` with the
/// device's own `GraphicsDevice` inside an application, and handing the rows
/// to `qualityTablesSource` for that class.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_testing/src/quality_table_builder.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 80;

const String _out =
    '../flutter3d_core/lib/src/engine/render/tables/quality_tables.dart';

MeshNode _box(GraphicsDevice device, Vector3 size, Vector3 colour) => MeshNode(
  DeviceMesh.upload(device, CuboidShape(size: size).build()),
  Material(baseColor: Vector4(colour.x, colour.y, colour.z, 1.0)),
);

/// A room in daylight: a floor, a wall, crates, the sun casting and a lamp,
/// with ambient occlusion, reflections and contact shadows on.
({Scene scene, RenderView view, RenderSettings settings}) _room(
  GraphicsDevice device,
) {
  final camera = CameraNode()
    ..setPosition(0.0, 2.2, 5.5)
    ..lookAt(Vector3(0.0, 0.6, 0.0));
  final scene = Scene()
    ..add(
      _box(device, Vector3(12.0, 0.1, 12.0), Vector3(0.55, 0.5, 0.45))
        ..setPosition(0.0, -0.05, 0.0),
    )
    ..add(
      _box(device, Vector3(12.0, 4.0, 0.2), Vector3(0.7, 0.7, 0.75))
        ..setPosition(0.0, 2.0, -2.5),
    )
    ..add(camera);
  for (final (x, z, s) in const <(double, double, double)>[
    (-1.4, -0.8, 1.0),
    (0.3, -1.2, 0.7),
    (1.5, 0.2, 0.5),
    (-0.2, 0.6, 0.35),
  ]) {
    scene.add(
      _box(device, Vector3.all(s), Vector3(0.6, 0.35, 0.2))
        ..setPosition(x, s * 0.5, z)
        ..setRotationYawPitchRoll(x * 0.7, 0.0, 0.0),
    );
  }
  scene
    ..add(
      LightNode(intensity: 3.0)
        ..setPosition(3.0, 6.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 4.0,
        range: 6.0,
        color: Vector3(1.0, 0.7, 0.4),
      )..setPosition(1.0, 1.5, 1.0),
    );
  return (
    scene: scene,
    view: RenderView(camera: camera),
    settings: const RenderSettings(
      shadows: ShadowSettings(resolution: 512, cubeResolution: 128),
      ambientOcclusion: AmbientOcclusionSettings(enabled: true),
      reflections: ReflectionSettings(enabled: true),
      contactShadows: ContactShadowSettings(enabled: true),
    ),
  );
}

/// A colonnade in haze: pillars on a floor, the sun low through them, with
/// volumetric fog and light shafts on.
({Scene scene, RenderView view, RenderSettings settings}) _colonnade(
  GraphicsDevice device,
) {
  final camera = CameraNode()
    ..setPosition(0.0, 1.6, 7.0)
    ..lookAt(Vector3(0.0, 1.2, 0.0));
  final scene = Scene()
    ..add(
      _box(device, Vector3(20.0, 0.1, 20.0), Vector3(0.5, 0.5, 0.5))
        ..setPosition(0.0, -0.05, 0.0),
    )
    ..add(camera);
  for (var i = 0; i < 6; i++) {
    final z = -6.0 + i * 2.0;
    for (final x in const <double>[-2.0, 2.0]) {
      scene.add(
        _box(device, Vector3(0.4, 4.0, 0.4), Vector3(0.8, 0.78, 0.7))
          ..setPosition(x, 2.0, z),
      );
    }
  }
  scene.add(
    LightNode(intensity: 4.0)
      ..setPosition(-6.0, 3.0, -2.0)
      ..lookAt(Vector3(0.0, 0.0, 1.0)),
  );
  return (
    scene: scene,
    view: RenderView(camera: camera),
    settings: RenderSettings(
      shadows: const ShadowSettings(resolution: 512, cubeResolution: 128),
      volumetricFog: const VolumetricFogSettings(
        enabled: true,
        density: 0.08,
      ).copyWith(ambient: Vector3.all(0.05)),
      lightShafts: const LightShaftSettings(enabled: true),
    ),
  );
}

Future<void> main() async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final clock = Stopwatch()..start();
  final rows = await measureQualityTable(
    device: device,
    width: _width,
    height: _height,
    scenes: <QualityScene>[_room, _colonnade],
  );
  stdout.writeln('measured ${rows.length} settings in ${clock.elapsed}');
  for (final r in rows) {
    stdout.writeln(
      '  ${r.setting}: cost ${r.cost.toStringAsFixed(3)}, '
      'flip ${r.flip.toStringAsFixed(4)}',
    );
  }

  // The rasteriser's timing moves by a few per cent run to run; costs are
  // rounded so a re-run that measured the same thing writes the same file
  // more often than not. Nothing may cost more than full or less than zero.
  final rounded = <QualityMeasurement>[
    for (final r in rows)
      (
        setting: r.setting,
        cost: (math.min(r.cost, 1.0) * 100).round() / 100,
        flip: r.flip,
      ),
  ];
  final stand = (rows: rounded, measured: false);
  File(_out).writeAsStringSync(
    qualityTablesSource(
      <DeviceClass, ({List<QualityMeasurement> rows, bool measured})>{
        for (final c in DeviceClass.values) c: stand,
      },
      note:
          'The rows `QualityTable.of` reads — `N2`.\n'
          '\n'
          'Not yet measured on any device class: every class holds the same\n'
          'rows, measured on the software rasteriser at $_width×$_height over\n'
          'two scenes (a room with occlusion, reflections and contact shadows;\n'
          'a colonnade in volumetric fog with light shafts). The FLIP column\n'
          'is the pictures\' own; the cost column is the rasteriser\'s, which\n'
          'stands in until each class is measured with `measureQualityTable`\n'
          'on its own GPU. `AdaptiveQuality` corrects the rows it visits.',
    ),
  );
  stdout.writeln('wrote $_out');
}

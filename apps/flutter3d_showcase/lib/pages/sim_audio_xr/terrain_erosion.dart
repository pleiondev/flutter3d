/// One hill twice: on the left as it was made, on the right after scree has
/// slid off it, rain has run down it, or both.
///
/// Quoted by `terrain_erosion.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final class TerrainErosionDemo extends ShowcaseDemo {
  /// 0 thermal, 1 hydraulic, 2 both.
  int kind = 2;
  int seed = 7;
  double droplets = 3000;

  late final Heightfield _before;
  late Heightfield _after;
  late final MeshNode _left;
  late final MeshNode _right;
  late final DemoContext _context;

  static const int _side = 33;

  /// How far apart the two hills stand, in metres along x.
  static const double _apart = 18.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 46.0
      ..pitch = 0.6
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 2.0, 0.0);
  }

  // #region hill
  /// A steep hill with a ridge across it: slopes past what loose ground
  /// holds, and a valley for water to find. Heights in metres, a metre a
  /// cell.
  static Heightfield _hill() {
    final heights = Float32List(_side * _side);
    for (var z = 0; z < _side; z++) {
      for (var x = 0; x < _side; x++) {
        final double dx = x - 16.0, dz = z - 16.0;
        final double r = math.sqrt(dx * dx + dz * dz);
        heights[z * _side + x] =
            math.max(0.0, 9.0 - 0.6 * r) +
            1.2 * math.sin(x * 0.7) * math.cos(z * 0.5);
      }
    }
    return Heightfield(
      columns: _side,
      rows: _side,
      cellSize: 1.0,
      heights: heights,
      origin: Vector3(-16.0, 0.0, -16.0),
    );
  }
  // #endregion hill

  // #region erode
  /// The hill after [kind]: scree first, then rain, when it is both. Each
  /// answers a new field and leaves the one it was given alone.
  Heightfield _erode(Heightfield field) => switch (kind) {
    0 => erodeThermally(field, talus: 0.7, passes: 60),
    1 => erodeHydraulically(field, seed: seed, droplets: droplets.round()),
    _ => erodeHydraulically(
      erodeThermally(field, talus: 0.7, passes: 60),
      seed: seed,
      droplets: droplets.round(),
    ),
  };
  // #endregion erode

  @override
  Scene build(DemoContext context) {
    _context = context;
    _before = _hill();
    _after = _erode(_before);
    _left = MeshNode(
      DeviceMesh.upload(context.device, _meshOf(_before)),
      RenderMaterial(
        name: 'before',
        baseColor: LinearColor.fromSrgb(0.55, 0.5, 0.42, 1.0),
      ),
      name: 'before',
    )..setPosition(-_apart / 2, 0.0, 0.0);
    _right = MeshNode(
      DeviceMesh.upload(context.device, _meshOf(_after)),
      RenderMaterial(
        name: 'after',
        baseColor: LinearColor.fromSrgb(0.45, 0.55, 0.38, 1.0),
      ),
      name: 'after',
    )..setPosition(_apart / 2, 0.0, 0.0);
    return Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(_left)
      ..add(_right)
      ..add(
        // Low, so the gullies throw shadows of their own.
        LightNode(name: 'sun', intensity: 2.8 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.8, -0.5, -0.3)),
      );
  }

  void _again() {
    _after = _erode(_before);
    _right.mesh = DeviceMesh.upload(_context.device, _meshOf(_after));
  }

  /// The field as triangles, two a cell, each vertex with the field's own
  /// normal there.
  static MeshData _meshOf(Heightfield field) {
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    final Vector3 normal = Vector3.zero();
    for (var z = 0; z < field.rows; z++) {
      for (var x = 0; x < field.columns; x++) {
        final double wx = field.origin.x + x * field.cellSize;
        final double wz = field.origin.z + z * field.cellSize;
        field.normalAt(wx, wz, normal);
        builder.addVertex(
          position: Vector3(wx, field.sample(x, z), wz),
          normal: normal.clone(),
        );
      }
    }
    for (var z = 0; z + 1 < field.rows; z++) {
      for (var x = 0; x + 1 < field.columns; x++) {
        final int a = z * field.columns + x;
        final int b = a + 1;
        final int c = a + field.columns;
        final int d = c + 1;
        builder
          ..addTriangle(a, c, b)
          ..addTriangle(b, c, d);
      }
    }
    return builder.build();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Erosion',
      options: const <String>['Thermal', 'Hydraulic', 'Both'],
      index: () => kind,
      onChanged: (int i) {
        kind = i;
        _again();
      },
    ),
    SliderControl(
      'Droplets',
      min: 500,
      max: 8000,
      divisions: 15,
      value: () => droplets,
      onChanged: (double v) {
        droplets = v;
        _again();
      },
      format: (double v) => v.round().toString(),
    ),
    SliderControl(
      'Seed',
      min: 1,
      max: 20,
      divisions: 19,
      value: () => seed.toDouble(),
      onChanged: (double v) {
        seed = v.round();
        _again();
      },
      format: (double v) => v.round().toString(),
    ),
  ];

  // #region measure
  /// Every sample added up: the ground's volume, in cubic metres here.
  static double _total(Heightfield f) =>
      f.copyOfSamples().fold(0.0, (double a, double b) => a + b);

  /// The volume of the samples at least [from] metres from the hill's top.
  static double _foot(Heightfield f, {double from = 12.0}) {
    var sum = 0.0;
    for (var z = 0; z < f.rows; z++) {
      for (var x = 0; x < f.columns; x++) {
        final double dx = x - 16.0, dz = z - 16.0;
        if (dx * dx + dz * dz >= from * from) sum += f.sample(x, z);
      }
    }
    return sum;
  }

  /// The highest sample.
  static double _peak(Heightfield f) => f.copyOfSamples().reduce(math.max);
  // #endregion measure

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Each kind on its own, and both: the top is lower, the foot is higher,
    // and none of the ground went anywhere.
    for (var k = 0; k < 3; k++) {
      kind = k;
      final Heightfield after = _erode(_before);
      final double was = _total(_before);
      final double drift = (_total(after) - was).abs();
      if (drift > was * 1e-4) {
        throw StateError('erosion $k lost ${drift.toStringAsFixed(3)} m³');
      }
      if (!(_peak(after) < _peak(_before))) {
        throw StateError('erosion $k left the top where it was');
      }
      if (!(_foot(after) > _foot(_before))) {
        throw StateError('erosion $k put nothing down at the foot');
      }
    }
    // #endregion check
    kind = 2;
    if (frame.drawCalls < 2) throw StateError('the two hills were not drawn');
  }
}

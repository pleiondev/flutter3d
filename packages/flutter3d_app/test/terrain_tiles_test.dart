/// A heightfield drawn as tiles — `gfx-87n`, one test per clause of the row.
///
///     flutter test test/terrain_tiles_test.dart
///
/// **A crack is measured as sky enclosed by ground.** The clear is red and the
/// ground white; a red pixel with ground both above and below it in the same
/// column is the sky showing *through* the terrain rather than over it, which
/// is what a crack is. The measure is checked three ways before it is trusted:
/// a field at one level everywhere has none, the same seam without skirts has
/// some, and with skirts it has none again. The middle one is what makes the
/// other two mean anything.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

/// Ground that ripples along Z fast enough that a coarse edge — a straight
/// line through every fourth sample — misses it by most of a metre.
Heightfield _rippled() {
  const side = 33;
  final heights = Float32List(side * side);
  for (var r = 0; r < side; r++) {
    for (var c = 0; c < side; c++) {
      heights[r * side + c] = 0.9 * math.sin(r * 1.4) + 0.2 * math.sin(c * 0.3);
    }
  }
  return Heightfield(
    columns: side,
    rows: side,
    cellSize: 1.0,
    heights: heights,
  );
}

CpuDevice _device() => CpuDevice(
  width: _width,
  height: _height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<Uint8List> _draw(
  CpuDevice device,
  List<SceneNode> nodes, {
  required Vector3 eye,
  required Vector3 target,
  ShaderLibrary? materials,
}) async {
  final renderer = Renderer.create(device: device, materials: materials);
  final scene = Scene();
  for (final node in nodes) {
    scene.add(node);
  }
  final camera = CameraNode()
    ..setPosition(eye.x, eye.y, eye.z)
    ..lookAt(target);
  scene.add(camera);
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(1, 0, 0, 1)),
    ],
    settings: const RenderSettings(),
  );
  final pixels = await device.readPixels(frame.frame);
  return pixels!.buffer.asUint8List();
}

bool _sky(Uint8List p, int x, int y) {
  final i = (y * _width + x) * 4;
  return p[i] > 150 && p[i + 1] < 90 && p[i + 2] < 90;
}

/// Red pixels with ground somewhere above them and somewhere below.
int _enclosedSky(Uint8List p) {
  var count = 0;
  for (var x = 0; x < _width; x++) {
    var groundAbove = false;
    var pending = 0;
    for (var y = 0; y < _height; y++) {
      if (_sky(p, x, y)) {
        if (groundAbove) pending++;
      } else {
        // Ground below the sky run just counted: that run was enclosed.
        count += pending;
        pending = 0;
        groundAbove = true;
      }
    }
  }
  return count;
}

/// The two tiles either side of the seam at x = 16, at the levels given.
List<SceneNode> _seam(
  CpuDevice device,
  HeightfieldTiles tiles, {
  required int left,
  required int right,
  required bool skirts,
}) {
  final white = Material(
    lighting: LightingModel.unlit,
    baseColor: Vector4(1, 1, 1, 1),
  );
  MeshNode tile(int x, int z, int level) => MeshNode(
    DeviceMesh.upload(
      device,
      meshDataOf(
        tiles.build(x, z, level: level, material: 'ground', skirts: skirts),
      ),
    ),
    white,
  );
  return <SceneNode>[
    for (var z = 0; z < 2; z++) ...<SceneNode>[
      tile(0, z, left),
      tile(1, z, right),
    ],
  ];
}

void main() {
  // Looking along +X across the seam, from the low side and down at it, which
  // is the angle a crack under a raised edge shows from.
  final eye = Vector3(8, 4, 16);
  final target = Vector3(24, -1, 16);
  final tiles = HeightfieldTiles(_rippled(), tileCells: 16, levels: 3);

  test('the measure finds no crack where there is no seam', () async {
    final device = _device();
    final frame = await _draw(
      device,
      _seam(device, tiles, left: 0, right: 0, skirts: false),
      eye: eye,
      target: target,
    );
    expect(_enclosedSky(frame), 0);
  });

  test('two levels without skirts open a crack the measure sees', () async {
    final device = _device();
    final frame = await _draw(
      device,
      _seam(device, tiles, left: 0, right: 2, skirts: false),
      eye: eye,
      target: target,
    );
    expect(
      _enclosedSky(frame),
      greaterThan(0),
      reason:
          'the seam does not crack from here, so the next test proves '
          'nothing',
    );
  });

  test('with skirts, the same seam has no crack', () async {
    final device = _device();
    final frame = await _draw(
      device,
      _seam(device, tiles, left: 0, right: 2, skirts: true),
      eye: eye,
      target: target,
    );
    expect(_enclosedSky(frame), 0);
  });

  test('a tile\'s level follows the camera, and returns without uploading', () {
    final terrain = TerrainTiles(
      device: _device(),
      tiles: tiles,
      material: Material(lighting: LightingModel.unlit),
      chooser: const TileLevelChooser(nearest: 10, levels: 3),
    );
    expect(terrain.nodes, hasLength(4));

    // Standing over tile (0, 0): it draws finest, the diagonal tile coarsest.
    terrain.update(Vector3(4, 2, 4));
    expect(terrain.levelOf(0, 0), 0);
    expect(terrain.levelOf(1, 1), 1);

    // Walk to the far corner and back, twice. Levels swap, and the second
    // round uploads nothing the first did not.
    terrain
      ..update(Vector3(60, 2, 60))
      ..update(Vector3(4, 2, 4));
    final afterFirstRound = terrain.uploads;
    terrain
      ..update(Vector3(60, 2, 60))
      ..update(Vector3(4, 2, 4));
    expect(terrain.uploads, afterFirstRound);
    expect(terrain.levelOf(0, 0), 0);
  });

  test('height and cover reach a material written in source', () async {
    // No shader written for this terrain: a material in the language reads
    // `world.y` for the height bands and samples the base colour slot as a
    // cover map, and the software backend draws it through the same stage
    // any language material goes through.
    const source = '''
material Ground {
  texture cover = base_color_texture;
  fragment {
    let high = smoothstep(-0.5, 0.5, world.y);
    let band = mix(vec3(0.1, 0.4, 0.1), vec3(1.0, 1.0, 1.0), high);
    return vec4(band * sample(cover, uv).rgb, 1.0);
  }
}
''';
    final program = specialiseMaterial(
      parseMaterial(source),
      const MaterialVariant('Ground'),
    );

    // Low on the left half, high on the right, so height is one clean edge.
    const side = 33;
    final heights = Float32List(side * side);
    for (var r = 0; r < side; r++) {
      for (var c = 0; c < side; c++) {
        heights[r * side + c] = c < 16 ? -1.0 : 1.0;
      }
    }
    final field = Heightfield(
      columns: side,
      rows: side,
      cellSize: 1.0,
      heights: heights,
    );

    final device = _device();
    // A cover that is white everywhere but a blue near edge, spread once over
    // the whole field by setting a texture's worth of metres to its width.
    final cover = device.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[
          80, 80, 255, 255, 80, 80, 255, 255, //
          255, 255, 255, 255, 255, 255, 255, 255,
        ]),
      ),
    );
    final terrain = TerrainTiles(
      device: device,
      tiles: HeightfieldTiles(field, tileCells: 16, levels: 2),
      material: Material(
        lighting: const LightingModel('Ground', 'Ground'),
        albedo: cover,
      ),
      chooser: const TileLevelChooser(nearest: 100, levels: 2),
      metresPerTexture: 32,
    )..update(Vector3(16, 40, 16));

    final frame = await _draw(
      device,
      terrain.nodes,
      eye: Vector3(16, 40, 16.01),
      target: Vector3(16, 0, 16),
      materials: CpuShaderLibrary(<String, CpuStage>{
        'Ground': CpuStage.fragment(MaterialProgramStage(program)),
      }),
    );

    (int, int, int) at(int x, int y) {
      final i = (y * _width + x) * 4;
      return (frame[i], frame[i + 1], frame[i + 2]);
    }

    // Straight down: the low half on one side of the frame, the high half on
    // the other. Which side is which depends on the camera's handedness, so
    // the test asks for a difference between the two rather than a direction.
    final (lr, lg, lb) = at(_width ~/ 4, _height * 3 ~/ 4);
    final (hr, hg, hb) = at(_width * 3 ~/ 4, _height * 3 ~/ 4);
    final low = lr + lg + lb;
    final high = hr + hg + hb;
    expect(
      (low - high).abs(),
      greaterThan(150),
      reason: 'height did not reach the material: $low against $high',
    );
    // And the cover: its blue edge is blue on screen, over whichever half of
    // the ground it lies on.
    var blue = 0;
    for (var i = 0; i < frame.length; i += 4) {
      if (frame[i + 2] > frame[i] + 60 && frame[i + 2] > frame[i + 1] + 60) {
        blue++;
      }
    }
    expect(blue, greaterThan(100), reason: 'the cover map did not reach it');
  });
}

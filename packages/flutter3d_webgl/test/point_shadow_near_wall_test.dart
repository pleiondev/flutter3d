/// A point light close to the wall it lights, drawn through this backend.
///
///     flutter test --platform chrome test/point_shadow_near_wall_test.dart
///
/// **Every cube-shadow scene in the golden set puts its light in open space**,
/// a metre or more from anything, where one face of the cube map covers
/// everything the light reaches. A torch does not: it hangs a third of a metre
/// off a wall, so the wall runs out of that face within a metre of the flame
/// and continues into the four faces around it. That is the case nothing
/// covered, and it is the case a dungeon is built out of.
///
/// The software backend draws this scene with no shadowing at all — the wall is
/// the only surface, and a surface does not shadow itself — so a straight edge
/// across it is this backend disagreeing with the one that has no driver in it.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 192;
const int _height = 96;

/// How far the flame hangs off the wall. The crypt's own number.
const double _standoff = 0.35;

void main() {
  test('a wall lit by a torch has no straight edge across it', () async {
    final device = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');

    TextureHandle texel(List<int> rgba) {
      final made = device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      );
      if (made == null) fail('the device would not make a 1x1 texture');
      return made;
    }

    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    final scene = Scene();

    // A corridor rather than a single wall, because a single wall is the case
    // that already works: the crypt's rooms have a floor, a ceiling and a wall
    // behind the camera, and every one of them lands in a *different* face of
    // the same cube map. That is what a torch's light meets and what no golden
    // scene has ever contained.
    final stone = Material(
      name: 'stone',
      baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
      roughness: 0.9,
    );
    void box(Vector3 size, Vector3 at, String name) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape(size: size).build()),
          stone,
          name: name,
        )..setPositionFrom(at),
      );
    }

    box(Vector3(8.0, 4.0, 0.4), Vector3(0.0, 0.0, -0.2), 'wall');
    box(Vector3(8.0, 0.4, 12.0), Vector3(0.0, -2.2, 6.0), 'floor');
    box(Vector3(8.0, 0.4, 12.0), Vector3(0.0, 2.2, 6.0), 'ceiling');
    box(Vector3(0.4, 4.0, 12.0), Vector3(-4.2, 0.0, 6.0), 'left');
    box(Vector3(0.4, 4.0, 12.0), Vector3(4.2, 0.0, 6.0), 'right');

    // Six torches for four atlas rows, which is the crypt's own arithmetic.
    for (var i = 0; i < 6; i++) {
      scene.add(
        LightNode(
          type: LightType.point,
          color: Vector3(1.0, 1.0, 1.0),
          intensity: i == 0 ? 6.0 : 2.0,
          range: 13.0,
          castsShadow: true,
          name: 'torch$i',
        )..setPosition(
          i == 0 ? 0.0 : (i.isEven ? -3.6 : 3.6),
          i == 0 ? 0.0 : 1.4,
          i == 0 ? _standoff : 2.0 + i.toDouble(),
        ),
      );
    }

    final camera = CameraNode(
      projection: const PerspectiveProjection(fovYRadians: 1.0),
    )..setPosition(0.0, 0.0, 6.0);
    scene.add(camera);

    // Three frames before the one that is read: the static atlas is baked on
    // the way through the first, and a frame read too early is a frame drawn
    // before its own shadows.
    late Uint8List pixels;
    for (var i = 0; i < 4; i++) {
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[
          RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      final read = await device.readPixels(result.frame);
      pixels = read!.buffer.asUint8List();
    }

    // The row through the flame, in the middle of the wall.
    final row = <double>[
      for (var x = 0; x < _width; x++)
        () {
          final at = ((_height ~/ 2) * _width + x) * 4;
          return (0.2126 * pixels[at] +
                  0.7152 * pixels[at + 1] +
                  0.0722 * pixels[at + 2]) /
              255.0;
        }(),
    ];

    // Only the columns that are wall: the frame is wider than the eight metres
    // of it, and the silhouette against the clear colour is a legitimate cliff.
    var worst = 0.0;
    var at = 0;
    for (var i = 0; i < row.length - 1; i++) {
      // Both sides have to be wall: the wall ends before the frame does, and
      // its silhouette against the clear colour is a hundred-percent fall that
      // means nothing.
      if (row[i] < 0.05 || row[i + 1] < 0.05) continue;
      final brighter = row[i] > row[i + 1] ? row[i] : row[i + 1];
      final step = (row[i] - row[i + 1]).abs() / brighter;
      if (step > worst) {
        worst = step;
        at = i;
      }
    }

    expect(
      worst,
      lessThan(0.35),
      reason:
          'brightness falls by ${(worst * 100).toStringAsFixed(0)}% between '
          'columns $at and ${at + 1} on a flat wall, where the distance to the '
          'light barely changes — that is a cube-face boundary, not a falloff. '
          'Row: ${row.map((double v) => (v * 99).round()).toList()}',
    );

    device.dispose();
  });
}

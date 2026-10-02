/// An orthographic camera through the effects that used to assume the rays
/// meet at the eye — `P7`.
///
///     dart test test/orthographic_test.dart
///
/// Through an orthographic lens the rays are parallel, and the eye's position
/// along the axis is only where the camera was put: moving it changes nothing
/// in the picture. Each test here holds one thing that read that position as a
/// point the light travels to — a highlight, the fog, the sky — to the
/// parallel rays instead.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// A wall facing the camera and filling the frame, of [material], seen from
/// [distance] metres through [projection], with one light from the front
/// and above.
Float32List _render(
  Projection projection, {
  double distance = 4.0,
  RenderSettings settings = const RenderSettings(
    bloom: BloomSettings(enabled: false),
    look: LookSettings(dither: 0.0),
  ),
  Material? material,
  bool wall = true,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();
  if (wall) {
    scene.add(
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          material ??
              Material(
                baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
                roughness: 0.2,
                metallic: 1.0,
              ),
        )
        ..setPosition(0.0, 0.0, -distance)
        ..setScale(40.0, 40.0, 0.1),
    );
  }
  scene.add(
    LightNode(intensity: 3.0)..lookAt(Vector3(0.0, -0.3, -1.0).normalized()),
  );
  final camera = CameraNode(projection: projection);
  scene.add(camera);
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  return Float32List.fromList(device.readHdrPixels(result.frame));
}

Vector3 _at(Float32List frame, int x, int y) {
  final i = (y * _width + x) * 4;
  return Vector3(frame[i], frame[i + 1], frame[i + 2]);
}

/// How far apart the brightest and darkest of five points across the frame
/// are, in the red channel.
double _spread(Float32List frame) {
  final reds = <double>[
    for (final (x, y) in <(int, int)>[
      (_width ~/ 2, _height ~/ 2),
      (4, 4),
      (_width - 5, 4),
      (4, _height - 5),
      (_width - 5, _height - 5),
    ])
      _at(frame, x, y).x,
  ];
  return reds.reduce((a, b) => a > b ? a : b) -
      reds.reduce((a, b) => a < b ? a : b);
}

const OrthographicProjection _ortho = OrthographicProjection(height: 6.0);
const PerspectiveProjection _perspective = PerspectiveProjection(
  fovYRadians: 1.2,
);

void main() {
  test('an orthographic matrix is told from a perspective one', () {
    // Mutation: test the bottom row's last entry alone, and a perspective
    // matrix that happens to keep one there reads as orthographic.
    final view = Matrix4.identity()..setTranslationRaw(0.0, -1.0, -5.0);
    for (final range in DepthRange.values) {
      expect(
        isOrthographic(
          toDepthRange(_ortho.toMatrix(1.5), range) * view as Matrix4,
        ),
        isTrue,
      );
      expect(
        isOrthographic(
          toDepthRange(_perspective.toMatrix(1.5), range) * view as Matrix4,
        ),
        isFalse,
      );
    }
  });

  test('a highlight does not slide across a flat wall', () {
    // Mutation: read `FragInfo.camera_position` for the view direction in
    // `readSurface`, and the metal wall brightens towards wherever the eye's
    // point projects — the very slide a pan would show.
    expect(_spread(_render(_ortho)), lessThan(0.02));
    // The same wall through a perspective lens does vary: the test can see a
    // slide when there is one.
    expect(_spread(_render(_perspective)), greaterThan(0.05));
  });

  test('where the camera stands along its axis changes nothing lit', () {
    // Mutation: as above — a view direction from the eye's point moves with
    // the eye, and a highlight with it.
    final near = _render(_ortho, distance: 3.0);
    final far = _render(_ortho, distance: 12.0);
    for (final (x, y) in <(int, int)>[(8, 8), (_width - 9, _height - 9)]) {
      final a = _at(near, x, y);
      final b = _at(far, x, y);
      expect((a - b).length, lessThan(0.01), reason: 'at ($x, $y)');
    }
  });

  test('fog lies flat on a wall the camera faces', () {
    // Mutation: keep the radial `EyeDistance` through an orthographic lens,
    // and the fog rings round the middle of the frame.
    final fogged = _render(
      _ortho,
      distance: 20.0,
      material: Material(
        lighting: LightingModel.unlit,
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      ),
      settings: RenderSettings(
        bloom: const BloomSettings(enabled: false),
        look: const LookSettings(dither: 0.0),
        fog: FogSettings(color: Vector3.zero(), density: 0.05),
      ),
    );
    expect(_spread(fogged), lessThan(0.01));
  });

  test('the sky is a gradient, not one colour', () {
    // Mutation: hand the sky the orthographic matrix's own corner rays, which
    // are all the view axis, and the frame is a single colour.
    final sky = _render(
      _ortho,
      wall: false,
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        look: LookSettings(dither: 0.0),
        sky: SkySettings(enabled: true),
      ),
    );
    final top = _at(sky, _width ~/ 2, 1);
    final bottom = _at(sky, _width ~/ 2, _height - 2);
    expect((top - bottom).length, greaterThan(0.05));
  });
}

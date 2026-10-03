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

import 'dart:math' as math;
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

/// An isometric board, the way a strategy game looks at one: a floor sixty
/// metres on a side with a post at each of [posts], the sun low across it,
/// and the camera [back] metres up its axis from the board's middle, looking
/// down at thirty-five degrees through a box [height] metres tall.
///
/// Returns the renderer after one frame with three cascades, and the camera.
({Renderer renderer, CameraNode camera, Scene scene}) _board({
  List<Vector3> posts = const <Vector3>[],
  double back = 80.0,
  double height = 20.0,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene();
  MeshNode block(Vector3 size, Vector3 at) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
  )..setPosition(at.x, at.y, at.z);
  scene.add(block(Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0)));
  for (final post in posts) {
    scene.add(block(Vector3(0.6, 3.0, 0.6), post + Vector3(0.0, 1.5, 0.0)));
  }
  scene.add(
    LightNode(type: LightType.directional, intensity: 2.0, castsShadow: true)
      ..setLocalForward(Vector3(-0.4, -0.8, 0.3)),
  );
  final pitch = 35.0 * math.pi / 180.0;
  final axis = Vector3(0.0, -math.sin(pitch), -math.cos(pitch));
  final camera = CameraNode(projection: OrthographicProjection(height: height))
    ..setPosition(-axis.x * back, -axis.y * back, -axis.z * back)
    ..lookAt(Vector3.zero());
  scene.add(camera);
  final renderer = Renderer.create(device: device)
    ..render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(cascades: 3),
      ),
    );
  return (renderer: renderer, camera: camera, scene: scene);
}

/// Which cascade the shading reads at [point] and how wide it is: the first
/// whose split [point]'s distance from the eye has not passed and whose
/// sphere holds it, which is the fall-through `shadow.glsl` makes.
({int index, double radius}) _cascadeAt(
  Renderer renderer,
  CameraNode camera,
  Vector3 point,
) {
  final radii = renderer.debugCascadeRadii;
  final centres = renderer.debugCascadeCentres;
  final splits = renderer.debugCascadeSplits;
  final distance = (point - camera.readWorldPosition()).length;
  var index = 0;
  if (radii.length > 1 && distance > splits[0]) index = 1;
  if (radii.length > 2 && distance > splits[1]) index = 2;
  while (index < radii.length - 1 &&
      (point - centres[index]).length > radii[index]) {
    index++;
  }
  return (index: index, radius: radii[index]);
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

  test('the first cascade ends inside the box, not in the air before it', () {
    // Mutation: drop the orthographic branch in `_renderShadowMap`, and the
    // split is perspective's — about nine metres from an eye eighty metres
    // short of the board, in front of everything the box holds.
    final board = _board();
    final eye = board.camera.readWorldPosition();
    final forward = board.camera.readForward();
    // The nearest and farthest of the floor the camera sees, along its axis.
    final bounds = board.scene.computeBounds(castersOnly: true);
    final depths = <double>[
      for (var i = 0; i < 8; i++)
        (Vector3(
                  i & 1 == 0 ? bounds.min.x : bounds.max.x,
                  i & 2 == 0 ? bounds.min.y : bounds.max.y,
                  i & 4 == 0 ? bounds.min.z : bounds.max.z,
                ) -
                eye)
            .dot(forward),
    ];
    final nearest = depths.reduce(math.min);
    final split = board.renderer.debugCascadeSplits.first;
    expect(split, greaterThan(nearest));
    expect(split, lessThan(depths.reduce(math.max)));
    // And the box, not the whole floor: the floor reaches forty metres
    // either side of the board's middle along the axis, and the box sees
    // about twenty of them.
    expect(split, lessThan(80.0 + 5.0));
  });

  test('near and far casters get the same texel', () {
    // Mutation: as above, and both posts fall through to the last cascade,
    // the whole sixty-metre floor; or put the first split well short of the
    // box's middle, and both land in the second cascade.
    const nearPost = <double>[0.0, 0.0, 8.0];
    const farPost = <double>[0.0, 0.0, -8.0];
    final board = _board(
      posts: <Vector3>[Vector3.array(nearPost), Vector3.array(farPost)],
    );
    final near = _cascadeAt(
      board.renderer,
      board.camera,
      Vector3.array(nearPost),
    );
    final far = _cascadeAt(
      board.renderer,
      board.camera,
      Vector3.array(farPost),
    );
    final whole = board.renderer.debugCascadeRadii.last;
    expect(near.index, lessThan(2), reason: 'the near post in the last');
    expect(far.index, lessThan(2), reason: 'the far post in the last');
    expect(near.index, lessThan(far.index));
    expect(near.radius, lessThan(whole * 0.7));
    expect(far.radius, lessThan(whole * 0.7));
    final ratio =
        math.max(near.radius, far.radius) / math.min(near.radius, far.radius);
    expect(ratio, lessThan(1.5));
  });

  test('where the camera stands along its axis barely moves a cascade', () {
    // The eye's place along the axis changes nothing in the picture, so it
    // should not change which world a texel covers either. It does a little:
    // the shading picks a cascade by distance from the eye, which adds the
    // box's sideways reach to the depth, and an eye close to the board has
    // to fit the second cascade a little wider for it. One rounding step of
    // the radius, an eighth of an octave, and no more.
    final close = _board(back: 40.0).renderer;
    final distant = _board(back: 120.0).renderer;
    for (var i = 0; i < 2; i++) {
      final a = close.debugCascadeRadii[i];
      final b = distant.debugCascadeRadii[i];
      expect(math.max(a, b) / math.min(a, b), lessThan(1.1), reason: '$i');
    }
  });
}

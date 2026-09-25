/// Air with a thickness: it dims what is behind it by the path through it,
/// keeps each edge's own depth when it is brought up from half resolution,
/// and glows around the torches the view's cells hold — `S4`.
///
///     dart test test/volumetric_fog_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A green unlit wall twenty metres off, authored as [wall], with a red
/// unlit card authored as [card] two metres off in front of it, seen head on
/// through [fog].
///
/// The air is given a black albedo, so it scatters none of the default sun a
/// scene without lights is handed and only takes away. The frame is compared
/// as it comes out, display encoding and all: each test sets up the frame it
/// expects through the same pipeline rather than inverting that pipeline.
Float32List _cardAndWall(
  VolumetricFogSettings fog, {
  double wall = 1.0,
  double card = 1.0,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(60, 60, 0.1)).build(),
        ),
        Material(
          lighting: LightingModel.unlit,
          baseColor: Vector4(0.0, wall, 0.0, 1.0),
        ),
      )..setPosition(0.0, 0.0, -20.0),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(0.5, 0.5, 0.05)).build(),
        ),
        Material(
          lighting: LightingModel.unlit,
          baseColor: Vector4(card, 0.0, 0.0, 1.0),
        ),
      )..setPosition(0.1, 0.05, -2.0),
    )
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      volumetricFog: fog.copyWith(color: Vector3.zero()),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The sRGB encode: what a material colour is authored in, so a wall
/// authored as `_encode(t)` shows linear light `t`.
double _encode(double x) => x <= 0.0031308
    ? x * 12.92
    : 1.055 * math.pow(x, 1.0 / 2.4).toDouble() - 0.055;

const int _torchWidth = 96;
const int _torchHeight = 64;

/// `L6`'s floor under sixty-four small lights, in fog of [albedo], the last
/// of eight frames of one renderer.
Float32List _fogTorches({required bool clustered, required double albedo}) {
  final device = CpuDevice(
    width: _torchWidth,
    height: _torchHeight,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 9.0, 4.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(lighting: LightingModel.lambert),
        )
        ..setPosition(0.0, -0.05, 0.0)
        ..setScale(12.0, 0.1, 12.0),
    )
    ..add(camera);
  for (var i = 0; i < 8; i++) {
    for (var j = 0; j < 8; j++) {
      scene.add(
        LightNode(type: LightType.point, intensity: 2.0, range: 1.5)
          ..setPosition(i - 3.5, 0.3, j - 3.5),
      );
    }
  }
  final renderer = Renderer.create(device: device);
  final settings = RenderSettings(
    tonemap: false,
    bloom: const BloomSettings(enabled: false),
    clusteredLights: clustered,
    volumetricFog: const VolumetricFogSettings(
      enabled: true,
      density: 0.3,
      heightFalloff: 1.0,
      steps: 16,
      distance: 20.0,
    ).copyWith(color: Vector3.all(albedo)),
  );
  FrameResult render() => renderer.render(
    width: _torchWidth,
    height: _torchHeight,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
  );
  for (var i = 0; i < 7; i++) {
    render();
  }
  return device.readHdrPixels(render().frame);
}

/// A torch three metres behind a black wall three metres ahead of the eye, seen
/// through air of [albedo], its shadow cast when [castsShadow]. Eight more
/// lights far off to the side overflow the slots, so the cells are cut and
/// the air reads the torch from them. The last of four frames.
Float32List _torchBehindWall({
  required bool castsShadow,
  required double albedo,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(40, 40, 0.2)).build(),
        ),
        Material(
          lighting: LightingModel.lambert,
          baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        ),
      )..setPosition(0.0, 0.0, -3.0),
    )
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 20.0,
        range: 8.0,
        castsShadow: castsShadow,
      )..setPosition(0.0, 0.0, -6.0),
    )
    ..add(camera);
  for (var i = 0; i < 8; i++) {
    scene.add(
      LightNode(type: LightType.point, intensity: 0.5, range: 0.5)
        ..setPosition(30.0 + i, 0.0, -10.0),
    );
  }
  final renderer = Renderer.create(device: device);
  final settings = RenderSettings(
    tonemap: false,
    bloom: const BloomSettings(enabled: false),
    clusteredLights: true,
    volumetricFog: const VolumetricFogSettings(
      enabled: true,
      density: 0.2,
      heightFalloff: 0.0,
      steps: 16,
      distance: 20.0,
    ).copyWith(color: Vector3.all(albedo)),
  );
  FrameResult render() => renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
  );
  for (var i = 0; i < 3; i++) {
    render();
  }
  return device.readHdrPixels(render().frame);
}

const int _creaseWidth = 64;
const int _creaseHeight = 48;

/// A floor with a wall across the back of it, the crease between them
/// occluded by [occlusion] when it is on, seen through [fog] that glows
/// with a uniform ambient in-scatter.
Float32List _crease(VolumetricFogSettings fog, {required bool occlusion}) {
  final device = CpuDevice(
    width: _creaseWidth,
    height: _creaseHeight,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final cube = DeviceMesh.upload(device, CuboidShape().build());
  MeshNode slab(Vector3 at, Vector3 scale) => MeshNode(cube, Material())
    ..setPosition(at.x, at.y, at.z)
    ..setScale(scale.x, scale.y, scale.z);
  final camera = CameraNode()
    ..setPosition(0.0, 2.5, 3.0)
    ..lookAt(Vector3(0.0, 0.0, -0.5));
  final scene = Scene()
    ..add(slab(Vector3(0.0, -0.05, 0.0), Vector3(8.0, 0.1, 8.0)))
    ..add(slab(Vector3(0.0, 1.0, -1.0), Vector3(8.0, 2.0, 0.2)))
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _creaseWidth,
    height: _creaseHeight,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      ambientOcclusion: AmbientOcclusionSettings(
        enabled: occlusion,
        radius: 0.6,
      ),
      volumetricFog: fog.copyWith(
        color: Vector3.all(1.0),
        ambient: Vector3.all(0.5),
      ),
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// The largest difference between two frames, channel by channel.
double _largestDifference(Float32List a, Float32List b) {
  var largest = 0.0;
  for (var i = 0; i < a.length; i++) {
    largest = math.max(largest, (a[i] - b[i]).abs());
  }
  return largest;
}

double _sum(Float32List frame) {
  var total = 0.0;
  for (var i = 0; i < frame.length; i += 4) {
    total += frame[i] + frame[i + 1] + frame[i + 2];
  }
  return total;
}

void main() {
  test('off by default, and air with no density is no pass at all', () {
    expect(const VolumetricFogSettings().enabled, isFalse);
    expect(const RenderSettings().volumetricFog.enabled, isFalse);
    expect(RenderSettings.passOrder, contains('volumetric fog'));
    final off = _cardAndWall(const VolumetricFogSettings());
    final empty = _cardAndWall(
      const VolumetricFogSettings(enabled: true, density: 0.0),
    );
    expect(empty, off);
  });

  test('the far wall keeps e^(−σd) of itself through uniform air', () {
    final fogged = _cardAndWall(
      const VolumetricFogSettings(enabled: true, density: 0.05, distance: 60),
    );
    // Wall pixels clear of the card, near the corner and off the axis: to
    // the wall's front face, 19.95 metres down the axis, over the cosine.
    for (final (x, y) in const <(int, int)>[(4, 4), (16, 16), (60, 8)]) {
      final share = math.exp(-0.05 * _rayLength(19.95, x, y));
      // The same wall with that share of its light authored in, unfogged.
      final expected = _cardAndWall(
        const VolumetricFogSettings(),
        wall: _encode(share),
      );
      final at = (y * _size + x) * 4 + 1;
      // The strides add to the distance exactly, whatever the offset, so the
      // wall keeps the analytic share. Mutation: pre-attenuate by the
      // offset as the shafts' march does, and it keeps a stride's less.
      expect(fogged[at], closeTo(expected[at], 2e-3), reason: '($x, $y)');
    }
  });

  test('thin air above its base height lets the wall through', () {
    final clear = _cardAndWall(const VolumetricFogSettings());
    final thin = _cardAndWall(
      const VolumetricFogSettings(
        enabled: true,
        density: 0.05,
        distance: 60,
        heightFalloff: 2.0,
        baseHeight: -6.0,
      ),
    );
    const at = (4 * _size + 4) * 4 + 1;
    // At the eye's height the air is e^(−12) of its base density.
    expect(thin[at] / clear[at], greaterThan(0.99));
  });

  test('the half-resolution fog keeps the card\'s edge where it is', () {
    const sigma = 0.1;
    final clear = _cardAndWall(const VolumetricFogSettings());
    final fogged = _cardAndWall(
      const VolumetricFogSettings(enabled: true, density: sigma, distance: 60),
    );
    // Two metres of air keep e^(−0.2) ≈ 0.82 of the card, and a card
    // authored at a little less than that is what its every pixel has to
    // stay above. A plain bilinear stretch hands the card's rim a share of
    // the wall's twenty metres, e^(−2) ≈ 0.14, and the rim drops far below.
    final floor = _cardAndWall(const VolumetricFogSettings(), wall: 0.0);
    final dimmed = _cardAndWall(
      const VolumetricFogSettings(),
      card: _encode(0.78),
    );
    var cardPixels = 0;
    var below = 0;
    for (var i = 0; i < _size * _size; i++) {
      if (clear[i * 4] < 0.5 || clear[i * 4 + 1] > 0.01) continue;
      // Card pixels only, where the card fills the pixel and not the wall.
      if (floor[i * 4] != clear[i * 4]) continue;
      cardPixels++;
      if (fogged[i * 4] < dimmed[i * 4]) below++;
    }
    expect(cardPixels, greaterThan(20));
    // Mutation: weigh the four texels by their bilinear share alone.
    expect(below, 0);
  });

  test('fog-torches: the air glows around the lights the cells hold', () {
    // The same fog twice, once scattering and once only absorbing: the
    // difference is the light the air sends to the eye and nothing else.
    final glowing = _fogTorches(clustered: true, albedo: 1.0);
    final absorbing = _fogTorches(clustered: true, albedo: 0.0);
    for (final value in glowing) {
      expect(value.isFinite, isTrue);
    }
    // Scattering only adds: no pixel is darker for the air having an albedo.
    for (var i = 0; i < glowing.length; i++) {
      expect(glowing[i], greaterThanOrEqualTo(absorbing[i] - 1e-6));
    }
    // A few percent of the frame, gathered in halos around the torches: the
    // air is thin a metre up and a torch reaches a metre and a half.
    // Mutation: leave `albedo.w` at nought and the two frames are the same.
    expect(_sum(glowing), greaterThan(_sum(absorbing) * 1.01));

    // Without the cells the air knows no torch at all: scattering or not,
    // it only dims the floor.
    expect(
      _fogTorches(clustered: false, albedo: 1.0),
      _fogTorches(clustered: false, albedo: 0.0),
    );
  });

  test('a torch behind a wall lights no air on this side of it', () {
    // What the air in front of the wall scatters of the torch: the frame
    // with an albedo, less the same frame only absorbing.
    double glow({required bool castsShadow}) =>
        _sum(_torchBehindWall(castsShadow: castsShadow, albedo: 1.0)) -
        _sum(_torchBehindWall(castsShadow: castsShadow, albedo: 0.0));
    final leaking = glow(castsShadow: false);
    final shadowed = glow(castsShadow: true);
    // Without its shadow the torch lights the air through the stone, a halo
    // on a wall that is black.
    expect(leaking, greaterThan(0.5));
    // With it every point between the eye and the wall is behind the wall
    // from the torch, all but the last few centimetres against its face,
    // which the depth bias leaves lit as it leaves the face itself. Mutation:
    // leave the atlas row out of the light's list row, and the two glows are
    // the same; start the march at the near plane again, and its last step
    // lands inside the stone, lit, and the glow is a quarter of the leak.
    expect(shadowed, lessThan(leaking * 0.2));
  });

  test('fog-crease: the occlusion darkens the wall and not the air', () {
    // Without fog the crease is plainly darker with the occlusion on: the
    // comparisons below are not of two frames that never differed.
    const clear = VolumetricFogSettings();
    expect(
      _largestDifference(
        _crease(clear, occlusion: true),
        _crease(clear, occlusion: false),
      ),
      greaterThan(0.05),
    );

    // Air so thick the wall keeps e^(−12) of itself: the picture is the
    // in-scatter and nothing else, and a crease behind it has nothing left
    // to darken. Mutation: leave the occlusion to the composite, which
    // multiplies it into the in-scatter too, and the crease is drawn on the
    // air as a dark line.
    const dense = VolumetricFogSettings(
      enabled: true,
      density: 3.0,
      steps: 32,
      distance: 20.0,
    );
    expect(
      _largestDifference(
        _crease(dense, occlusion: true),
        _crease(dense, occlusion: false),
      ),
      lessThan(2e-3),
    );

    // Thin air still shows the crease: the occlusion moved, it did not go.
    const thin = VolumetricFogSettings(
      enabled: true,
      density: 0.1,
      distance: 20.0,
    );
    expect(
      _largestDifference(
        _crease(thin, occlusion: true),
        _crease(thin, occlusion: false),
      ),
      greaterThan(0.02),
    );
  });
}

/// The length of the ray through pixel ([x], [y]) of the default camera to
/// the plane [depth] metres ahead: the depth over the cosine to the axis.
double _rayLength(double depth, int x, int y) {
  final camera = CameraNode();
  final inverse = Matrix4.copy(camera.viewProjection(1.0))..invert();
  final ndcX = (x + 0.5) / _size * 2.0 - 1.0;
  final ndcY = 1.0 - (y + 0.5) / _size * 2.0;
  final far = inverse.transformed(Vector4(ndcX, ndcY, 1.0, 1.0));
  final along = Vector3(far.x / far.w, far.y / far.w, far.z / far.w)
    ..normalize();
  return depth / along.dot(Vector3(0.0, 0.0, -1.0));
}

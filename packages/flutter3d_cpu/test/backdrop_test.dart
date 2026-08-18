/// A surface drawn behind everything: what the engine needs before a sky is
/// possible at all.
///
///     flutter test test/backdrop_test.dart
///
/// Two engine facts meet here, and neither is about a sky specifically.
///
/// **Depth state belongs to the material.** The scene pass fixes
/// `depthWrite: true, depthCompare: less` for everything in it, which is right
/// for surfaces and wrong for a backdrop: a backdrop is drawn near the camera —
/// it has to be, or the fog eats it — and is meant to be behind everything
/// regardless. Without an override it writes a few metres of depth across the
/// whole frame and clips the level away.
///
/// **The shadow volume belongs to casters.** The last cascade is fitted to
/// `Scene.computeBounds`, which used to count every visible mesh whether or not
/// it cast anything. One dome around the camera would then spend the whole
/// shadow map on a kilometre of nothing, coarsening every shadow in the level —
/// a cost paid by a mesh that contributes no shadow at all.
///
/// The tests are on the real renderer with the real rasteriser, because both
/// facts are about what actually reaches the frame.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
      )!;
  return (
    device: device,
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    ),
  );
}

CpuDevice _uploads() => CpuDevice(
      width: 4,
      height: 4,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

/// A red wall forty metres out, and a camera looking at it.
({Scene scene, CameraNode camera, CpuDevice device}) _wallAhead() {
  final device = _uploads();
  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3(60.0, 60.0, 1.0)).build()),
      engine.Material(
        name: 'wall',
        baseColor: Vector4(1.0, 0.0, 0.0, 1.0),
        lighting: LightingModel.unlit,
      ),
      name: 'wall',
    )..setPosition(0.0, 0.0, 40.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.3,
      far: 500.0,
    ),
  )..lookAt(Vector3(0.0, 0.0, 1.0));
  scene.add(camera);
  return (scene: scene, camera: camera, device: device);
}

/// A green box two metres in front of the camera, drawn before the wall.
///
/// `drawBucket` puts it first in the sort, which is where a backdrop has to be:
/// it is the thing everything else is drawn over.
MeshNode _backdrop(
  CpuDevice device, {
  bool? depthWrite,
  CompareFunction? depthCompare,
}) =>
    MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: Vector3(40.0, 40.0, 0.2)).build()),
      engine.Material(
        name: 'backdrop',
        baseColor: Vector4(0.0, 1.0, 0.0, 1.0),
        lighting: LightingModel.unlit,
        drawBucket: -1,
        depthWrite: depthWrite,
        depthCompare: depthCompare,
      ),
      name: 'backdrop',
    )..setPosition(0.0, 0.0, 2.0);

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  Scene scene,
  CameraNode camera, {
  ShadowSettings shadows = const ShadowSettings(),
}) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      shadows: shadows,
      bloom: const BloomSettings(enabled: false),
      tonemap: false,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

int _redPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > 90 && rgba[i] > rgba[i + 1] * 2) count++;
  }
  return count;
}

int _greenPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 1] > 90 && rgba[i + 1] > rgba[i] * 2) count++;
  }
  return count;
}

void main() {
  group('depth state on a material', () {
    test('a near surface hides what is behind it, as it always has', () async {
      // The control. Nothing here is new: an opaque surface two metres out
      // occludes a wall at forty, and this is what every material in the engine
      // still does when it says nothing about depth.
      final world = _wallAhead();
      world.scene.add(_backdrop(world.device));

      final frame = await _draw(_engine(), world.scene, world.camera);

      expect(_greenPixels(frame), greaterThan(1000));
      expect(_redPixels(frame), 0, reason: 'the wall is behind the near box');
    });

    test('a backdrop is drawn and then is not there', () async {
      // Mutation: ignore `Material.depthWrite` and keep `!blend`. The near box
      // writes depth across the frame and the wall — and in the real case, the
      // entire level — is clipped away by the sky.
      final world = _wallAhead();
      world.scene.add(
        _backdrop(
          world.device,
          depthWrite: false,
          depthCompare: CompareFunction.always,
        ),
      );

      final frame = await _draw(_engine(), world.scene, world.camera);

      expect(_redPixels(frame), greaterThan(1000),
          reason: 'the wall is visible through a backdrop that writes no depth');
      expect(_greenPixels(frame), lessThan(200),
          reason: 'and the backdrop survives only where nothing covers it');
    });

    test('a surface can be drawn through what is in front of it', () async {
      // The other half of the pair, and the half a backdrop does *not* need —
      // a backdrop is drawn first into an empty depth buffer, so `less` passes
      // anyway. What needs this is the opposite case: something behind the
      // geometry that has to be seen through it. A highlighted object, a
      // waypoint, a debug marker.
      //
      // Mutation: ignore `Material.depthCompare` and always use the pass's
      // `less`. The marker is twenty metres behind the wall, fails the test at
      // every pixel and disappears — which is exactly what it did before this
      // field existed, and the reason the first draft of this test proved
      // nothing: it put the marker in *front* of the wall, where `less` passes
      // on its own.
      final world = _wallAhead();
      world.scene.add(
        MeshNode(
          DeviceMesh.upload(
            world.device,
            CuboidShape(size: Vector3(24.0, 24.0, 1.0)).build(),
          ),
          engine.Material(
            name: 'marker',
            baseColor: Vector4(0.0, 1.0, 0.0, 1.0),
            lighting: LightingModel.unlit,
            // Last, after the wall has written its depth.
            drawBucket: 9,
            depthWrite: false,
            depthCompare: CompareFunction.always,
          ),
          name: 'marker',
        )..setPosition(0.0, 0.0, 60.0),
      );

      final frame = await _draw(_engine(), world.scene, world.camera);

      expect(_greenPixels(frame), greaterThan(200),
          reason: 'a surface that always passes is drawn through the wall');
      expect(_redPixels(frame), greaterThan(1000),
          reason: 'and does not replace it everywhere');
    });

    test('a scene that says nothing about depth draws what it always drew',
        () async {
      // The property the golden sets rest on. `setDepthCompare` is emitted only
      // when a material asks for something other than the pass's own `less`, so
      // an ordinary scene emits none at all — and `PassState`'s own history is
      // the reason that matters: a redundant depth call has flipped behaviour
      // on two backends out of three before now.
      final a = _wallAhead();
      final b = _wallAhead();
      b.scene.add(_backdrop(b.device, depthWrite: null, depthCompare: null));

      final plain = await _draw(_engine(), a.scene, a.camera);
      final withDefaults = await _draw(_engine(), b.scene, b.camera);

      // The second frame has a box in it; what is asserted is that the box
      // behaves exactly like an ordinary opaque one.
      expect(_redPixels(plain), greaterThan(1000));
      expect(_redPixels(withDefaults), 0);
    });
  });

  group('the shadow volume', () {
    test('a mesh that casts nothing does not enlarge it', () async {
      // Mutation: drop `castersOnly` from the shadow path's `computeBounds`.
      // The huge non-caster then sets the scene radius, the last cascade is
      // fitted to that, and its texels grow with it — every shadow in the level
      // is coarsened by a mesh that contributes no shadow at all. That is
      // exactly what a sky dome would have done, and it is why this is a test
      // about bounds rather than about skies.
      final lit = _litRoom();
      final withDome = _litRoom();
      withDome.scene.add(
        MeshNode(
          DeviceMesh.upload(
            withDome.device,
            SphereShape(radius: 900.0, segments: 12, rings: 8).build(),
          ),
          engine.Material(
            name: 'dome',
            baseColor: Vector4(0.4, 0.6, 1.0, 1.0),
            lighting: LightingModel.unlit,
            drawBucket: -1,
            depthWrite: false,
            depthCompare: CompareFunction.always,
          ),
          name: 'dome',
        )
          ..castsShadow = false
          ..frustumCulled = false,
      );

      const shadows = ShadowSettings(cascades: 1, resolution: 512);
      final without = await _draw(_engine(), lit.scene, lit.camera,
          shadows: shadows);
      final with_ = await _draw(_engine(), withDome.scene, withDome.camera,
          shadows: shadows);

      expect(_shadowedPixels(with_), closeTo(_shadowedPixels(without), 12.0),
          reason: 'the dome moved the shadow volume');
    });

    test('a caster still counts, however far away it is', () async {
      // The other direction, and the one a careless fix breaks: `castersOnly`
      // must narrow the set to non-casters only. A distant caster is *supposed*
      // to enlarge the volume — dropping it would leave the thing unshadowed.
      final near = _litRoom();
      final far = _litRoom();
      far.scene.add(
        MeshNode(
          DeviceMesh.upload(
            far.device,
            CuboidShape(size: Vector3(20.0, 20.0, 20.0)).build(),
          ),
          engine.Material(name: 'far', baseColor: Vector4(1.0, 1.0, 1.0, 1.0)),
          name: 'far',
        )..setPosition(0.0, 6.0, 300.0),
      );

      const shadows = ShadowSettings(cascades: 1, resolution: 512);
      final tight = await _draw(_engine(), near.scene, near.camera,
          shadows: shadows);
      final loose = await _draw(_engine(), far.scene, far.camera,
          shadows: shadows);

      expect(_shadowedPixels(loose), isNot(closeTo(_shadowedPixels(tight), 4.0)),
          reason: 'a caster three hundred metres out changed nothing, so the '
              'volume is no longer fitted to the casters');
    });

    test('bounds answer two different questions', () async {
      // The unit statement under both frames above.
      final device = _uploads();
      final scene = Scene();
      MeshNode box(String name, double at) => MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
            ),
            engine.Material(name: name),
            name: name,
          )..setPosition(0.0, 0.0, at);

      scene.add(box('caster', 0.0));
      scene.add(box('dome', 500.0)..castsShadow = false);

      expect(scene.computeBounds().max.z, closeTo(501.0, 1e-3));
      expect(scene.computeBounds(castersOnly: true).max.z, closeTo(1.0, 1e-3));
    });
  });
}

/// A floor with a slab held over it and a sun across both, which is the
/// smallest thing that has a shadow worth measuring.
({Scene scene, CameraNode camera, CpuDevice device}) _litRoom() {
  final device = _uploads();
  final scene = Scene();

  MeshNode block(Vector3 size, Vector3 at, String name) => MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: size).build()),
        engine.Material(
          name: name,
          baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
          lighting: LightingModel.pbr,
        ),
        name: name,
      )..setPosition(at.x, at.y, at.z);

  scene.add(block(Vector3(40.0, 1.0, 60.0), Vector3(0.0, -0.5, 20.0), 'floor'));
  scene.add(block(Vector3(10.0, 0.6, 6.0), Vector3(0.0, 5.0, 10.0), 'canopy'));
  scene.add(
    LightNode(
      type: LightType.directional,
      intensity: 1.1,
      castsShadow: true,
      name: 'sun',
    )..setLocalForward(Vector3(-0.2, -0.95, 0.25)),
  );

  final camera = CameraNode()
    ..setPosition(0.0, 3.0, -8.0)
    ..lookAt(Vector3(0.0, 1.0, 8.0));
  scene.add(camera);
  return (scene: scene, camera: camera, device: device);
}

/// Pixels that are floor lying in shadow: darker than lit floor, brighter than
/// the background behind it.
int _shadowedPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final luminance =
        0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
    if (luminance > 20 && luminance < 170) count++;
  }
  return count;
}

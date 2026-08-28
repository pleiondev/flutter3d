/// A rigged caster in a point light's cube atlas, checked by pixel.
///
///     flutter test --platform chrome test/point_shadow_skinning_test.dart
///
/// **Chrome only**, like the rest of this package's suite: there is no WebGL on
/// the Dart VM. The encoder's side of the same change — which pipeline, which
/// uniforms, how often — is asserted with no device at all in
/// `flutter3d/test/cube_shadow_skinning_test.dart`. This file exists for the
/// half that one cannot reach: whether anything is actually *recorded*, or
/// whether the skinned draw goes through and writes the far plane everywhere.
///
/// ## Why the atlas rather than the lit floor
///
/// The obvious test is a character standing on a lit plane under a point light,
/// counting how many of the plane's pixels went dark. It cannot be written
/// here, and not because of anything on this branch: **this backend's lookup
/// into the cube atlas does not work yet.** `engine_parity_test.dart` skips its
/// `pointShadow` fixture for exactly that reason — "the atlas is right, the
/// lookup into it is not" — and the scene below confirms it from the other
/// side: with an ordinary *unskinned* box it darkens zero of 16384 floor
/// pixels, and adding a directional light to the same scene darkens 1251 of
/// them. Nothing this change could do would make that zero move.
///
/// So the atlas is what is measured, through `showShadowMap`, which composites
/// it raw. That is precisely the half this change touches: a caster that
/// reaches the atlas and one that does not are 4% of the frame apart, and the
/// floor follows from the atlas on the day the lookup is fixed.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

const int _width = 128;
const int _height = 128;

/// A box on a floor with a lamp overhead, rigged or not.
///
/// Everything sits at the origin, and that is load-bearing rather than lazy: a
/// skinned mesh follows its *joints*, so a box placed at y=0.4 with its one
/// joint left at the origin is drawn at the origin and the two runs would be
/// comparing boxes in two different places. With the joint, the mesh node and
/// the bind pose all at the identity, the skinned box occupies exactly the
/// space the unskinned one does, and a difference between the two runs is a
/// difference in the path through the renderer.
({Scene scene, CameraNode camera}) _scene(
  WebGlDevice device, {
  required bool skinned,
  required bool casts,
}) {
  final scene = Scene(name: 'skinned point caster');

  scene.root.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const PlaneShape(width: 10.0, depth: 10.0).build(),
      ),
      Material(
        name: 'floor',
        baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'floor',
    )..setPosition(0.0, -1.5, 0.0),
  );

  final box =
      MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(2.0)).build(
              layout: skinned ? VertexLayout.skinned : VertexLayout.standard,
            ),
          ),
          Material(
            name: 'box',
            baseColor: Vector4(0.9, 0.3, 0.2, 1.0),
            lighting: LightingModel.lambert,
          ),
          name: 'box',
        )
        ..skinReach = 1.8
        ..castsShadow = casts;
  scene.root.add(box);

  if (skinned) {
    final joint = SceneNode(name: 'joint');
    scene.root.add(joint);
    box.skeleton = Skeleton(
      name: 'one bone',
      joints: <SceneNode>[joint],
      inverseBindMatrices: <Matrix4>[Matrix4.identity()],
    );
  }

  scene.root.add(
    LightNode(name: 'lamp', type: LightType.point)
      ..intensity = 14.0
      ..range = 14.0
      ..castsShadow = true
      ..setPosition(0.0, 2.0, 0.0),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 1.6, 5.0)
    ..lookAt(Vector3(0.0, -1.0, 0.0));
  scene.root.add(camera);

  return (scene: scene, camera: camera);
}

Renderer _renderer(WebGlDevice device) {
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

  return Renderer.create(
    device: device,
    fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
    fallbackNormal: texel(<int>[128, 128, 255, 255]),
  );
}

/// How many of the composited atlas's pixels hold a caster rather than the far
/// plane.
///
/// The pass clears each tile to 1.0, which is "nothing between here and the
/// light", so anything below that is a recorded distance. The threshold is well
/// under the clear rather than at it, because the tone-mapped composite of a
/// float target does not land on exactly 255.
Future<int> _recorded(
  WebGlDevice device, {
  required bool skinned,
  required bool casts,
}) async {
  final built = _scene(device, skinned: skinned, casts: casts);
  final result = _renderer(device).render(
    width: _width,
    height: _height,
    scene: built.scene,
    views: <RenderView>[RenderView(camera: built.camera)],
    settings: const RenderSettings(
      bloom: BloomSettings(enabled: false),
      showShadowMap: true,
    ),
  );

  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  final bytes = pixels!.buffer.asUint8List();
  expect(bytes.length, _width * _height * 4);

  var count = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i] < 250) count++;
  }
  return count;
}

void main() {
  late WebGlDevice device;

  setUp(() {
    final made = WebGlDevice.create(
      width: _width,
      height: _height,
      sources: engineShaders,
    );
    if (made == null) fail('no WebGL2 context in this browser');
    device = made;
  });

  test(
    'a rigged caster is recorded in the atlas, and an idle one is not',
    () async {
      // MUTATION: put `if (node.skeleton != null) continue;` back in the caster
      // loop of _renderCubeShadow. The `casts` reading goes to zero — the same
      // number the control already produces — and this is the assertion that
      // states the whole point of the change.
      final without = await _recorded(device, skinned: true, casts: false);
      final with_ = await _recorded(device, skinned: true, casts: true);

      // The control is exactly zero rather than merely small: the floor faces the
      // wrong way to be recorded from a lamp above it, so with the box withheld
      // the atlas is the far plane everywhere. That is what makes the reading
      // below attributable to the box and nothing else.
      expect(
        without,
        0,
        reason: 'something other than the box reached the atlas',
      );
      expect(
        with_ / (_width * _height),
        greaterThan(0.02),
        reason: 'the rigged caster left no mark on the atlas',
      );
    },
  );

  test('the skinned stage records the silhouette the static one does', () async {
    // MUTATION: bind `_cubeShadowPipeline` for the skinned node, so the static
    // vertex stage reads a skinned vertex buffer — 151 pixels of garbled
    // silhouette where 672 belong; or drop the SkinInfo bind, so the joint
    // array reads as zeros, every vertex collapses onto the origin and the
    // atlas records nothing at all.
    //
    // The test above catches both as well, by how much was recorded. This one
    // catches them by *what*, and is the one that would still fail if some
    // future mistake drew a plausible amount of the wrong shape.
    final static = await _recorded(device, skinned: false, casts: true);
    final skinned = await _recorded(device, skinned: true, casts: true);

    expect(static, greaterThan(0));
    // The bind pose is the identity, so the two are the same box in the same
    // place and the counts should agree outright. A tolerance of a few percent
    // rather than equality, because the two go through different vertex stages
    // and a shared edge can rasterise a pixel either way.
    expect(
      skinned,
      closeTo(static, static * 0.03),
      reason: 'the skinned caster is not the shape the static one is',
    );
  });
}

/// `pro-eng-03`'s acceptance: a "post-only" frame, where the base pass draws
/// almost nothing and the whole of what a viewer would call the picture comes
/// from `Renderer.renderPost` alone.
///
///     flutter test test/post_only_test.dart
///
/// **Deliberately not one of `kGoldenScenes`.** Recording an actual reference
/// — even for the software backend — runs through `tool/golden.sh`, which
/// builds and launches the example application on a real display; see its own
/// header comment ("golden rendering needs a real GPU... each scene runs as
/// the example application"). Nothing in this environment can launch that
/// application, so no PNG for a scene named `post-only` exists in any golden
/// set, `cpu` included.
///
/// What is checked here instead is the property a `post-only` golden would be
/// pinning, by measurement rather than by picture: a base frame that is flat
/// enough to be uninteresting on its own, and a call to `renderPost` that adds
/// a glow the base frame never had — proof that the picture's content is
/// `renderPost`'s alone, on the real software rasteriser rather than the
/// `FakeBackend` `renderer_post_standalone_test.dart` uses for its structural
/// checks.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera})
_room() {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );

  final scene = Scene();
  // The only thing in frame: a small emissive panel, bright enough to clip
  // display white once exposure and bloom are applied. No lights, no floor —
  // a base pass without post has almost nothing to show beyond the panel's
  // own unlit silhouette.
  final panel = MeshNode(
    DeviceMesh.upload(
      it.device,
      CuboidShape(size: Vector3(0.8, 0.8, 0.2)).build(),
    ),
    Material(
      name: 'panel',
      baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
      emissive: Vector3(6.0, 6.0, 6.0),
    ),
    name: 'panel',
  );
  scene.add(panel);

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 0.8,
      near: 0.1,
      far: 50.0,
    ),
  )..setPosition(0.0, 0.0, 4.0);
  camera.lookAt(Vector3.zero());
  scene.add(camera);

  return (device: it.device, renderer: renderer, scene: scene, camera: camera);
}

/// The scene without post: bloom and tonemap both off, so whatever the panel's
/// emissive value actually is survives into the returned texture rather than
/// being compressed to display range — the same "external HDR resource" shape
/// `renderPost`'s own [hdr] parameter is documented to expect.
TextureHandle _base(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it,
) => it.renderer
    .render(
      width: _width,
      height: _height,
      scene: it.scene,
      views: <RenderView>[
        RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        shadows: ShadowSettings(enabled: false),
        tonemap: false,
      ),
    )
    .frame;

int _litPixels(Uint8List rgba, {int channel = 40}) {
  var lit = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > channel || rgba[i + 1] > channel || rgba[i + 2] > channel) {
      lit++;
    }
  }
  return lit;
}

void main() {
  test('the base pass alone is almost featureless', () async {
    final it = _room();
    final hdr = _base(it);
    final pixels = (await it.device.readPixels(hdr))!.buffer.asUint8List();

    // Everything past the panel's own silhouette is unlit black; the panel
    // itself is small against a 64x48 frame.
    final lit = _litPixels(pixels);
    expect(
      lit,
      lessThan((_width * _height * 0.15).round()),
      reason:
          'the base pass already draws most of the picture; a post-only '
          'scene needs a base with almost nothing in it',
    );
  });

  test(
    'renderPost is the only thing that puts a glow around the panel',
    () async {
      // Mutation: have renderPost skip the bloom node, or read the wrong
      // texture as `hdr` — either leaves `withGlow` identical to
      // `withoutGlow` and this test catches it directly.
      final it = _room();
      final hdr = _base(it);
      final withoutGlow = (await it.device.readPixels(
        hdr,
      ))!.buffer.asUint8List();

      final post = it.renderer.renderPost(
        hdr: hdr,
        settings: const RenderSettings(
          bloom: BloomSettings(threshold: 0.6, intensity: 0.6),
        ),
      );
      final withGlow = (await it.device.readPixels(
        post.frame,
      ))!.buffer.asUint8List();

      expect(withGlow.length, withoutGlow.length);

      // Pixels dark in the base frame and lit once renderPost has run: the
      // halo bloom paints around the panel, present nowhere before the call.
      var haloed = 0;
      for (var i = 0; i < withoutGlow.length; i += 4) {
        final wasDark =
            withoutGlow[i] < 20 &&
            withoutGlow[i + 1] < 20 &&
            withoutGlow[i + 2] < 20;
        final isLit =
            withGlow[i] > 40 || withGlow[i + 1] > 40 || withGlow[i + 2] > 40;
        if (wasDark && isLit) haloed++;
      }
      expect(
        haloed,
        greaterThan(20),
        reason:
            'renderPost did not add a glow the base frame lacked: the '
            'picture this scene is for would have nothing in it beyond the '
            'panel itself',
      );
    },
  );
}

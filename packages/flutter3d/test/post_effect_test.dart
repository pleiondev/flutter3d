/// An application can add a pass after the composite, and be seen doing it.
///
///     flutter test test/post_effect_test.dart
///
/// Three separate gaps stood between "a post effect is just a `RenderNode`" and
/// a post effect anybody could write, and each one failed in a way that looks
/// like working code:
///
///   * **Order.** Application nodes were all registered before the post chain.
///     A node there declaring `reads: [frame]` bound to a version the composite
///     had not written; declaring only `writes: [frame]` put it *first*, where
///     the composite then discarded its output with `LoadAction.dontCare`. The
///     pass ran, cost its time, and left nothing.
///   * **Plumbing.** The covering triangle, its indices, the pass state, the
///     clamped sampler and the pipeline cache were all private to `Renderer`,
///     and a node is handed a `GraphicsDevice` rather than a `Renderer`.
///   * **Delivery.** `FrameResult.frame` was the renderer's own `_ldrColor`
///     field rather than the graph's newest version of `frame`. A pass after
///     the composite would draw the right picture into a texture nobody looked
///     at — and every symptom of that reads as "my effect does nothing".
///
/// The third is why this file asserts on the pixels the *caller* is handed
/// rather than on the node having run.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 36;

/// A post effect written the way an application would have to write one.
///
/// It reaches for nothing private: it declares what it touches, takes its
/// target out of the frame's resources, and draws through
/// [RenderServices.drawFullscreen]. If any of that needed something the engine
/// keeps to itself, this class could not be written outside `renderer.dart` —
/// which was the state of things before, and is the thing being tested.
final class _TintNode extends RenderNode {
  _TintNode(this.shader);

  final ShaderHandle shader;

  @override
  String get name => 'tint';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    // The version the composite wrote comes in; the version this produces goes
    // out. Both are called `frame`, and the registration order is what tells
    // them apart.
    final source = frame.resources.texture(FrameResourceIds.frame);
    final target = frame.resources.transient(
      RenderTargetSpec(
        width: source.width,
        height: source.height,
        format: source.format,
      ),
    );
    frame.services.drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: shader,
        textures: <String, TextureHandle>{'source_texture': source},
      ),
    );
    frame.resources.provide(FrameResourceIds.frame, target);
  }
}

/// Halves the green channel of whatever it is handed.
///
/// Deliberately something no other pass in the engine does, and deliberately
/// per-channel: a test that looked for "darker" could be satisfied by exposure,
/// by tone mapping, or by the effect not running while something else changed.
final class _TintShader implements CpuFragmentShader {
  const _TintShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final source = bindings.textures['source_texture'];
    if (source == null) return Vector4(1.0, 0.0, 1.0, 1.0);
    final texel = source.sample(v[0], v[1]);
    return Vector4(texel.x, texel.y * 0.5, texel.z, texel.w);
  }
}

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(<String, CpuStage>{
      ...builtinCpuShaders(),
      // A stage the engine has never heard of, registered by the application —
      // which on this backend is all "shipping your own shader" amounts to.
      'Tint': const CpuStage.fragment(_TintShader()),
    }),
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

({Scene scene, CameraNode camera}) _ball() {
  final scene = Scene()..ambientIntensity = 0.8;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(device, SphereShape(radius: 1.0).build()),
      Material(
        name: 'ball',
        baseColor: Vector4(0.7, 0.7, 0.7, 1.0),
        lighting: LightingModel.lambert,
      ),
      name: 'ball',
    ),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, -1.6)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw({FramePhase? phase}) async {
  final engine = _engine();
  if (phase != null) {
    engine.renderer.nodes.add(
      _TintNode(engine.device.shaders['Tint']!),
      phase: phase,
    );
  }
  final room = _ball();
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// Mean red and green over the whole frame, 0..255.
(double, double) _means(Uint8List rgba) {
  var r = 0.0, g = 0.0;
  final n = _width * _height;
  for (var i = 0; i < n; i++) {
    r += rgba[i * 4];
    g += rgba[i * 4 + 1];
  }
  return (r / n, g / n);
}

void main() {
  test('a present-phase node changes the frame the caller is handed', () async {
    // The whole point, and it is asserted on the returned pixels rather than on
    // the node having executed.
    //
    // Mutation: return the renderer's own `_ldrColor` from `render` instead of
    // `resources.output(frame)`. The node still runs, the tint is still drawn,
    // and this frame comes back untinted — which is the failure that was worth
    // building a test around, because nothing about it looks broken.
    //
    // Mutation: register present-phase nodes with the overlay ones. The graph
    // then binds the tint's read to a version before the composite, and the
    // composite's write is the newest — same result, nothing tinted.
    final plain = await _draw();
    final tinted = await _draw(phase: FramePhase.present);

    final (plainR, plainG) = _means(plain);
    final (tintedR, tintedG) = _means(tinted);

    expect(
      tintedR,
      closeTo(plainR, 1.0),
      reason: 'red moved, so this is not the green-halving effect running',
    );
    expect(
      tintedG,
      lessThan(plainG * 0.75),
      reason:
          'green did not fall: the pass after the composite drew into '
          'something the caller was never handed',
    );
  });

  test('the same node before the composite is refused, not ignored', () async {
    // The other half, and it turned out better than expected. The worry was
    // that a node registered in the old slot would draw into a version the
    // composite then discarded — running, costing time, and leaving nothing.
    // For a node that reads *and* writes `frame`, that is not what happens: the
    // composite reads the version this node produced and this node reads the
    // version the composite produced, and the graph names the loop and refuses
    // to compile.
    //
    // Which is the strongest possible argument for the phase existing. Without
    // it a post effect after the composite is not wrong or dim or subtly
    // mis-ordered — it cannot be built at all, and the message says why.
    //
    // Mutation: register present-phase nodes with the overlay ones. This throws
    // instead of tinting, and the test above fails with it.
    await expectLater(
      _draw(phase: FramePhase.overlay),
      throwsA(
        isA<FrameGraphError>().having(
          (FrameGraphError e) => e.toString(),
          'message',
          contains('depend on each other in a loop'),
        ),
      ),
    );
  });
}

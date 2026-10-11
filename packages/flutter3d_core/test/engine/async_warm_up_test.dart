/// `Renderer.warmUpInSlices` links through `createPipelineAsync`, and what
/// it links is the pipeline of the stages the renderer has when the link
/// completes, not of those it had when the link began.
///
/// **The device holds every asynchronous link until the test lets it go**,
/// as WebGPU's `createRenderPipelineAsync` and WebGL2's parallel compile
/// hold theirs for a few frames: a link that is out while a shader reload
/// lands is the case on those two backends, and on a device that links in
/// the calling turn it never happens.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

/// The pipeline the scene's one lit box draws with.
const String _lit = 'MeshVertex+PbrOpaque';

/// A [FakeBackend] whose asynchronous links wait for [release].
final class _HeldLinks extends GraphicsDevice {
  _HeldLinks(this.inner);

  final FakeBackend inner;

  /// The links asked for and not yet let go.
  final List<void Function()> _held = <void Function()>[];

  /// How many asynchronous links were asked for.
  int asked = 0;

  /// Completes every link asked for so far, each linking now.
  void release() {
    final held = _held.toList();
    _held.clear();
    for (final link in held) {
      link();
    }
  }

  @override
  Future<PipelineHandle> createPipelineAsync(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) {
    asked++;
    final linked = Completer<PipelineHandle>();
    _held.add(
      () => linked.complete(
        inner.createPipeline(vertex, fragment, layout: layout),
      ),
    );
    return linked.future;
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => inner.createPipeline(vertex, fragment, layout: layout);

  @override
  void releasePipeline(PipelineHandle pipeline) =>
      inner.releasePipeline(pipeline);

  @override
  PipelineRefusals get pipelineRefusals => inner.pipelineRefusals;

  @override
  TextureFormat get defaultColorFormat => inner.defaultColorFormat;

  @override
  TextureFormat get defaultDepthStencilFormat =>
      inner.defaultDepthStencilFormat;

  @override
  FramebufferOrigin get framebufferOrigin => inner.framebufferOrigin;

  @override
  DepthRange get depthRange => inner.depthRange;

  @override
  TextureFormat get hdrColorFormat => inner.hdrColorFormat;

  @override
  int get preferredSampleCount => inner.preferredSampleCount;

  @override
  DeviceFeatures get features => inner.features;

  @override
  DeviceLimits get limits => inner.limits;

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      inner.textureFormatSupport(format);

  @override
  ShaderLibrary get shaders => inner.shaders;

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) =>
      inner.loadShaders(bytes);

  @override
  TextureHandle createTexture(TextureDescriptor descriptor) =>
      inner.createTexture(descriptor);

  @override
  void releaseTexture(TextureHandle texture) => inner.releaseTexture(texture);

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => inner.createCubeRenderTarget(
    size: size,
    format: format,
    mipLevels: mipLevels,
  );

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) => inner.createTextureFromPixels(
    width: width,
    height: height,
    format: format,
    pixels: pixels,
    mipLevels: mipLevels,
  );

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => inner.createCubeTextureFromPixels(
    size: size,
    format: format,
    faces: faces,
    mipLevels: mipLevels,
  );

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) =>
      inner.overwriteTexture(target, rgba, region: region, mipLevel: mipLevel);

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      inner.uploadGeometry(bytes, usage);

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) => inner.overwriteGeometry(target, offsetInBytes, bytes);

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      inner.releaseGeometry(geometry);

  @override
  void beginFrame() => inner.beginFrame();

  @override
  void onFrameComplete(void Function() whenDone) =>
      inner.onFrameComplete(whenDone);

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      inner.beginRenderPass(descriptor);

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) =>
      inner.readback(texture, region: region);

  @override
  void dispose() => inner.dispose();
}

/// A lit box in front of a camera, and a renderer on [device].
({Renderer renderer, Scene scene, CameraNode camera}) _stage(
  GraphicsDevice device,
) {
  final camera = CameraNode();
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        RenderMaterial(),
      )..setPosition(0.0, 0.0, -5.0),
    )
    ..add(camera);
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<void> _warmUp(
  ({Renderer renderer, Scene scene, CameraNode camera}) stage,
) => stage.renderer.warmUpInSlices(
  width: 16,
  height: 16,
  scene: stage.scene,
  views: <RenderView>[RenderView(camera: stage.camera)],
  slice: Duration.zero,
);

void main() {
  test('a warm-up through a recorder links on the device underneath it, '
      'off the calling turn', () async {
    // Mutation: drop `createPipelineAsync` from `RecordingDevice`, and the
    // base class's default links through the recorder's `createPipeline` in
    // the calling turn: the held device is never asked.
    final held = _HeldLinks(FakeBackend());
    final recorder = RecordingDevice(held);
    final stage = _stage(recorder);
    final warming = _warmUp(stage);
    await Future<void>.delayed(Duration.zero);
    expect(held.asked, greaterThan(0));
    expect(
      recorder.events.whereType<TraceCreatePipeline>().map(
        (e) => '${e.vertex}+${e.fragment}',
      ),
      isNot(contains(_lit)),
      reason: 'a link still out is not in the trace',
    );

    held.release();
    await warming;
    expect(
      recorder.events.whereType<TraceCreatePipeline>().map(
        (e) => '${e.vertex}+${e.fragment}',
      ),
      contains(_lit),
    );
  });

  test('a shader reload while a link is out leaves no pipeline of the old '
      'stages in the cache', () async {
    // Mutation: cache what `_linkAsync` gets back without asking whether the
    // shaders were reloaded since it began, and the warm-up frames draw with
    // the pipeline linked before the reload: it is linked once.
    final held = _HeldLinks(FakeBackend());
    final stage = _stage(held);
    final warming = _warmUp(stage);
    await Future<void>.delayed(Duration.zero);
    expect(held.asked, greaterThan(0));

    stage.renderer.relinkShaders();
    held.release();
    await warming;

    final linked = held.inner.linkedPipelines.where((n) => n == _lit).length;
    expect(linked, 2, reason: 'once before the reload, once after it');
    stage.renderer.render(
      width: 16,
      height: 16,
      scene: stage.scene,
      views: <RenderView>[RenderView(camera: stage.camera)],
    );
    expect(
      held.inner.linkedPipelines.where((n) => n == _lit).length,
      2,
      reason: 'the one linked after the reload is cached and kept',
    );
  });

  test('a warm-up asked for after the reload links again rather than '
      'waiting on the link of before it', () async {
    // Mutation: leave `_linking` alone in `relinkShaders`, and the second
    // warm-up joins the first one's link, which is discarded: the frames
    // after it link in the calling turn instead, and nothing is asked of the
    // device the second time.
    final held = _HeldLinks(FakeBackend());
    final stage = _stage(held);
    final first = _warmUp(stage);
    await Future<void>.delayed(Duration.zero);
    final before = held.asked;

    stage.renderer.relinkShaders();
    final second = _warmUp(stage);
    await Future<void>.delayed(Duration.zero);
    expect(held.asked, greaterThan(before));

    held.release();
    await Future.wait(<Future<void>>[first, second]);
  });
}

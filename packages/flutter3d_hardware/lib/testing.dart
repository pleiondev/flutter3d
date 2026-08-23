/// A graphics backend that draws nothing and remembers everything.
///
/// The counterpart to the fake texture source in `frame_resources_test.dart`,
/// and it exists for the same reason. Every type a pass used to name —
/// `gpu.RenderPass`, `gpu.HostBuffer`, `gpu.Shader`, `gpu.RenderPipeline` —
/// needed a live device to construct, so nothing that *encoded* anything could
/// be tested at all. What a node draws was checked by looking at a golden image
/// twelve minutes later, or not at all.
///
/// With the backend arriving as a value, a node can be handed one of these and
/// asked what it did: which passes it opened, what they were attached to, what
/// state it left them in, what it bound and how many times it drew.
///
/// ## Why it is in `lib/`, and in this package
///
/// **It was four hundred and seventy-five lines in two copies, and they had
/// already drifted.** `flutter3d/test/fake_backend.dart` and
/// `flutter3d_particles/test/fake_backend.dart` were the same file down to the
/// paragraph above — which still names a test that only exists in one of them —
/// and the particles copy was twenty-six lines behind: no `pendingFrames`, no
/// `completesImmediately`, no `uploadedPixels`. A test written against it could
/// not ask the question those exist to answer, and nothing said so.
///
/// This package rather than a new one, because that is what it depends on:
/// `flutter3d_hardware` and `flutter/widgets`, and nothing else. A separate
/// `flutter3d_fakes` would be a twenty-second workspace entry holding one file.
///
/// In `lib/` rather than in a shared `test/`, because a package cannot import
/// another package's `test/` — which is the reason there were two copies.
///
/// ```dart
/// import 'package:flutter3d_hardware/testing.dart';
/// ```
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One thing recorded into a pass, in order.
///
/// A sealed hierarchy rather than a list of strings, so a test asserts on
/// values it can construct rather than on a rendering of them — a string
/// comparison would pass for the wrong reasons the first time a `toString`
/// changed.
sealed class Recorded {
  const Recorded();
}

final class RecordedDraw extends Recorded {
  const RecordedDraw({this.instanceCount = 1});

  /// How many instances the draw asked for. One for every draw this engine
  /// made before mesh particles, which is why the characterisation snapshots
  /// print `draw` unadorned unless it is anything else.
  final int instanceCount;
}

final class RecordedPipeline extends Recorded {
  const RecordedPipeline(this.pipeline);
  final PipelineHandle pipeline;
}

final class RecordedBlend extends Recorded {
  const RecordedBlend(this.state, this.attachment);
  final BlendState? state;
  final int attachment;
}

final class RecordedTexture extends Recorded {
  const RecordedTexture(this.slot, this.texture, this.sampler);
  final String slot;
  final TextureHandle texture;
  final SamplerOptions? sampler;
}

final class RecordedUniformBlock extends Recorded {
  const RecordedUniformBlock(this.shader, this.block, this.members);
  final ShaderHandle shader;
  final String block;
  final Map<String, Float32List> members;
}

final class RecordedVertices extends Recorded {
  const RecordedVertices(this.count, {required this.transient, this.slot = 0});

  /// Which vertex buffer slot this filled. Zero for every draw in the engine
  /// except an instanced one, which is what makes a non-zero value worth
  /// asserting on.
  final int slot;
  final int count;

  /// True when the data was built this frame rather than living on the device.
  final bool transient;
}

final class RecordedIndices extends Recorded {
  const RecordedIndices(this.type, this.count, {required this.transient});
  final IndexType type;
  final int count;
  final bool transient;
}

final class RecordedViewport extends Recorded {
  const RecordedViewport(this.rect);
  final ScreenRect rect;
}

final class RecordedScissor extends Recorded {
  const RecordedScissor(this.rect);
  final ScreenRect rect;
}

final class RecordedClearBindings extends Recorded {
  const RecordedClearBindings();
}

/// Rasteriser state, recorded **in sequence** as well as kept as a field.
///
/// The fields answer "what was it set to"; these answer "in what order, and
/// how many times". Those are different questions and only the second one
/// catches the interesting mistakes. A pass that sets depth write twice, or
/// sets it after the draw that needed it, or stops setting it at all because a
/// refactor decided the value was already right, reads identically through the
/// fields and differently here.
///
/// It matters most where state changes *inside* a pass: the cube atlas blanks
/// each tile with depth write off and compare `always`, then restores both for
/// the casters. Through the fields that whole loop is one final value.
final class RecordedPrimitiveType extends Recorded {
  const RecordedPrimitiveType(this.type);
  final PrimitiveType type;
}

final class RecordedPolygonMode extends Recorded {
  const RecordedPolygonMode(this.mode);
  final PolygonMode mode;
}

final class RecordedCullMode extends Recorded {
  const RecordedCullMode(this.mode);
  final CullMode mode;
}

final class RecordedWindingOrder extends Recorded {
  const RecordedWindingOrder(this.order);
  final WindingOrder order;
}

final class RecordedDepthWrite extends Recorded {
  const RecordedDepthWrite(this.enabled);
  final bool enabled;
}

final class RecordedDepthCompare extends Recorded {
  const RecordedDepthCompare(this.compare);
  final CompareFunction compare;
}

/// A pass that was opened, and everything that went into it.
final class FakePass implements CommandEncoder {
  FakePass(this.descriptor);

  final RenderPassDescriptor descriptor;

  /// Everything recorded, in order.
  final List<Recorded> commands = <Recorded>[];

  bool submitted = false;

  // Terminal state, which is what most assertions actually want: whether the
  // pass was left writing depth matters, the order the flag was toggled in
  // usually does not.
  PrimitiveType? primitiveType;
  PolygonMode? polygonMode;
  CullMode? cullMode;
  WindingOrder? windingOrder;
  bool? depthWrite;
  CompareFunction? depthCompare;

  int get drawCount => commands.whereType<RecordedDraw>().length;

  ColorTarget get color => descriptor.colors.single;

  Iterable<T> recordedOf<T extends Recorded>() => commands.whereType<T>();

  @override
  void setViewport(ScreenRect rect) => commands.add(RecordedViewport(rect));

  @override
  void setScissor(ScreenRect rect) => commands.add(RecordedScissor(rect));

  @override
  void setPrimitiveType(PrimitiveType type) {
    primitiveType = type;
    commands.add(RecordedPrimitiveType(type));
  }

  @override
  void setPolygonMode(PolygonMode mode) {
    polygonMode = mode;
    commands.add(RecordedPolygonMode(mode));
  }

  @override
  void setCullMode(CullMode mode) {
    cullMode = mode;
    commands.add(RecordedCullMode(mode));
  }

  @override
  void setWindingOrder(WindingOrder order) {
    windingOrder = order;
    commands.add(RecordedWindingOrder(order));
  }

  @override
  void setDepthWrite(bool enabled) {
    depthWrite = enabled;
    commands.add(RecordedDepthWrite(enabled));
  }

  @override
  void setDepthCompare(CompareFunction compare) {
    depthCompare = compare;
    commands.add(RecordedDepthCompare(compare));
  }

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      commands.add(RecordedBlend(state, attachment));

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      commands.add(RecordedPipeline(pipeline));

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount,
          {int slot = 0}) =>
      commands.add(RecordedVertices(vertexCount, transient: false, slot: slot));

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      commands.add(RecordedVertices(vertexCount, transient: true, slot: slot));

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      commands.add(RecordedIndices(type, indexCount, transient: false));

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      commands.add(RecordedIndices(type, indexCount, transient: true));

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    commands.add(RecordedUniformBlock(shader, blockName, members));
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) =>
      commands.add(RecordedTexture(slot, texture, sampler));

  @override
  void clearBindings() => commands.add(const RecordedClearBindings());

  @override
  void draw({int instanceCount = 1}) =>
      commands.add(RecordedDraw(instanceCount: instanceCount));

  @override
  void submit() => submitted = true;
}

/// A bundle that has every stage anybody asks for, except the ones it is told
/// to withhold.
///
/// Withholding matters: `ParticleContributor` draws nothing when its stages are
/// missing, and that path had never been exercised.
final class FakeShaderLibrary implements ShaderLibrary {
  FakeShaderLibrary({this.missing = const <String>{}});

  final Set<String> missing;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) => missing.contains(name)
      ? null
      : _handles.putIfAbsent(
          name, () => ShaderHandle(backend: name, name: name));
}

/// A device that records rather than draws.
final class FakeBackend implements GraphicsDevice {
  FakeBackend({
    Set<String> missingShaders = const <String>{},
    this.supportsWireframe = true,
  }) : shaders = FakeShaderLibrary(missing: missingShaders);

  @override
  final FakeShaderLibrary shaders;

  /// Settable, because the interesting case is the backend that says no —
  /// OpenGL ES has no `glPolygonMode`, and the engine is supposed to decline
  /// its own wireframe setting rather than let the request reach a backend
  /// that would refuse it mid-frame.
  @override
  final bool supportsWireframe;

  /// True, because a fake has nothing to be incapable with. The real answer is
  /// a device property, and the two backends that have one disagree.
  @override
  bool get supportsMipmaps => true;

  @override
  bool get supportsCubeTextures => true;

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
  }) =>
      faces.length == 6
          ? TextureHandle(
              backend: const Object(),
              width: size,
              height: size,
              format: format,
              type: TextureType.textureCube,
            )
          : null;

  /// The engine's own convention, so a fake never exercises the remap. The
  /// backends that need the other one are covered by running them.
  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  int get preferredSampleCount => 4;

  /// Every pass ever opened, in the order it was opened.
  final List<FakePass> passes = <FakePass>[];

  final List<RenderTargetSpec> createdTextures = <RenderTargetSpec>[];

  int frames = 0;
  int _serial = 0;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.b8g8r8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat =>
      TextureFormat.d24UnormS8Uint;

  @override
  bool get supportsOffscreenMsaa => true;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) {
    createdTextures.add(spec);
    return TextureHandle(
      backend: 'fake ${_serial++}',
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );
  }

  /// Frames whose work the GPU has not "finished".
  ///
  /// Held rather than run, so a test can decide when a frame is over — which is
  /// the whole question the renderer's finished-frame textures turn on.
  final List<void Function()> pendingFrames = <void Function()>[];

  /// Whether [onFrameComplete] runs its callback at once.
  ///
  /// True by default, so every test that does not care about this sees a
  /// backend that finishes as it goes.
  bool completesImmediately = true;

  @override
  void onFrameComplete(void Function() whenDone) {
    if (completesImmediately) {
      whenDone();
      return;
    }
    pendingFrames.add(whenDone);
  }

  /// Lets the oldest unfinished frame complete.
  void finishOldestFrame() {
    if (pendingFrames.isEmpty) return;
    pendingFrames.removeAt(0)();
  }

  /// Pixel uploads, in order, so a test can assert what reached the device.
  final List<RenderTargetSpec> uploadedTextures = <RenderTargetSpec>[];

  /// The bytes of each of those, for a test that cares what colour it was.
  final List<ByteData> uploadedPixels = <ByteData>[];

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final spec = RenderTargetSpec(
      width: width,
      height: height,
      format: format,
      storageMode: StorageMode.hostVisible,
    );
    uploadedTextures.add(spec);
    uploadedPixels.add(pixels);
    return createTexture(spec);
  }

  @override
  PipelineHandle createPipeline(
          ShaderHandle vertex, ShaderHandle fragment,
          {VertexLayoutSpec? layout}) =>
      PipelineHandle(
        backend: '${vertex.name}+${fragment.name}',
        name: '${vertex.name}+${fragment.name}',
      );

  /// Recorded with its usage, because a backend exists that cannot change its
  /// mind about one later.
  final List<GeometryUsage> uploads = <GeometryUsage>[];

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    uploads.add(usage);
    return _geometry(bytes);
  }

  GeometryBuffer _geometry(ByteData bytes) => GeometryBuffer(
        backend: 'uploaded ${_serial++}',
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );

  @override
  void beginFrame() => frames++;

  /// Nothing was drawn, so there is nothing to show, and pretending otherwise
  /// would be worse than refusing: a test handed a blank widget could assert
  /// something about a frame that never existed. Nothing under test here
  /// reaches this — only an application does, once per frame.
  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) =>
      throw UnsupportedError(
        'FakeBackend draws nothing, so there is nothing to present of $frame',
      );

  /// Null, which is a legitimate answer rather than a refusal: it is what a
  /// real device says about a texture whose pixels cannot be read.
  @override
  Future<ByteData?> readPixels(TextureHandle texture) =>
      Future<ByteData?>.value();

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final pass = FakePass(descriptor);
    passes.add(pass);
    return pass;
  }
}

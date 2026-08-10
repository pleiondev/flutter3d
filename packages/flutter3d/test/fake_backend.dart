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
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/graphics/command_encoder.dart';
import 'package:flutter3d/src/engine/graphics/formats.dart';
import 'package:flutter3d/src/engine/graphics/geometry_buffer.dart';
import 'package:flutter3d/src/engine/graphics/graphics_device.dart';
import 'package:flutter3d/src/engine/graphics/render_target_pool.dart';
import 'package:flutter3d/src/engine/graphics/sampler.dart';
import 'package:flutter3d/src/engine/graphics/shader.dart';
import 'package:flutter3d/src/engine/graphics/texture.dart';

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
  const RecordedDraw();
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
  const RecordedVertices(this.count, {required this.transient});
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
  void setPrimitiveType(PrimitiveType type) => primitiveType = type;

  @override
  void setPolygonMode(PolygonMode mode) => polygonMode = mode;

  @override
  void setCullMode(CullMode mode) => cullMode = mode;

  @override
  void setWindingOrder(WindingOrder order) => windingOrder = order;

  @override
  void setDepthWrite(bool enabled) => depthWrite = enabled;

  @override
  void setDepthCompare(CompareFunction compare) => depthCompare = compare;

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      commands.add(RecordedBlend(state, attachment));

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      commands.add(RecordedPipeline(pipeline));

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount) =>
      commands.add(RecordedVertices(vertexCount, transient: false));

  @override
  void bindVertexData(ByteData bytes, int vertexCount) =>
      commands.add(RecordedVertices(vertexCount, transient: true));

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
  void draw() => commands.add(const RecordedDraw());

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
  FakeBackend({Set<String> missingShaders = const <String>{}})
      : shaders = FakeShaderLibrary(missing: missingShaders);

  @override
  final FakeShaderLibrary shaders;

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

  @override
  PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment) =>
      PipelineHandle(
        backend: '${vertex.name}+${fragment.name}',
        name: '${vertex.name}+${fragment.name}',
      );

  @override
  GeometryBuffer uploadGeometry(ByteData bytes) => GeometryBuffer(
        backend: 'uploaded ${_serial++}',
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );

  @override
  void beginFrame() => frames++;

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final pass = FakePass(descriptor);
    passes.add(pass);
    return pass;
  }
}

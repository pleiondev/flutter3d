/// One thing recorded into a [FakePass], in order.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

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

final class RecordedBlendColor extends Recorded {
  const RecordedBlendColor(this.color);
  final Vector4 color;
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

/// A stencil configuration, with the back face only when one was named.
final class RecordedStencil extends Recorded {
  const RecordedStencil(this.front, this.back);
  final StencilState front;
  final StencilState? back;
}

final class RecordedStencilReference extends Recorded {
  const RecordedStencilReference(this.value);
  final int value;
}

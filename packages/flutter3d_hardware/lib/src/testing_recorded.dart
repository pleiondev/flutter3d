/// One thing recorded into a [FakePass], in order.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One thing recorded into a pass, in order.
///
/// A hierarchy of values rather than a list of strings, so a test asserts on
/// values it can construct rather than on a rendering of them — a string
/// comparison would pass for the wrong reasons the first time a `toString`
/// changed.
///
/// **Open, not sealed, since 1.0.** A pass gains calls in minor releases, and
/// each new kind of record would have been a new case every exhaustive
/// `switch` over a sealed type had to add: a break in a minor. A `switch`
/// over a [Recorded] ends with a wildcard, as a test that names only the
/// records it cares about already does.
abstract base class Recorded {
  /// Lets a subclass be a `const` value.
  const Recorded();
}

/// `PassEncoder.draw`, with the instance count and index window it asked for.
final class RecordedDraw extends Recorded {
  /// Records a draw of [instanceCount] instances over the index window from
  /// [firstIndex].
  const RecordedDraw({
    this.instanceCount = 1,
    this.firstIndex = 0,
    this.indexCount,
  });

  /// How many instances the draw asked for. One for every draw this engine
  /// made before mesh particles, which is why the characterisation snapshots
  /// print `draw` unadorned unless it is anything else.
  final int instanceCount;

  /// The window of the bound indices the draw read — `P7`. Zero and null, the
  /// whole binding, for every draw that did not ask for less.
  final int firstIndex;

  /// How many indices the window covers, a count; null for the rest of the
  /// binding from [firstIndex].
  final int? indexCount;
}

/// `PassEncoder.bindPipeline`.
final class RecordedPipeline extends Recorded {
  /// Records [pipeline] bound.
  const RecordedPipeline(this.pipeline);

  /// The pipeline handle the pass was given.
  final PipelineHandle pipeline;
}

/// `PassEncoder.setBlend`, for one colour attachment.
final class RecordedBlend extends Recorded {
  /// Records [state] set on colour attachment [attachment].
  const RecordedBlend(this.state, this.attachment);

  /// The blend state; null turns blending off.
  final BlendState? state;

  /// The colour attachment index, zero for the first.
  final int attachment;
}

/// `PassEncoder.setBlendColor`.
final class RecordedBlendColor extends Recorded {
  /// Records the blend constant [color] set.
  const RecordedBlendColor(this.color);

  /// The blend constant, linear RGBA, unitless.
  final LinearColor color;
}

/// `PassEncoder.bindTexture`.
final class RecordedTexture extends Recorded {
  /// Records [texture] bound to [slot] of [shader] with [sampler].
  const RecordedTexture(this.slot, this.texture, this.sampler, {this.shader});

  /// The sampled-texture binding's name as the stage declares it.
  final String slot;

  /// The texture handle bound.
  final TextureHandle texture;

  /// The sampler the call named; null when it named none, which a backend reads
  /// as `SamplerDescriptor.linearRepeat`.
  final SamplerDescriptor? sampler;

  /// The stage it was bound through. It was not recorded, so a test could not
  /// tell a texture bound to the vertex stage from one bound to the fragment
  /// stage. Null only where a test built one by hand.
  final ShaderHandle? shader;
}

/// `PassEncoder.bindUniformBlock`.
final class RecordedUniformBlock extends Recorded {
  /// Records the block [block] of [shader] bound with [members].
  const RecordedUniformBlock(this.shader, this.block, this.members);

  /// The stage the block belongs to.
  final ShaderHandle shader;

  /// The block's name as the stage declares it.
  final String block;

  /// Each member's floats by name, as the call handed them.
  final Map<String, Float32List> members;
}

/// `PassEncoder.bindVertexBuffer` or `bindVertexData`: how many vertices, not
/// which buffer.
final class RecordedVertices extends Recorded {
  /// Records [count] vertices bound to [slot], [transient] when they came as
  /// bytes built this frame.
  const RecordedVertices(this.count, {required this.transient, this.slot = 0});

  /// Which vertex buffer slot this filled. Zero for every draw in the engine
  /// except an instanced one, which is what makes a non-zero value worth
  /// asserting on.
  final int slot;

  /// How many vertices the binding holds, a count.
  final int count;

  /// True when the data was built this frame rather than living on the device.
  final bool transient;
}

/// `PassEncoder.bindIndexBuffer` or `bindIndexData`: the width and count, not
/// which buffer.
final class RecordedIndices extends Recorded {
  /// Records [count] indices of [type], [transient] when they came as bytes
  /// built this frame.
  const RecordedIndices(this.type, this.count, {required this.transient});

  /// The width of each index.
  final IndexType type;

  /// How many indices the binding holds, a count.
  final int count;

  /// True when the indices were built this frame (`bindIndexData`) rather than
  /// living on the device.
  final bool transient;
}

/// `PassEncoder.setViewport`.
final class RecordedViewport extends Recorded {
  /// Records [viewport] set.
  const RecordedViewport(this.viewport);

  /// The viewport as it was set — a [PassViewport] since 1.0.0-rc.1.
  final PassViewport viewport;

  /// [viewport]'s rectangle in whole pixels, which is what every pass of
  /// the engine sets and what a test asserts on.
  ScreenRect get rect => viewport.rect;
}

/// `PassEncoder.setScissor`.
final class RecordedScissor extends Recorded {
  /// Records the scissor [rect] set.
  const RecordedScissor(this.rect);

  /// The scissor rectangle, in pixels of the attachment.
  final ScreenRect rect;
}

/// `PassEncoder.clearBindings`.
final class RecordedClearBindings extends Recorded {
  /// Records the bindings cleared; every one is the same value.
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
  /// Records [type] set.
  const RecordedPrimitiveType(this.type);

  /// The primitive the following draws assemble.
  final PrimitiveType type;
}

/// `PassEncoder.setPolygonMode`, in sequence; see [RecordedPrimitiveType].
final class RecordedPolygonMode extends Recorded {
  /// Records [mode] set.
  const RecordedPolygonMode(this.mode);

  /// Whether the following draws fill triangles or draw their edges.
  final PolygonMode mode;
}

/// `PassEncoder.setAlphaToCoverage`, in sequence; see [RecordedPrimitiveType].
final class RecordedAlphaToCoverage extends Recorded {
  /// Records alpha to coverage turned on or off.
  const RecordedAlphaToCoverage(this.enabled);

  /// Whether fragment alpha drives the sample coverage mask.
  final bool enabled;
}

/// `PassEncoder.setCullMode`, in sequence; see [RecordedPrimitiveType].
final class RecordedCullMode extends Recorded {
  /// Records [mode] set.
  const RecordedCullMode(this.mode);

  /// The faces the following draws discard.
  final CullMode mode;
}

/// `PassEncoder.setWindingOrder`, in sequence; see [RecordedPrimitiveType].
final class RecordedWindingOrder extends Recorded {
  /// Records [order] set.
  const RecordedWindingOrder(this.order);

  /// The winding treated as the front face.
  final WindingOrder order;
}

/// `PassEncoder.setDepthWrite`, in sequence; see [RecordedPrimitiveType].
final class RecordedDepthWrite extends Recorded {
  /// Records depth writes turned on or off.
  const RecordedDepthWrite(this.enabled);

  /// Whether passing fragments write their depth.
  final bool enabled;
}

/// `PassEncoder.setDepthCompare`, in sequence; see [RecordedPrimitiveType].
final class RecordedDepthCompare extends Recorded {
  /// Records [compare] set.
  const RecordedDepthCompare(this.compare);

  /// How a fragment's depth is compared with the stored one.
  final CompareFunction compare;
}

/// A stencil configuration, with the back face only when one was named.
final class RecordedStencil extends Recorded {
  /// Records the stencil states [front] and [back] set.
  const RecordedStencil(this.front, this.back);

  /// The state for front-facing triangles, and for back-facing ones when [back]
  /// is null.
  final StencilState front;

  /// The state for back-facing triangles; null when [front] applies to both.
  final StencilState? back;
}

/// `PassEncoder.setStencilReference`, in sequence; see [RecordedPrimitiveType].
final class RecordedStencilReference extends Recorded {
  /// Records the reference [value] set.
  const RecordedStencilReference(this.value);

  /// The reference as the call gave it, before a backend keeps its low eight
  /// bits.
  final int value;
}

/// A 1.0-surface call — a storage bind, a query, an indirect or bundled
/// draw, a buffer write, a copy — recorded by name with its arguments.
///
/// **One variant for the whole 1.0 surface rather than one per call**, so
/// that a test switching over [Recorded] keeps compiling when the contract
/// gains a call, which under 1.0's semver it may in any minor release. A test
/// that cares asks for [name] and reads [arguments], which is whatever value
/// the call was handed (a descriptor, a record of its parameters).
final class RecordedCall extends Recorded {
  /// Records the call [name] with [arguments].
  const RecordedCall(this.name, {this.arguments});

  /// The member's name, as the contract spells it.
  final String name;

  /// What the call was handed: a descriptor, or a record of its parameters;
  /// null for a call that takes none.
  final Object? arguments;

  @override
  String toString() => 'RecordedCall($name, $arguments)';
}

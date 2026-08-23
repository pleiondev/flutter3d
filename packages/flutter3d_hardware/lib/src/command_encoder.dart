/// Recording a render pass, in the engine's own vocabulary.
///
/// **Nothing in `graphics/` may import `flutter_gpu`** —
/// `test/graphics_is_backend_free_test.dart` enforces it. See
/// `graphics/formats.dart` for why the directory exists.
///
/// ## What this is, and what it deliberately is not
///
/// Every pass this engine draws has the same shape: describe a target, open it,
/// set some rasteriser state, bind a pipeline and some buffers and textures,
/// draw, submit. That shape is what [CommandEncoder] models. It was derived by
/// reading all eight pass sites in the renderer plus the two in the extension
/// API, and **every member here has at least one caller**; anything flutter_gpu
/// offers that no pass in this engine uses — stencil configuration, depth
/// range, separate depth and stencil load/store actions, non-indexed draws —
/// is absent rather than passed through. An interface member with no user is a
/// guess about a second backend, and this file was written when there was no
/// second backend to check a guess against.
///
/// Instancing was on that list until mesh particles needed it, which is the
/// rule working rather than failing. It arrived when something asked, and it
/// arrived in this engine's shape — an argument on [PassEncoder.draw] and a
/// slot on the vertex binds — rather than as flutter_gpu's split into
/// `draw(vertexCount)` and `drawIndexed(indexCount)`, which would have added a
/// member no pass here has ever wanted. There are three backends now, so the
/// guess can be checked, and it is: by a conformance test rather than a
/// golden, because the three reach instancing three different ways.
///
/// ## Where flutter_gpu's model and the engine's intent differ
///
/// Four places, and they are the places a WebGL2 or Vulkan backend will strain.
/// They are recorded here rather than in a report because they are properties
/// of *this file*.
///
///  1. **A command buffer and its pass are fused.** flutter_gpu has both, and
///     Metal allows one open encoder per buffer with no way to end one — so
///     every site in this engine creates a buffer, opens exactly one pass and
///     submits. Ordering between passes is by *submission*, which is the fact
///     the frame graph leans on. A backend that wants many passes in one buffer,
///     or an explicit `end()` distinct from `submit()`, sees the two collapsed
///     into [CommandEncoder.submit] and has to split them again on its side.
///
///  2. **Rasteriser state is per draw, not per pipeline.** Cull mode, winding,
///     depth compare, depth write, polygon mode and blend are *pass* state on
///     Impeller, which is why they are methods here. On Vulkan they belong to
///     the pipeline object, so a Vulkan backend must accumulate these calls and
///     look a pipeline up at [PassEncoder.draw] rather than at
///     [PassEncoder.bindPipeline]. This is the sharpest divergence in the file
///     and the one that cannot be papered over: it is an Impeller shape
///     showing through, and the engine genuinely does change cull mode between
///     draws inside a pass.
///
///  3. **A uniform block is named members, not bytes.** The caller says which
///     block and which members; where the bytes live until the GPU has read
///     them, and how they are packed, is the backend's business. flutter_gpu
///     answers with a per-frame bump allocator (`HostBuffer`) and std140
///     offsets from shader reflection. That allocator used to be a parameter on
///     the extension API — `ContributorFrame.host` — which made a lifetime
///     rule of one backend into a term of the engine's vocabulary.
///
///  4. **Blend is one call.** flutter_gpu has `setColorBlendEnable` and
///     `setColorBlendEquation`; no site in this engine ever enables blending
///     without setting an equation, or sets one without enabling. So there is
///     one method and `null` means off.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'formats.dart';
import 'geometry_buffer.dart';
import 'sampler.dart';
import 'shader.dart';
import 'texture.dart';
import 'vertex_layout_spec.dart';

/// A rectangle of a render target, in pixels.
///
/// One type for both the viewport and the scissor, because every site in this
/// engine sets them to the same rectangle — with one exception, the composite's
/// overlay loop, which re-aims the viewport per view inside a scissor that
/// already covers the whole frame. That exception is why they are still two
/// methods and not one.
final class ScreenRect {
  const ScreenRect({
    this.x = 0,
    this.y = 0,
    required this.width,
    required this.height,
  });

  /// The whole of a texture.
  factory ScreenRect.of(TextureHandle texture) =>
      ScreenRect(width: texture.width, height: texture.height);

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ScreenRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'ScreenRect($x, $y, ${width}x$height)';
}

/// How a draw is combined with what the attachment already holds.
///
/// A value type with `==`, so a backend can cache one native object per
/// distinct state and a test can assert on the state a pass was left in — the
/// same two reasons `SamplerOptions` is one.
///
/// The field set and the defaults are flutter_gpu's, unchanged, which is what
/// makes [alphaBlend] exactly the equation the engine used to get by
/// constructing an empty `ColorBlendEquation`.
final class BlendState {
  const BlendState({
    this.colorOperation = BlendOperation.add,
    this.sourceColorFactor = BlendFactor.one,
    this.destinationColorFactor = BlendFactor.oneMinusSourceAlpha,
    this.alphaOperation = BlendOperation.add,
    this.sourceAlphaFactor = BlendFactor.one,
    this.destinationAlphaFactor = BlendFactor.oneMinusSourceAlpha,
  });

  /// Source over destination, with the source colour taken as premultiplied —
  /// the source factor is [BlendFactor.one] and not `sourceAlpha`. What
  /// transparent materials draw with.
  static const BlendState alphaBlend = BlendState();

  /// Both terms added. What particles and the bloom upsample draw with.
  ///
  /// Addition is commutative, which is what lets a thousand particles composite
  /// correctly in one unsorted batch.
  static const BlendState additive = BlendState(
    sourceColorFactor: BlendFactor.one,
    destinationColorFactor: BlendFactor.one,
    sourceAlphaFactor: BlendFactor.one,
    destinationAlphaFactor: BlendFactor.one,
  );

  final BlendOperation colorOperation;
  final BlendFactor sourceColorFactor;
  final BlendFactor destinationColorFactor;
  final BlendOperation alphaOperation;
  final BlendFactor sourceAlphaFactor;
  final BlendFactor destinationAlphaFactor;

  @override
  bool operator ==(Object other) =>
      other is BlendState &&
      other.colorOperation == colorOperation &&
      other.sourceColorFactor == sourceColorFactor &&
      other.destinationColorFactor == destinationColorFactor &&
      other.alphaOperation == alphaOperation &&
      other.sourceAlphaFactor == sourceAlphaFactor &&
      other.destinationAlphaFactor == destinationAlphaFactor;

  @override
  int get hashCode => Object.hash(
        colorOperation,
        sourceColorFactor,
        destinationColorFactor,
        alphaOperation,
        sourceAlphaFactor,
        destinationAlphaFactor,
      );
}

/// One colour attachment of a pass.
final class ColorTarget {
  const ColorTarget({
    required this.texture,
    this.resolveTexture,
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    this.clearValue,
  });

  /// Where the rasteriser writes. Multisampled when [resolveTexture] is set.
  final TextureHandle texture;

  /// Where a multisampled [texture] is resolved to when the pass ends.
  ///
  /// Setting this means [storeAction] must be a resolving one; the backend
  /// checks. Attachments in one pass must agree on sample count, which is the
  /// constraint that makes the scene pass drop multisampling entirely whenever
  /// the surface buffer is wanted.
  final TextureHandle? resolveTexture;

  /// [LoadAction.clear] covers the **whole attachment** however the viewport
  /// and the scissor are set. The shadow atlas depends on that: it loads, and
  /// blanks one tile by drawing inside it.
  final LoadAction loadAction;
  final StoreAction storeAction;

  /// Null clears to transparent black. Linear light, not sRGB, for anything
  /// written into an HDR target.
  final vm.Vector4? clearValue;
}

/// The depth attachment of a pass.
///
/// Far narrower than what the backend offers, and that is the engine's model
/// rather than an omission: every pass here clears depth on entry, discards it
/// on exit, and uses no stencil at all. There is nothing to configure, so
/// nothing is offered. A pass that wanted to *load* depth would be asking for
/// something no pass in this engine has ever asked for, and the interface
/// should grow when one does.
final class DepthTarget {
  const DepthTarget({required this.texture, this.clearValue = 1.0});

  final TextureHandle texture;

  /// The far plane. One under this engine's `[0, 1]` depth convention; a
  /// reversed-Z backend would want zero, which is why it is a parameter.
  final double clearValue;
}

/// Everything a pass draws into.
final class RenderPassDescriptor {
  const RenderPassDescriptor({required this.colors, this.depth});

  /// In shader output order. Two of them exactly once — the scene pass, which
  /// writes lit colour and the surface buffer together.
  ///
  /// A pipeline may declare more outputs than the target has attachments and
  /// the extra is discarded, which is what lets the scene shaders write the
  /// surface buffer unconditionally and this list decide whether anyone is
  /// listening. See RESEARCH.md.
  final List<ColorTarget> colors;

  final DepthTarget? depth;
}

/// A pass that is open, into which draws are recorded.
///
/// This is what a `PassContributor` is handed: it draws into a pass it does not
/// own, so it can record but must not end. Ending belongs to whoever opened it,
/// which is why [CommandEncoder] is a separate type — the overlay stage was
/// once handed a pass whose command buffer had already been submitted, and the
/// split is that trap made unreachable by the type.
abstract interface class PassEncoder {
  /// Where the rasteriser may write.
  void setViewport(ScreenRect rect);

  /// Where fragments survive. Bounds a draw, and — unlike a clear — is honoured
  /// by one.
  void setScissor(ScreenRect rect);

  void setPrimitiveType(PrimitiveType type);
  void setPolygonMode(PolygonMode mode);
  void setCullMode(CullMode mode);
  void setWindingOrder(WindingOrder order);

  void setDepthWrite(bool enabled);
  void setDepthCompare(CompareFunction compare);

  /// Blending for one colour attachment; null switches it off.
  ///
  /// [attachment] is an index into `RenderPassDescriptor.colors`.
  void setBlend(BlendState? state, {int attachment = 0});

  /// Binds the pair of stages the following draws run.
  ///
  /// **Bindings do not survive this call.** A backend is free to drop every
  /// buffer, uniform and texture binding when the pipeline changes — the
  /// flutter_gpu backend must, because its pass replays every binding it has
  /// ever been handed at each draw, keyed by the shader that bound it, and a
  /// stale block from the previous pipeline's shader can land on a slot the
  /// new pipeline reads. Every site in this engine therefore binds what a
  /// draw needs *after* binding its pipeline, never before.
  void bindPipeline(PipelineHandle pipeline);

  /// Binds geometry the device already holds — a mesh, or the one triangle
  /// every full-screen pass draws.
  ///
  /// [slot] is which of the pipeline's [VertexLayoutSpec.buffers] this fills.
  /// Zero is the only slot anything used before instancing, and slots must be
  /// filled densely — see the note on [VertexLayoutSpec].
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount, {int slot = 0});

  /// Binds vertices built this frame.
  ///
  /// The bytes are consumed by the time this returns; where they live until the
  /// GPU has read them is the backend's problem, which is the whole reason this
  /// takes bytes rather than a buffer the caller had to allocate.
  ///
  /// This is where per-instance data goes: it is built every frame from a
  /// simulation, which is exactly what this method is for.
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0});

  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount);

  /// Binds indices built this frame. See [bindVertexData].
  void bindIndexData(ByteData bytes, IndexType type, int indexCount);

  /// Fills the uniform block [blockName] of [shader] from [members] and binds
  /// it. False when the shader has no such block.
  ///
  /// Members the compiled shader does not read are skipped rather than treated
  /// as errors — the unlit model legitimately has no `light_direction` — and a
  /// block the compiler dropped entirely comes back false. That distinction is
  /// load-bearing: binding a block a compiled shader does not have takes the
  /// process down with no Dart stack.
  ///
  /// Every uniform in this engine is a float vector, a matrix or an array of
  /// either, which is why [Float32List] is the only value type. Integer and
  /// boolean uniforms are encoded as floats in the shaders on purpose.
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  );

  /// Binds [texture] to the sampler called [slot] in [shader].
  ///
  /// A shader that declares a sampler must have something bound to it, so
  /// "no texture" is a neutral texture rather than an absent binding — and
  /// binding a slot the compiler dropped is a native crash rather than a no-op,
  /// which is why every call site here is gated on what the material's lighting
  /// model declares.
  /// A null [sampler] means [SamplerOptions.linearRepeat], not the
  /// `SamplerOptions` constructor's own defaults.
  ///
  /// Stated because it was not. Both hardware backends had chosen
  /// `linearRepeat` independently, so they agreed and nobody wrote the rule
  /// down; the third backend read this interface, took the constructor
  /// defaults — nearest and clamp — and every textured picture it drew had
  /// hard seams where the others had soft ones. Two percent of every textured
  /// golden, and it looked like a filtering bug in the new backend rather than
  /// a question the contract had never answered.
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  });

  /// Forgets every binding, leaving rasteriser state alone.
  ///
  /// Needed because bindings outlive a draw: the mesh loop leaves an index
  /// buffer and a pipeline bound, and the next thing in the pass may have a
  /// different vertex layout or no indices at all.
  void clearBindings();

  /// Draws what is bound. Always indexed — there is no non-indexed path in this
  /// engine, which is why the debug overlay keeps an identity index sequence.
  ///
  /// [instanceCount] draws the bound geometry that many times, with the vertex
  /// stage seeing an instance index and reading any attribute whose
  /// [BufferLayout.stepMode] is [VertexStepMode.instance] from a per-instance
  /// buffer. One means an ordinary draw and is the only value anything asked
  /// for before mesh particles.
  ///
  /// **The one count that belongs to the draw rather than to a binding.** Every
  /// other count here travels with the thing it counts — vertices with the
  /// vertex buffer, indices with the index buffer — because that is where it is
  /// known. An instance count is not a property of any buffer: the same mesh and
  /// the same instance buffer can be drawn a hundred times or ten.
  ///
  /// Zero draws nothing, which matters because the number usually comes from a
  /// live population: a particle system with nothing alive should not be a
  /// special case at every call site.
  void draw({int instanceCount = 1});
}

/// A pass somebody opened, and must therefore close.
///
/// Held by whatever created it — a `RenderNode`, or the renderer's own passes.
/// A `PassContributor` gets the [PassEncoder] half instead and cannot submit.
abstract interface class CommandEncoder implements PassEncoder {
  /// Ends the pass and hands it to the queue.
  ///
  /// Passes execute in submission order, and that — not the order passes were
  /// built in — is the ordering the frame graph derives and this engine relies
  /// on. Nothing may be recorded afterwards.
  void submit();
}

/// Recording a render pass, in the engine's own vocabulary.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
/// See
/// `graphics/formats.dart` for why the directory exists.
///
/// ## What this is, and what it deliberately is not
///
/// Every pass this engine draws has the same shape: describe a target, open it,
/// set some rasteriser state, bind a pipeline and some buffers and textures,
/// draw, submit. That shape is what [CommandEncoder] models. It was derived by
/// reading all eight pass sites in the renderer plus the two in the extension
/// API, and **every member here has at least one caller**; anything flutter_gpu
/// offers that no pass in this engine uses — depth range, separate depth
/// load/store actions, non-indexed draws — is absent rather than passed
/// through. An interface member with no user is a guess about a second
/// backend, and this file was written when there was no second backend to
/// check a guess against.
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
/// The stencil was on it too, and left it the same way: the x-ray stage marks
/// where an enemy is visible and paints a silhouette where it is not, and
/// that is a stencil test or nothing. It arrived whole — flutter_gpu's
/// configuration, reference and per-face split, under [PassEncoder.setStencil]
/// and [PassEncoder.setStencilReference] — because the two consumers behind
/// it, a selection outline and a portal, each want a different corner of the
/// same eight operations, and a member per corner would be three interfaces
/// for one piece of hardware.
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
///
/// [ScreenRect], [BlendState] and the descriptor types a pass is opened with
/// are `render_pass_descriptor.dart`, re-exported from here — this file is the
/// two verbs, [PassEncoder] and [CommandEncoder], and everything above is
/// about them.
library;

import 'dart:typed_data';

import 'formats.dart';
import 'geometry_buffer.dart';
import 'render_pass_descriptor.dart';
import 'sampler.dart';
import 'shader.dart';
import 'texture.dart';
import 'vertex_layout_spec.dart';

export 'render_pass_descriptor.dart';

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

  /// How the following draws assemble their vertices.
  ///
  /// **A backend need not have all five, and one here does not.** The software
  /// rasteriser draws [PrimitiveType.triangle] and [PrimitiveType.line] and
  /// throws an [UnsupportedError] for the other three — from the draw rather
  /// than from here, because that is where it finds out. There is no capability
  /// to ask first, unlike wireframe or the stencil: nothing in this engine has
  /// ever wanted a strip or a point, so no query would have had a caller. What
  /// the contract does promise is the refusal — a backend may not assemble one
  /// primitive as another, because three points drawn as a triangle is a
  /// picture nobody asked for and no error anywhere.
  ///
  /// Held by the conformance check
  /// `every primitive type is assembled as itself or refused`, which draws all
  /// five and compares how much each one painted.
  void setPrimitiveType(PrimitiveType type);

  /// Filled or drawn as edges. Ask `GraphicsDevice.supportsWireframe` before
  /// naming [PolygonMode.line]: a backend that cannot draw it throws an
  /// [UnsupportedError] rather than filling.
  void setPolygonMode(PolygonMode mode);
  void setCullMode(CullMode mode);
  void setWindingOrder(WindingOrder order);

  void setDepthWrite(bool enabled);
  void setDepthCompare(CompareFunction compare);

  /// The stencil test for the draws that follow.
  ///
  /// [front] applies to front-facing triangles and, when [back] is null, to
  /// back-facing ones as well — which is what every caller in this engine
  /// wants, and why the second is optional rather than required. A pass
  /// starts with [StencilState.disabled] on both faces, whatever the previous
  /// pass left, and a caller that turned the test on says
  /// `setStencil(StencilState.disabled)` when it is done: on a backend whose
  /// setters are global context state, the next draw inherits this one's.
  ///
  /// Meaningful only against a depth attachment whose format
  /// `TextureFormatStencil.hasStencil` says carries one. Ask
  /// `GraphicsDevice.supportsStencil` before configuring it at all.
  void setStencil(StencilState front, {StencilState? back});

  /// The value the stencil test compares against and
  /// [StencilOperation.setToReferenceValue] stores. Eight bits; zero until
  /// set.
  ///
  /// A wider value keeps its low eight bits and loses the rest, on every
  /// backend, through [StencilState.narrowReference] — see it for why the
  /// three would otherwise each answer differently.
  void setStencilReference(int value);

  /// Blending for one colour attachment; null switches it off.
  ///
  /// [attachment] is an index into `RenderPassDescriptor.colors`.
  ///
  /// **One backend of the three honours the index, and that is a term of this
  /// contract rather than a bug in the other two.** Impeller passes it to
  /// flutter_gpu's `colorAttachmentIndex`; WebGL2 would need
  /// `EXT_draw_buffers_indexed`, which is optional there, and the software
  /// rasteriser keeps one blend state for the pass. Both of those set
  /// attachment zero whatever index is named — so a caller that sets one state
  /// on attachment zero and a different one on attachment one gets its second
  /// call applied to the first attachment on two backends out of three, with no
  /// error and a plausible picture.
  ///
  /// Which is why the engine has exactly one caller that passes an index — the
  /// MRT probe, switching blending *off* on attachment one when it is already
  /// off on attachment zero, so the substitution is a no-op. Anything wanting
  /// two attachments to blend *differently* needs the extension and a
  /// capability query beside it, and neither exists; write the state you want
  /// on attachment zero and treat the index as a hint until they do.
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
  /// **A block the compiler dropped is false; a block missing a member the
  /// caller named throws.** The two look alike and are not: a compiler drops a
  /// whole block nothing reads, which is ordinary and which the caller is
  /// entitled to shrug at, but a block that exists *without* one of the members
  /// written into it means the two ends disagree about its shape. Zeros are a
  /// plausible value for most of what goes through here — a shadow strength of
  /// zero is a scene with no shadows and no error — so silence there is
  /// indistinguishable from working.
  ///
  /// That distinction is load-bearing in the other direction too: binding a
  /// block a compiled shader does not have takes the process down with no Dart
  /// stack, which is why the block case is a return value rather than a throw.
  ///
  /// **This doc comment used to say the opposite**, on the grounds that "the
  /// unlit model legitimately has no `light_direction`". It has one: `FragInfo`
  /// is declared once, in `lib/surface.glsl`, and every shader that reads any
  /// of it includes the whole block. The web backend threw all along and drew
  /// every golden, which is what settled it — the same bundle was a named
  /// exception in a browser and a quietly wrong picture on a phone.
  ///
  /// A backend with no reflection of its shaders cannot tell the two apart and
  /// is not asked to: the software rasteriser hands the block to a Dart shader
  /// that looks up what it needs by name, so a member nobody reads costs a map
  /// entry. What is forbidden is a backend that *can* see the disagreement and
  /// says nothing.
  ///
  /// **So the return value is `true` unconditionally on such a backend**, and a
  /// caller branching on it must know that. There is nothing for the software
  /// rasteriser to answer `false` about — a Dart stage declares no blocks, so
  /// "the compiler dropped this one" is not a state it has — and returning
  /// `false` for a block it had merely never been handed would be inventing an
  /// answer. The value is therefore a report from the backends that reflect and
  /// a constant from the one that does not, which is the honest shape and not a
  /// forgotten branch. The conformance check
  /// `a block missing a member the caller named is refused` uses exactly this
  /// to tell the two kinds of backend apart before holding either to the member
  /// rule.
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

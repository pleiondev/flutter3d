/// The value types a [TextureHandle] and a [PipelineHandle] carry on this
/// backend, and what shader reflection told [WebGlDevice.createPipeline]
/// about a linked program.
///
/// Split out of `webgl_device.dart` because these have no state of their own
/// to hide — they are the shapes `WebGlTexture`/`WebGlProgram`/etc. plugged
/// into a `TextureHandle.backend` or `PipelineHandle.backend`, read back out
/// by [WebGlDevice] and [WebGlEncoder] on the other side.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

/// The name every refusal from this backend gives it —
/// `UnsupportedCapabilityException.backend`.
const String webglBackendName = 'WebGL2';

/// What [operation] throws for a request this backend has the feature for
/// and still cannot honour — a format WebGL2 has no layout for, a copy
/// between two kinds of buffer it keeps apart — since 1.0.0-rc.1: the
/// HAL's `DeviceResourceException`, in the words every backend refuses with,
/// where it was an untyped `UnsupportedError`.
DeviceResourceException webglRefusal(String operation, String reason) =>
    DeviceResourceException(
      operation: operation,
      backend: webglBackendName,
      reason: reason,
    );

/// What a [TextureHandle] carries on this backend.
///
/// Either a texture or a renderbuffer: WebGL2 cannot sample a multisampled
/// attachment, so a multisampled target is a renderbuffer and is resolved by
/// blitting. `deviceTransient` — Impeller's tile memory — has no equivalent and
/// becomes an ordinary renderbuffer, which is the closest honest thing: not
/// sampleable, attachment only.
final class WebGlTexture {
  /// A texture over [texture] or, for a target that cannot be sampled,
  /// [renderbuffer], bound as [target].
  WebGlTexture({
    this.texture,
    this.renderbuffer,
    this.target = web.WebGLRenderingContext.TEXTURE_2D,
    this.rendered = false,
  });

  /// The texture object, or null when this is a renderbuffer.
  final web.WebGLTexture? texture;

  /// The renderbuffer of a multisampled or transient target, resolved by a
  /// blit; null for a sampleable texture.
  final web.WebGLRenderbuffer? renderbuffer;

  /// Whether this texture's contents were drawn rather than handed over.
  ///
  /// The two are stored the opposite way up on this backend, and there is no
  /// setting that makes them agree. `texImage2D` puts the first row it is given
  /// at texture coordinate zero, so an uploaded image has its top there, which
  /// is what every glTF UV expects. Rendering puts row zero at the *bottom*,
  /// because that is where GL's framebuffer origin is — the engine already
  /// knows this and states it as [FramebufferOrigin.bottomLeft], which is why
  /// `toFramebufferOrigin` exists for the shadow face matrices.
  ///
  /// [GraphicsDevice.readPixels] is the one place that has to tell them apart:
  /// it promises rows from the top of the picture, and only one of the two
  /// kinds needs turning over to keep that promise.
  final bool rendered;

  /// What this is bound as: `TEXTURE_2D`, or `TEXTURE_CUBE_MAP` for a cube.
  ///
  /// Carried rather than assumed at each call site. Every `bindTexture`,
  /// `texParameteri` and upload in this file used to name `TEXTURE_2D`
  /// literally, and a cube bound as a 2D texture is not an error — it is a
  /// different texture object, so the draw samples nothing and shows black.
  final int target;

  /// Whether a stage can sample this: false for a renderbuffer.
  bool get isSampleable => texture != null;

  /// Whether the last bind set a comparison or a level-of-detail clamp on
  /// this texture — state of the texture in GL, not of the bind.
  ///
  /// **State, so mutable.** A bind with a plain sampler puts the defaults
  /// back only when this says something else is there, so the samplers every
  /// pass before 1.0 bound issue exactly the calls they always did.
  bool extendedSampling = false;
}

/// A sampler of a linked program: the texture unit it owns, and the texture
/// target its GLSL type samples — `TEXTURE_2D`, `TEXTURE_CUBE_MAP`,
/// `TEXTURE_2D_ARRAY` or `TEXTURE_3D` — which is the target a draw clears it
/// on when it was left unbound.
typedef WebGlSampler = ({int unit, int target});

/// What a `StorageBuffer` made by `GraphicsDevice.createBuffer` carries on
/// this backend.
///
/// **WebGL2 types a buffer at its first binding, for life**: one first bound
/// to `ELEMENT_ARRAY_BUFFER` holds indices and may be bound nowhere else but
/// the two copy targets, and one bound anywhere else never becomes an index
/// buffer. [elementArray] is which of the two this one is, decided from its
/// usage when it was made, so every later binding can be checked before the
/// driver refuses it with an `INVALID_OPERATION` nobody reads.
final class WebGlBuffer {
  /// A buffer over [buffer], typed for life by [elementArray].
  WebGlBuffer(this.buffer, {required this.elementArray});

  /// The GL buffer object.
  final web.WebGLBuffer buffer;

  /// True when the buffer holds indices: it is bound to `ELEMENT_ARRAY_BUFFER`
  /// and the copy targets and nowhere else.
  final bool elementArray;

  /// Whether a `mapBuffer` mapping of it is outstanding. State: every copy
  /// and write refuses a mapped buffer, as the contract says a pass must.
  bool mapped = false;
}

/// What a `QuerySet` carries on this backend: one GL query object per
/// index, and which of them a pass has actually written — an unwritten
/// query reads zero, and asking GL for the result of one that never began
/// is `INVALID_OPERATION`.
final class WebGlQuerySet {
  /// A set over [queries], none of them written yet.
  WebGlQuerySet(this.queries);

  /// One GL query per index; null once the set is released.
  final List<web.WebGLQuery?> queries;

  /// The indices a pass has begun a query on; the rest read zero.
  final Set<int> written = <int>{};
}

/// What a [PipelineHandle] carries when the pair would not link: the pair,
/// to link again at the next bind, and the program once a link takes.
///
/// A driver's linker is not obliged to agree with every other driver's, and
/// a pair one browser refuses threw from `createPipeline` and failed every
/// frame. It is reported to `GraphicsDevice.pipelineRefusals` instead, and
/// the encoder's bind links it again until the record says it is left
/// refused.
final class WebGlUnlinkedPipeline {
  /// The refused pair [vertex] and [fragment], with the [layout] the pipeline
  /// was asked for.
  WebGlUnlinkedPipeline(this.vertex, this.fragment, this.layout);

  /// The vertex stage the link refused.
  final ShaderHandle vertex;

  /// The fragment stage the link refused.
  final ShaderHandle fragment;

  /// The vertex layout the pipeline was made with, or null to take it from the
  /// shader.
  final VertexLayoutDescriptor? layout;

  /// The handle a later link made, kept so the next bind does not link
  /// again, and given back with the handle that carries this; null until a
  /// link takes.
  PipelineHandle? relinked;

  /// The program [relinked] carries, or null.
  WebGlProgram? get linked => relinked?.backend as WebGlProgram?;
}

/// A linked program plus what reflection told us about it.
final class WebGlProgram {
  /// A linked [program] with its reflection; the lists and maps are copied
  /// unmodifiable.
  WebGlProgram(
    this.program,
    List<WebGlAttribute> attributes,
    Map<String, WebGlBlock> blocks,
    Map<String, WebGlSampler> samplers, {
    this.layout,
    this.fragmentOutputs,
  }) : attributes = List<WebGlAttribute>.unmodifiable(attributes),
       blocks = Map<String, WebGlBlock>.unmodifiable(blocks),
       samplers = Map<String, WebGlSampler>.unmodifiable(samplers);

  /// The linked GL program object.
  final web.WebGLProgram program;

  /// What the pipeline was built with, or null to keep guessing from the
  /// shader. See `WebGlDevice.createPipeline` and `WebGlEncoder._describeVertices`.
  final VertexLayoutDescriptor? layout;

  /// Vertex attributes in location order, with their float component counts.
  ///
  /// **This is the gap the HAL inherited from flutter_gpu, closed here.**
  /// `PassEncoder.bindVertexBuffer` hands over a buffer and a vertex count and
  /// nothing else: flutter_gpu takes the layout from the order of `in`
  /// declarations in the vertex shader, so the HAL never had to carry one.
  /// WebGL2 will not infer it — every attribute needs an explicit
  /// `vertexAttribPointer`.
  ///
  /// It is reconstructible without changing the contract, because the same
  /// thing that defines the layout on flutter_gpu defines it here: the shader.
  /// Attributes are read back by location, each contributes its component
  /// count, and the vertex is their sum interleaved in that order — which is
  /// exactly the convention `VertexLayout` in the engine already documents.
  /// So the seam survives, but only because both backends agree to take the
  /// layout from the shader. A backend that wanted an explicit descriptor
  /// would need the HAL to grow one.
  final List<WebGlAttribute> attributes;

  /// Uniform block name to its index and size.
  final Map<String, WebGlBlock> blocks;

  /// Sampler uniform name to the texture unit it owns for the life of the
  /// program, and whether it samples a cube. See `_reflectSamplers`.
  final Map<String, WebGlSampler> samplers;

  /// The colour locations the fragment stage writes, or null where its source
  /// could not be read for them, in which case every attachment is drawn to.
  ///
  /// **A pass may carry more colour attachments than a stage writes, and GL
  /// ES refuses the draw for it.** The temporal pass draws into the colour
  /// and the velocity target together, and a hashed splat's fragment stage
  /// writes only the colour. With both draw buffers active WebGL2 rejects
  /// every such draw as `INVALID_OPERATION` ("active draw buffers with
  /// missing fragment shader outputs") and draws nothing, so the encoder
  /// turns the buffers this set leaves out to `NONE` for the draw, which
  /// leaves those attachments as they were, as the other backends do.
  final Set<int>? fragmentOutputs;

  /// The floats one interleaved vertex takes: every attribute's component
  /// count, summed.
  int get vertexFloats {
    var total = 0;
    for (final a in attributes) {
      total += a.componentCount;
    }
    return total;
  }
}

/// A vertex attribute of a linked program, as reflection reported it.
final class WebGlAttribute {
  /// The attribute at [location], [componentCount] floats wide.
  const WebGlAttribute(this.location, this.componentCount);

  /// The attribute's location, which `vertexAttribPointer` takes.
  final int location;

  /// How many floats the attribute reads, one to four.
  final int componentCount;
}

/// A uniform block of a linked program, as reflection reported it.
final class WebGlBlock {
  /// The block at [index], [sizeInBytes] long, with its members at [offsets].
  const WebGlBlock(this.index, this.sizeInBytes, this.offsets);

  /// The block's index in the program, as `getUniformBlockIndex` answers.
  final int index;

  /// The block's data size in bytes, std140 padding included.
  final int sizeInBytes;

  /// Member name to byte offset, as std140 laid it out. Reflected rather than
  /// computed: the spec's packing rules are the driver's to apply.
  final Map<String, int> offsets;
}

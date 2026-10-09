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
/// `UnsupportedCapability.backend`.
const String webglBackendName = 'WebGL2';

/// What a [TextureHandle] carries on this backend.
///
/// Either a texture or a renderbuffer: WebGL2 cannot sample a multisampled
/// attachment, so a multisampled target is a renderbuffer and is resolved by
/// blitting. `deviceTransient` — Impeller's tile memory — has no equivalent and
/// becomes an ordinary renderbuffer, which is the closest honest thing: not
/// sampleable, attachment only.
final class WebGlTexture {
  WebGlTexture({
    this.texture,
    this.renderbuffer,
    this.target = web.WebGLRenderingContext.TEXTURE_2D,
    this.rendered = false,
  });

  final web.WebGLTexture? texture;
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
  WebGlBuffer(this.buffer, {required this.elementArray});

  final web.WebGLBuffer buffer;
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
  WebGlQuerySet(this.queries);

  final List<web.WebGLQuery?> queries;
  final Set<int> written = <int>{};
}

/// A linked program plus what reflection told us about it.
final class WebGlProgram {
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

  int get vertexFloats {
    var total = 0;
    for (final a in attributes) {
      total += a.componentCount;
    }
    return total;
  }
}

final class WebGlAttribute {
  const WebGlAttribute(this.location, this.componentCount);
  final int location;
  final int componentCount;
}

final class WebGlBlock {
  const WebGlBlock(this.index, this.sizeInBytes, this.offsets);
  final int index;
  final int sizeInBytes;

  /// Member name to byte offset, as std140 laid it out. Reflected rather than
  /// computed: the spec's packing rules are the driver's to apply.
  final Map<String, int> offsets;
}

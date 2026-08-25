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
}

/// A linked program plus what reflection told us about it.
final class WebGlProgram {
  WebGlProgram(this.program, this.attributes, this.blocks, this.samplers,
      {this.layout});

  final web.WebGLProgram program;

  /// What the pipeline was built with, or null to keep guessing from the
  /// shader. See `WebGlDevice.createPipeline` and `WebGlEncoder._describeVertices`.
  final VertexLayoutSpec? layout;

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

  /// Sampler uniform name to its texture unit.
  final Map<String, int> samplers;

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

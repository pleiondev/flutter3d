/// Creating and releasing the GL objects that outlive a single pass.
///
/// **Persistent, not transient.** The buffers a pass makes for `submit`-time
/// geometry are already deleted at the end of the pass that made them — see
/// `WebGlEncoder.submit` — because their lifetime is the pass. A texture from
/// [webglCreateTexture] or [webglCreateCubeTextureFromPixels] has no such
/// moment: WebGL2 objects are explicitly deletable, unlike flutter_gpu's
/// `Texture`, so nothing frees these unless something tracks them and calls
/// `gl.deleteTexture`/`gl.deleteRenderbuffer`/`gl.deleteBuffer` itself. That
/// tracking and the eventual deletion are what this file is for;
/// [WebGlDevice] owns the lists these functions are handed and is the only
/// caller.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_formats.dart';
import 'webgl_types.dart';

/// Wraps [backend] and [spec] into the [TextureHandle] every creation path
/// here returns.
TextureHandle webglTextureHandle(WebGlTexture backend, RenderTargetSpec spec) =>
    TextureHandle(
      backend: backend,
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );

/// [faces] in `+X, −X, +Y, −Y, +Z, −Z` order as one cube texture, or null when
/// they disagree about size or count. See `GraphicsDevice.createCubeTextureFromPixels`.
TextureHandle? webglCreateCubeTextureFromPixels(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures, {
  required int size,
  required TextureFormat format,
  required List<ByteData> faces,
  List<List<ByteData>>? mipLevels,
}) {
  if (faces.length != 6) return null;
  for (final face in faces) {
    // RGBA8, four bytes a texel, as everywhere the CPU uploads.
    if (face.lengthInBytes != size * size * 4) return null;
  }
  // Checked before a single byte is uploaded: `texStorage2D` fixes the level
  // count immutably, so a chain that turns out to be malformed halfway through
  // leaves a texture that cannot be corrected, only thrown away.
  final levels = mipLevels ?? const <List<ByteData>>[];
  var check = size;
  for (final level in levels) {
    if (level.length != 6) return null;
    check = check > 1 ? check >> 1 : 1;
    for (final face in level) {
      if (face.lengthInBytes != check * check * 4) return null;
    }
  }

  final texture = gl.createTexture();
  if (texture != null) persistentTextures.add(texture);
  gl.bindTexture(web.WebGLRenderingContext.TEXTURE_CUBE_MAP, texture);
  gl.texStorage2D(
    web.WebGLRenderingContext.TEXTURE_CUBE_MAP,
    1 + levels.length,
    textureFormatToGl(format),
    size,
    size,
  );

  // The six face targets are **consecutive constants** starting at
  // `TEXTURE_CUBE_MAP_POSITIVE_X`, in the order +X, −X, +Y, −Y, +Z, −Z — the
  // same order the interface documents and the same order Impeller's slices
  // take. That the two agree is what the conformance check is for; that they
  // are consecutive is what makes this a loop rather than a table.
  void upload(int level, int side, List<ByteData> six) {
    for (var i = 0; i < 6; i++) {
      final bytes = six[i];
      gl.texSubImage2D(
        web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + i,
        level,
        0,
        0,
        side.toJS,
        side.toJS,
        web.WebGLRenderingContext.RGBA.toJS,
        web.WebGLRenderingContext.UNSIGNED_BYTE,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      );
    }
  }

  upload(0, size, faces);
  var side = size;
  for (var level = 0; level < levels.length; level++) {
    side = side > 1 ? side >> 1 : 1;
    upload(level + 1, side, levels[level]);
  }

  return TextureHandle(
    backend: WebGlTexture(
      texture: texture,
      target: web.WebGLRenderingContext.TEXTURE_CUBE_MAP,
    ),
    width: size,
    height: size,
    format: format,
    type: TextureType.textureCube,
  );
}

/// A texture or renderbuffer matching [spec], with a chain [levels] deep.
/// See `GraphicsDevice.createTexture`.
TextureHandle webglCreateTexture(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures,
  List<web.WebGLRenderbuffer> persistentRenderbuffers,
  RenderTargetSpec spec, {
  int levels = 1,
  bool rendered = true,
}) {
  final internal = textureFormatToGl(spec.format);
  if (spec.sampleCount > 1 || spec.storageMode == StorageMode.deviceTransient) {
    // Multisampled or attachment-only: a renderbuffer. Cannot be sampled,
    // which is what `deviceTransient` already promises on the other backend.
    final buffer = gl.createRenderbuffer();
    if (buffer != null) persistentRenderbuffers.add(buffer);
    gl.bindRenderbuffer(web.WebGLRenderingContext.RENDERBUFFER, buffer);
    if (spec.sampleCount > 1) {
      gl.renderbufferStorageMultisample(
        web.WebGLRenderingContext.RENDERBUFFER,
        spec.sampleCount,
        internal,
        spec.width,
        spec.height,
      );
    } else {
      gl.renderbufferStorage(
        web.WebGLRenderingContext.RENDERBUFFER,
        internal,
        spec.width,
        spec.height,
      );
    }
    return webglTextureHandle(
      WebGlTexture(renderbuffer: buffer, rendered: rendered),
      spec,
    );
  }

  final texture = gl.createTexture();
  if (texture != null) persistentTextures.add(texture);
  gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, texture);
  gl.texStorage2D(
    web.WebGLRenderingContext.TEXTURE_2D,
    levels,
    internal,
    spec.width,
    spec.height,
  );
  return webglTextureHandle(
    WebGlTexture(texture: texture, rendered: rendered),
    spec,
  );
}

/// A texture already holding [pixels] and, optionally, [mipLevels] below it.
/// See `GraphicsDevice.createTextureFromPixels`.
TextureHandle? webglCreateTextureFromPixels(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures,
  List<web.WebGLRenderbuffer> persistentRenderbuffers, {
  required int width,
  required int height,
  required TextureFormat format,
  required ByteData pixels,
  List<ByteData>? mipLevels,
}) {
  // RGBA8 is the only format the engine uploads from the CPU, and four bytes
  // a texel is the whole of the size question here — WebGL has no padding to
  // ask about, unlike Impeller's base mip size.
  if (pixels.lengthInBytes != width * height * 4) return null;

  // **Allocated with the whole chain up front.** `texStorage2D` fixes the
  // number of levels for the texture's life, and a level written into a
  // texture allocated for one is an INVALID_OPERATION — dropped, with the
  // frame coming back looking merely unfiltered. So the count is decided
  // here and the levels are filled afterwards.
  final levels = mipLevels == null ? 1 : mipLevels.length + 1;
  final handle = webglCreateTexture(
    gl,
    persistentTextures,
    persistentRenderbuffers,
    RenderTargetSpec(width: width, height: height, format: format),
    levels: levels,
    // Its rows come from the caller, not from a draw, so they are already the
    // way up the engine states an image. See [WebGlTexture.rendered].
    rendered: false,
  );
  final backend = handle.backend as WebGlTexture;
  gl.bindTexture(web.WebGLRenderingContext.TEXTURE_2D, backend.texture);

  void upload(int level, int w, int h, ByteData bytes) {
    gl.texSubImage2D(
      web.WebGLRenderingContext.TEXTURE_2D,
      level,
      0,
      0,
      w.toJS,
      h.toJS,
      web.WebGLRenderingContext.RGBA.toJS,
      web.WebGLRenderingContext.UNSIGNED_BYTE,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
    );
  }

  upload(0, width, height, pixels);
  if (mipLevels != null) {
    var w = width;
    var h = height;
    for (var i = 0; i < mipLevels.length; i++) {
      w = w > 1 ? w >> 1 : 1;
      h = h > 1 ? h >> 1 : 1;
      upload(i + 1, w, h, mipLevels[i]);
    }
    // Without this the texture is incomplete for any minifying filter and
    // samples as black — the same failure mode as the float-linear extension,
    // and just as silent. `glGenerateMipmap` is deliberately not called: the
    // levels are the engine's, identical on three backends, and generating a
    // second set here would put this backend one filter away from the others.
    gl.texParameteri(
      web.WebGLRenderingContext.TEXTURE_2D,
      web.WebGL2RenderingContext.TEXTURE_MAX_LEVEL,
      mipLevels.length,
    );
  }
  return handle;
}

/// Geometry uploaded once and bound many times, until the device that made it
/// is disposed. See `GraphicsDevice.uploadGeometry`.
GeometryBuffer webglUploadGeometry(
  web.WebGL2RenderingContext gl,
  List<web.WebGLBuffer> persistentBuffers,
  ByteData bytes,
  GeometryUsage usage,
) {
  final buffer = gl.createBuffer();
  if (buffer != null) persistentBuffers.add(buffer);
  // **WebGL binds a buffer to its target for life.** One bound to
  // ARRAY_BUFFER can never afterwards be bound to ELEMENT_ARRAY_BUFFER, and
  // the attempt is an INVALID_OPERATION: the draw is dropped and the frame
  // comes back the clear colour with nothing logged.
  //
  // There is no neutral target to park it on either — COPY_WRITE_BUFFER
  // commits it just as ARRAY_BUFFER does, which is what the harness found the
  // hard way. So [usage] has to be known here, and that is why the contract
  // carries it.
  final target = switch (usage) {
    GeometryUsage.vertices => web.WebGLRenderingContext.ARRAY_BUFFER,
    GeometryUsage.indices => web.WebGLRenderingContext.ELEMENT_ARRAY_BUFFER,
  };
  gl.bindBuffer(target, buffer);
  gl.bufferData(
    target,
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
    web.WebGLRenderingContext.STATIC_DRAW,
  );
  return GeometryBuffer(
    backend: buffer!,
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
  );
}

/// Deletes every tracked texture, renderbuffer and buffer, and empties the
/// three lists. See `GraphicsDevice.dispose`.
void webglDisposePersistentResources(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures,
  List<web.WebGLRenderbuffer> persistentRenderbuffers,
  List<web.WebGLBuffer> persistentBuffers,
) {
  for (final texture in persistentTextures) {
    gl.deleteTexture(texture);
  }
  persistentTextures.clear();
  for (final buffer in persistentRenderbuffers) {
    gl.deleteRenderbuffer(buffer);
  }
  persistentRenderbuffers.clear();
  for (final buffer in persistentBuffers) {
    gl.deleteBuffer(buffer);
  }
  persistentBuffers.clear();
}

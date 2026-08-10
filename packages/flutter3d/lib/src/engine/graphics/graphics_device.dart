/// The backend, as a value.
///
/// **Nothing in `graphics/` may import `flutter_gpu`** —
/// `test/graphics_is_backend_free_test.dart` enforces it.
library;

import 'dart:typed_data';

import 'command_encoder.dart';
import 'formats.dart';
import 'geometry_buffer.dart';
import 'render_target_pool.dart';
import 'shader.dart';

/// Everything the engine needs a graphics backend for.
///
/// **A value, never a global.** flutter_gpu's own device is a singleton —
/// `gpu.gpuContext` — and reaching it from a top-level function was how the
/// renderer and its nodes made textures and command buffers. Nothing above the
/// backend does that any more: a device arrives through `Renderer.create` and
/// travels to the passes in `NodeFrame` and `ContributorFrame`. Two things
/// depend on that being true. A backend cannot be a separate package while the
/// core reaches into it, and a **fake** backend — the only way a node's drawing
/// is ever testable off a device — cannot displace a singleton.
///
/// It implements [TextureAllocator] rather than owning a second way to make a
/// texture, so `RenderTargetPool` takes the device directly and every texture
/// in the engine is created by one rule.
abstract interface class GraphicsDevice implements TextureAllocator {
  /// The colour format this device prefers.
  ///
  /// A property of the running context and not a constant: the answer differs
  /// by platform, which is the whole point of asking.
  TextureFormat get defaultColorFormat;

  /// The depth/stencil format this device prefers. Legitimately
  /// [TextureFormat.unknown] on a context that has none.
  TextureFormat get defaultDepthStencilFormat;

  /// Whether a multisampled offscreen target is available at all.
  bool get supportsOffscreenMsaa;

  /// The compiled bundle this device was built with.
  ///
  /// On the device rather than on `RenderServices` because it is a property of
  /// the backend, not of the renderer: it is where a [ShaderHandle] comes from,
  /// and a handle from one device means nothing to another.
  ShaderLibrary get shaders;

  /// Links two stages into something that can be bound.
  ///
  /// Expensive — it compiles and links on the backend — so callers cache. The
  /// engine keys its cache on the *pair*, because a skinned mesh has a different
  /// vertex layout and the layout comes from the vertex stage alone.
  PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment);

  /// Uploads geometry that will outlive the frame.
  ///
  /// For the two buffers the renderer keeps: the full-screen triangle, and the
  /// identity index sequence the debug overlay draws through. Per-frame
  /// geometry does not come here — see `PassEncoder.bindVertexData`.
  GeometryBuffer uploadGeometry(ByteData bytes);

  /// Tells the backend a new frame is starting.
  ///
  /// The one member here that is about time rather than about resources, and it
  /// exists because every backend has *something* that has to rotate: on
  /// flutter_gpu it is the ring of per-frame uniform allocators, which cannot be
  /// reset in place because `submit` is asynchronous and the GPU may still be
  /// reading the frame before last. A backend with nothing to rotate implements
  /// this as nothing.
  void beginFrame();

  /// Opens a pass and returns the encoder that records into it.
  ///
  /// The returned encoder must be submitted; see [CommandEncoder.submit].
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor);
}

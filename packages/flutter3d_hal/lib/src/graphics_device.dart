/// The backend, as a value.
///
/// **Nothing in this package may import `flutter_gpu`** —
/// `test/no_backend_test.dart` enforces it.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'command_encoder.dart';
import 'formats.dart';
import 'geometry_buffer.dart';
import 'render_target_pool.dart';
import 'shader.dart';
import 'texture.dart';

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
  /// Every mesh in the engine comes through here, plus the two buffers the
  /// renderer keeps: the full-screen triangle and the identity index sequence
  /// the debug overlay draws through. Per-frame geometry does not — see
  /// `PassEncoder.bindVertexData`.
  ///
  /// [usage] is required and cannot be defaulted; see [GeometryUsage] for the
  /// backend that binds a buffer to its target permanently.
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage);

  /// Creates a texture already holding [pixels].
  ///
  /// One call rather than create-then-write, because that is what the engine
  /// means every time: a procedural texture and a decoded PNG are both "make me
  /// a texture out of these bytes", and a two-step version would leave a window
  /// in which a texture exists holding nothing. Whether the backend needs a
  /// staging copy, a particular storage mode or a flipped origin to get the
  /// bytes there is its own business.
  ///
  /// Null when [pixels] is not the size the device wants for a texture of that
  /// description — which is how a decoder that disagreed about the dimensions
  /// degrades to "no texture" rather than taking the whole model down.
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
  });

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

  /// A widget that shows the finished frame.
  ///
  /// **This used to be `ui.Image imageOf(...)`, and that was an Impeller shape
  /// wearing a neutral name.** On flutter_gpu a texture becomes a `ui.Image`
  /// for free — `Texture.asImage()` hands Flutter the same GPU allocation — so
  /// "the frame is an image" looked like a fact about rendering rather than
  /// about one API.
  ///
  /// It is not. A WebGL2 backend has no such path: the only route to a
  /// `ui.Image` is `readPixels` into CPU memory and `decodeImageFromPixels`
  /// back onto the GPU. Measured at the golden suite's own 480x360, that is
  /// 17.7 ms per frame against a 16.7 ms budget for the whole frame, and
  /// `readPixels` is 347 us of it — the cost is putting the pixels *back*. A
  /// contract that demands an image demands that round trip, so it does not
  /// describe a renderer on that backend at all.
  ///
  /// What both backends can do is produce something Flutter will show:
  /// flutter_gpu wraps its image, and a WebGL2 backend hands over the canvas it
  /// drew into, composited by the browser. So the contract asks for the widget
  /// and lets each answer in its own way.
  ///
  /// The cost of the honesty, stated once: on a backend that presents a
  /// platform view, the frame is composited by something other than Flutter,
  /// so it cannot be arbitrarily transformed, blended or layered by the widget
  /// tree the way an image can. [fit] is the part of that which every caller
  /// actually used, and it is offered because both can honour it.
  /// [quality] defaults to none because a rendered frame is already at the
  /// resolution it will be shown at, and smoothing one is a way to lose detail
  /// the renderer just paid for. It is a parameter rather than a constant only
  /// because the letterboxed golden window scales.
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  });

  /// The texture's pixels: **premultiplied** RGBA8, row-major from the
  /// top-left.
  ///
  /// One layout, named, because the only thing anybody does with these is
  /// compare them against pixels that came from somewhere else — and two sides
  /// of a comparison that disagree about premultiplication differ on every
  /// translucent texel while looking identical on screen.
  ///
  /// Separate from [present] because it is a different question with a
  /// different cost. Presenting happens every frame and must be nearly free;
  /// reading back happens when something wants to *look* at what a pass wrote —
  /// the golden suite comparing a frame, the MRT probe checking that a second
  /// attachment was honoured — and is affordable on both backends precisely
  /// because it stops at CPU memory.
  ///
  /// Null when the texture cannot be read: `deviceTransient` lives in tile
  /// memory, and there is nothing there to read once the pass has ended.
  Future<ByteData?> readPixels(TextureHandle texture);
}

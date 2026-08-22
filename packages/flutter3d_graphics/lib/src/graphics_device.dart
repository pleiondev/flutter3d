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
import 'vertex_layout_spec.dart';

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

  /// Where row zero of a render target is.
  ///
  /// Asked because a shader sampling a texture the engine drew has to be told:
  /// see `toFramebufferOrigin`. The engine's own frames are presented and read
  /// back consistently by each backend, so this is not about the picture — it
  /// is about the maps the lighting pass looks into.
  FramebufferOrigin get framebufferOrigin;

  /// What this backend's clip space maps depth onto.
  ///
  /// Asked rather than assumed. The engine builds its projections for
  /// [DepthRange.zeroToOne] because that is what it was written against, and
  /// corrects at the boundary for a backend that says otherwise — which is
  /// cheaper and far easier to check than a second projection path.
  DepthRange get depthRange;

  /// The format to render high dynamic range colour into.
  ///
  /// The engine renders in linear HDR and tone maps at the end, so it needs a
  /// colour target with range above one. Which format that is belongs to the
  /// backend: `RGBA16F` is the obvious answer and is not free everywhere —
  /// WebGL2 accepts it as a texture format and refuses to render to it until
  /// `EXT_color_buffer_float` is asked for, which is a thing only a backend can
  /// know to do.
  ///
  /// Asked rather than assumed, because the failure when it is wrong is an
  /// incomplete framebuffer: every draw silently discarded, no error raised,
  /// and a frame of transparent black with every counter reporting success.
  TextureFormat get hdrColorFormat;

  /// Samples to use for multisampled targets, or 1 for none.
  ///
  /// One number rather than a boolean, because "does MSAA work" and "how much"
  /// are different questions and the engine had only been asking the first —
  /// then hardcoding four. A backend that supports multisampling at a different
  /// count, or that would rather not, has somewhere to say so.
  int get preferredSampleCount;

  /// Whether a multisampled offscreen target is available at all.
  ///
  /// Kept beside [preferredSampleCount] rather than folded into it: a device
  /// may report a count it can multisample *with* while still being unable to
  /// give the engine an offscreen target to use it on.
  bool get supportsOffscreenMsaa;

  /// Whether a texture built with a hand-supplied mip chain samples correctly.
  ///
  /// Asked rather than assumed, and the failure it guards against is not a
  /// missing feature but a silent one: flutter_gpu reports this as
  /// `doesSupportManuallyMippedTextures`, and its own documentation says that
  /// on OpenGL ES 2 devices without `GL_APPLE_texture_max_level` such a texture
  /// **samples as black**. Not blurrier, not unfiltered — black. A caller that
  /// did not ask would see an effect disappear on one class of device with
  /// nothing logged anywhere.
  bool get supportsMipmaps;

  /// Whether a cube texture can be created and sampled.
  ///
  /// Asked rather than assumed for the same reason as [supportsMipmaps]: no
  /// backend here reports it as a capability, so the honest answer is a probe
  /// or a constant, and which of the two it is belongs to the backend. A caller
  /// that gets false has to have something to fall back to — for the sky that
  /// is the procedural gradient, which is why the textured sky is an option on
  /// top of it rather than a replacement for it.
  bool get supportsCubeTextures;

  /// Whether [PolygonMode.line] can be drawn.
  ///
  /// False on OpenGL ES, which has no `glPolygonMode` — wireframe there means
  /// drawing line primitives from an index buffer built for the purpose, which
  /// is a decision for whoever owns the geometry and not a substitution a
  /// backend may make on its own.
  ///
  /// Ask before requesting it. A backend that cannot draw it refuses loudly
  /// rather than filling the triangles instead, because a silent substitution
  /// here looks exactly like the wireframe setting having no effect.
  bool get supportsWireframe;

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
  ///
  /// [layout] says where the vertex inputs come from, and **null means the
  /// backend works it out from the shader** — which is what every pipeline in
  /// this engine did before instancing and what all of them still do. Passing
  /// one is how a pipeline gets a second buffer stepping per instance, because
  /// no reflection can tell a backend which of two buffers that is.
  ///
  /// A caller that caches pipelines must key on the layout as well as on the
  /// pair. Two layouts over one stage pair are two different pipelines, and
  /// handing back the first for the second is a draw that reads instance data
  /// as vertices — which draws a picture rather than raising anything.
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  });

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
  ///
  /// [mipLevels] are the smaller copies, from half size downwards, and the
  /// texture is built with a chain exactly as long as the list. **They are
  /// supplied rather than generated**, and that is the same lesson as
  /// `linearRepeat`: WebGL2 has `glGenerateMipmap` and Impeller does not, so
  /// letting each backend make its own chain is two backends agreeing by
  /// accident and a third answering differently — at a scale nobody would
  /// attribute to the filter. `MipChain.build` makes them once, above the seam,
  /// and every backend uploads the same bytes.
  ///
  /// Ask [supportsMipmaps] first. A device that answers false is not merely
  /// slower with a chain; on OpenGL ES 2 without `GL_APPLE_texture_max_level` a
  /// hand-built chain samples as black.
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  });

  /// Uploads six square images as one cube texture.
  ///
  /// [faces] are in the order every graphics API in use agrees on:
  /// **+X, −X, +Y, −Y, +Z, −Z**. Documented once, here, because it is the piece
  /// of this that has no natural check: a table with two entries transposed
  /// produces a sky that is complete, seamless and wrong, and it looks like a
  /// sky somebody authored badly rather than like a bug. The conformance suite
  /// draws six known directions against six known colours for exactly this.
  ///
  /// Every face is [size] by [size] — cube faces are square by definition, and
  /// a rectangular one is a mistake worth refusing rather than resizing.
  ///
  /// Null when the device cannot do it, or when a face is not the size its
  /// description says. Null rather than a throw for the same reason
  /// [createTextureFromPixels] returns null: an asset that disagrees about its
  /// own dimensions should cost a texture, not the frame.
  ///
  /// Ask [supportsCubeTextures] first.
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
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

  /// Runs [whenDone] once the GPU has finished with the frame being encoded now.
  ///
  /// **The one thing a caller cannot work out for itself.** A finished frame is
  /// handed to the window as a texture the backend still owns, and drawing into
  /// that texture again while the compositor is reading it is a frame drawn
  /// half-and-half. The only defence without this is to keep N of them and hope
  /// N is enough — and what N has to be depends on the display's rate, the
  /// build's speed and how far behind the GPU is, none of which the engine
  /// knows. With this it does not have to guess: a texture goes back into
  /// rotation when the work that read it is done.
  ///
  /// A backend whose submission is synchronous — the software rasteriser, and
  /// WebGL, where the canvas is composited by the browser — calls [whenDone]
  /// straight away, and is telling the truth when it does.
  void onFrameComplete(void Function() whenDone);

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

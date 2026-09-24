/// The backend, as a value.
///
/// **Nothing in this package may import `flutter_gpu`** —
/// `tool/structure.dart`'s "the hardware layer names no graphics API" rule
/// enforces it, over every file in this package's `lib/`.
library;

import 'dart:typed_data';

import 'command_encoder.dart';
import 'compute.dart';
import 'formats.dart';
import 'geometry_buffer.dart';
import 'gpu_timings.dart';
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

  /// Whether `PassEncoder.setBlendColor` reaches the hardware.
  ///
  /// The four [BlendFactor] values that read a blend constant are only usable
  /// where this is true. It is not a property of the hardware — Metal, Vulkan
  /// and GL all have the constant — but of what the backend can reach: the
  /// Impeller backend goes through flutter_gpu, whose `RenderPass` exposes no
  /// blend-constant setter at all, so it answers false and there is nothing it
  /// can do about that from Dart.
  ///
  /// **False carries a promise, and it is a refusal.** A backend that answers
  /// false throws an [UnsupportedError] from `PassEncoder.setBlendColor`, and
  /// throws from `PassEncoder.setBlend` when the state names one of the four —
  /// see `BlendState.usesBlendColor`. Drawing the term as zero instead is the
  /// exact failure this capability was added to end: a plausible picture with a
  /// term missing from it, and nothing anywhere saying so.
  bool get supportsBlendColor;

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

  /// Whether a pass can draw into a mip level below the base — see
  /// `ColorTarget.mipLevel`.
  ///
  /// Asked rather than assumed, and it is the one capability here that splits
  /// a single backend by platform: flutter_gpu reports it as
  /// `doesSupportFramebufferRenderMipmap`, true on Metal and Vulkan and false
  /// on its OpenGL ES path, where an attachment naming a level other than zero
  /// is refused. WebGL2 attaches any level with `framebufferTexture2D`, and
  /// the software rasteriser writes into whichever array it is pointed at.
  ///
  /// Rendering into a cube *face* is not gated by this — every backend that
  /// answers true to [supportsCubeTextures] can attach a face at the base
  /// level. What this decides is whether a probe's roughness chain can be
  /// filtered on the device: a reflection probe renders six views into a cube
  /// and then convolves them into the levels below, and the second half needs
  /// a level to draw into. A device that says no gets **no probe at all** —
  /// see `ReflectionProbeNode.supportedOn`, which asks this and
  /// [supportsCubeTextures] together — because a cube with a base level only
  /// is a mirror at every roughness, which is a picture nobody asked for; the
  /// material there goes on reading the scene's environment.
  bool get supportsRenderToMip;

  /// Allocates a cube texture a pass can draw into, face by face and level by
  /// level, with nothing in it yet.
  ///
  /// The counterpart of [createCubeTextureFromPixels] for a cube the device
  /// fills itself. That one uploads a chain built on the host and refuses
  /// render-target usage, because until reflection probes nothing rendered
  /// into a face; this one is device-private, holds [mipLevels] levels counting
  /// the base, and is named as an attachment through `ColorTarget.face` and
  /// `ColorTarget.mipLevel`. Its contents start undefined, as
  /// [createTexture]'s do — a pass clears what it draws into.
  ///
  /// [format] is what a probe wants: the HDR colour format, so a reflected sun
  /// keeps its range. A depth attachment for a face is an ordinary 2D texture
  /// of the face's size from [createTexture], not part of the cube.
  ///
  /// Null when the device cannot make cubes — ask [supportsCubeTextures] — and
  /// a chain longer than the device will allocate is trimmed to what it will,
  /// the same rule the upload path follows. Ask [supportsRenderToMip] before
  /// drawing into any level but the base.
  ///
  /// Not from the render target pool, and deliberately: `RenderTargetSpec` is
  /// the pool's key and carries no shape, so a cube in the pool would be lent
  /// out in a 2D target's place — see `TextureHandle.type`. Probes are few and
  /// long-lived, and the renderer holds them itself.
  TextureHandle? createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  });

  /// Whether [PolygonMode.line] can be drawn.
  ///
  /// False on OpenGL ES, which has no `glPolygonMode` — wireframe there means
  /// drawing line primitives from an index buffer built for the purpose, which
  /// is a decision for whoever owns the geometry and not a substitution a
  /// backend may make on its own.
  ///
  /// Ask before requesting it. A backend that cannot draw it **throws an
  /// [UnsupportedError]** rather than filling the triangles instead, because a
  /// silent substitution here looks exactly like the wireframe setting having
  /// no effect. Typed, and not a bare exception, because the caller asking is
  /// choosing between two ways of drawing and cannot act on "something went
  /// wrong".
  ///
  /// Both halves are held by the conformance check `wireframe is drawn as edges
  /// or refused, never filled`, which counts what a triangle painted: a backend
  /// answering false must throw, and one answering true must leave the interior
  /// alone. It is the one capability here that differs across all three
  /// backends, and until that check existed neither answer was tested — a
  /// backend that said true and filled the triangles passed the whole suite.
  bool get supportsWireframe;

  /// Whether the depth attachment this device hands out carries a stencil
  /// that `PassEncoder.setStencil` can test against.
  ///
  /// Ask before requesting it, as with [supportsWireframe]: a stencil test
  /// configured against an attachment that has none passes always on one API
  /// and is an invalid descriptor on another, and neither is the silhouette
  /// somebody asked for. The renderer's x-ray stage draws nothing at all on a
  /// device that answers false, which is a picture without silhouettes rather
  /// than a frame with something wrong in it.
  ///
  /// True on all three backends here — every depth format the engine names
  /// packs eight stencil bits beside the depth, and the software rasteriser
  /// keeps a byte per pixel for the purpose. It is a question rather than a
  /// constant because [defaultDepthStencilFormat] is allowed to be
  /// [TextureFormat.unknown], and a device with no depth-stencil format has
  /// no stencil either.
  bool get supportsStencil;

  /// Whether a texture uploaded in [format] can be created and sampled here.
  ///
  /// **The question a block-compressed format needs asked, and the one no
  /// backend was asking.** Every value of `TextureFormat` has a name on every
  /// backend, and that is where the agreement ends: BC is a desktop family,
  /// ETC2 a mobile and WebGL2 one, ASTC newer still, and the software
  /// rasteriser samples raw texels and decodes none of them. Impeller answers
  /// from flutter_gpu's own per-family capability, WebGL2 from the extensions
  /// its context handed back, the software backend with a constant no for
  /// anything compressed. A loader asks here before it uploads, and a false
  /// is a texture left out with a reason — not an `ArgumentError` out of an
  /// allocation, and not a texture full of block bytes read as RGBA.
  ///
  /// About sampling only. A render target is asked for through
  /// [hdrColorFormat], [defaultColorFormat] and [createTexture], and a
  /// compressed format is never one anywhere.
  bool supportsTextureFormat(TextureFormat format);

  /// The most taps a sampler may take along a foreshortened axis, or 1 for a
  /// device that filters isotropically and nothing else.
  ///
  /// Asked rather than assumed, and a number rather than a boolean for the
  /// same reason [preferredSampleCount] is: "does anisotropic filtering work"
  /// and "how far" are different questions. Impeller answers from
  /// flutter_gpu's `maxSamplerAnisotropy`, WebGL2 from
  /// `EXT_texture_filter_anisotropic` when the context hands it back and 1
  /// when it does not, and the software rasteriser with a constant 1 — it
  /// picks one level per triangle and takes one tap, and says so.
  ///
  /// A `SamplerOptions.anisotropy` above this is clamped by the backend
  /// rather than refused, so a caller may ask for sixteen without asking
  /// first. The reason to ask anyway is to *decide* — the bridge asks so it
  /// can hand a level's materials `min(8, maxAnisotropy)` once rather than
  /// per bind, and a setting that offers the choice to a player has to know
  /// whether there is one.
  int get maxAnisotropy;

  /// How many colour attachments one render pass may open — `gfx-50n`.
  ///
  /// One, or more. **Asked rather than assumed, and the failure it guards
  /// against is the worst kind this interface has:** on Impeller's OpenGL ES
  /// path a second attachment reaches an `FML_CHECK`, so the process aborts
  /// in release. It does not draw the wrong picture, log a warning or fall
  /// back — it stops. Every other capability here guards against something
  /// that produces a frame somebody can look at.
  ///
  /// A number rather than a boolean for the reason [maxAnisotropy] is one:
  /// "does MRT work" and "how many" are different questions, and a deferred
  /// pass wanting four attachments has to be able to find out that it may
  /// have two.
  ///
  /// **What the engine does with a one**: the scene pass stops declaring that
  /// it writes the surface buffer, so every node that reads it — occlusion,
  /// reflections, the shafts, the lens — is culled by the frame graph and
  /// reported as `PassSkip.starved`. Those effects are then off on that
  /// device and the frame is otherwise the frame it always was. A caller who
  /// wants to know why asks `CompiledFrameGraph.skipped`, which names the
  /// pass and the reason; nothing has to guess from a picture.
  ///
  /// Opening more attachments than this throws rather than aborting, which is
  /// the promise that makes the number worth publishing.
  int get maxColorAttachments;

  /// The compiled bundle this device was built with.
  ///
  /// On the device rather than on `RenderServices` because it is a property of
  /// the backend, not of the renderer: it is where a [ShaderHandle] comes from,
  /// and a handle from one device means nothing to another.
  ShaderLibrary get shaders;

  /// Builds a library from a bundle that arrived as bytes.
  ///
  /// **The one way a shader reaches a device without being an asset.** The
  /// engine's own bundle is compiled ahead of time and loaded by asset path,
  /// which is right for the engine and useless for two callers: an editor that
  /// rebuilds a bundle and wants to see the result without restarting, and an
  /// application that ships or fetches shaders the engine never heard of and
  /// wants them on every backend it runs on. Both hand bytes in here and get a
  /// [LoadedShaderLibrary] back — layered under the engine's with
  /// `LayeredShaderLibrary`, or handed to `Renderer.create` as `materials`.
  ///
  /// [bytes] are a `ShaderBundle`: a header naming the bundle, the SDK it was
  /// compiled on and the stages it holds, then one section per backend that
  /// needs compiled code. Each backend takes its own section — Impeller
  /// reparses `impellerc` output through `ShaderLibrary.fromBytes`, WebGL2
  /// compiles the GLSL ES text the browser is given — and the software
  /// rasteriser, which runs Dart and compiles nothing, answers the bundle's
  /// names with the stages it already has.
  ///
  /// **Refused by name, never answered with nothing.** Bytes that are not a
  /// bundle, a bundle with no section for this backend, a compiled section
  /// from an SDK other than the running one, and — on the backend that cannot
  /// compile — a stage it has no Dart for all throw `ShaderBundleRefused`
  /// carrying the bundle's name. A device that returned an empty library
  /// instead would produce a renderer failing at the first draw for want of a
  /// stage, which names the stage and not the file to rebuild. The SDK check
  /// is what a compiled section needs: the bundle format is tied to the
  /// Flutter version, and a stage compiled for another one does not fail to
  /// parse so much as draw something else.
  ///
  /// **A loaded library lives as long as the device.** There is no call to
  /// release one — a backend keeps what it compiled until `dispose`, and
  /// the handles it handed out are held by whatever resolved them, so a
  /// release would have to know who. An application whose shaders change
  /// over its run loads one bundle and `refresh`es it in place, which is what
  /// the identity promise is for; loading a fresh bundle per level keeps
  /// every level's stages for the device's lifetime.
  ///
  /// Asynchronous because flutter_gpu's own loader is; on every backend here
  /// the future completes in the same turn.
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes);

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

  /// Writes [bytes] into [target] starting [offsetInBytes] into it, in place.
  ///
  /// **Visible starting the next pass, never the one already encoded.** None
  /// of the four backends here promise anything about a draw already recorded
  /// against the old bytes — WebGL2's `bufferSubData`, WebGPU's
  /// `queue.writeBuffer` and flutter_gpu's `DeviceBuffer.overwrite` are all
  /// queued relative to *submission*, not to the moment this call returns, so
  /// a pass encoded and submitted before this call still draws what it was
  /// given. A caller that needs the new bytes in the frame being built has to
  /// call this before recording the draw, not after.
  ///
  /// [offsetInBytes] and `bytes.lengthInBytes` must together fit inside
  /// [target] — `offsetInBytes + bytes.lengthInBytes <= target.lengthInBytes`
  /// — checked here rather than left to a backend, because a backend that
  /// caught it would report three different exceptions for one mistake.
  ///
  /// [target] must be a buffer this device itself returned from
  /// [uploadGeometry], not a slice of unrelated bytes — the same requirement
  /// [releaseGeometry] already carries.
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  );

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

  /// Overwrites [region] (the whole texture by default) of [target]'s base
  /// level with [rgba] — raw RGBA8 bytes, `region.width * region.height * 4`
  /// of them, row-major from the top the same way [readback] answers them.
  ///
  /// **[readbackFormats] again, and only the base level.** The same two
  /// linear eight-bit layouts [readback] insists on, for the same reason: a
  /// caller round-tripping a region — read it, edit it, write it back —
  /// needs the two ends to agree on what the bytes mean, and a third format
  /// each backend would decode differently is exactly the mismatch
  /// [readback] already refuses. Refuses (throws `UnsupportedError`) any
  /// other [target].format, including every compressed one — a block
  /// covers a 4x4 texel footprint, and a region write that lands mid-block
  /// would ask a backend to rewrite a compressed block from decoded bytes
  /// it does not carry — and refuses [mipLevel] other than zero, because
  /// patching one level of a chain that carries more would leave the rest
  /// silently stale, with nothing anywhere saying the picture at another
  /// level is no longer the one this level was built from.
  ///
  /// Visible starting the next pass, the same promise [overwriteGeometry]
  /// makes and for the same reason: nothing here rewinds a pass already
  /// submitted against the old bytes.
  ///
  /// **Asynchronous because one backend's own write is.** Three of the four
  /// can patch a region of an existing texture directly; flutter_gpu's own
  /// `Texture` can only overwrite a *whole* mip level at once, so writing a
  /// region there means reading the level back first — [readback]'s own
  /// asynchronous half — patching it in memory, and writing the whole level
  /// back. On the other three the future completes in the same turn, the
  /// same shape [loadShaders] is asynchronous for.
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  });

  /// Uploads six square images as one cube texture.
  ///
  /// [faces] are in the order every graphics API in use agrees on:
  /// **+X, −X, +Y, −Y, +Z, −Z**. Documented once, here, because it is the piece
  /// of this that has no natural check: a table with two entries transposed
  /// produces a sky that is complete, seamless and wrong, and it looks like a
  /// sky somebody authored badly rather than like a bug. The conformance check
  /// `a cube map answers the face a direction points at` draws six known
  /// directions against six known colours for exactly this, through the
  /// cube-sky stage pair, and names the transposed pair when it fails.
  ///
  /// Every face is [size] by [size] — cube faces are square by definition, and
  /// a rectangular one is a mistake worth refusing rather than resizing.
  ///
  /// Null when the device cannot do it, or when a face is not the size its
  /// description says. Null rather than a throw for the same reason
  /// [createTextureFromPixels] returns null: an asset that disagrees about its
  /// own dimensions should cost a texture, not the frame.
  ///
  /// [mipLevels] are the smaller copies, from half size downwards: one entry
  /// per level, each holding six faces in the same order as [faces]. Null or
  /// empty gives a cube with a base level only, which is what a sky wants.
  ///
  /// **Roughness is what these are for.** A sky is sampled at one level and
  /// needs none; a prefiltered radiance map is a cube whose levels *are* the
  /// roughness scale, each one the environment convolved a little further. That
  /// is the one use, and it is why this takes a chain the caller has already
  /// built rather than offering to generate one: the levels are not a box blur
  /// of each other, and a device that filled them by halving would produce
  /// something that looks nearly right and is wrong everywhere it matters.
  ///
  /// Built above the seam for the same reason [createTextureFromPixels]'s are —
  /// `flutter_gpu` has no `generateMipmap` — so both backends receive the same
  /// bytes and the two golden sets stay comparable.
  ///
  /// Ask [supportsCubeTextures] first.
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
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
  ///
  /// **A pass starts covering the whole of its attachment and nothing else.**
  /// Both the viewport and the scissor are the full attachment until the caller
  /// says otherwise, and neither carries over from the pass before it. This is
  /// stated because it was assumed: every pass this engine opens sets a viewport
  /// of its own before drawing, so a backend that inherited the last pass's
  /// rectangle — or its canvas's — went unnoticed until
  /// `flutter3d_conformance` asked. What it cost was a shadow-atlas tile
  /// clipping every draw of the pass that followed it, discarded silently and
  /// visible only as a frame that is right in one rectangle and untouched
  /// everywhere else.
  ///
  /// The two checks that hold it are `a pass covers the whole of its
  /// attachment` and `a pass does not inherit the previous pass's scissor`.
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor);

  /// The texture's pixels: **premultiplied** RGBA8, row-major from the
  /// top-left.
  ///
  /// One layout, named, because the only thing anybody does with these is
  /// compare them against pixels that came from somewhere else — and two sides
  /// of a comparison that disagree about premultiplication differ on every
  /// translucent texel while looking identical on screen.
  ///
  /// Separate from presenting a frame because it is a different question with
  /// a different cost. Presenting happens every frame and must be nearly free;
  /// reading back happens when something wants to *look* at what a pass wrote —
  /// the golden suite comparing a frame, the MRT probe checking that a second
  /// attachment was honoured — and is affordable on both backends precisely
  /// because it stops at CPU memory.
  ///
  /// Null when the texture cannot be read: `deviceTransient` lives in tile
  /// memory, and there is nothing there to read once the pass has ended.
  Future<ByteData?> readPixels(TextureHandle texture);

  /// The pixels of [region] — the whole texture by default — **as they stand
  /// at this point in the queue**, without waiting for the GPU to get there.
  ///
  /// Same bytes as [readPixels]: premultiplied RGBA8, rows from the top, the
  /// region's own width times four per row. What differs is *when* the
  /// question is answered, and that is the whole reason this exists beside
  /// it. [readPixels] is for looking at a finished picture: a golden run, a
  /// probe, a test — a caller that has stopped drawing and can afford to wait.
  /// This is for a caller that is still drawing and wants last frame's answer
  /// while this frame goes on: an exposure meter reading a luminance target,
  /// an editor reading the id under the cursor. Two promises make that work:
  ///
  ///  * **The copy is queued where it was asked for.** A pass submitted after
  ///    this call, drawing into the same texture, does not reach the bytes:
  ///    they are the texture as the passes before this call left it. The
  ///    conformance check `a readback returns the frame before` clears red,
  ///    asks, clears blue, and gets red.
  ///  * **Nothing here stalls the caller.** The hardware backends copy on the
  ///    GPU and resolve the future when the queue reports the copy done —
  ///    flutter_gpu through `submit`'s completion callback, WebGL2 through a
  ///    pixel-pack buffer and a fence — so the frame being encoded is not
  ///    held up by a frame the GPU is still on. The software rasteriser has
  ///    nothing to wait for and answers at once, which is the truth there.
  ///
  /// The future therefore usually completes a frame or two later, and a caller
  /// that wants this frame's picture has asked the wrong question. Ask for
  /// [readPixels] instead.
  ///
  /// [region] is stated from the top left, in the texture's own pixels, like
  /// every rectangle in this interface, and must lie inside the texture. One
  /// pixel is a legitimate region and the cheapest one: the editor's pick reads
  /// exactly that.
  ///
  /// Throws an [ArgumentError] rather than answering null for what cannot be
  /// read — a `deviceTransient` texture, a multisampled one, a cube, a region
  /// outside the texture, and a texture in any format but the two linear
  /// eight-bit RGBA layouts (`readbackFormats`: `r8g8b8a8UNormInt` and
  /// `b8g8r8a8UNormInt`). The handle carries every one of those facts, so the
  /// caller can ask before requesting; a null here would have to be told apart
  /// from a copy the driver refused, and those are different mistakes. The
  /// format is refused rather than converted because the three backends would
  /// convert differently — one of them into a picture of zeros with no error —
  /// and the bytes above are promised to be the same bytes everywhere. A float
  /// target is read through [readPixels], or drawn into an eight-bit one
  /// first, which is what the exposure meter's luminance pass is. An sRGB
  /// target is refused for the same reason with a message of its own: the
  /// encoding is what the three would disagree about, one handing back the
  /// stored bytes and another the linear values they stand for.
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region});

  /// Releases one geometry buffer, rather than waiting for the whole device to
  /// go.
  ///
  /// The contract is `TextureAllocator.releaseTexture`'s, which this device is
  /// also required to implement — that one is declared beside `createTexture`
  /// because the pool that owns most of the engine's targets holds an
  /// allocator rather than a device.
  void releaseGeometry(GeometryBuffer geometry);

  /// Releases every persistent resource this device holds — the textures and
  /// geometry buffers handed out by [createTexture], [createTextureFromPixels],
  /// [createCubeTextureFromPixels], [createCubeRenderTarget] and
  /// [uploadGeometry].
  ///
  /// **What "release" means is a property of the backend, not a promise this
  /// method makes uniformly.** WebGL2 objects are explicitly deletable — a
  /// `WebGLTexture` or `WebGLBuffer` the driver is still holding onto is a real
  /// leak, not a GC artefact — so that backend actually calls `gl.deleteTexture`
  /// and friends here. flutter_gpu's `Texture` has no native dispose at all;
  /// see the note at `GpuRenderBackend.supportsCubeTextures` for why letting one
  /// go out of scope is the only release path that backend has, which makes its
  /// implementation of this method a deliberate no-op rather than an omission.
  /// The software rasteriser holds nothing but Dart lists, which the garbage
  /// collector already reclaims, so its implementation is a no-op for a third,
  /// unrelated reason.
  ///
  /// Call once, when the device is being torn down. Nothing here promises safe
  /// reuse afterwards — a disposed device's handles are no longer valid on
  /// backends that actually freed them.
  void dispose();

  // ------------------------------------------------------------------------
  // The rest of this interface is the 0.8 cycle's, declared in 0.8.0 so that
  // no patch release has to add a member: each backend is its own package on
  // a caret range of this one, and a member added in 0.8.1 would break every
  // backend published before it. A capability that is not built yet answers
  // false or empty, and its creators throw an [UnsupportedError].
  // ------------------------------------------------------------------------

  /// Whether this device measures how long the GPU spends in each labelled
  /// pass — `H2`. When true, [onGpuTimings] is called with them.
  ///
  /// False on Impeller (flutter_gpu has no timer query), on the software
  /// rasteriser (whose passes run on the CPU and are timed where they are
  /// encoded) and on WebGL2 without `EXT_disjoint_timer_query_webgl2`. WebGPU
  /// answers from whether the adapter granted `timestamp-query`.
  bool get supportsGpuTimestamps;

  /// Sets where each frame's GPU timings go, a frame or two after it was
  /// encoded; null stops them. Never called on a device whose
  /// [supportsGpuTimestamps] is false.
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener);

  /// Whether compute pipelines can be created and dispatched — `H6`. The
  /// members below it throw an [UnsupportedError] where this is false.
  bool get supportsCompute;

  /// A storage buffer holding [bytes]. [hostReadable] allows [readBuffer].
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
  });

  /// A pipeline from a compute stage of this device's shader library.
  ComputePipelineHandle createComputePipeline(ShaderHandle shader);

  /// Opens a compute pass; [label] names it to a debugger and to
  /// [onGpuTimings].
  ComputeEncoder beginComputePass({String? label});

  /// The contents of [buffer], once every pass submitted before this call has
  /// finished writing it. [buffer] must be `hostReadable`.
  Future<ByteData> readBuffer(StorageBuffer buffer);

  /// Releases one storage buffer, as [releaseGeometry] releases geometry.
  void releaseStorageBuffer(StorageBuffer buffer);

  /// Whether a 32-bit float texture can be drawn into and sampled with
  /// linear filtering.
  ///
  /// Asked by the shadow filter that stores moments in one (`S2`), which
  /// declines on a device answering false and falls back to the fixed
  /// kernel. Both halves are one answer because that filter needs both: a
  /// target it can render its moments into, and a sampler that blends
  /// neighbouring texels of it.
  bool get supportsFloat32Filtering;

  /// Whether a pass with several colour targets can blend each differently.
  ///
  /// Reserved for weighted blended transparency (`R8`), whose two targets
  /// blend additively and multiplicatively in one draw; without it the draws
  /// go twice, once per target. False everywhere in 0.8.0.
  bool get supportsIndependentBlend;

  /// The formats this device can present an extended-range frame in, empty
  /// when it can only present standard range.
  ///
  /// `R9`: empty on Impeller (whose Apple extended formats upstream
  /// removed), WebGL2 and the software rasteriser; WebGPU answers
  /// `rgba16float` on a display that reports a high dynamic range. A frame
  /// rendered with `OutputTransform.extendedSrgb` is drawn in the first of
  /// these.
  List<TextureFormat> get hdrOutputFormats;
}

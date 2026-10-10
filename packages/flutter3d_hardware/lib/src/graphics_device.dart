/// The backend, as a value.
///
/// **Nothing in this package may import `flutter_gpu`** —
/// `tool/structure.dart`'s "the hardware layer names no graphics API" rule
/// enforces it, over every file in this package's `lib/`.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'command_encoder.dart';
import 'compute.dart';
import 'device_exceptions.dart';
import 'formats.dart';
import 'geometry_buffer.dart';
import 'gpu_timings.dart';
import 'render_target_pool.dart';
import 'resources.dart';
import 'sampler.dart';
import 'shader.dart';
import 'texture.dart';
import 'transfer.dart';
import 'vertex_layout_spec.dart';

/// Everything the engine needs a graphics backend for.
///
/// **A value, never a global.** flutter_gpu's own device is a singleton —
/// `gpu.gpuContext` — and reaching it from a top-level function was how the
/// renderer and its nodes made textures and command buffers. Nothing above the
/// backend does that any more: a device arrives through `Renderer.create` and
/// travels to the passes in `RenderFrame` and `ContributorFrame`. Two things
/// depend on that being true. A backend cannot be a separate package while the
/// core reaches into it, and a **fake** backend — the only way a node's drawing
/// is ever testable off a device — cannot displace a singleton.
///
/// It implements [TextureAllocator] rather than owning a second way to make a
/// texture, so `RenderTargetPool` takes the device directly and every texture
/// in the engine is created by one rule.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
abstract base class GraphicsDevice with TextureAllocator {
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
  /// Throws `UnsupportedCapability` when the device cannot make cubes — ask
  /// `features.has(DeviceFeature.cubeTextures)` — and a chain longer than the
  /// device will allocate is trimmed to what it will, the same rule the upload
  /// path follows. Ask `features.has(DeviceFeature.renderToMipLevel)` before
  /// drawing into any level but the base. (It answered null before 1.0.)
  ///
  /// Not from the render target pool, and deliberately: `RenderTargetDescriptor` is
  /// the pool's key and carries no shape, so a cube in the pool would be lent
  /// out in a 2D target's place — see `TextureHandle.type`. Probes are few and
  /// long-lived, and the renderer holds them itself.
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  });

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
  /// compile — a stage it has no Dart for all throw `ShaderBundleException`
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
    VertexLayoutDescriptor? layout,
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
  /// Throws a [DeviceResourceException] when [pixels] is not the size the
  /// device wants for a texture of that description (it answered null before
  /// 1.0). A loader that would rather lose one texture than the model catches
  /// it where it uploads, which is where a decoder that disagreed about the
  /// dimensions can still be named.
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
  /// Ask `features.has(DeviceFeature.manualMipmaps)` first. A device that
  /// answers false is not merely slower with a chain; on OpenGL ES 2 without
  /// `GL_APPLE_texture_max_level` a hand-built chain samples as black.
  TextureHandle createTextureFromPixels({
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
  /// Throws `UnsupportedCapability` when the device cannot make cubes, and a
  /// [DeviceResourceException] when there are not six faces or a face is not
  /// the size its description says — the same rule as
  /// [createTextureFromPixels], whose caller decides whether an asset that
  /// disagrees about its own dimensions costs a texture or the frame.
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
  /// Ask `features.has(DeviceFeature.cubeTextures)` first.
  TextureHandle createCubeTextureFromPixels({
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

  /// The pixels of [region] — the whole texture by default — **as they stand
  /// at this point in the queue**: premultiplied RGBA8, row-major from the
  /// top-left, the region's own width times four per row.
  ///
  /// One layout, named, because the only thing anybody does with these is
  /// compare them against pixels that came from somewhere else — and two sides
  /// of a comparison that disagree about premultiplication differ on every
  /// translucent texel while looking identical on screen.
  ///
  /// **The one way to read a texture back, since 1.0.** `readPixels` was a
  /// second call for the same bytes that answered null where this throws; a
  /// finished picture (a golden run, a probe, a test) and last frame's answer
  /// while this frame goes on (an exposure meter, the id under the cursor)
  /// are both this. Two promises make the second work:
  ///
  ///  * **The copy is queued where it was asked for.** A pass submitted after
  ///    this call, drawing into the same texture, does not reach the bytes:
  ///    they are the texture as the passes before this call left it. The
  ///    conformance check `a readback returns the frame before` clears red,
  ///    asks, clears blue, and gets red.
  ///  * **Nothing here stalls the caller** for an eight-bit texture. The
  ///    hardware backends copy on the GPU and resolve the future when the
  ///    queue reports the copy done — flutter_gpu through `submit`'s
  ///    completion callback, WebGL2 through a pixel-pack buffer and a fence —
  ///    so the frame being encoded is not held up by a frame the GPU is still
  ///    on. The software rasteriser has nothing to wait for and answers at
  ///    once, which is the truth there.
  ///
  /// The future therefore usually completes a frame or two later.
  ///
  /// [region] is stated from the top left, in the texture's own pixels, like
  /// every rectangle in this interface, and must lie inside the texture. One
  /// pixel is a legitimate region and the cheapest one: the editor's pick reads
  /// exactly that.
  ///
  /// **A whole texture in another format is converted**, which is how a float
  /// target (the engine's HDR colour) is looked at: each backend draws or
  /// converts it into eight-bit RGBA on its own path, which may wait for the
  /// GPU. See [readbackConverts]. A *region* of one is refused, because a
  /// partial conversion is the place three backends would disagree.
  ///
  /// Throws an [ArgumentError] for what cannot be read at all — a
  /// `deviceTransient` texture, a multisampled one, a cube, a region outside
  /// the texture, a region of a texture outside `readbackFormats` — because
  /// the handle carries every one of those facts and the caller can ask before
  /// requesting. Throws a [DeviceResourceException] when the device has the
  /// texture and still cannot hand its pixels over: a format this backend has
  /// no conversion for.
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

  /// Sets where each frame's GPU timings go, a frame or two after it was
  /// encoded; null stops them. Never called on a device whose
  /// [supportsGpuTimestamps] is false.
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  /// A storage buffer holding [bytes]. [hostReadable] allows [readBuffer];
  /// [bindableAsIndices] gives it a `StorageBuffer.asIndices` a draw can
  /// bind as 32-bit indices once a compute pass has written them — `H11`.
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) => throw refuse(DeviceFeature.compute);

  /// A pipeline from a compute stage of this device's shader library.
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) =>
      throw refuse(DeviceFeature.compute);

  /// Opens a compute pass; [label] names it to a debugger and to
  /// [onGpuTimings]. [timestampWrites] (since 1.0) names where the pass
  /// writes its start and end GPU times — `DeviceFeature.timestampQuery`.
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) => throw refuse(DeviceFeature.compute);

  /// The contents of [buffer], once every pass submitted before this call has
  /// finished writing it. [buffer] must be `hostReadable`.
  Future<ByteData> readBuffer(StorageBuffer buffer) =>
      Future<ByteData>.error(refuse(DeviceFeature.compute));

  /// Releases one storage buffer, as [releaseGeometry] releases geometry.
  void releaseStorageBuffer(StorageBuffer buffer) {}

  /// The formats this device can present an extended-range frame in, empty
  /// when it can only present standard range.
  ///
  /// `R9`: empty on Impeller (whose Apple extended formats upstream
  /// removed), WebGL2 and the software rasteriser; WebGPU answers
  /// `rgba16float` on a display that reports a high dynamic range. A frame
  /// rendered with `OutputTransform.extendedSrgb` is drawn in the first of
  /// these.
  List<TextureFormat> get hdrOutputFormats => const <TextureFormat>[];

  // ------------------------------------------------------------------------
  // 1.0: capabilities as one answer, and the rest of a modern GPU.
  //
  // **The `supportsX` getters above are superseded by [features] and
  // [limits]**, and every backend answers them from those through
  // `DeviceCapabilityForwarders`, so the two cannot disagree. They are
  // `@Deprecated` from 1.0.0 and go in 2.0.0; nothing in this repository asks
  // them any more, and a caller outside it keeps a working answer until then —
  // see "Capabilities and stability" in this package's README.
  //
  // Everything a [DeviceFeature] gates throws `UnsupportedCapability` on a
  // device without it. All of it is the 1.0 contract under strict semver: a
  // backend that gains a capability starts listing the feature, and nothing
  // here changes.
  // ------------------------------------------------------------------------

  /// What this device can do — every optional capability, as one set.
  ///
  /// Ask this rather than the `supportsX` getters, which read it. A feature
  /// this version of the contract does not name cannot be in it; a feature it
  /// names and this device lacks answers false, and every call that feature
  /// gates throws `UnsupportedCapability`.
  DeviceFeatures get features;

  /// How much of everything this device has. See [DeviceLimits].
  DeviceLimits get limits;

  /// What [format] can be used for here: sampled, filtered, rendered,
  /// blended, multisampled, resolved, used as depth, bound as storage.
  ///
  /// A format this device cannot allocate at all answers
  /// [TextureFormatSupport.none].
  TextureFormatSupport textureFormatSupport(TextureFormat format);

  /// Writes [data] into [region] (the whole level by default) of level
  /// [mipLevel] of [target], in [target]'s own format, rows [bytesPerRow]
  /// apart (tightly packed by default; a compressed format counts rows of
  /// blocks). Visible starting the next pass, as [overwriteGeometry].
  ///
  /// The general form of [overwriteTexture], which takes RGBA8 at the base
  /// level only. `DeviceFeature.textureWrites`.
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) => throw refuse(DeviceFeature.textureWrites);

  /// A buffer of [BufferDescriptor.lengthInBytes] bytes, for the usages it
  /// names, holding [contents] (zeros by default).
  ///
  /// The general form of [createStorageBuffer] and [uploadGeometry]: one
  /// allocation a compute pass writes, an indirect draw reads its counts
  /// from, and a draw binds as vertices (`StorageBuffer.asVertices`) or
  /// indices (`StorageBuffer.asIndices`). `DeviceFeature.buffers`; a
  /// [BufferUsage.storage] buffer needs `compute` or `renderStageStorage`,
  /// and a [BufferUsage.indirect] one `indirectDraw` or `indirectDispatch`.
  /// Released through [releaseStorageBuffer].
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) => throw refuse(DeviceFeature.buffers);

  /// Writes [bytes] into [target] at [offsetInBytes], in place. Visible
  /// starting the next pass, as [overwriteGeometry]; an offset and length
  /// that do not fit throw an [ArgumentError] before anything is written.
  ///
  /// The call a simulation makes every step to feed a compute pass its
  /// inputs. Any buffer [createStorageBuffer] or [createBuffer] made with
  /// [BufferUsage.copyDestination]. Gated by `compute` or `buffers`,
  /// whichever made the buffer possible.
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) =>
      throw refuse(DeviceFeature.buffers);

  /// A set of [count] queries of [type] — `DeviceFeature.occlusionQuery` or
  /// `DeviceFeature.timestampQuery`.
  QuerySet createQuerySet(QueryType type, int count) =>
      throw refuse(type.feature);

  /// The results of [count] queries of [querySet] from [first], once every
  /// pass submitted before this call has finished: sample counts for
  /// occlusion, nanoseconds for timestamps. A query no pass wrote reads zero.
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) => Future<List<int>>.error(refuse(DeviceFeature.occlusionQuery));

  /// Releases one query set, as [releaseStorageBuffer] releases a buffer.
  void releaseQuerySet(QuerySet querySet) {}

  /// Opens a pass of copies between buffers and textures. Never refused —
  /// each copy is gated by its own feature. See [TransferEncoder].
  TransferEncoder beginTransferPass({String? label}) =>
      throw refuse(DeviceFeature.bufferCopy);

  /// Maps [sizeInBytes] bytes (to the end by default) of [buffer] from
  /// [offsetInBytes] into host memory, once every pass submitted before this
  /// call is done with it — `DeviceFeature.mappedBuffers`.
  ///
  /// The staging-buffer path, both ways: [MapMode.read] on a
  /// [BufferUsage.hostReadable] buffer that a transfer pass copied results
  /// into, [MapMode.write] on a [BufferUsage.hostWritable] one the host
  /// fills and a transfer pass copies onward. See [MappedBuffer] for how long
  /// the bytes are valid. [readBuffer] is this, copied out and unmapped, for
  /// a whole buffer.
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => Future<MappedBuffer>.error(refuse(DeviceFeature.mappedBuffers));

  /// Opens an encoder whose draws are kept as a [RenderBundle], to be
  /// replayed into any pass whose attachments match [descriptor] —
  /// `DeviceFeature.renderBundles`. See [RenderBundleEncoder] for what a
  /// bundle cannot record.
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) => throw refuse(DeviceFeature.renderBundles);

  // ------------------------------------------------------------------------
  // 1.0, wave 3: a base class with defaults. Every member below has a body,
  // so a backend written against 1.0.0 keeps compiling when one is added in
  // a minor. A feature-gated member's default refuses with
  // [UnsupportedCapability]; anything that is only a courtesy to a debugger
  // does nothing.
  // ------------------------------------------------------------------------

  /// The name a refusal from this device gives as its backend. The runtime
  /// type by default; a backend overrides it with the name a person knows it
  /// by ("WebGPU", "Impeller").
  String get backendName => '$runtimeType';

  /// The refusal for [feature] on this device, for a default body or a
  /// backend's own gate to throw: `throw refuse(DeviceFeature.compute)`.
  @protected
  UnsupportedCapability refuse(DeviceFeature feature, {String? reason}) =>
      UnsupportedCapability(feature, backend: backendName, reason: reason);

  /// The refusal for a request this device has the feature for and still
  /// cannot honour, for a backend to throw from [operation]:
  /// `throw refuseResource('createTextureFromPixels', 'the pixels are …')`.
  @protected
  DeviceResourceException refuseResource(
    String operation,
    String reason, {
    Object? cause,
  }) => DeviceResourceException(
    operation: operation,
    backend: backendName,
    reason: reason,
    cause: cause,
  );

  /// [createPipeline] without holding up the caller: the future completes
  /// when the pipeline is linked.
  ///
  /// **Where a backend can compile off the thread, this is where it does.**
  /// WebGPU's `createRenderPipelineAsync` is the model. The default links in
  /// the calling turn and hands back a completed future, which is what a
  /// backend without asynchronous compilation (Impeller, WebGL2 without
  /// `KHR_parallel_shader_compile`, the software rasteriser) can honestly do.
  /// A refused link completes the future with the error instead of throwing.
  Future<PipelineHandle> createPipelineAsync(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) async => createPipeline(vertex, fragment, layout: layout);

  /// [createComputePipeline], asynchronously; see [createPipelineAsync]. For a
  /// caller warming a compute pass up behind a loading screen.
  Future<ComputePipelineHandle> createComputePipelineAsync(
    ShaderHandle shader,
  ) async => createComputePipeline(shader);

  /// Releases a pipeline [createPipeline] made. Does nothing by default: a
  /// backend whose pipelines are reclaimed with their last reference is
  /// right to.
  void releasePipeline(PipelineHandle pipeline) {}

  /// Releases a pipeline [createComputePipeline] made, as [releasePipeline].
  void releaseComputePipeline(ComputePipelineHandle pipeline) {}

  /// Releases a bundle [createRenderBundleEncoder] recorded.
  void releaseRenderBundle(RenderBundle bundle) {}

  /// Gives back what this device made to sample with [sampler], if it made
  /// anything.
  ///
  /// **A sampler is a value here, not a handle**: a [SamplerDescriptor] is
  /// handed to every bind, and has nothing of its own to dispose. A backend
  /// whose API wants an object for it makes one per distinct description
  /// and keeps it — WebGPU a `GPUSampler`, Impeller a `SamplerOptions` —
  /// and this drops that one, so a tool that swept through many anisotropy
  /// levels or level clamps does not keep every one for the device's life.
  /// The next bind of an equal description makes it again. A draw already
  /// encoded keeps what it was bound with.
  ///
  /// Does nothing by default, which is the whole of it on a backend that
  /// samples by value (WebGL2 sets the texture's parameters at each bind; the
  /// software rasteriser reads the description itself).
  void releaseSampler(SamplerDescriptor sampler) {}

  /// Each time the device stops working: a WebGPU device lost, a WebGL
  /// context lost or restored. An external source, so a [Stream].
  ///
  /// **What a loss means for the caller.** Every handle this device made is
  /// spent; a frame drawn after it draws nothing. A [DeviceLoss] that
  /// [DeviceLoss.isRecoverable] (a WebGL context that the browser restores)
  /// is followed by another event with [DeviceLoss.restored] true, after
  /// which the application rebuilds its renderer on the same device; any
  /// other loss means opening a new device.
  ///
  /// **Every backend's, not WebGL's alone.** This is the one place a caller
  /// learns of a loss, whichever backend it opened, so each backend reports
  /// here whatever its API lets it see: WebGPU its `device.lost` and the
  /// errors it would otherwise only log, WebGL its context events, Impeller
  /// and the software rasteriser at least their own [dispose] as
  /// [DeviceLossReason.destroyed]. A caller listens once, on whatever it
  /// opened, and never asks which backend it was. A backend from outside
  /// this repository owes the same; the empty default is only what one
  /// inherits before it says anything, and it reads as "never lost".
  Stream<DeviceLoss> get lost => const Stream<DeviceLoss>.empty();

  /// Whether the device is lost now, and not restored — the state [lost]
  /// reports the changes of, so a caller that subscribed late can ask. Every
  /// backend that reports on [lost] answers here too.
  bool get isLost => false;

  /// Names [resource] — a [TextureHandle], [GeometryBuffer], [StorageBuffer],
  /// [PipelineHandle], [QuerySet] or [RenderBundle] this device made — for a
  /// GPU debugger, a frame capture and the memory report.
  ///
  /// A backend whose API carries labels (WebGPU's `label`) passes it on; the
  /// default keeps it where [labelOf] reads it, and does nothing else.
  void setLabel(Object resource, String label) => _labels[resource] = label;

  /// The label [setLabel] gave [resource], or null when it has none.
  String? labelOf(Object resource) => _labels[resource];

  final Expando<String> _labels = Expando<String>('resource labels');
}

/// A device that reads a buffer back in the calling turn —
/// `DeviceFeature.synchronousReadback`.
///
/// **A capability a device opts into, not a member every device carries**,
/// since 1.0 (E.12 of the API review): WebGPU has no such call by design, and
/// a member every device had to answer was a member three of four answered
/// with a refusal. Asked with `device is SynchronousBufferReadback`; a device
/// that is one lists [DeviceFeature.synchronousReadback] in its features.
/// The software rasteriser and WebGL2 are.
base mixin SynchronousBufferReadback on GraphicsDevice {
  /// The bytes of [buffer] (a range of them), read back in the calling turn.
  ///
  /// **A stall, on purpose.** The call waits for every pass submitted before
  /// it, which is the price WebGL2's `getBufferSubData` charges and the
  /// reason WebGPU has no such call. For a tool or a test that would rather
  /// block than restructure; a frame loop wants
  /// [GraphicsDevice.readBuffer] or [GraphicsDevice.mapBuffer]. [buffer]
  /// must be [BufferUsage.hostReadable].
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  });
}

/// Why a device stopped working — `GraphicsDevice.lost`.
@immutable
final class DeviceLoss {
  /// A loss for [reason], as the backend described it in [message].
  const DeviceLoss({
    required this.reason,
    this.message = '',
    this.isRecoverable = false,
    this.restored = false,
  });

  /// What happened.
  final DeviceLossReason reason;

  /// The backend's own words, for a log.
  final String message;

  /// Whether the same device can come back: a WebGL context the browser may
  /// restore. A WebGPU device lost is not; a new one has to be opened.
  final bool isRecoverable;

  /// True on the event that says a recoverable loss is over: the context is
  /// back, and every resource has to be made again.
  final bool restored;

  @override
  String toString() =>
      'DeviceLoss(${reason.name}${restored ? ', restored' : ''}'
      '${message.isEmpty ? '' : ': $message'})';
}

/// The reasons a [DeviceLoss] can give. An open set: a backend may report a
/// reason a later minor names.
@immutable
final class DeviceLossReason {
  const DeviceLossReason._(this.name);

  /// The reason's stable name, as reports and logs spell it.
  final String name;

  /// The application destroyed the device itself.
  static const DeviceLossReason destroyed = DeviceLossReason._('destroyed');

  /// The platform took it away: a driver reset, a GPU removed, a WebGL
  /// context the browser reclaimed.
  static const DeviceLossReason unknown = DeviceLossReason._('unknown');

  /// Every reason this version names.
  static const List<DeviceLossReason> values = <DeviceLossReason>[
    destroyed,
    unknown,
  ];

  @override
  String toString() => 'DeviceLossReason.$name';
}

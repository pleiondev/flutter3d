/// Shader stages and pipelines, as the engine holds them: by name, and
/// otherwise opaque.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
/// See
/// `graphics/formats.dart` for why the directory exists.
///
/// ## Why this layer is thin on purpose
///
/// The engine never *compiles* a shader. The bundle is built ahead of time by
/// `impellerc` — `tool/build_shaders.sh` — and every stage is reached by the
/// name it was given there. There is no runtime source, no permutation
/// generator, and no second shader story to design against, so an abstraction
/// richer than "look a stage up, pair two of them, bind the pair" would be
/// modelling a client that does not exist.
///
/// What *can* arrive at run time is a whole bundle, as bytes — see
/// `GraphicsDevice.loadShaders` and [LoadedShaderLibrary]. That adds one thing
/// to the vocabulary, reloading, and nothing to what a stage is.
///
/// What the handles *do* buy is that the type of a stage is not a backend type.
/// That is what lets [ShaderHandle] appear in `CommandEncoder.bindUniformBlock`
/// and in the extension-facing frames without dragging a backend into them.
library;

import 'dart:typed_data';

import 'graphics_device.dart';

/// One compiled stage of a pipeline — a vertex or a fragment program.
///
/// Opaque by construction: the engine looks a stage up, hands it to
/// [ShaderLibrary]'s owner to be paired into a pipeline, and names it when
/// filling a uniform block or a sampler slot. It never inspects one.
///
/// [name] is carried rather than derived because it is the only thing the
/// engine can say about a stage in an error message, and because a fake in a
/// test needs something to be recognised by.
/// What a compiled stage keeps: the uniform blocks and samplers its compiled
/// function has a slot for, by name.
typedef StageBindings = ({Set<String> blocks, Set<String> samplers});

/// One member of a uniform block as the compiler lays it out — `H1`.
typedef UniformMemberLayout = ({
  int offset,
  int byteLength,
  int elements,
  String type,
});

///
/// ## Who owns a stage
///
/// **The library that compiled it.** A [ShaderLibrary] answers a name with a
/// handle and keeps it, so two lookups of one name give one handle and a
/// [LoadedShaderLibrary] can keep it working across a reload. Whoever asked
/// holds a reference to the library's handle, not a copy of its own.
///
/// [dispose] gives that reference back: the library forgets the handle, and
/// frees what the backend compiled for it where the backend holds anything
/// (WebGL deletes the shader object; a WebGPU module, an Impeller stage and a
/// software stage are dropped and collected). The next lookup of the same
/// name compiles or wraps the stage afresh, under a new handle. Pipelines
/// already linked from it keep drawing until they are disposed themselves,
/// on every backend. A disposed handle must not be linked or bound again,
/// and a [LoadedShaderLibrary.refresh] no longer counts it as in use.
///
/// The renderer resolves its stages once and holds them for its lifetime,
/// so a handle a renderer still draws with is not the caller's to dispose:
/// dispose the renderer's stages by dropping the renderer and the device
/// with it. What [dispose] is for is a stage an application looked up for
/// itself (a tool's preview, a stage it linked by hand) and is done with.
final class ShaderHandle {
  ShaderHandle._({
    required this.backend,
    required this.name,
    this.kept,
    this.layouts,
    void Function(ShaderHandle handle)? release,
  }) : _release = release; // ignore: prefer_initializing_formals

  final void Function(ShaderHandle handle)? _release;

  /// Gives this handle back to the library that made it, once; see "Who owns
  /// a stage" above. A second call does nothing, and a handle made without a
  /// library (a test's) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The backend's own object for this stage.
  ///
  /// `Object` for the reason `TextureHandle.backend` is: every layer above the
  /// backend must be able to hold one without knowing what is inside, and a
  /// type parameter would spread through all of them.
  final Object backend;

  /// The entry point this stage was found under, as the bundle spells it.
  final String name;

  /// What the compiled stage kept, or null where the library cannot say —
  /// `gfx-92n`.
  ///
  /// **The answer reflection cannot give.** Reflection reports a block the
  /// GLSL declared even when the compiler dropped it, and binding that
  /// phantom is a native crash inside Metal: the 0.7.1 crash, where an unlit
  /// draw was handed a light list nobody declared live. The engine's own
  /// stages come with `stageBindings`, generated from what impellerc kept and
  /// held to a fresh compile by a test, and every backend fills this from it.
  /// A stage from an application's own bundle has no such table and is null
  /// here, and the renderer then goes by what its `LightingModel` declares.
  ///
  /// A backend refuses a bind this names as absent, answering false exactly
  /// as it does for a slot the stage never declared.
  final StageBindings? kept;

  /// How the compiler laid out each of this stage's uniform blocks, or null
  /// where the library cannot say — `H1`. From the bundle's own table
  /// (`uniformBlocks` in `flutter3d_shaders`), for the backends that do not
  /// reflect a block's members themselves, so a member the caller named and
  /// the block does not have is refused by name everywhere.
  final Map<String, Map<String, UniformMemberLayout>>? layouts;

  /// Whether [block] may be bound: false when [kept] says it was dropped,
  /// true otherwise.
  bool mayBindBlock(String block) => kept?.blocks.contains(block) ?? true;

  /// Whether [sampler] may be bound, as [mayBindBlock].
  bool mayBindSampler(String sampler) =>
      kept?.samplers.contains(sampler) ?? true;

  @override
  String toString() => 'ShaderHandle($name)';
}

/// A vertex and a fragment stage, linked into something that can be bound.
///
/// Deliberately **not** a description of pipeline state. On this backend cull
/// mode, winding, depth compare and blend are *pass* state and are set per
/// draw; a pipeline is exactly the pair of stages. A backend that needs the
/// state baked in — Vulkan does — has to fold it in on its own side, and this
/// is one of the places that will strain. See the note on `CommandEncoder`.
final class PipelineHandle {
  PipelineHandle._(this._release, {required this.backend, required this.name});

  final void Function(PipelineHandle)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  final Object backend;

  /// `vertex+fragment`, for profiling and for a fake to be asserted against.
  final String name;

  @override
  String toString() => 'PipelineHandle($name)';
}

/// The stages a compiled bundle holds, addressed by name.
///
/// An interface with one operator, because that is the whole of what the engine
/// asks of a bundle. A missing name comes back null rather than throwing: the
/// callers differ on what to do about it — the renderer refuses to start,
/// `ParticleContributor` complains once and draws nothing — and only they can
/// decide.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
abstract base mixin class ShaderLibrary {
  /// The stage called [name], or null if the bundle has none.
  ShaderHandle? operator [](String name);
}

/// A library a device built from bytes it was handed, and can rebuild.
///
/// What `GraphicsDevice.loadShaders` returns. It answers names like any
/// [ShaderLibrary]; what it adds is [refresh], and the one promise that makes
/// reloading worth having: **a handle already handed out keeps its identity
/// and keeps working.** The renderer resolves its vertex stages once and holds
/// the handles for its lifetime, so a reload that answered the same names with
/// new handles would leave every pipeline the renderer builds afterwards
/// linking against stale objects. Each backend keeps the promise its own way —
/// flutter_gpu mutates the stage in place, WebGL swaps the compiled object
/// inside the handle, the software rasteriser never had anything to swap — and
/// the conformance suite checks it by identity.
///
/// Reloading does not rebuild pipelines. A pipeline is a pair of stages linked
/// on the backend, and the linked object is the caller's to drop:
/// `Renderer.relinkShaders` is the engine's half of the same gesture. Until
/// it is dropped it keeps drawing the code it was linked from, on every
/// backend — a frame between a refresh and a relink is the old picture, not
/// a missing one.
///
/// There is no `dispose` for the library: it lives as long as the device that
/// built it, and `GraphicsDevice.loadShaders` says why. A stage of it is given
/// back one at a time, with `ShaderHandle.dispose`.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
base mixin LoadedShaderLibrary on ShaderLibrary {
  /// The bundle's own name, as its header spells it — what a refusal names.
  String get name;

  /// Reparses [bytes] into this library in place.
  ///
  /// [bytes] are a whole bundle, the same shape `GraphicsDevice.loadShaders`
  /// took, and the same refusals apply: bytes that are not a bundle, a section
  /// this backend has none of, an SDK it was not compiled on, a stage this
  /// backend cannot run. A refused reload throws `ShaderBundleException` and
  /// **leaves the library as it was**, so an editor that rebuilt a bundle
  /// wrongly keeps drawing with the one that worked.
  ///
  /// **A bundle that no longer names a stage already handed out is refused
  /// too, naming the stage.** The handle is the renderer's for its lifetime —
  /// that is the identity promise above — so a library that answered a name
  /// once and then accepted a bundle without it would leave a live handle
  /// over a stage the bundle does not have: on one backend a pipeline that
  /// still draws the old code, on another a link error at the next frame,
  /// and in both cases a picture that disagrees with the file. Every backend
  /// refuses the same way, before anything is swapped, and the conformance
  /// suite holds them to it. A name that was asked for and answered null is
  /// not in use, and a bundle may drop or add it freely.
  void refresh(ByteData bytes);
}

/// Two libraries consulted in order, the first winning.
///
/// **The extension point an application needs, and the whole of it.** A
/// [ShaderLibrary] answers one question — what stage goes by this name — so a
/// library that asks one source and then another is the entire mechanism for
/// letting an application add a shader the engine did not ship. There is no
/// registry to manage and nothing to unregister: the application owns its
/// library and hands it in.
///
/// **[first] wins on a clash, and that is deliberate.** An application naming a
/// stage the engine already has is either replacing it on purpose or has
/// collided by accident, and of the two the first is worth supporting: an
/// application that wants its own `Pbr` should get its own `Pbr`. A collision it
/// did not intend shows up as its own shader running everywhere, which is
/// visible immediately — unlike the other order, where the engine's would
/// silently win and the new shader would appear to have no effect at all.
final class LayeredShaderLibrary with ShaderLibrary {
  const LayeredShaderLibrary(this.first, this.second);

  final ShaderLibrary first;
  final ShaderLibrary second;

  @override
  ShaderHandle? operator [](String name) => first[name] ?? second[name];
}

/// Any number of libraries consulted in order, the first that answers
/// winning — `P8`.
///
/// What a game with more than one compiled material bundle hands the
/// renderer: each `.f3dmat` the build hook compiles is a bundle of its own,
/// and [LayeredShaderLibrary] takes two. The same rule as there — the
/// earlier library wins a clash — for the same reason.
///
/// The list is copied, so a caller adding to its own list afterwards changes
/// nothing here; a renderer that takes libraries one at a time keeps its own
/// stack — see `renderer.renderSteps.addMaterials`.
final class ShaderLibraryStack with ShaderLibrary {
  ShaderLibraryStack(Iterable<ShaderLibrary> libraries)
    : libraries = List<ShaderLibrary>.unmodifiable(libraries);

  /// The libraries, searched first to last.
  final List<ShaderLibrary> libraries;

  @override
  ShaderHandle? operator [](String name) {
    for (final library in libraries) {
      final found = library[name];
      if (found != null) return found;
    }
    return null;
  }
}

/// A [ShaderHandle] over a backend's own compiled [backend] stage — for a
/// backend's [ShaderLibrary], from `package:flutter3d_hardware/backend.dart`.
///
/// [release] is what the handle's `dispose` calls, once: the library's own
/// forgetting of it, and freeing what the backend compiled for it. Null for a
/// handle no library keeps.
ShaderHandle wrapShader({
  required Object backend,
  required String name,
  StageBindings? kept,
  Map<String, Map<String, UniformMemberLayout>>? layouts,
  void Function(ShaderHandle handle)? release,
}) => ShaderHandle._(
  backend: backend,
  name: name,
  kept: kept,
  layouts: layouts,
  release: release,
);

/// Takes [handle] out of [handles] if it is still the one kept under its
/// name — the `release` most libraries hand [wrapShader]. A library that
/// frees a backend object as well does so beside it.
void forgetShader(Map<String, ShaderHandle?> handles, ShaderHandle handle) {
  if (identical(handles[handle.name], handle)) handles.remove(handle.name);
}

/// A [PipelineHandle] over a backend's own linked [backend] pipeline, for a
/// backend. [owner]'s `releasePipeline` is what the handle's `dispose` calls.
PipelineHandle wrapPipeline({
  required Object backend,
  required String name,
  GraphicsDevice? owner,
}) => PipelineHandle._(owner?.releasePipeline, backend: backend, name: name);

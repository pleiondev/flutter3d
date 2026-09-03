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

/// One compiled stage of a pipeline — a vertex or a fragment program.
///
/// Opaque by construction: the engine looks a stage up, hands it to
/// [ShaderLibrary]'s owner to be paired into a pipeline, and names it when
/// filling a uniform block or a sampler slot. It never inspects one.
///
/// [name] is carried rather than derived because it is the only thing the
/// engine can say about a stage in an error message, and because a fake in a
/// test needs something to be recognised by.
final class ShaderHandle {
  const ShaderHandle({required this.backend, required this.name});

  /// The backend's own object for this stage.
  ///
  /// `Object` for the reason `TextureHandle.backend` is: every layer above the
  /// backend must be able to hold one without knowing what is inside, and a
  /// type parameter would spread through all of them.
  final Object backend;

  /// The entry point this stage was found under, as the bundle spells it.
  final String name;

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
  const PipelineHandle({required this.backend, required this.name});

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
abstract interface class ShaderLibrary {
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
/// `Renderer.relinkShaders` is the engine's half of the same gesture.
abstract interface class LoadedShaderLibrary implements ShaderLibrary {
  /// The bundle's own name, as its header spells it — what a refusal names.
  String get name;

  /// Reparses [bytes] into this library in place.
  ///
  /// [bytes] are a whole bundle, the same shape `GraphicsDevice.loadShaders`
  /// took, and the same refusals apply: bytes that are not a bundle, a section
  /// this backend has none of, an SDK it was not compiled on, a stage this
  /// backend cannot run. A refused reload throws `ShaderBundleRefused` and
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
final class LayeredShaderLibrary implements ShaderLibrary {
  const LayeredShaderLibrary(this.first, this.second);

  final ShaderLibrary first;
  final ShaderLibrary second;

  @override
  ShaderHandle? operator [](String name) => first[name] ?? second[name];
}

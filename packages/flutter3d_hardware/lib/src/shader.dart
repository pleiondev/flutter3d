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
/// What the handles *do* buy is that the type of a stage is not a backend type.
/// That is what lets [ShaderHandle] appear in `CommandEncoder.bindUniformBlock`
/// and in the extension-facing frames without dragging a backend into them.
library;

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

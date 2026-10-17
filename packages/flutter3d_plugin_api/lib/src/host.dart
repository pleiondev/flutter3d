import 'events.dart';
import 'loop.dart';
import 'manifest.dart';
import 'registration.dart';
import 'render.dart';
import 'simulation_profile.dart';
import 'version.dart';

/// What a plugin is handed in `install`: the engine's registries, as this
/// plugin sees them.
///
/// **Every registry here is scoped to the plugin being installed.** What it
/// registers is tracked and cancelled when the plugin is switched off, ranked
/// by its place in the install order, and checked against its manifest — a
/// view plugin is refused a step system here, at the call, with its name in
/// the message.
///
/// ## The kernel's registries and the rest
///
/// [loop] and [events] are the kernel's and every engine has them. Everything
/// else — render steps, decoders, entity kinds, editor pieces, MCP tools —
/// is a [PluginRegistry] some package of the engine provides, looked up by
/// its type with [registry]. That is what lets a later step of the engine
/// add a registry without this interface changing: the package that fills a
/// registry declares it (`DecoderRegistry` in `flutter3d_core`,
/// `EntityKindRegistry` in `flutter3d_sim`, `EditorRegistry` in
/// `flutter3d_editor_core`, `McpToolRegistry` in `flutter3d_mcp`) and hands
/// it to the host. An engine without, say, an editor has no editor
/// registry, and a plugin that wants one either asks [maybeRegistry] or is
/// refused by name.
///
/// Made by the plugin host: `base`, so a member added in a later minor
/// arrives with a default.
abstract base class PluginHost {
  const PluginHost();

  /// The manifest of the plugin being installed.
  PluginManifest get manifest;

  /// The plugin API this engine provides.
  PluginApiVersion get apiVersion;

  /// The graphics backend the engine runs on, or null when it draws nothing
  /// — a server, a test.
  String? get backend;

  /// What the simulation the plugin is installed in promises about its
  /// numbers. A plugin that relies on a capability asks it
  /// (`host.profile.isBitExact`), never which profile it is.
  ///
  /// `SimulationProfile.deterministic` unless the host says otherwise: what
  /// every engine was before there was a second profile.
  ///
  /// **The world's own profile is the same one.** What a world is made of —
  /// its gravity, air, medium, where it sits on the Earth and this profile —
  /// is a `WorldProperties` (`flutter3d_matter`, which stands on this
  /// package and so cannot be named in a signature here), read where the
  /// bodies are (`CollisionWorld.properties`) and by a level
  /// (`Level.worldOver`). A plugin that steps bodies reads the world there,
  /// and the substances in it through `host.registry<MaterialCatalog>()`;
  /// the engine's loop stages a world whose `WorldProperties.profile` is
  /// this one.
  SimulationProfile get profile => SimulationProfile.deterministic;

  /// The loop's phases and systems.
  LoopRegistry get loop;

  /// The event bus.
  EventRegistry get events;

  /// The registry of type [R]. Throws a [StateError] naming [R] and the
  /// plugin when this engine has none.
  R registry<R extends PluginRegistry>();

  /// The registry of type [R], or null when this engine has none.
  R? maybeRegistry<R extends PluginRegistry>();
}

// The typed slots. Each is filled by the package that owns the thing it
// registers, in the step of the plugin plan that opens it; until then an
// engine has none of them and `maybeRegistry` answers null. They are
// declared here, empty, so the API version a plugin names already knows
// their types. Each is `base`: a member added to one later arrives with a
// default, which is a minor version of the plugin API.

/// Render steps, anchored to the engine's passes. Filled by the renderer.
///
/// **The slot, not the whole of it.** A render step is a switch over the
/// renderer's settings and a node is a pass in its frame graph, and neither
/// type can be named in the contract, which stands on the foundation alone. So the renderer in
/// `flutter3d_core` fills this slot with `RendererSteps`, which adds
/// `addStep` and `addNode(node, at: anchor)`, and a plugin that draws asks
/// for that type: `host.registry<RendererSteps>()`. What this interface
/// carries is what holds without the renderer's types: the places a node may
/// go, [anchors].
///
/// An engine gets one by handing its renderer's registry to the plugin host
/// among its registries: `EngineLoop(registries: [renderer.renderSteps])`.
abstract base class RenderStepRegistry extends PluginRegistry {
  const RenderStepRegistry();

  /// Where a plugin's node may go, in the order the frame meets them —
  /// [RenderAnchor.values] for this engine.
  List<RenderAnchor> get anchors => RenderAnchor.values;

  /// The name of every node placed through this registry and its plugins'
  /// views, at every anchor, in the order the frame meets them; the
  /// engine's own passes are not among them. What the conformance suite
  /// reads to know whether a plugin draws. Empty unless the renderer says.
  List<String> get nodeNames => const <String>[];
}

import 'events.dart';
import 'loop.dart';
import 'manifest.dart';
import 'registration.dart';
import 'render.dart';
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
}

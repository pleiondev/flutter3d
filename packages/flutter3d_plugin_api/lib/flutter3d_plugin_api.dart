/// The interfaces a flutter3d plugin is written against.
///
/// A plugin is a [Flutter3dPlugin]: a [PluginManifest] — its id, the plugin
/// API version it was written for, its dependencies, the backends it runs
/// on, whether it touches the simulation or only the view, the permissions
/// it asks for — and an `install` that registers what it adds through the
/// [PluginHost] it is handed.
///
/// The host's registries are the engine's: [LoopRegistry] for phases and
/// systems, [EventRegistry] for the bus, and typed slots
/// ([RenderStepRegistry], [DecoderRegistry], [EntityKindRegistry],
/// [EditorRegistry], [McpToolRegistry]) that the engine's packages fill.
/// [PluginManager] is the host itself: it checks versions, orders
/// dependencies and switches plugins on and off at step boundaries, and the
/// loop in `flutter3d_sim` owns one.
///
/// **No dependencies**, so a plugin depends on this and on nothing of the
/// engine's that can change under it. See the package README for discovery
/// through `plugins.g.dart`, and for [RenderAnchor], the places in the frame
/// a plugin's pass may go.
///
/// **And the engine's foundation types, re-exported** from
/// `flutter3d_foundation`, where they live since 1.0.0-rc.1:
/// [Flutter3dException] and its families, the root of everything the engine
/// throws; [WorldPosition], a place in the world in double precision;
/// [LinearColor], the one colour type; [Issue]; the file envelope
/// ([FormatSpec], [FormatDocument]); and [Registration]. A plugin's
/// signatures name them, so a plugin gets them from this one import. A
/// package that needs them and not the contract depends on the foundation.
/// `docs/CONTRACTS.md` gives the units they are in.
library;

// The foundation types the contract's signatures name, by the names this
// package held before they moved, so a plugin written against it keeps
// compiling. `flutter3d_foundation`'s vector crossings and `Portable` are
// not the contract's and are not re-exported.
export 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        CapabilityException,
        DocumentFormatException,
        Flutter3dException,
        Flutter3dFormatException,
        FormatDocument,
        FormatMigration,
        FormatRefusal,
        FormatSpec,
        Issue,
        IssueSink,
        LinearColor,
        PluginException,
        Registration,
        ResourceException,
        WorldPosition;

export 'src/changes.dart';
export 'src/data_section.dart';
export 'src/ecs.dart';
export 'src/events.dart';
export 'src/formats.dart';
export 'src/host.dart';
export 'src/loop.dart';
export 'src/manager.dart';
export 'src/manifest.dart';
export 'src/order.dart';
export 'src/plugin_version.dart';
export 'src/registration.dart';
export 'src/render.dart';
export 'src/simulation.dart';
export 'src/simulation_version.dart';
export 'src/version.dart';
export 'src/vm_extensions.dart';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PluginException;

import 'host.dart';
import 'plugin_ids.dart';
import 'plugin_version.dart';
import 'version.dart';

/// Whether a plugin changes what the simulation computes, or only what is
/// shown of it.
///
/// **The line replays are drawn on.** Switching a simulation plugin on at
/// step 300 changes every step after it, so the switch is written into the
/// run and a replay makes it at the same step. Switching a view plugin —
/// bloom, a debug overlay, a sound pack — changes nothing a replay checks,
/// and an older build may open the run regardless.
///
/// The host holds a view plugin to its word: it may not add a step phase,
/// a system to a step phase, or a subscriber to the step channel. A
/// [tooling] plugin is held to the same, and further: it registers no
/// subsystem and no render step, node or shader stage, since a game ships
/// without it.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1), so a
/// later minor may name another kind; anything that is not [view] or
/// [tooling] is treated as touching the simulation, the safe reading of a
/// kind this build does not know.
final class PluginTouches {
  const PluginTouches._(this.name);

  /// Runs inside the fixed step: phases, systems, step subscriptions.
  static const PluginTouches simulation = PluginTouches._('simulation');

  /// Runs only in the frame: frame phases, frame subscriptions, render steps,
  /// editor pieces.
  static const PluginTouches view = PluginTouches._('view');

  /// Runs only in the tools around a game: the editor's pieces, panels and
  /// hints, and the tools it offers an agent. Leaves `SimulationVersion`
  /// alone, as a [view] plugin does, and adds no subsystem, render step,
  /// node or shader stage, so an application that is not an editor need not
  /// install it at all: nothing a game draws or steps depends on it.
  static const PluginTouches tooling = PluginTouches._('tooling');

  /// Every value this version names, in declaration order. A later
  /// version appends; nothing is removed or renamed within a major.
  static const List<PluginTouches> values = <PluginTouches>[
    simulation,
    view,
    tooling,
  ];

  /// The value called [name], or null for a name this version does not
  /// know, which is what a file written by a later version can carry.
  static PluginTouches? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Reads a name back. A name this build does not know is kept as it was
  /// written, so a manifest read and written again says what it said, and
  /// it is treated as [simulation] — the kind held to every rule — until a
  /// build that knows it reads it.
  static PluginTouches named(String name) => switch (name) {
    'view' => view,
    'simulation' => simulation,
    'tooling' => tooling,
    _ => PluginTouches._(name),
  };

  /// The kind's name, as a manifest's `touches` writes it. A name this build
  /// does not know is kept as written ([isKnown] is false then).
  final String name;

  /// Whether this build knows the kind: [simulation], [view] or [tooling].
  bool get isKnown =>
      name == simulation.name || name == view.name || name == tooling.name;

  /// Whether a plugin of this kind may change the simulation: every kind but
  /// [view] and [tooling], an unknown one included.
  bool get simulates => this != view && this != tooling;

  @override
  bool operator ==(Object other) =>
      other is PluginTouches && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// Something a plugin says it will reach for beyond the engine's own API.
///
/// **Declared rather than enforced, for a Dart plugin.** A Dart plugin is
/// compiled into the application and trusted as any dependency is; nothing
/// in a Dart process can stop it opening a socket. What the declaration buys
/// is that the engine refuses access *where it hands access out* — to a
/// Wasm module, a data plugin, an interpreted script — and that a person
/// installing a plugin reads what it asks for. Open, like `GameAction`: a
/// host may name its own.
final class PluginPermission {
  /// A permission named [name]: one of the constants here, or a host's own.
  const PluginPermission(this.name);

  /// Talks to the network.
  static const PluginPermission network = PluginPermission('network');

  /// Reads or writes files outside the application's assets.
  static const PluginPermission files = PluginPermission('files');

  /// Offers tools to an agent through the project's MCP servers. Checked by
  /// `McpTools.addTool`, and by the editor's MCP server before it offers a
  /// plugin's editor commands as tools: a plugin that did not ask for it is
  /// refused there, and its commands stay the editor's own, so a person
  /// installing a plugin sees that it talks to agents.
  static const PluginPermission tools = PluginPermission('tools');

  /// Takes over a step or a shader stage the engine draws: provides a
  /// built-in render step, or hands the renderer a stage under one of the
  /// engine's names. Checked by the renderer: a plugin from outside the
  /// engine takes over only what its `RenderStepAddon` declares in
  /// `replaces` and `replacesStages`, and only with this permission, so a
  /// person installing it sees that it changes what the engine draws, and
  /// everything else it adds stays in its namespace.
  static const PluginPermission replace = PluginPermission('replace');

  /// Every value this version names, in declaration order. A later
  /// version appends; nothing is removed or renamed within a major.
  static const List<PluginPermission> values = <PluginPermission>[
    network,
    files,
    tools,
    replace,
  ];

  /// The value called [name], or null for a name this version does not
  /// know, which is what a file written by a later version can carry.
  static PluginPermission? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The permission's name, as a manifest's `permissions` writes it and a
  /// person installing the plugin reads it.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PluginPermission && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// What a plugin says about itself before it is installed.
///
/// Read by the host before `install` runs: the version is checked, the
/// dependencies ordered, the backend matched, so a plugin that cannot run
/// is refused with a sentence instead of failing halfway through
/// registering.
///
/// **Grows by optional fields, and keeps what it does not know.** A
/// manifest read from a document — a data plugin's, a Wasm module's, a
/// catalogue's — may carry keys a later minor added; [extra] holds them as
/// they were and [toJson] writes them back, so a tool that reads and writes
/// a manifest does not strip what it did not understand.
final class PluginManifest {
  /// A manifest for the plugin [id] written against [apiVersion].
  ///
  /// Checks nothing here: a malformed id is refused when the plugin is
  /// installed ([idProblem]). Without [version] the plugin is
  /// [PluginVersion.none]; without [touches] it is held to every rule of
  /// [PluginTouches.simulation].
  const PluginManifest({
    required this.id,
    required this.apiVersion,
    this.version = PluginVersion.none,
    this.simulationVersion = 1,
    this.dependsOn = const <String>[],
    this.backends = const <String>{},
    this.touches = PluginTouches.simulation,
    this.permissions = const <PluginPermission>{},
    this.description,
    this.extra = const <String, Object?>{},
  });

  /// Reads a manifest, or throws a [PluginFormatException] saying why not. Keys
  /// it does not know go to [extra].
  factory PluginManifest.fromJson(Map<String, Object?> json) {
    List<String> names(String key) => switch (json[key]) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw PluginFormatException('"$key" is not a list of names', json),
    };
    final id = json['id'];
    if (id is! String) {
      throw PluginFormatException('the manifest names no plugin id', json);
    }
    final version = json['apiVersion'];
    if (version is! String) {
      throw PluginFormatException(
        'the manifest of "$id" names no plugin API version',
        json,
      );
    }
    final touches = json['touches'];
    final description = json['description'];
    final own = json['version'];
    final simulation = json['simulationVersion'] ?? 1;
    if (own != null && own is! String) {
      throw PluginFormatException(
        'the manifest of "$id" gives its version as $own, not as text',
        json,
      );
    }
    if (simulation is! int || simulation < 0) {
      throw PluginFormatException(
        'the manifest of "$id" names simulation version $simulation',
        json,
      );
    }
    final manifest = PluginManifest(
      id: id,
      apiVersion: PluginApiVersion.parse(version),
      version: own is String ? PluginVersion.parse(own) : PluginVersion.none,
      simulationVersion: simulation,
      // A dependency on an engine plugin by its id from before 1.0 is on
      // the plugin of that id now.
      dependsOn: List<String>.unmodifiable(<String>[
        for (final entry in names('dependsOn')) liftPluginDependency(entry),
      ]),
      backends: names('backends').toSet(),
      touches: touches is String
          ? PluginTouches.named(touches)
          : PluginTouches.simulation,
      permissions: <PluginPermission>{
        for (final name in names('permissions')) PluginPermission(name),
      },
      description: description is String ? description : null,
      extra: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in json.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      }),
    );
    // Read now, so a range that is not one is refused with the manifest.
    manifest.dependencies;
    return manifest;
  }

  /// The plugin's name, unique among the plugins of one engine: lower case
  /// letters, digits, `_`, `.` and `-`, starting with a letter.
  ///
  /// Up to its first dot, also the [namespace] everything it registers is
  /// filed under, its MCP tools and editor pieces included, so it should be
  /// the package's name or start with it.
  final String id;

  /// The plugin API this plugin was written against. See [PluginApiVersion].
  final PluginApiVersion apiVersion;

  /// This plugin's own release, which another plugin's [dependsOn] range is
  /// held to. [PluginVersion.none] for a plugin that names none, which only
  /// a dependency accepting any version installs beside.
  final PluginVersion version;

  /// The number of this plugin's simulation, by `SimulationVersion`'s
  /// promise: bumped by a minor release that changes what a step computes,
  /// never by a patch. Read only for a plugin that [touches] the simulation;
  /// a run and a network hello carry it under the plugin's id.
  final int simulationVersion;

  /// The plugins that must be installed, and enabled, before this one, each
  /// as `'id'` or `'id <range>'` — `'heat'`, `'heat ^1.2.0'`,
  /// `'heat >=1.0.0 <3.0.0'` (see [PluginDependency]). A dependency is
  /// installed first, so what it registers is there when this plugin's
  /// `install` runs, and one whose [version] is outside the range is
  /// refused with both numbers named.
  final List<String> dependsOn;

  /// The graphics backends this plugin runs on, by `GraphicsDevice` name —
  /// `'webgpu'`, `'cpu'` — or empty for all of them. A plugin that does not
  /// run on the engine's backend is installed switched off, with the reason
  /// in its status.
  final Set<String> backends;

  /// Whether it changes the simulation or only the view. Simulation by
  /// default, because that is the safe answer to get wrong: a view plugin
  /// mislabelled as simulation costs a line in a replay file, the other way
  /// round costs a replay that does not hold.
  final PluginTouches touches;

  /// What it reaches for beyond the engine's API. See [PluginPermission].
  final Set<PluginPermission> permissions;

  /// One sentence for a plugin list.
  final String? description;

  /// Keys this build does not know, kept as they were read.
  final Map<String, Object?> extra;

  static final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');

  /// The namespaces of the engine's own plugins: every package this
  /// repository publishes on pub.dev, today or under the name it had at
  /// 0.8 (`pointer_lock` is `flutter3d_pointer_lock` now). pub.dev gives a
  /// package name to one publisher, so nobody else can ship a plugin under
  /// one of these.
  ///
  /// **Only names that were published.** The `flutter3d_addon_*` packages
  /// of 0.8 never were, and `flutter3d_demo_content` never will be, so
  /// anybody could publish one; none of them is here. The plugins the
  /// add-ons had are named after the packages that ship them now.
  ///
  /// Held to the repository's published packages and the 0.8.5 release's
  /// by a test, so a package added to the engine is added here, and a minor
  /// that adds one only adds to the list.
  static const Set<String> engineNamespaces = <String>{
    'flame_flutter3d',
    'flame_flutter3d_audio',
    'flame_multiplayer',
    'flame_multiplayer_dashwire',
    'flutter3d',
    'flutter3d_app',
    'flutter3d_audio',
    'flutter3d_audio_core',
    'flutter3d_build',
    'flutter3d_build_hooks',
    'flutter3d_camera',
    'flutter3d_conformance',
    'flutter3d_conformance_render',
    'flutter3d_core',
    'flutter3d_cpu',
    'flutter3d_editor_core',
    'flutter3d_editor_mcp',
    'flutter3d_editor_play',
    'flutter3d_editor_widgets',
    'flutter3d_education',
    'flutter3d_education_lti',
    'flutter3d_effects',
    'flutter3d_elements',
    'flutter3d_fields',
    'flutter3d_foundation',
    'flutter3d_game',
    'flutter3d_game_kit',
    'flutter3d_game_physics',
    'flutter3d_game_platformer',
    'flutter3d_game_racing',
    'flutter3d_game_shooter',
    'flutter3d_game_strategy',
    'flutter3d_game_ui',
    'flutter3d_hardware',
    'flutter3d_hub',
    'flutter3d_impeller',
    'flutter3d_lab',
    'flutter3d_level_scene',
    'flutter3d_lints',
    'flutter3d_lti',
    'flutter3d_matter',
    'flutter3d_mcp',
    'flutter3d_mcp_kit',
    'flutter3d_mesh',
    'flutter3d_model_core',
    'flutter3d_model_mcp',
    'flutter3d_net',
    'flutter3d_net_webrtc',
    'flutter3d_particles',
    'flutter3d_physics',
    'flutter3d_physics_native',
    'flutter3d_plugin_api',
    'flutter3d_plugin_runtime',
    'flutter3d_pointer_lock',
    'flutter3d_post',
    'flutter3d_samples',
    'flutter3d_shaders',
    'flutter3d_sim',
    'flutter3d_sim_mcp',
    'flutter3d_stereo',
    'flutter3d_testing',
    'flutter3d_voxel',
    'flutter3d_webgl',
    'flutter3d_webgpu',
    'flutter3d_wgpu',
    'pad_input',
    'pointer_lock',
  };

  /// The first segments the engine names its own areas by, which no plugin
  /// from outside may take as its [namespace]: the areas of its MCP tools
  /// (`light.add`), of its VM extensions (`ext.flutter3d.render.capture`)
  /// and of its events (`physics.contact`), and the areas a later minor is
  /// expected to bring.
  ///
  /// **Why a plugin may not be called `light`.** Its MCP tools are offered
  /// as `<namespace>.<name>` beside the server's own, and its VM extensions
  /// sit at `ext.flutter3d.<id>.<verb>` beside the engine's, so a plugin
  /// named after an area the engine adds in a minor would lose its tools to
  /// the server's, or stop the application at start with an extension
  /// registered twice. Refusing the name at install, before 1.0.0, is what
  /// lets a minor add to an area without breaking a plugin. Held to the
  /// `.mcp` and `.vm` snapshots and the engine's event names by a test;
  /// [reservedNamespace] is refused separately, for names as well.
  ///
  /// **Frozen at 1.0.0.** An area added here later would refuse a plugin
  /// already installed under that name, which is a break, so a test holds
  /// the set to the list 1.0.0 shipped. An area a 1.x minor brings goes
  /// under [reservedNamespace] (`f3d.<area>.<tool>` for an MCP tool,
  /// `f3d.<area>.<name>` for an event, `ext.flutter3d.f3d.<area>.` for a VM
  /// extension), or under a name with an upper-case letter, which no plugin
  /// id can have (`docs/CONTRACTS.md`, "Namespaces").
  static const Set<String> reservedAreas = <String>{
    // The MCP servers' areas.
    'animationGraph', 'asset', 'behavior', 'brush', 'capture', 'clip',
    'command', 'cutscene', 'experiment', 'game', 'history', 'image', 'joint',
    'key', 'kit', 'level', 'light', 'lod', 'material', 'mesh', 'modifier',
    'object', 'paint', 'play', 'plugin', 'prefab', 'project', 'render',
    'retopology', 'rig', 'run', 'scene', 'sculpt', 'selection', 'shapeDriver',
    'shapeKey', 'simulation', 'skeleton', 'skin', 'state', 'texture',
    'textureGraph', 'track', 'type', 'uv', 'view',
    // The VM extensions' areas.
    'assets', 'cvar', 'timeline', 'version',
    // The events' areas.
    'actor', 'animation', 'elements', 'origin', 'physics', 'platformer',
    'racing', 'sequence', 'shooter', 'strategy', 'wasm',
    // Areas the engine has as packages and may give tools or events.
    'audio', 'camera', 'editor', 'effects', 'fields', 'hub',
    'input', 'matter', 'net', 'particles', 'post', 'sim', 'voxel', 'xr',
  };

  /// The engine's own namespace: `f3d.`, which no plugin from outside the
  /// engine may register a name in.
  static const String reservedNamespace = 'f3d';

  static const Set<String> _known = <String>{
    'id',
    'apiVersion',
    'version',
    'simulationVersion',
    'dependsOn',
    'backends',
    'touches',
    'permissions',
    'description',
  };

  /// [dependsOn], read. Throws a [PluginFormatException] for an entry whose
  /// range is not one.
  List<PluginDependency> get dependencies => <PluginDependency>[
    for (final entry in dependsOn) PluginDependency.parse(entry),
  ];

  /// The ids [dependsOn] names, without their ranges.
  List<String> get dependencyIds => <String>[
    for (final dependency in dependencies) dependency.id,
  ];

  /// Whether this plugin runs on [backend]; null asks about no backend in
  /// particular, which every plugin answers yes to.
  bool runsOn(String? backend) =>
      backend == null || backends.isEmpty || backends.contains(backend);

  /// Why [id] is not a usable name, or null when it is: an id that is not
  /// lower case letters, digits, `_`, `.` and `-`, one with `__` in it, or,
  /// when the plugin is not the engine's own, whose [namespace] is one of
  /// the engine's [reservedAreas], or the namespace of a 0.8 add-on whose
  /// plugins' ids readers lift to the engine's.
  ///
  /// **`__` is the dot of a shader's name.** A lighting model `acme.Ink` is
  /// compiled as the stage `acme__Ink`, and an id with `__` in it could
  /// spell another plugin's stage (`acme__ink` + `Glow` is `acme` +
  /// `ink__Glow`).
  String? get idProblem {
    if (!_idPattern.hasMatch(id)) {
      return 'a plugin id is lower case letters, digits, "_", "." and "-", '
          'starting with a letter; "$id" is not one';
    }
    if (id.contains('__')) {
      return 'a plugin id has no "__", which is how a shader spells the dot '
          'of a name in the plugin\'s namespace; "$id" has one';
    }
    if (isEngine) return null;
    if (reservedAreas.contains(namespace)) {
      return 'plugin "$id" takes the namespace "$namespace", which names one '
          'of the engine\'s own areas (its MCP tools, VM extensions and '
          'events start with it); a plugin names itself after its package';
    }
    if (retiredPluginNamespaces.contains(namespace)) {
      return 'plugin "$id" takes the namespace "$namespace", which the '
          'engine\'s own plugins were named by before 1.0, and a recorded run '
          'that names them is read as naming the engine\'s; a plugin names '
          'itself after its package';
    }
    return null;
  }

  /// The namespace every name this plugin registers starts with, a dot after
  /// it: its [id] up to the first dot — the package that ships it, so the
  /// effects of one package (`acme_frost.frost`, `acme_frost.haze`) share
  /// `acme_frost.`.
  ///
  /// **What keeps a name of a plugin's from meeting one of the engine's, or
  /// another plugin's** (D23): a render step, a node, an anchor, a settings
  /// slot, a resource it makes, a light type, a format — each is
  /// `<namespace>.<name>`, so a name the engine adds in a minor (which never
  /// carries a plugin's namespace) cannot be one a plugin already took. `f3d`
  /// is the engine's own and no plugin from outside it may use it. Names are
  /// compared case-sensitively everywhere.
  String get namespace {
    final dot = id.indexOf('.');
    return dot < 0 ? id : id.substring(0, dot);
  }

  /// Whether this plugin ships with the engine — its [namespace] is one of
  /// [engineNamespaces] — and so registers the engine's own names, which
  /// carry no plugin's namespace. Every engine plugin is named after the
  /// package that ships it, as every other plugin is.
  ///
  /// Decided by the lists, never by a prefix: pub.dev reserves no
  /// `flutter3d_` prefix, so a package published as `flutter3d_frost` by
  /// somebody else is a plugin from outside and is held to its namespace.
  bool get isEngine => engineNamespaces.contains(namespace);

  /// Why this plugin may not register [name] as [what] — a sentence naming
  /// both — or null when it may: [name] is `<namespace>.<something>`, or the
  /// plugin is one of the engine's own ([isEngine]).
  String? nameProblem(String name, {required String what}) {
    if (isEngine) return null;
    if (namespace == reservedNamespace) {
      return 'plugin "$id" registered $what "$name": the namespace '
          '"$reservedNamespace" is the engine\'s own, and a plugin from outside '
          'it names itself after its package';
    }
    final prefix = '$namespace.';
    if (name.startsWith(prefix) && name.length > prefix.length) return null;
    return 'plugin "$id" registered $what "$name": every name a plugin '
        'registers is in its namespace, "$prefix<name>", so a name the engine '
        'or another plugin adds later cannot be one it already took';
  }

  /// [name] as this plugin publishes it: `<namespace>.<name>` for a bare
  /// name, [name] itself when it is already in the namespace. What the
  /// editor's pieces and panels and a plugin's MCP tools are filed under,
  /// so the editor half of a package (`acme_boats.editor`) and its runtime
  /// half (`acme_boats`) publish into one namespace, as their quantities,
  /// fields and render steps already are.
  ///
  /// Throws an [ArgumentError] for an empty name, and a [PluginException]
  /// naming both for a name outside the namespace ([nameProblem]).
  String qualify(String name, {required String what}) {
    if (name.isEmpty) throw ArgumentError.value(name, what, 'needs a name');
    final whole = name.contains('.') ? name : '$namespace.$name';
    if (nameProblem(whole, what: what) case final problem?) {
      throw PluginException(problem);
    }
    return whole;
  }

  /// The manifest as a document writes it, with [extra] first and its own
  /// keys over them. A field at its default is left out; [fromJson] reads it
  /// back.
  Map<String, Object?> toJson() => <String, Object?>{
    ...extra,
    'id': id,
    'apiVersion': apiVersion.toString(),
    if (version != PluginVersion.none) 'version': version.toString(),
    if (simulationVersion != 1) 'simulationVersion': simulationVersion,
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    if (backends.isNotEmpty) 'backends': backends.toList(),
    'touches': touches.name,
    if (permissions.isNotEmpty)
      'permissions': <String>[for (final p in permissions) p.name],
    if (description != null) 'description': description,
  };

  @override
  String toString() => version == PluginVersion.none
      ? '$id (plugin API $apiVersion)'
      : '$id $version (plugin API $apiVersion)';
}

/// One plugin: a manifest, and what it registers when installed.
///
/// **The one unit everything outside the kernel is written as.** Effects,
/// elements, genres, formats, tools: each is a class like this, found by
/// discovery or handed to the engine in a list, and installed through the
/// same [PluginHost] the engine's own pieces use.
///
/// ```dart
/// final class TrailsPlugin extends Flutter3dPlugin {
///   @override
///   PluginManifest get manifest => const PluginManifest(
///     id: 'trails',
///     apiVersion: PluginApiVersion(1, 0),
///     touches: PluginTouches.view,
///   );
///
///   @override
///   void install(PluginHost host) {
///     host.events.onFrame<Landed>('trails.dust', (landed) => _puff(landed));
///   }
/// }
/// ```
///
/// **Everything [install] registers is withdrawn when the plugin is switched
/// off.** Each registry returns a `Registration`, and the host keeps them
/// for the plugin: disabling cancels them all, newest first, and enabling
/// runs [install] again. [uninstall] is for whatever the plugin holds that
/// is not a registration — a file it opened, a cache it filled.
///
/// `base`, so a member added in a later minor of the API arrives with a
/// default and every plugin keeps compiling: a plugin `extends` this and
/// is itself `final` or `base`.
abstract base class Flutter3dPlugin {
  /// For a plugin class, which supplies [manifest] and [install].
  const Flutter3dPlugin();

  /// What the plugin is and needs, read before it is installed: its id, the
  /// API it was written against, its dependencies and what it touches.
  PluginManifest get manifest;

  /// Registers this plugin's phases, systems, subscriptions and the rest.
  ///
  /// Called at a step boundary — once at start, and again each time the
  /// plugin is switched back on — never in the middle of a step.
  ///
  /// **Synchronous, and so is every registration it makes**: each returns
  /// its `Registration` at once. What has to load first — a kernel placed
  /// on a device, a pipeline — loads behind the registration, and the frame
  /// skips it as `PassSkip.pending` until it is there. What the plugin has
  /// to load itself goes in [ready].
  void install(PluginHost host);

  /// Loads what the plugin needs before it is whole — a shader library its
  /// lighting model draws with, a table its system reads — after [install]
  /// has registered everything, and completes when it has. Completes at
  /// once unless overridden.
  ///
  /// **Awaited by whoever wants the plugin whole, never by a frame or a
  /// step.** The engine calls it after each [install] and keeps going: what
  /// the plugin registered already stands, and a registration that waits
  /// on the load is pending meanwhile. `PluginManager.whenReady` completes
  /// once every installed plugin's [ready] has. One that throws switches
  /// the plugin off at the next step boundary, with its dependents, and
  /// the error as `PluginStatus.reason`.
  ///
  /// Registrations made from here, after an `await`, are the plugin's like
  /// those [install] made, and are withdrawn with them; one made after the
  /// plugin was switched off is withdrawn at once.
  Future<void> ready(PluginHost host) async {}

  /// Releases what [install] took that is not a registration. The
  /// registrations themselves are cancelled by the host after this returns.
  void uninstall(PluginHost host) {}

  @override
  String toString() => manifest.id;
}

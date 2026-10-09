import 'host.dart';
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
/// a system to a step phase, or a subscriber to the step channel.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1), so a
/// later minor may name a third kind; anything that is not [view] is
/// treated as touching the simulation, the safe reading of a kind this
/// build does not know.
final class PluginTouches {
  const PluginTouches._(this.name);

  /// Runs inside the fixed step: phases, systems, step subscriptions.
  static const PluginTouches simulation = PluginTouches._('simulation');

  /// Runs only in the frame: frame phases, frame subscriptions, render steps,
  /// editor pieces.
  static const PluginTouches view = PluginTouches._('view');

  /// Reads a name back. A name this build does not know is kept as it was
  /// written, so a manifest read and written again says what it said, and
  /// it is treated as [simulation] — the kind held to every rule — until a
  /// build that knows it reads it.
  static PluginTouches named(String name) => switch (name) {
    'view' => view,
    'simulation' => simulation,
    _ => PluginTouches._(name),
  };

  final String name;

  /// Whether this build knows the kind: [simulation] or [view].
  bool get isKnown => name == simulation.name || name == view.name;

  /// Whether a plugin of this kind may change the simulation: every kind but
  /// [view], an unknown one included.
  bool get simulates => this != view;

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
  const PluginPermission(this.name);

  /// Talks to the network.
  static const PluginPermission network = PluginPermission('network');

  /// Reads or writes files outside the application's assets.
  static const PluginPermission files = PluginPermission('files');

  /// Offers tools to an agent through the project's MCP servers. Checked by
  /// `McpTools.addTool`: a plugin that did not ask for it is refused there,
  /// so a person installing a plugin sees that it talks to agents.
  static const PluginPermission tools = PluginPermission('tools');

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

  /// The plugin's name, unique among the plugins of one engine: lower case
  /// letters, digits, `_`, `.` and `-`, starting with a letter.
  ///
  /// Also the namespace its MCP tools and editor pieces are filed under, so
  /// it should be the package's name or start with it.
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

  /// [dependsOn], read. Throws a [PluginFormatException] for an entry whose
  /// range is not one.
  List<PluginDependency> get dependencies => <PluginDependency>[
    for (final entry in dependsOn) PluginDependency.parse(entry),
  ];

  /// The ids [dependsOn] names, without their ranges.
  List<String> get dependencyIds => <String>[
    for (final dependency in dependencies) dependency.id,
  ];

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

  /// Whether this plugin runs on [backend]; null asks about no backend in
  /// particular, which every plugin answers yes to.
  bool runsOn(String? backend) =>
      backend == null || backends.isEmpty || backends.contains(backend);

  static final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');

  /// Why [id] is not a usable name, or null when it is.
  String? get idProblem => _idPattern.hasMatch(id)
      ? null
      : 'a plugin id is lower case letters, digits, "_", "." and "-", '
            'starting with a letter; "$id" is not one';

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
      dependsOn: names('dependsOn'),
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
  const Flutter3dPlugin();

  PluginManifest get manifest;

  /// Registers this plugin's phases, systems, subscriptions and the rest.
  ///
  /// Called at a step boundary — once at start, and again each time the
  /// plugin is switched back on — never in the middle of a step.
  void install(PluginHost host);

  /// Releases what [install] took that is not a registration. The
  /// registrations themselves are cancelled by the host after this returns.
  void uninstall(PluginHost host) {}

  @override
  String toString() => manifest.id;
}

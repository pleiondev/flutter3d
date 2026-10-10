/// The package layers of `tasks/1.0-boundaries.md`, and the detectors the
/// rules about them run.
///
/// **A layer is a promise about what a package may need.** Each package
/// stands in one layer and depends at run time only on packages in layers
/// below it, so the foundation knows nothing of the plugin contract, the
/// physics nothing of the renderer, and the simulation nothing of a screen.
/// The publishing order in ARCHITECTURE.md §16 is a different list: it is
/// computed from what the pubspecs say, while this is what they are meant
/// to say; since the boundary work emptied its list of pending exceptions
/// (step C of `tasks/1.0-boundaries.md`), the two agree.
///
/// **What the target map leaves to a sentence is said here as a number.**
/// The map in the task names the layers of the packages the boundary work
/// moves; every other package is placed one layer past the deepest package
/// it needs once the pending moves are done, and a package that is added
/// later is placed by hand, here, with the rest. A package missing from the
/// map is a finding: a new package is placed on purpose or not at all.
///
/// Plain Dart over strings, like `api.dart`: the detectors take the facts as
/// arguments, so `proveDetectorsWork` can run them on a made-up tree before
/// the real one is read.
library;

/// The layer each package stands in, from 0 (the foundation, under
/// everything) up.
///
/// Every name here is a package: `flutter3d_elements`, the last one placed
/// ahead of its move (the elements' simulation, split out of
/// `flutter3d_effects`, move 8), is one now.
const Map<String, int> packageLayers = <String, int>{
  // L0: nothing of the engine's beneath them.
  'flutter3d_foundation': 0,
  'flutter3d_lints': 0,
  'flutter3d_samples': 0,
  'pad_input': 0,
  'pointer_lock': 0,
  // L1: the plugin contract and the graphics vocabulary, side by side.
  'flutter3d_plugin_api': 1,
  'flutter3d_hardware': 1,
  // L2: what a world is made of, and the shaders' text.
  'flutter3d_matter': 2,
  'flutter3d_shaders': 2,
  // L3: the physics, the audio's mix, the renderer's core and the backends.
  'flutter3d_physics': 3,
  'flutter3d_audio_core': 3,
  'flutter3d_core': 3,
  'flutter3d_cpu': 3,
  'flutter3d_impeller': 3,
  'flutter3d_webgl': 3,
  'flutter3d_webgpu': 3,
  // L4: the native core with no renderer under it, the simulation, and what
  // stands on the core alone.
  'flutter3d_physics_native': 4,
  'flutter3d_sim': 4,
  'flutter3d_particles': 4,
  'flutter3d_audio': 4,
  'flutter3d_build_hooks': 4,
  'flutter3d_editor_widgets': 4,
  'flutter3d_mesh': 4,
  'flutter3d_post': 4,
  // L5: the elements' simulation, the level as a scene, the engine's shell,
  // and what stands on the simulation.
  'flutter3d_elements': 5,
  'flutter3d_level_scene': 5,
  'flutter3d': 5,
  'flutter3d_camera': 5,
  'flutter3d_conformance': 5,
  'flutter3d_editor_play': 5,
  'flutter3d_education': 5,
  'flutter3d_model_core': 5,
  'flutter3d_net': 5,
  'flutter3d_plugin_runtime': 5,
  'flutter3d_voxel': 5,
  // L6: the views of the elements, the application and the editor's core,
  // both over the level scene.
  'flutter3d_effects': 6,
  'flutter3d_app': 6,
  'flutter3d_editor_core': 6,
  'flutter3d_testing': 6,
  'flutter3d_net_webrtc': 6,
  'flame_multiplayer': 6,
  // L7: the game facade, the kits, the genres, and the tools over the
  // editor's core.
  'flutter3d_game': 7,
  'flutter3d_game_kit': 7,
  'flutter3d_game_platformer': 7,
  'flutter3d_game_racing': 7,
  'flutter3d_game_shooter': 7,
  'flutter3d_game_strategy': 7,
  'flutter3d_mcp': 7,
  'flutter3d_stereo': 7,
  'flame_multiplayer_dashwire': 7,
  // L8: what stands on the game or on the tools.
  'flutter3d_game_ui': 8,
  'flutter3d_game_physics': 8,
  'flutter3d_build': 8,
  'flutter3d_sim_mcp': 8,
  'flame_flutter3d': 8,
  'flutter3d_demo_content': 8,
  // L9
  'flame_flutter3d_audio': 9,
};

/// The names in [packageLayers] that are not packages yet, placed ahead of
/// the move that makes them. Empty since `flutter3d_elements` came out of
/// the effects (move 8).
const Set<String> plannedPackages = <String>{};

/// Dependencies a package may not have although the layers would allow
/// them, each with the sentence of the target map that forbids it.
const Map<String, Map<String, String>> layerForbidden =
    <String, Map<String, String>>{
      'flutter3d_physics_native': <String, String>{
        'flutter3d_core':
            'the native physics core names no renderer: the ragdoll a '
            'skeleton goes limp into belongs to the game layer',
      },
      'flutter3d': <String, String>{
        'flutter3d_sim':
            'the engine\'s shell is over the core; a game that wants the '
            'simulation names it, or `flutter3d_game`',
        'flutter3d_physics':
            'the engine\'s shell is over the core and re-exports no physics',
        'flutter3d_audio_core':
            'the engine\'s shell is over the core and re-exports no audio',
      },
    };

/// What is wrong with [dependencies] (each package's run-time sibling
/// dependencies) against [layers] and [forbidden], as
/// `(package, dependency, why)`: a package with no layer, a dependency on a
/// package in the same layer or above, or one the map forbids.
///
/// A dependency on something that is not a package of the repository (a
/// pub.dev package) is not this detector's business.
List<(String, String?, String)> layerProblems(
  Map<String, Set<String>> dependencies, {
  required Map<String, int> layers,
  required Map<String, Map<String, String>> forbidden,
}) => <(String, String?, String)>[
  for (final package in dependencies.keys.toList()..sort())
    if (layers[package] == null)
      (
        package,
        null,
        'has no layer: place it in `packageLayers` '
            '(tool/structure/layers.dart), one past the deepest package it '
            'needs',
      )
    else
      for (final dependency in dependencies[package]!.toList()..sort())
        if (dependencies.containsKey(dependency))
          if (forbidden[package]?[dependency] case final String why)
            (package, dependency, 'is forbidden: $why')
          else if (layers[dependency] case final int at
              when at >= layers[package]!)
            (
              package,
              dependency,
              'is in L$at, and $package in L${layers[package]} may depend '
                  'only on layers below it',
            ),
];

/// The names of the phases [loopSource] (the plugin API's `loop.dart`)
/// declares, `LoopPhase.step('<name>')` and `LoopPhase.frame('<name>')`.
Set<String> declaredLoopPhases(String loopSource) => <String>{
  for (final match in RegExp(
    r"""LoopPhase\.(?:step|frame)\(\s*'([^']+)'\s*\)""",
  ).allMatches(loopSource))
    match.group(1)!,
};

/// The phases among [phases] named after one package of [packageNames]: the
/// phase `x` and the package `flutter3d_x`.
///
/// **A phase named for a package reads as that package's**, and a phase in
/// the plugin API is the engine's: every plugin may put a system in it. The
/// `elements` phase was named after the one package that filled it, and
/// would have been named after `flutter3d_elements` once that existed.
Set<String> phasesNamedForAPackage(
  Iterable<String> phases,
  Iterable<String> packageNames,
) {
  final subjects = <String>{
    for (final name in packageNames)
      if (name.startsWith('flutter3d_')) name.substring('flutter3d_'.length),
  };
  return <String>{
    for (final phase in phases)
      if (subjects.contains(phase)) phase,
  };
}

/// Phases named like a package that every package may still call its own,
/// with why: the name is the subsystem's, and more than one package fills
/// it.
const Map<String, String> loopPhaseSharesAPackageName = <String, String>{
  'physics':
      'the bodies of both backends step here, `flutter3d_physics`\' and '
      '`flutter3d_physics_native`\'s, and every genre\'s rules for them',
  'audio':
      'the mix of `flutter3d_audio_core` runs here, and any backend\'s or '
      'game\'s sound',
  'camera':
      'every genre places its own camera here, `flutter3d_camera`\'s '
      'virtual cameras among them',
};

/// The types [apiText] (a package's `api/<package>.api`) declares in its
/// main library [library] that nothing in the contract names: not
/// reachable from [roots] through a signature, a supertype, or a name the
/// library re-exports.
///
/// **What a contract package declares is what its signatures need.** A type
/// no root reaches is a type a plugin cannot be handed or asked for, so it
/// is somebody else's: a host's handle, a registry nothing in the contract
/// fills. Reachable means: a root; a name in the declaration line or a
/// member line of a reachable type; a type whose own declaration line (its
/// `extends`, `implements`, `with`) names a reachable one, because a
/// subtype of a contract type is handed out as that type; and every name the
/// library re-exports. Functions and constants are not types and are not
/// asked about.
Set<String> unreachableContractTypes(
  Map<String, ({String header, List<String> members})> declarations, {
  required Set<String> roots,
  required Set<String> reexported,
}) {
  bool names(String text, String name) =>
      RegExp('(?<![\\w\$])${RegExp.escape(name)}(?![\\w\$])').hasMatch(text);
  final reached = <String>{...roots, ...reexported};
  var grew = true;
  while (grew) {
    grew = false;
    for (final MapEntry(key: name, value: block) in declarations.entries) {
      if (reached.contains(name)) continue;
      final header = block.header.replaceFirst(name, '');
      final byHeader = reached.any((String r) => names(header, r));
      final byUse = declarations.entries.any(
        (MapEntry<String, ({String header, List<String> members})> other) =>
            reached.contains(other.key) &&
            other.key != name &&
            <String>[
              other.value.header,
              ...other.value.members,
            ].any((String line) => names(line, name)),
      );
      if (byHeader || byUse) {
        reached.add(name);
        grew = true;
      }
    }
  }
  return <String>{
    for (final MapEntry(key: name, value: block) in declarations.entries)
      if (!reached.contains(name) && isTypeDeclaration(block.header)) name,
  };
}

/// Whether a snapshot's declaration line declares a type: a class, a mixin,
/// an enum, an extension type or a typedef.
bool isTypeDeclaration(String header) => RegExp(
  r'^(?:@\S+\s+)*(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
  r'(?:class|mixin|enum|typedef|extension\s+type)\b',
).hasMatch(header.trimLeft());

/// Where the plugin contract starts: what a plugin is, what it is handed,
/// and the host that runs it. Everything else the plugin API declares is
/// reached from these.
const Set<String> pluginContractRoots = <String>{
  'Flutter3dPlugin',
  'PluginHost',
  'PluginManager',
};

/// How many types the plugin API may declare. It was 77 before the boundary
/// work moved the foundation and the simulation host out; a type added to
/// the contract comes with its reason in review and this number raised by
/// hand, and a type that leaves lowers it.
///
/// 54 after the moves; 57 with `DataSection`, `DataSectionContext` and
/// `DataSectionRegistry` (move 14), so that a subsystem reads its own
/// section of a `.f3dplugin` and the runtime that reads the document
/// depends on none of them.
const int pluginApiTypeBudget = 57;

/// The packages of the simulation stack: what steps a run, which a server
/// replays with no window and no GPU.
const Set<String> simulationStack = <String>{
  'flutter3d_sim',
  'flutter3d_physics',
  'flutter3d_physics_native',
  'flutter3d_elements',
  'flutter3d_matter',
  'flutter3d_foundation',
};

/// What the simulation stack may not import, each with why: the renderer's
/// core, the graphics vocabulary, the shaders and the particles, which are
/// all something drawn.
const Map<String, String> simulationMayNotImport = <String, String>{
  'flutter3d_core': 'the scene, the meshes and the renderer',
  'flutter3d_hardware': 'the graphics vocabulary a device speaks',
  'flutter3d_shaders': 'the shaders\' text',
  'flutter3d_particles': 'what is drawn of smoke, sparks and spray',
};

/// The imports among [imports] (each library of a package, as its path,
/// with the `package:` URIs it imports or exports) that reach a package of
/// [forbidden], as `(path, package)`.
///
/// **Rule 6 of `tasks/1.0-boundaries.md`: the simulation draws nothing.**
/// A step that imports the renderer's core has a scene node within reach,
/// and a server that replays the run resolves a renderer it never opens;
/// the elements' simulation was split from its views so that it does not.
/// The layers already keep the pubspecs right; this reads the sources, so
/// an import through a dependency of a dependency is caught too.
List<(String, String)> simulationImportProblems(
  Map<String, List<String>> imports, {
  required Set<String> forbidden,
}) => <(String, String)>[
  for (final path in imports.keys.toList()..sort())
    for (final uri in imports[path]!)
      if (RegExp(r'^package:([a-z0-9_]+)/').firstMatch(uri)?.group(1)
          case final String package when forbidden.contains(package))
        (path, package),
];

/// Whether [package] is part of the runtime a player's game resolves: the
/// application, the game facade, the widgets, the kits and the genres, the
/// elements and their views, and the audio.
bool isRuntimePackage(String package) =>
    package == 'flutter3d_app' ||
    package.startsWith('flutter3d_game') ||
    const <String>{
      'flutter3d_effects',
      'flutter3d_elements',
      'flutter3d_audio',
      'flutter3d_audio_core',
    }.contains(package);

/// The tools no runtime package may depend on at run time, each with why:
/// the editors, the build tool, the agent servers and the modeller's core.
const Map<String, String> runtimeMayNotDependOn = <String, String>{
  'flutter3d_editor_core': 'the level editor\'s document layer',
  'flutter3d_editor_widgets': 'the editors\' widgets',
  'flutter3d_editor_play': 'the editor\'s Play, which runs a game',
  'flutter3d_build': 'the build tool and its servers',
  'flutter3d_build_hooks': 'the material compiler a build hook runs',
  'flutter3d_mcp': 'the agent servers',
  'flutter3d_sim_mcp': 'the server that plays a game for an agent',
  'flutter3d_model_core': 'the modeller\'s document layer',
};

/// Run-time dependencies of the runtime on a tool that are deliberate, as
/// `'<package> -> <tool>'`, each with why. An entry that is no longer a
/// dependency is a finding, so the list does not outlive its reason.
const Map<String, String> runtimeToolDependencyAllowed = <String, String>{
  'flutter3d_effects -> flutter3d_build_hooks':
      'the effects compile their own materials in `hook/build.dart`, a '
      'process the Flutter tool starts at build time, and a hook can import '
      'only the package\'s `dependencies:`; nothing under `lib/` names it, '
      'so no game\'s code is compiled against the material compiler',
};

/// **Rule 7 of `tasks/1.0-boundaries.md`: the runtime is not a tool.** The
/// run-time dependencies, as `(package, tool)`, of every runtime package
/// ([runtime]) in [dependencies] on one of [tools]. A dev dependency is not
/// in [dependencies] and is not asked about: a test may drive an editor.
List<(String, String)> runtimeToolDependencies(
  Map<String, Set<String>> dependencies, {
  required bool Function(String package) runtime,
  required Set<String> tools,
}) => <(String, String)>[
  for (final package in dependencies.keys.toList()..sort())
    if (runtime(package))
      for (final dependency in dependencies[package]!.toList()..sort())
        if (tools.contains(dependency)) (package, dependency),
];

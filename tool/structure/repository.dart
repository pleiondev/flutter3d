/// What this repository is made of, and where each rule is relaxed.
///
/// **One table rather than a file per package.** The rules used to live as a
/// `boundaries_test.dart` in each package, which meant a new package was
/// covered only if somebody remembered to add one — and thirteen of twenty-one
/// were not. A runner that walks `packages/` covers a new package the day it
/// exists, and every exemption is visible in one place instead of being spread
/// across twenty-one files nobody reads together.
///
/// Every entry here should say *why*. An exemption nobody explained is an
/// exemption on its way to being the rule.
library;

import 'dart:io';

/// Every package that holds one genre's vocabulary.
///
/// Two of them did not exist when the list was written. They are named anyway,
/// because the cost of a name in a list is nothing and the cost of finding out
/// later is a package that was allowed to grow the wrong way for a month.
const List<String> genrePackages = <String>[
  'flutter3d_game_shooter',
  'flutter3d_game_platformer',
  'flutter3d_game_racing',
];

/// Every application in this repository, which is also its directory name.
///
/// `_demo_` marks the three that exist to show the engine works. The other two
/// are tools — a level editor and the seed a new project starts from — and
/// rules about *games* filter on the infix rather than carrying a fourth list.
const List<String> applications = <String>[
  'flutter3d_demo_dungeon',
  'flutter3d_demo_platformer',
  'flutter3d_demo_racing',
  'flutter3d_editor',
  'flutter3d_template_app',
];

/// Packages the genre rule does not apply to, and why.
const Map<String, String> genreRuleExempt = <String, String>{
  'flutter3d_game_shooter': 'it is a genre; the rule it keeps is isolation',
  'flutter3d_game_platformer': 'it is a genre',
  'flutter3d_game_racing': 'it is a genre',
};

/// Which files of a genre package are allowed to reach a renderer.
///
/// An allowlist rather than a directory rule, so that a second file needing a
/// renderer is a deliberate line here rather than a `mv`. The platformer's list
/// is empty and that is the strongest form of the rule: nothing there draws at
/// all, and it does not depend on `flutter3d`.
const Map<String, Set<String>> genreMayDraw = <String, Set<String>>{
  'flutter3d_game_shooter': <String>{'lib/src/weapon_view.dart'},
  'flutter3d_game_racing': <String>{'lib/bridge.dart'},
  'flutter3d_game_platformer': <String>{},
};

/// Packages the repeatable-step rule does **not** apply to, and why.
///
/// **This was the other way round**, and the file it lives in opens by naming
/// exactly that mistake: the rules used to be a test per package, "and thirteen
/// of twenty-one were not covered because somebody had to remember". The
/// repeatable-step rule was then written as a table of five packages to *scan*
/// — so a new genre, or any new package a fixed step runs through, got no scan
/// for `DateTime.now()` or an unseeded `Random()` until somebody edited the
/// table. The default was exempt, which is the shape that had just been
/// removed.
///
/// It is exclusions now, so a package added tomorrow is covered today, and
/// taking one out of the rule costs a sentence saying why. `_exemptionsResolve`
/// checks this list the way it checks every other: a name here that is not a
/// package is a rule that has outlived its subject.
const Map<String, String> notARepeatableStep = <String, String>{
  'flutter3d': 'a renderer draws a frame; the clock it reads is the frame\'s',
  'flutter3d_impeller': 'a backend, not a step',
  'flutter3d_webgl': 'a backend, not a step',
  'flutter3d_cpu': 'a backend, not a step',
  'flutter3d_hardware': 'the vocabulary a backend implements',
  'flutter3d_conformance': 'a test suite for backends',
  'flutter3d_shaders': 'GLSL and a manifest',
  'flutter3d_samples': 'fixtures',
  'flutter3d_particles':
      'display: particles are drawn, never simulated in a '
      'fixed step, and their emitters take the frame\'s delta',
  'flutter3d_testing': 'a test helper',
  'flutter3d_screens': 'screens, which run on the frame clock and say so',
  'flutter3d_session':
      'a run\'s lifecycle: it loads and saves, and steps '
      'nothing itself',
  'flutter3d_app': 'a barrel with no code in it',
  'flutter3d_backend': 'chooses a device and steps nothing',
  'flutter3d_bridge': 'display: it reads a simulation and moves nodes',
  'flutter3d_audio': 'display: a mix is recomputed once a frame',
  'pad_input': 'a device, read once a frame',
  'pointer_lock': 'a platform channel',
};

/// Files inside a scanned package that are allowed to be unrepeatable, and why.
const Map<String, Map<String, String>> repeatableStepExempt =
    <String, Map<String, String>>{
      'flutter3d_sim': <String, String>{
        'lib/src/save/game_random.dart': 'it is the seeded generator',
      },
    };

/// Files in `flutter3d_hardware` allowed to name Flutter, and why.
///
/// The `flutter_gpu` half of that rule has no exceptions and never will. The
/// Flutter half is narrower than it looks: it is there to stop Flutter's
/// vocabulary leaking into this one, and `PixelFormat` is the collision it was
/// written for — already handled by naming ours `TextureFormat`.
///
/// **`package:flutter/` is banned as well as `dart:ui`, on purpose.** Widgets
/// re-export half of `dart:ui`, so a rule naming only `dart:ui` would let the
/// whole of Flutter in through a technicality, and the exemptions below would
/// be documenting a loophole rather than a decision.
const Map<String, String> hardwareMayUseFlutter = <String, String>{
  'graphics_device.dart':
      'GraphicsDevice.present returns a widget showing the finished frame, '
      'which every backend must produce and only Flutter can name',
  'testing_fake_backend.dart':
      'FakeBackend implements GraphicsDevice.present, which is a '
      'widget by the line above',
};

/// Files in `flutter3d` held to a stricter rule than the rest, and why.
const Map<String, String> engineAlsoFreeOfDartUi = <String, String>{
  'lib/src/engine/render/frame_resources.dart':
      'the frame graph would stop being unit-testable off a device — a dart:ui '
      'import would not break the build, it would break the suite, and the '
      'analyser would report only that a test no longer compiles',
};

/// Files in `flutter3d` that must still compile with `dart compile exe`, and
/// why — checked **through their imports**, not just their own text.
///
/// The difference from [engineAlsoFreeOfDartUi] is the whole point. That map
/// reads one file and asks what it imports; this one follows the imports until
/// they stop, because the way this breaks is never a `dart:ui` line in the file
/// named. It broke exactly once, like this: `mesh_geometry.dart` declared both
/// `MeshGeometry`, which needs no device, and `DeviceMesh`, which holds two
/// buffers a device made. One `flutter3d_hardware` import served both. Through
/// it `geometry.dart` reached `GraphicsDevice`, whose `present` returns a
/// `Widget` — so every file that generated or decoded a mesh reached
/// `package:flutter/widgets.dart`, four hops away and named nowhere.
///
/// Nothing failed on a device, which is why it survived. What failed was
/// `dart compile exe`, where `dart:ui` does not exist: the benchmark stopped
/// building, and the numbers in ARCHITECTURE.md §14 became numbers nobody could
/// re-run. A rule that reads single files would have stayed green throughout.
const Map<String, String> engineCompilesOffDevice = <String, String>{
  'tool/bench/bench.dart':
      'the benchmark is compiled ahead of time on purpose, so that the figures '
      'in ARCHITECTURE.md §14 come from the pipeline a release build uses — a '
      'suite that cannot be compiled produces numbers that cannot be '
      'contradicted',
  'lib/src/engine/geometry/geometry.dart':
      'the CPU geometry layer says it depends on no graphics backend, and every '
      'unit test of bounds, shapes and mesh maths is spent on that being true',
};

/// Sentences that say a number of scenes and are not claims about how many
/// there are, with the fragment that identifies each and why it is spared.
///
/// **The rule reads Dart now, and Dart is where this repository keeps its
/// history.** A comment saying "thirty goldens leaked thirty of them" is right
/// about the afternoon it describes and would be a lie rewritten to say
/// thirty-nine; a comment saying "two goldens caught it at 25% and 0.6%" counts
/// the two that caught a bug, not the set. Both read exactly like the claims the
/// rule exists to recount, and no phrasing tells them apart — which is why this
/// is a table of sentences rather than a cleverer regular expression.
///
/// The key is a fragment of the sentence *as the prose reads*, wrap undone. It
/// has to span the number, and `_exemptionsResolve` checks that it is still in
/// the file: rewrite the sentence and the exemption stops applying, which is the
/// direction that matters. An exemption that outlives its sentence is the rule
/// quietly narrower than it reads.
const Map<String, Map<String, String>>
goldenCountExempt = <String, Map<String, String>>{
  // History: right about the day it describes.
  'packages/flutter3d/example/lib/src/spike/golden_extras.dart':
      <String, String>{
        'all twenty-seven goldens came back byte-identical':
            'the run that found the pool bug, on the day it was run',
      },
  'packages/flutter3d/lib/src/engine/render/renderer.dart': <String, String>{
    'gives all twenty-seven goldens byte-identical':
        'the experiment that settled the registration order, as it was run',
  },
  'packages/flutter3d/test/xray_test.dart': <String, String>{
    'a call thirty-four goldens were recorded without':
        'the recording those goldens came from; a later set does not '
        'change what that one was recorded without',
  },
  'packages/flutter3d_testing/lib/src/golden.dart': <String, String>{
    'thirty goldens leaked thirty of them':
        'the leak as it was found, and the second number is the first',
  },
  'packages/flutter3d_cpu/test/ssao_test.dart': <String, String>{
    'carried "thirty-one goldens" for eight scenes':
        'the wrong number this rule was extended to catch, quoted. Both '
        'numbers in it are about the drift, not about today',
  },
  'packages/flutter3d_webgl/test/bloom_orientation_test.dart': <String, String>{
    'thirty-two goldens did not':
        'the set on the day a flipped blit got past it',
  },
  'tool/structure/rules.dart': <String, String>{
    '"thirty scenes" in `tool/ci.sh`':
        'the three wrong answers this rule was written for, quoted',
    '"twenty-six scenes" in `golden_web.sh`': 'the same three',
    '"32 scenes" in `ARCHITECTURE.md`': 'the same three',
    'still saying "thirty scenes" two recounts later':
        'why the prose pages are scanned, told as what happened',
    'said "thirty-one goldens" for eight scenes':
        'the drift that made the rule read Dart, quoted from the file it '
        'was found in',
  },

  // A subset: the number is right about some of them.
  'packages/flutter3d/example/lib/cpu_main.dart': <String, String>{
    'Two scenes, switched with the space bar':
        'the example application\'s two scenes, which are not a golden set',
  },
  'packages/flutter3d/lib/src/engine/render/lighting_model.dart':
      <String, String>{
        'Two goldens caught it at 25% and 0.6%':
            'the two that caught it, named with what each one showed',
      },
  'packages/flutter3d/test/lighting_model_test.dart': <String, String>{
    'which two goldens found at 25% and 0.6%': 'the same two',
  },
  'packages/flutter3d_cpu/lib/src/cpu_encoder.dart': <String, String>{
    'the twenty-seven scenes that have no mip chain':
        'the scenes without a mip chain, which is fewer than all of them',
  },
  'packages/flutter3d_cpu/test/engine_parity_test.dart': <String, String>{
    'the lesson of two goldens that sat at 0.178%':
        'the two that sat under a threshold nobody was reading',
  },
  'packages/flutter3d_webgl/test/engine_parity_test.dart': <String, String>{
    'how two goldens sat under one': 'the same two',
    'the lesson of two goldens that sat at 0.178%': 'the same two',
    'equal on both backends across six scenes': 'the six the atlas appeared in',
  },
  'packages/flutter3d_webgl/lib/engine_shaders.dart': <String, String>{
    'equal on both backends across six scenes':
        'the six the atlas appeared in, restated in each generated shader',
  },
  'packages/flutter3d_webgl/test/cross_backend_test.dart': <String, String>{
    'Seven scenes have been in the second group':
        'the seven that disagreed by whole percents, counted across the life '
        'of this backend rather than today',
    'the three scenes that were exactly': 'the three that were exactly zero',
  },
  // ARCHITECTURE.md's four are the same species, written up rather than in
  // a comment: each counts the scenes one measurement touched.
  'ARCHITECTURE.md': <String, String>{
    'five scenes passed through it': 'the five that passed one merge',
    'Six scenes disagreed by whole percents':
        'the six the third set found on the day it was recorded',
    'the three scenes that were': 'the three that were exactly zero',
    'Six scenes were in whole percents': 'the same six',
  },
};

/// Calls that put a document's contents into a world, or dress what it built.
///
/// Each is something a shipped game does exactly once, and a second caller is a
/// second answer to "what is in this level" — which will disagree with the
/// first, not today but on the day somebody adds a field to one of them.
///
/// **Deliberately not the simulation constructors**, and this list was narrowed
/// after they were tried: `slope_test.dart` builds a bare `PlatformerSimulation`
/// on purpose, because it measures the shape of a level's brushes and spawning
/// its entities would put a crate in the way. Those are narrower harnesses, not
/// second assemblies, and a rule calling them offenders is a rule people learn
/// to route around.
const List<String> assemblyCalls = <String>[
  'spawnInto(',
  'startSlot(',
  'ActorVisuals(',
  'FixtureVisuals(',
];

// ------------------------------------------------------------------ the tree

/// The repository root, found by walking up from wherever this was run.
///
/// Walked rather than assumed, so that `dart run tool/structure.dart` works
/// from a subdirectory — which is where somebody chasing one rule will be.
Directory get repositoryRoot {
  var dir = Directory.current;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: flutter3d_workspace')) {
      return dir;
    }
    final up = dir.parent;
    if (up.path == dir.path) {
      throw StateError(
        'no flutter3d_workspace pubspec above ${Directory.current.path} — '
        'run this from inside the repository',
      );
    }
    dir = up;
  }
}

/// Every package directory, by name.
Map<String, Directory> get packages => _childrenOf('packages');

/// Every application directory, by name.
Map<String, Directory> get apps => _childrenOf('apps');

Map<String, Directory> _childrenOf(String what) {
  final root = repositoryRoot;
  final entries = Directory('${root.path}/$what')
      .listSync()
      .whereType<Directory>()
      .where((Directory d) => File('${d.path}/pubspec.yaml').existsSync());
  return <String, Directory>{
    for (final dir in entries) dir.path.split(Platform.pathSeparator).last: dir,
  };
}

/// Every `.dart` file under [dir], recursively, skipping build output.
///
/// `build/` and `.dart_tool/` hold copies of the very files being scanned, so a
/// walk that included them would report every offence twice and every path in a
/// form nobody can open.
List<File> dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where(
        (File f) =>
            !f.path.contains(
              '${Platform.pathSeparator}build${Platform.pathSeparator}',
            ) &&
            !f.path.contains('.dart_tool'),
      )
      .toList();
}

/// [file]'s path relative to [dir], in the form the rules and the exemption
/// tables use: forward slashes, no leading dot.
String relative(File file, Directory dir) => file.path
    .substring(dir.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

/// Enums a published package may keep, and why each is machinery.
///
/// **The rule this feeds refuses an enum in a published package**, because a
/// published enum is a closed list somebody else's `switch` is written against:
/// adding a value to it is a breaking change, and for a package whose whole
/// purpose is that other people build on it, that is the wrong shape by
/// default. The audit that produced this table is `doc/boundary-0.5.0.md`.
///
/// What survives is machinery: a set that is finite, ours, and complete — the
/// backends' mirror of `flutter_gpu`, a document key the engine has to
/// understand to act on, a state the whole repository is built around. Content
/// — what a weapon fires, what a monster is doing, where an asset lives — is
/// not on this list, and four such enums were opened rather than added to it.
///
/// A file's entry names each enum and says why. An enum that appears in a
/// published package without a reason here fails the rule, which is the point:
/// the next one has to be argued for rather than typed.
const Map<String, Map<String, String>>
boundaryEnumExempt = <String, Map<String, String>>{
  'flutter3d/lib/src/engine/assets/gltf/gltf_accessor_type.dart':
      <String, String>{
        'GltfComponentType':
            "the glTF specification's own component types. The set is the "
            "format's, and a file that names a fifth is not a glTF file",
        'GltfAccessorType':
            "the same specification's accessor types, for the same reason",
      },
  'flutter3d/lib/src/engine/assets/gltf/gltf_primitive_mode.dart':
      <String, String>{
        'GltfPrimitiveMode':
            "the glTF specification's seven primitive modes, numbered by the "
            'format',
      },
  'flutter3d/lib/src/engine/assets/surface_material.dart': <String, String>{
    'SurfaceAlphaMode':
        "glTF's three alpha modes. A decoder for another format maps onto "
        'these; it does not add to them',
    'TextureWrap':
        'the three wrap modes glTF names, which are also the three every '
        'GPU sampler has',
  },
  'flutter3d/lib/src/engine/render/material.dart': <String, String>{
    'MaterialAlphaMode':
        'the engine side of SurfaceAlphaMode, and a fourth would need a '
        'pipeline the shaders do not have',
  },
  'flutter3d/lib/src/engine/animation/animation_track.dart': <String, String>{
    'AnimationInterpolation':
        "glTF's three interpolations; the sampler implements exactly these",
    'AnimationPath':
        'the four channel targets glTF defines. A fifth is not a thing the '
        'format can express',
  },
  'flutter3d/lib/src/engine/animation/animation_target.dart': <String, String>{
    'AnimationWrap':
        'how a clip ends. Each value is a branch in the sampler, so a fifth '
        'is code rather than a name',
  },
  'flutter3d/lib/src/engine/scene/light_node.dart': <String, String>{
    'LightType':
        'the three the lit shaders have code for. A fourth kind of light is '
        'a shader, not a value',
  },
  'flutter3d/lib/src/engine/scene/mesh_node.dart': <String, String>{
    'ShadowCastingMode':
        "the engine side of the level document's ShadowCasting, which is "
        'closed for the reason that one is',
  },
  'flutter3d/lib/src/engine/render/render_node.dart': <String, String>{
    'FramePhase':
        "the renderer's own passes, in the order it runs them. A phase it "
        'does not run is not a phase',
  },
  'flutter3d/lib/src/engine/render/render_view.dart': <String, String>{
    'SortMode':
        'the orders the renderer knows how to sort in. Each is code in the '
        'sort, not a label',
  },
  'flutter3d/lib/src/engine/render/composite_mix.dart': <String, String>{
    'CompositeView':
        'which buffer the composite shows. Each value is a branch in a '
        'shader that ships compiled',
  },
  'flutter3d/lib/src/engine/render/resource_desc.dart': <String, String>{
    'ResourceOrigin':
        'where a frame resource comes from, which the frame graph switches '
        'on to allocate it',
  },
  'flutter3d/lib/src/engine/render/shadow_settings.dart': <String, String>{
    'ShadowCasterFaces':
        'which faces go into the shadow map. Three ways to set cull state, '
        'and there is no fourth',
  },
  'flutter3d/lib/src/engine/render/parity_scene.dart': <String, String>{
    'ParityScene':
        'names the fixtures this repository compares across backends. '
        'Adding one is recording three golden sets, which is not something '
        'a caller does',
  },
  'flutter3d/lib/src/engine/assets/model_loader.dart': <String, String>{
    'ModelFormat':
        'names the three decoders this package ships, plus auto. A format it '
        'does not ship never reaches this switch: a game supplies a '
        "ModelDecoder on the request and that decoder's own `handles` picks "
        'it, before any of these are consulted. Adding a value here means '
        'adding a decoder to this package',
  },
  'flutter3d/lib/src/engine/assets/obj/obj_loader.dart': <String, String>{
    'ObjNormals':
        'what to do when an OBJ has no normals. Smooth or flat, and there '
        'is no third answer the decoder could give',
  },
  'flutter3d_physics/lib/src/collider.dart': <String, String>{
    'ColliderKind':
        'the four the solver has paths for. A fifth kind is a solver '
        'change, not a value',
  },
  'flutter3d_physics/lib/src/collision_wedge.dart': <String, String>{
    'WedgeUphill':
        'which way a wedge rises. Four directions on a grid, and geometry '
        'has no fifth',
  },
  'flutter3d_sim/lib/src/level/brush.dart': <String, String>{
    'ShadowCasting':
        'a level document key. The engine has to understand it to act on '
        'it, so a document naming a mode this build does not know is a '
        'document it cannot draw — see doc/boundary-0.5.0.md',
  },
  'flutter3d_sim/lib/src/level/level_light.dart': <String, String>{
    'LevelLightType':
        "the document's spelling of LightType, closed for the reason that "
        'one is',
  },
  'flutter3d_sim/lib/src/level/level_issue.dart': <String, String>{
    'LevelIssueSeverity':
        'how badly a level is wrong. Three, and the validator decides what '
        'to do with each',
  },
  'flutter3d_sim/lib/src/world/mover.dart': <String, String>{
    'MoverState':
        'where a moving platform is in its cycle, which its own step '
        'drives. A game does not put it in a state the step cannot leave',
  },
  'flutter3d_sim/lib/src/loop/run_outcome.dart': <String, String>{
    'RunOutcome':
        'playing, won, lost. The vocabulary all three games and every '
        'screen are built on, and the same set RunStatus is sealed around',
  },
  'flutter3d_game_shooter/lib/src/simulation.dart': <String, String>{
    'GameState':
        'whether this simulation is running, over, or finished. Pausing and '
        "cutscenes belong to the application; these three are the step's "
        'own',
  },
  'flutter3d_game_platformer/lib/src/simulation.dart': <String, String>{
    'RunState': 'the same three the shooter has, in this genre',
  },
  'flutter3d_game_racing/lib/src/race_phase.dart': <String, String>{
    'RacePhase':
        'countdown, running, finished. The lights, the race and the end of '
        'it, driven by this package',
  },
};

/// Whole packages whose enums are all machinery, and the one reason each time.
///
/// Three packages mirror something they do not own — `flutter_gpu`'s pipeline
/// state, the gamepad the platform reports, the pointer lock the browser has —
/// and every value in them exists because the thing on the other side has it.
/// A third-party backend or platform implementation is obliged to handle all of
/// them, which is the definition of a set that is finite and not ours to grow
/// on a whim. Listing them one at a time would be the same sentence twenty-five
/// times.
///
/// Adding a value to one of these is still a breaking change and is still
/// recorded as one; see `doc/boundary-0.5.0.md`.
const Map<String, String> boundaryEnumPackageExempt = <String, String>{
  'flutter3d_hardware':
      'mirrors flutter_gpu. Every value is one the graphics API has, and a '
      'third-party backend must handle each of them',
  'pad_input':
      'mirrors what a gamepad platform reports. The buttons and axes are the '
      "device's, not this package's",
  'pointer_lock':
      "mirrors the platform's pointer lock, which has exactly these states",
};

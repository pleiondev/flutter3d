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
    'Six scenes were in the second group':
        'the six that disagreed by whole percents',
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

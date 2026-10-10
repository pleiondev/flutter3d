/// The rules, each a walk of the tree returning what it found.
///
/// A rule is a name and a function. It reports rather than asserts, so the
/// runner can show every offence in one pass instead of the first one — which
/// matters for a rule that fires across twenty packages at once, where the
/// first offender says nothing about whether it is one mistake or twenty.
library;

import 'dart:io';

import 'api.dart';
import 'boundaries.dart';
import 'detectors.dart';
import 'layers.dart';
import 'migration.dart';
import 'naming.dart';
import 'repository.dart';
import 'schema.dart';

/// One rule: what it is called, and what it found.
typedef Rule = ({String name, List<Finding> Function() run});

/// Every rule, in the order that fails fastest and reads best.
List<Rule> get allRules => <Rule>[
  (name: 'no package names a genre', run: _noGenre),
  (name: 'no package depends on an application', run: _noApplicationDependency),
  (
    name: 'nothing shares a mutable value as a constant',
    run: _noSharedMutables,
  ),
  (name: 'a genre package draws only where it says', run: _genreIsolation),
  (name: 'a genre package reaches no other genre', run: _noSidewaysGenre),
  (name: 'a genre camera turns the shared rig', run: _genreCameraTurnsTheRig),
  (name: 'a step reaches for no clock and no loose dice', run: _repeatableStep),
  (name: 'the simulation names no Flutter', run: _flatDartNamesNoFlutter),
  (
    name: 'a flat Dart package resolves without the Flutter SDK',
    run: _flatDartResolvesWithoutFlutter,
  ),
  (name: 'the hardware layer names no graphics API', run: _hardwareNamesNoApi),
  (name: 'the hardware layer names no Flutter', run: _hardwareNamesNoFlutter),
  (name: 'the engine names no backend', run: _engineNamesNoBackend),
  (
    name: "no package reaches into another package's src",
    run: _noForeignSrcImports,
  ),
  (name: 'each assembly has one home per application', run: _oneAssembly),
  (name: 'no test builds its own world', run: _noHarnessAssembly),
  (name: 'the repository lists agree with the workspace', run: _listsAgree),
  (name: 'every exemption names a file that is there', run: _exemptionsResolve),
  (name: 'no application silences a print', run: _noSilencedPrints),
  (name: 'no tracked source mutes the sound for now', run: _noTemporaryMutes),
  (name: 'the Impeller runners are reachable', run: _impellerRunners),
  (name: 'the document says how many tests there are', run: _testCount),
  (
    name: 'an application that draws asks its platform for the GPU',
    run: _gpuIsEnabled,
  ),
  (name: 'the publishing order names every package', run: _publishingOrder),
  (name: 'a package depends only on the layers below it', run: _layersBelow),
  (
    name: 'the runtime depends on no editor, build tool or server',
    run: _runtimeIsNoTool,
  ),
  (
    name: 'the simulation stack imports nothing that draws',
    run: _simulationDrawsNothing,
  ),
  (
    name: 'the plugin API declares only the contract, within its budget',
    run: _pluginContract,
  ),
  (
    name: 'a package re-exports another only where the list allows it',
    run: _reexportsAllowedOnly,
  ),
  (
    name: 'no dependency is held only to re-export it',
    run: _noReexportOnlyDependency,
  ),
  (name: 'a package depends on what its code names', run: _declareWhatYouName),
  (
    name: 'a public name has one home across the published packages',
    run: _oneHomePerName,
  ),
  (
    name: 'internal, builtin and testing libraries are reached only on purpose',
    run: _restrictedLibraries,
  ),
  (
    name: 'every package agrees about versions with the workspace',
    run: _versionsAgree,
  ),
  (
    name: 'the documents agree on how many golden scenes there are',
    run: _goldenSceneCount,
  ),
  (
    name: 'a public member nothing calls says who it is for',
    run: _unreferencedPublicMembers,
  ),
  (
    name: 'every picture the site shows is a golden that exists',
    run: _goldenFiguresExist,
  ),
  (
    name: 'an enum in a published package is machinery or is not an enum',
    run: _boundaryEnums,
  ),
  (name: 'the documents agree on how many rules there are', run: _ruleCount),
  (
    name: 'the conformance suite says how many checks it runs',
    run: _conformanceCheckCount,
  ),
  (
    name: 'the documents agree on how many enums the HAL promises',
    run: _hardwareEnumCount,
  ),
  (
    name: 'the site names every shader a bundle must answer to',
    run: _shaderEntryPoints,
  ),
  (
    name: 'the compiled shader bundle is not older than its sources',
    run: _shaderBundleIsCurrent,
  ),
  (
    name: 'no vertex stage reaches for texelFetch',
    run: _noTexelFetchInVertexStages,
  ),
  (
    name: 'the surface buffer keeps carrying depth in metres',
    run: _surfaceDepthStays,
  ),
  (name: 'a step asks no machine for an answer', run: _portableStepArithmetic),
  (
    name: 'the view reads what the simulation publishes, not its world',
    run: _noWorldOutsideSimulation,
  ),
  (name: 'every skill is named for its package', run: _skillNames),
  (
    name: 'a package that says it runs on the web reaches no dart:io there',
    run: _webPackagesReachNoIo,
  ),
  (
    name: 'every published package declares its platforms, as SUPPORT.md says',
    run: _platformsDeclared,
  ),
  (
    name: 'every plugin marker names a class its own library declares',
    run: _pluginMarkersResolve,
  ),
  (
    name: 'a world\'s gravity, air and sea are read from the world',
    run: _worldNumbersFromTheWorld,
  ),
  (
    name: 'the core reads its substances from the generated catalogue header',
    run: _coreReadsTheCatalogue,
  ),
  (
    name: 'a light\'s intensity is lux or candela, not the pre-1.0 unit',
    run: _lightIntensitiesInLux,
  ),
  (
    name: 'every published API is the snapshot its package commits',
    run: _apiSnapshotsCurrent,
  ),
  (
    name: 'a break in a published API is labelled and versioned',
    run: _apiBreaksLabelled,
  ),
  (
    name: 'every deprecation names its versions and its replacement',
    run: _deprecationsDated,
  ),
  (
    name: 'every MCP tool and VM extension is the snapshot its package commits',
    run: _schemaSnapshotsCurrent,
  ),
  (
    name: 'a break in a tool or an extension is labelled and versioned',
    run: _schemaBreaksLabelled,
  ),
  (
    name: 'the flutter3d command is the surface its package commits',
    run: _cliSurfaceCurrent,
  ),
  (
    name: 'every versioned format has a fixture for each version it reads',
    run: _formatFixtures,
  ),
  (name: '.f3d writes codes, not enum ordinals', run: _noEnumOrdinalsInFormats),
  (
    name: 'every break since the last release has its migration',
    run: _breaksHaveMigrations,
  ),
  (
    name: 'the migration leaves no more by hand than its ceiling',
    run: _manualCeiling,
  ),
  (
    name: 'the migration counts people read are the table\'s',
    run: _migrationNumbers,
  ),
  (
    name: 'a type somebody implements is a base class, not an interface',
    run: _noNewInterfaces,
  ),
  (
    name: 'every exception hangs from Flutter3dException',
    run: _exceptionsHaveTheRoot,
  ),
  (
    name: 'public identifiers spell in American',
    run: () => _namingRule(
      (String snapshot, String package) => britishIdentifiersIn(snapshot),
      britishSpellingAllowed,
    ),
  ),
  (
    name: 'a type has one teardown verb, and creation has its own verbs',
    run: () => _namingRule(
      (String snapshot, String package) => verbProblemsIn(snapshot),
      verbAllowed,
    ),
  ),
  (
    name: 'no public name carries a unit the engine does not use',
    run: () => _namingRule(
      (String snapshot, String package) => unitSuffixesIn(snapshot),
      unitSuffixAllowed,
    ),
  ),
  (
    name: 'a boolean reads as a question, and none is positional',
    run: () => _namingRule(
      (String snapshot, String package) => booleanProblemsIn(snapshot),
      booleanAllowed,
    ),
  ),
  (
    name: 'no public constant is named with k',
    run: () => _namingRule(
      (String snapshot, String package) => kConstantsIn(snapshot),
      const <String, String>{},
    ),
  ),
  (
    name: 'a settings class is final, const, and copies every field',
    run: () => _namingRule(settingsProblemsIn, settingsAllowed),
  ),
  (name: 'every public number says its unit in its doc', run: _unitsDocumented),
];

// ------------------------------------------------------------------- genre

List<Finding> _noGenre() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    if (genreRuleExempt.containsKey(entry.key)) continue;
    // The rule's own vocabulary is the forbidden list itself.
    if (entry.key == 'flutter3d_boundaries') continue;

    final lib = Directory('${entry.value.path}/lib');
    for (final file in dartFilesIn(lib)) {
      final where = '${entry.key}/${relative(file, entry.value)}';
      // A generated table is data: base64 noise spells a "gun" now and then,
      // and nobody named anything.
      if (file.readAsStringSync().startsWith('// GENERATED by ')) continue;
      for (final genre in genrePackages) {
        if (reaches(file.readAsStringSync(), genre)) {
          found.add(Finding(where, 'imports $genre'));
        }
      }
      for (final said in genreWordsIn(file.readAsStringSync())) {
        found.add(Finding(where, said));
      }
    }
  }
  return found;
}

List<Finding> _noApplicationDependency() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml').readAsStringSync();
    for (final app in applications) {
      if (RegExp('^\\s+$app:', multiLine: true).hasMatch(pubspec)) {
        found.add(Finding(entry.key, 'depends on the $app application'));
      }
    }
  }
  return found;
}

// --------------------------------------------------------- shared mutables

List<Finding> _noSharedMutables() {
  final found = <Finding>[];
  for (final entry in <String, Directory>{...packages, ...apps}.entries) {
    final lib = Directory('${entry.value.path}/lib');
    for (final file in dartFilesIn(lib)) {
      // The detector's own examples live in the rule, not in a package.
      for (final said in sharedMutablesIn(file.readAsStringSync())) {
        found.add(
          Finding(
            '${entry.key}/${relative(file, entry.value)}',
            '$said — the first caller to scale it in place changes it for the '
                'whole process; return a fresh one from a getter',
          ),
        );
      }
    }
  }
  return found;
}

// --------------------------------------------------------- genre isolation

bool _draws(String source) =>
    reaches(source, 'package:flutter3d/') || reaches(source, 'flutter_gpu');

bool _namesFlutter(String source) =>
    reaches(source, 'package:flutter/') || reaches(source, 'dart:ui');

List<Finding> _genreIsolation() {
  final found = <Finding>[];
  for (final genre in genrePackages) {
    final dir = packages[genre];
    if (dir == null) continue;
    final mayDraw = genreMayDraw[genre] ?? const <String>{};
    final visible = genreBridgeHalf[genre] ?? const <String>{};

    for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
      final path = relative(file, dir);
      final source = file.readAsStringSync();
      if (!mayDraw.contains(path) && _draws(source)) {
        found.add(
          Finding(
            '$genre/$path',
            'the simulation half draws — move it into the bridge, or add it to '
                'genreMayDraw and say why',
          ),
        );
      }
      if (!visible.contains(path) && _namesFlutter(source)) {
        found.add(
          Finding(
            '$genre/$path',
            'the simulation half names Flutter — a widget belongs to what '
                'bridge.dart exports; move it there, or add it to '
                'genreBridgeHalf and say why',
          ),
        );
      }
    }

    // A file can keep to its half and still be handed over by the wrong door:
    // the simulation's barrel exporting a widget puts Flutter in front of every
    // caller that only wanted to step a run.
    final barrel = File('${dir.path}/lib/$genre.dart');
    if (barrel.existsSync()) {
      final source = barrel.readAsStringSync();
      for (final path in <String>{...mayDraw, ...visible}) {
        final uri = path.replaceFirst('lib/', '');
        if (reaches(source, "'$uri'")) {
          found.add(
            Finding(
              '$genre/lib/$genre.dart',
              'exports $uri, which belongs to the visible half — export it '
                  'from bridge.dart',
            ),
          );
        }
      }
    }

    // The allowlist fails in both directions. One naming a file that no longer
    // draws is a rule rotting into a description of work already done.
    for (final path in mayDraw) {
      final file = File('${dir.path}/$path');
      if (!file.existsSync()) {
        found.add(
          Finding('$genre/$path', 'is allowed to draw and is not there'),
        );
      } else if (!_draws(file.readAsStringSync())) {
        found.add(
          Finding('$genre/$path', 'no longer draws; take it off the list'),
        );
      }
    }
  }
  return found;
}

/// Every genre camera turns `CameraRig`, or says on [notARigCamera] why not.
///
/// Matched on the file name rather than on what the class extends, because the
/// failure this catches does not subclass anything: it is a new file called
/// `something_camera.dart` holding its own lerp. A camera that names the rig
/// has found the seam, whatever it does with it; one that never names it has
/// not, and that is the whole question.
///
/// Read out of the code rather than the whole file, because prose naming the
/// rig is what a reimplementation would have too — `follow_camera.dart` opens
/// by saying which parts moved to [CameraRig], and a file that explains the
/// seam while going around it is the case this must still catch. It is also not
/// an import check: the cameras reach the rig through the package barrel, so
/// the name never appears on an `import` line.
List<Finding> _genreCameraTurnsTheRig() {
  final found = <Finding>[];
  // Packages *and* applications, because the default has to be covered. The
  // repeatable-step rule learned this the expensive way — written as a table of
  // what to scan, it left a new genre unscanned until somebody remembered to
  // edit the table — and a camera is the same shape: the third one gets written
  // in a demo application, which is where a genre starts, more readily than in
  // a package that already has one.
  for (final entry in <String, Directory>{...packages, ...apps}.entries) {
    final dir = entry.value;
    for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
      final path = relative(file, dir);
      if (!path.split('/').last.contains('camera')) continue;
      if (notARigCamera.containsKey('${entry.key}/$path')) continue;
      if (!codeOf(file.readAsStringSync()).contains('CameraRig')) {
        found.add(
          Finding(
            '${entry.key}/$path',
            'is a camera that never names CameraRig — the smoothing, the '
                'impulse decay and the pull out of walls are already written '
                'once in flutter3d_camera; turn the rig, or add it to '
                'notARigCamera and say what it does instead',
          ),
        );
      }
    }
  }
  return found;
}

List<Finding> _noSidewaysGenre() {
  final found = <Finding>[];
  for (final genre in genrePackages) {
    final dir = packages[genre];
    if (dir == null) continue;
    for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
      for (final other in genrePackages) {
        if (other == genre) continue;
        if (reaches(file.readAsStringSync(), other)) {
          found.add(
            Finding(
              '$genre/${relative(file, dir)}',
              'reaches $other — a racing game borrowing a platformer\'s runner '
                  'would compile, and would tie the two together for as long as '
                  'nobody looked',
            ),
          );
        }
      }
    }
  }
  return found;
}

// -------------------------------------------------------- a repeatable step

/// **Every package, minus the ones excused by name.** This walked a table of
/// five packages to scan, which is the arrangement `repository.dart` opens by
/// describing as the thing that had just been removed: the default was exempt,
/// so a new genre package got no scan until somebody edited a list. It is
/// exclusions now — see [notARepeatableStep].
///
/// **And every application, minus the ones that step nothing** (decision 11
/// of `tasks/0.9-plugins.md`). It scanned packages only, while a game's step
/// is written in a demo first and moved into a package later, if ever: a
/// clock read there was invisible until it moved. The tools and the pages are
/// excused by [notARepeatedApp]; a demo's file that draws says so in
/// [repeatableStepExempt], under the application's name.
List<Finding> _repeatableStep() {
  final found = <Finding>[];
  for (final entry in _steppedDirectories.entries) {
    final dir = entry.value;
    final exempt = repeatableStepExempt[entry.key] ?? const <String, String>{};

    final files = dartFilesIn(Directory('${dir.path}/lib'));
    if (files.isEmpty) {
      found.add(
        Finding(entry.key, 'has no lib/ — a scan of nothing proves nothing'),
      );
      continue;
    }
    for (final file in files) {
      final path = relative(file, dir);
      if (exempt.containsKey(path)) continue;
      final said = unrepeatableIn(file.readAsStringSync());
      if (said != null) {
        found.add(
          Finding(
            '${entry.key}/$path',
            '$said — a step takes its randomness from a generator it was handed '
                'and never asks the system what time it is — see ARCHITECTURE.md 9.3',
          ),
        );
      }
    }
  }
  return found;
}

/// The packages and applications a run steps through, by name: what the
/// repeatable-step and the portable-arithmetic rules both scan.
///
/// One set for both rules, for the reason [_portableStepArithmetic] gives —
/// a directory a run steps through is one both apply to — and kept here so
/// the two cannot drift apart by one of them learning about `apps/` alone.
Map<String, Directory> get _steppedDirectories => <String, Directory>{
  for (final entry in packages.entries)
    if (!notARepeatableStep.containsKey(entry.key)) entry.key: entry.value,
  for (final entry in apps.entries)
    if (!notARepeatedApp.containsKey(entry.key)) entry.key: entry.value,
};

// ---------------------------------------------------------- the server's half

/// No package in [flatDartPackages] may name Flutter — in its library, its
/// tests or its binaries.
///
/// **This is the rule `flutter3d_sim` was created to make checkable.** A server
/// that verifies a submitted run has to replay it through the same simulation
/// the player ran, and that server is a Dart process in a container. One
/// `package:flutter/foundation.dart` for one `debugPrint` puts a Flutter SDK on
/// the critical path of the whole service, and it does so silently: everything
/// still builds, every test still passes, and the failure arrives months later
/// as a container that will not start.
///
/// The old invariant was a sentence in a pubspec — "depends only on flutter,
/// mouse_capture and vector_math" — which was both unchecked and wrong: the
/// package it described reached Flutter in eight files out of eighty-nine, and
/// nobody knew because nothing counted.
///
/// **It reads a list now rather than one package's name**, because the second
/// package arrived: `flutter3d_editor_core` came out of an application for the
/// same reason the simulation came out of a package, and the alternative was a
/// thirty-first rule that would have read the identical regexp over a different
/// directory. The rule keeps the name it was published under — ARCHITECTURE.md
/// and the site both quote it — and [flatDartPackages] says which packages it
/// is about and why each is there.
///
/// Tests and `bin/` are scanned as well as `lib/`, deliberately. A suite that
/// needs `flutter_test` to run is a suite CI can only run through Flutter, and
/// then the claim "this package stands alone" is true of the library and false
/// of the thing anybody actually executes.
List<Finding> _flatDartNamesNoFlutter() {
  // `package:flutter/`, `dart:ui` and `flutter_test` together, for the reason
  // `hardwareMayUseFlutter` gives about the first two: widgets re-export half
  // of `dart:ui`, so naming one without the other is a rule with a door in it.
  final forbidden = RegExp(
    r"'(package:flutter/|package:flutter_test/|dart:ui)",
  );

  final found = <Finding>[];
  for (final entry in flatDartPackages.entries) {
    final package = packages[entry.key];
    if (package == null) {
      found.add(
        Finding(
          entry.key,
          'is not a package any more, so the rule that it stays plain Dart has '
          'outlived its subject — take it out of flatDartPackages or '
          'restore the package',
        ),
      );
      continue;
    }

    for (final where in <String>['lib', 'test', 'bin']) {
      for (final file in dartFilesIn(Directory('${package.path}/$where'))) {
        if (!forbidden.hasMatch(file.readAsStringSync())) continue;
        found.add(
          Finding(
            relative(file, repositoryRoot),
            'names Flutter, and ${entry.key} is plain Dart because '
            '${entry.value}. Whatever wants Flutter belongs in the package or '
            'the application that already has it',
          ),
        );
      }
    }
  }
  return found;
}

/// A plain Dart package may not reach the Flutter SDK **through** a sibling.
///
/// **The rule beside this one reads `lib/`, and that is not where this arrives.**
/// `the simulation names no Flutter` scans source text, so a package with no
/// Flutter import at all passes it — and then `dart pub get` fails anyway,
/// because one of its dependencies declares `flutter: sdk` and pub resolves the
/// whole graph before a single file is read. That is not hypothetical: the
/// modeller's document layer was going to depend on `flutter3d` for `MeshData`,
/// which is one line in a pubspec and a package an agent's `dart run` cannot
/// start. `flutter3d_geometry` and `flutter3d_formats` exist because of it.
///
/// So this walks the graph rather than the files, and reports the path it took:
/// a name in the chain is where to break it. Dev dependencies count, for the
/// reason [pubspecDependencies] gives — `dart test` resolves those too, and a
/// package whose own suite needs the SDK is a package the container cannot
/// check.
///
/// Packages outside this workspace are not followed. `vector_math` and `test`
/// are pub's problem, and neither can grow a Flutter dependency without the
/// lock file saying so.
List<Finding> _flatDartResolvesWithoutFlutter() {
  final found = <Finding>[];

  final specs = <String, String>{};
  for (final entry in packages.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml');
    if (pubspec.existsSync()) specs[entry.key] = pubspec.readAsStringSync();
  }

  /// The shortest chain from [start] to a package asking for the SDK, or null.
  List<String>? pathToSdk(String start) {
    final queue = <List<String>>[
      <String>[start],
    ];
    final seen = <String>{start};
    while (queue.isNotEmpty) {
      final chain = queue.removeAt(0);
      final spec = specs[chain.last];
      if (spec == null) continue;
      if (dependsOnFlutterSdk(spec)) return chain;
      for (final name in pubspecDependencies(spec)) {
        if (!specs.containsKey(name) || !seen.add(name)) continue;
        queue.add(<String>[...chain, name]);
      }
    }
    return null;
  }

  for (final entry in flatDartPackages.entries) {
    if (!specs.containsKey(entry.key)) continue; // reported by the rule above
    final chain = pathToSdk(entry.key);
    if (chain == null) continue;
    final via = chain.length == 1 ? 'its own pubspec' : chain.join(' -> ');
    found.add(
      Finding(
        '${entry.key}/pubspec.yaml',
        'resolves the Flutter SDK through $via, and ${entry.key} is plain Dart '
            'because ${entry.value}. `dart pub get` fails on this before it '
            'reads a line of source, so no import scan can see it',
      ),
    );
  }
  return found;
}

// ------------------------------------------------------- backend containment

/// The files of `flutter3d_hardware`, or the one finding that says why there
/// are none to read.
///
/// Both hardware rules walk the same list, and both are worthless against an
/// empty one: a scan over no files reports nothing and is indistinguishable
/// from a scan over clean ones.
(List<File>, Finding?) _hardwareFiles() {
  final dir = packages['flutter3d_hardware'];
  if (dir == null) {
    return (
      const <File>[],
      const Finding('flutter3d_hardware', 'is not there'),
    );
  }
  final files = dartFilesIn(Directory('${dir.path}/lib'));
  if (files.isEmpty) {
    return (
      const <File>[],
      const Finding(
        'flutter3d_hardware',
        'has no lib/ — a scan that finds nothing proves nothing',
      ),
    );
  }
  return (files, null);
}

List<Finding> _hardwareNamesNoApi() {
  final (files, missing) = _hardwareFiles();
  if (missing != null) return <Finding>[missing];
  final dir = packages['flutter3d_hardware']!;

  final found = <Finding>[
    for (final file in files)
      if (reaches(file.readAsStringSync(), 'flutter_gpu'))
        Finding(
          'flutter3d_hardware/${relative(file, dir)}',
          'reaches a backend',
        ),
  ];

  if (File(
    '${dir.path}/pubspec.yaml',
  ).readAsStringSync().contains('flutter_gpu')) {
    found.add(
      const Finding(
        'flutter3d_hardware',
        'depends on a backend; backends depend on it, never the other way',
      ),
    );
  }
  return found;
}

/// The hardware layer's vocabulary is its own — Flutter's included.
///
/// **This was the back half of `the hardware layer names no graphics API`,
/// and a rule that fires under another rule's name is a rule nobody reads.**
/// A `dart:ui` import in `graphics_device.dart` was reported by a line that
/// says "graphics API", which is the one thing such an import is not; the
/// reader goes looking for a `flutter_gpu` they will not find. mcp-01n's own
/// acceptance asks for this rule by name for that reason, and the split costs
/// nothing: both halves read the same files, neither excuses the other's
/// findings, and the failure now says which boundary was crossed.
///
/// `package:flutter/` is banned alongside `dart:ui` because widgets re-export
/// half of `dart:ui` — [hardwareMayUseFlutter] carries the longer argument,
/// and is empty since `present()` left `GraphicsDevice` for `presentFrame` in
/// `flutter3d_app`.
List<Finding> _hardwareNamesNoFlutter() {
  final (files, missing) = _hardwareFiles();
  if (missing != null) return <Finding>[missing];
  final dir = packages['flutter3d_hardware']!;

  return <Finding>[
    for (final file in files)
      if (!hardwareMayUseFlutter.containsKey(file.uri.pathSegments.last) &&
          (reaches(file.readAsStringSync(), 'dart:ui') ||
              reaches(file.readAsStringSync(), 'package:flutter/')))
        Finding(
          'flutter3d_hardware/${relative(file, dir)}',
          "reaches Flutter — this package's vocabulary is its own. If this is "
              'genuinely something every backend must answer, name it in '
              'hardwareMayUseFlutter with the reason',
        ),
  ];
}

/// A published package's `lib/` imports no other package's `lib/src/`.
///
/// **A semver hole otherwise**: `src/` is outside the API snapshot, so a
/// package that reaches into another's can be broken by a patch release of
/// it that no constraint forbids. What one engine package needs of another's
/// internals is published as a library of its own — `flutter3d_shaders`'
/// `internal.dart`, `flutter3d_cpu`'s `builtin.dart` — which the snapshot
/// sees. Tests, examples and tools may still reach in; they are not
/// published code.
List<Finding> _noForeignSrcImports() {
  final found = <Finding>[];
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    final lib = Directory('${dir.path}/lib');
    if (!lib.existsSync()) continue;
    for (final file in dartFilesIn(lib)) {
      for (final other in foreignSrcImports(file.readAsStringSync(), name)) {
        found.add(
          Finding(
            '$name/${relative(file, dir)}',
            "imports $other's src/, which is outside its API: publish what "
                'is needed as a library of $other (as '
                "flutter3d_shaders' internal.dart does) and import that",
          ),
        );
      }
    }
  }
  return found;
}

List<Finding> _engineNamesNoBackend() {
  // mcp-03n moved the rendering core this check is about into
  // `flutter3d_core` — `flutter3d` itself is a thin Flutter shell over it
  // now (`ModelAsset`, `bindMaterial`, the two Flutter-named asset sources),
  // none of which reaches a backend either, but the package the guarantee
  // below is actually *for* is the one that used to be five files short of
  // naming no Flutter at all.
  final core = packages['flutter3d_core'];
  if (core == null) {
    return <Finding>[const Finding('flutter3d_core', 'is not there')];
  }
  final found = <Finding>[];

  for (final file in dartFilesIn(Directory('${core.path}/lib'))) {
    if (reaches(file.readAsStringSync(), 'flutter_gpu')) {
      found.add(
        Finding(
          'flutter3d_core/${relative(file, core)}',
          'names flutter_gpu, which this package must not know exists — '
              'whatever it needs belongs on GraphicsDevice or CommandEncoder',
        ),
      );
    }
  }

  final corePubspec = File('${core.path}/pubspec.yaml').readAsStringSync();
  for (final forbidden in <String>['flutter_gpu', 'flutter3d_impeller']) {
    // The import scan misses this: depending on a backend and using it through
    // the umbrella library names nothing textually and still welds the engine
    // to one.
    if (corePubspec.contains('\n  $forbidden:')) {
      found.add(
        Finding(
          'flutter3d_core',
          'depends on $forbidden — an application chooses a backend, the '
              'engine does not',
        ),
      );
    }
  }
  if (!corePubspec.contains('flutter3d_hardware:')) {
    found.add(
      const Finding(
        'flutter3d_core',
        'no longer depends on the hardware layer, so it is written against '
            'nothing and the two checks above are vacuous',
      ),
    );
  }

  // `engineAlsoFreeOfDartUi` held one file to a stricter rule than the rest
  // of `flutter3d` — `frame_resources.dart`, so the frame graph stayed
  // unit-testable off a device. It moved to `flutter3d_core` with the rest
  // of the render graph (mcp-03n), where `flatDartPackages`'s own check
  // already holds *every* file to that rule, not one — the exemption this
  // loop existed to apply has nothing left to apply that the wider rule does
  // not already cover.

  final engine = packages['flutter3d'];
  if (engine == null) {
    found.add(const Finding('flutter3d', 'is not there'));
    return found;
  }
  for (final entry in engineCompilesOffDevice.entries) {
    final file = File('${engine.path}/${entry.key}');
    if (!file.existsSync()) {
      found.add(
        Finding(
          'flutter3d/${entry.key}',
          'moved or was renamed; the rule moves with it',
        ),
      );
      continue;
    }
    final path = _pathToFlutter(file);
    if (path != null) {
      found.add(
        Finding(
          'flutter3d/${entry.key}',
          'reaches Flutter, so it no longer compiles ahead of time — '
              '${entry.value}\n      via ${path.join('\n       -> ')}',
        ),
      );
    }
  }
  return found;
}

/// The shortest import path from [start] to a file naming Flutter, or null.
///
/// Breadth-first so that what it reports is the shortest way in rather than the
/// first one the walk happened to take — the difference between a finding that
/// names the import to delete and one that names a file four hops downstream of
/// it. Relative imports resolve against the importing file; `package:` imports
/// against the workspace, which is what makes this cross the package boundary
/// the single-file scans cannot see. Anything it cannot resolve — the SDK, a
/// pub-cache dependency — is not walked: those are somebody else's tree, and
/// `package:flutter/` is recognised on sight rather than followed.
List<String>? _pathToFlutter(File start) {
  final roots = <String, String>{
    for (final entry in packages.entries) entry.key: '${entry.value.path}/lib',
  };
  final from = <String, String>{};
  final queue = <String>[start.absolute.path];
  final seen = <String>{queue.first};

  List<String> trail(String file, String last) {
    final steps = <String>[last];
    for (String? at = file; at != null; at = from[at]) {
      steps.add(at.replaceFirst('${repositoryRoot.path}/', ''));
    }
    return steps.reversed.toList();
  }

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final file = File(current);
    if (!file.existsSync()) continue;
    for (final uri in _importedUris(file.readAsStringSync())) {
      if (uri.startsWith('package:flutter/') || uri == 'dart:ui') {
        return trail(current, uri);
      }
      final resolved = _resolveImport(uri, current, roots);
      if (resolved == null || !seen.add(resolved)) continue;
      from[resolved] = current;
      queue.add(resolved);
    }
  }
  return null;
}

/// Every `import`/`export` target in [source], in the order written.
Iterable<String> _importedUris(String source) => RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
).allMatches(source).map((RegExpMatch m) => m.group(1)!);

/// Where an import URI lands on disk, or null when it leaves the workspace.
///
/// **Normalized, not just made absolute.** A relative import climbing out of
/// its own directory (`../asset_source.dart`, common wherever
/// `flutter3d_core/lib/src/formats/{f3d,gltf,obj,stl,usdz}/` reaches a sibling)
/// used to come back as a literal `.../f3d/../asset_source.dart` — a
/// different string for the same file depending on which directory imported
/// it from. `_pathToFlutter`'s `seen` set dedupes by string, so five
/// spellings of one file were five unvisited files, and revisiting a file
/// under a fresh spelling re-walked its own `../` imports into even longer,
/// still-distinct strings. What looked like a bounded breadth-first search
/// over roughly ninety real files instead grew past twenty thousand queued
/// entries before this was caught. `Uri.normalizePath()` collapses `..`
/// segments the way `File.absolute.path` never promises to, so the same file
/// reached two ways resolves to the same string both times.
String? _resolveImport(String uri, String from, Map<String, String> roots) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final root = roots[rest.substring(0, slash)];
    return root == null
        ? null
        : Uri.file(
            '$root/${rest.substring(slash + 1)}',
          ).normalizePath().toFilePath();
  }
  return Uri.file(
    '${File(from).parent.path}/$uri',
  ).normalizePath().toFilePath();
}

// ------------------------------------------------------------ one assembly

/// Source with comments and single-quoted strings taken out.
///
/// A doc comment naming `spawnInto` is a doc comment, and the rules are full of
/// them. A string is how a scan tests itself.
String _assemblyCode(String source) => source
    .split('\n')
    .map((String line) => line.replaceAll(RegExp(r'//.*'), ''))
    .join('\n')
    .replaceAll(RegExp("'[^']*'"), "''");

List<Finding> _oneAssembly() {
  final found = <Finding>[];
  for (final entry in apps.entries) {
    final homes = <String, List<String>>{};
    for (final file in dartFilesIn(Directory('${entry.value.path}/lib'))) {
      final code = _assemblyCode(file.readAsStringSync());
      for (final call in assemblyCalls) {
        if (code.contains(call)) {
          homes
              .putIfAbsent(call, () => <String>[])
              .add(relative(file, entry.value));
        }
      }
    }
    for (final call in homes.entries) {
      if (call.value.length > 1) {
        found.add(
          Finding(
            entry.key,
            'calls ${call.key} in ${call.value.length} places — '
            '${call.value.join(', ')}. The second is a second answer to what a '
            'level contains, and it will disagree with the first',
          ),
        );
      }
    }
  }

  // The other direction: a game with no shipped assembly passes by having
  // nothing to be the second copy of. Demos only — the editor builds levels
  // rather than playing one, and the template is a seed.
  final demos = applications.where((String a) => a.contains('_demo_'));
  if (demos.isEmpty) {
    found.add(const Finding('applications', 'no demo game is named `_demo_`'));
  }
  for (final demo in demos) {
    final staging = File(
      '${repositoryRoot.path}/apps/$demo/lib/src/staging.dart',
    );
    if (!staging.existsSync()) {
      found.add(Finding(demo, 'has no one place that assembles a run'));
    }
  }
  return found;
}

List<Finding> _noHarnessAssembly() {
  final found = <Finding>[];
  for (final entry in apps.entries) {
    for (final file in dartFilesIn(Directory('${entry.value.path}/test'))) {
      final code = _assemblyCode(file.readAsStringSync());
      for (final call in assemblyCalls) {
        if (code.contains(call)) {
          found.add(
            Finding(
              '${entry.key}/${relative(file, entry.value)}',
              "calls $call — a harness that is not the game is a harness that "
                  "agrees with any bug the game has. Call the game's own stage()",
            ),
          );
        }
      }
    }
  }
  return found;
}

// ----------------------------------------------------------------- the lists

List<Finding> _listsAgree() {
  final found = <Finding>[];
  final workspace = File(
    '${repositoryRoot.path}/pubspec.yaml',
  ).readAsStringSync();
  final members = <String>[
    for (final line in workspace.split('\n'))
      if (RegExp(r'^\s+-\s+(packages|apps)/').hasMatch(line)) line.trim(),
  ];

  final inWorkspace = <String>{
    for (final member in members)
      if (member.startsWith('- apps/')) member.substring('- apps/'.length),
  };
  if (applications.toSet().difference(inWorkspace).isNotEmpty ||
      inWorkspace.difference(applications.toSet()).isNotEmpty) {
    found.add(
      Finding(
        'applications',
        'the list and the workspace disagree: list has '
            '${applications.join(', ')}; workspace has ${inWorkspace.join(', ')}',
      ),
    );
  }

  final genresInWorkspace = <String>{
    for (final member in members)
      if (member.startsWith('- packages/flutter3d_game_') &&
          !notAGenre.containsKey(member.substring('- packages/'.length)))
        member.substring('- packages/'.length),
  };
  if (genrePackages.toSet().difference(genresInWorkspace).isNotEmpty ||
      genresInWorkspace.difference(genrePackages.toSet()).isNotEmpty) {
    found.add(
      Finding(
        'genrePackages',
        'the list and the workspace disagree: list has '
            '${genrePackages.join(', ')}; workspace has '
            '${genresInWorkspace.join(', ')}',
      ),
    );
  }
  return found;
}

/// How many rules the documents say there are, against how many there are.
///
/// **Two documents once carried two different wrong answers**, which is what a
/// number nobody can check looks like after a while. Neither is load-bearing on
/// its own — but a reader who finds one number wrong has no way to tell which of
/// the others are, and both documents are largely numbers like this one.
///
/// The count is written in digits wherever it is written, because a number in
/// prose is one nobody recounts and a digit is what a reader and a rule both
/// read the same way. A count spelled out as a word is a finding of its own, so
/// nobody drifts back to it.
List<Finding> _ruleCount() {
  final actual = allRules.length;
  final found = <Finding>[];

  void check(String path, RegExp pattern) {
    final file = File('${repositoryRoot.path}/$path');
    if (!file.existsSync()) {
      found.add(Finding(path, 'is not there'));
      return;
    }
    final match = pattern.firstMatch(file.readAsStringSync());
    if (match == null) {
      found.add(
        Finding(
          path,
          'no longer says how many rules there are, so nothing here can '
          'tell whether it is right',
        ),
      );
      return;
    }
    final said = match.group(1)!;
    if (int.tryParse(said) == null) {
      found.add(_spelledOut(path, match.group(0)!, said));
    } else if (said != '$actual') {
      found.add(Finding(path, 'says $said rules; there are $actual'));
    }
  }

  check('README.md', _countPhrasing('its # rules'));
  check('ARCHITECTURE.md', RegExp(r'Structure rules \| (\d+),'));

  // The site and CONTRIBUTING.md state the count too, each in the phrasing
  // its own sentence needed — "18 rules, under a second", "one of 19
  // scans" — and those were three different wrong answers at once. Matched
  // by phrasing, the way the golden scenes are, so "two rules check it"
  // about a pair of rules is not read as a claim about the total.
  // `ARCHITECTURE.md` is read for them too: its table is checked above, and
  // its prose said the count again, in words, where nothing read it.
  final phrasings = <RegExp>[
    _countPhrasing('# rules, under a second', caseSensitive: false),
    _countPhrasing('holds # rules'),
    _countPhrasing('one of # scans', caseSensitive: false),
    _countPhrasing('# green scans'),
    _countPhrasing('# checks that read source text'),
    _countPhrasing('one of the # checks it'),
    _countPhrasing('enforces # rules'),
    _countPhrasing('# rules, no device'),
    _countPhrasing(r'# rules\. All but two'),
  ];
  for (final page in <File>[
    File('${repositoryRoot.path}/ARCHITECTURE.md'),
    ..._prosePages(),
  ].where((File f) => f.existsSync())) {
    final text = page.readAsStringSync();
    for (final pattern in phrasings) {
      for (final match in pattern.allMatches(text)) {
        final claim = match.group(1)!;
        final number = int.tryParse(claim);
        if (number == null) {
          found.add(_spelledOut(_inRepository(page), match.group(0)!, claim));
        } else if (number != actual) {
          found.add(
            Finding(
              _inRepository(page),
              'says $claim rules; there are $actual',
            ),
          );
        }
      }
    }
  }

  found.addAll(_theTestingPageAddsUp(actual));
  return found;
}

/// The testing page names some of the rules in a table and counts the rest.
///
/// **The page whose subject is "a number in prose is a number nobody recounts"
/// was two short by its own addition**: eleven rules in the table and "ten more"
/// under it, against twenty-three. Neither number is wrong on its face, which is
/// why nobody noticed — it is the sum that fails, and a reader auditing which
/// rules exist stops before the last two.
///
/// So the sum is checked rather than the sentence: the table's rows are counted
/// where they are, and the number under it has to be the rest of them. The table
/// is found by its header, because the same page carries a per-package test
/// table whose rows look identical to a pattern.
List<Finding> _theTestingPageAddsUp(int actual) {
  const page = 'site/content/reference/testing.md';
  final file = File('${repositoryRoot.path}/$page');
  if (!file.existsSync()) return const <Finding>[];
  final text = file.readAsStringSync();

  final header = text.indexOf('| Rule | What it refuses |');
  if (header < 0) return const <Finding>[];
  final ends = text.indexOf('\n\n', header);
  final rows = RegExp(
    r'^\| `',
    multiLine: true,
  ).allMatches(text.substring(header, ends < 0 ? text.length : ends)).length;

  final rest = _countPhrasing(
    '# more check the lists',
    caseSensitive: false,
  ).firstMatch(text);
  if (rest == null) {
    return <Finding>[
      const Finding(
        page,
        'no longer says how many rules its table leaves out, so nothing here '
        'can tell whether the page adds up',
      ),
    ];
  }
  final said = int.tryParse(rest.group(1)!);
  if (said == null) {
    return <Finding>[_spelledOut(page, rest.group(0)!, rest.group(1)!)];
  }
  if (said == actual - rows) return const <Finding>[];
  return <Finding>[
    Finding(
      page,
      'names $rows rules in its table and says $said more, which is '
      '${said + rows} of $actual',
    ),
  ];
}

/// Every application that draws asks its platform to turn the GPU on.
///
/// **This is a per-application setting on every platform, and it fails
/// silently.** Flutter GPU is off unless an application asks: `Info.plist` wants
/// `FLTEnableFlutterGPU` on Apple platforms, and `AndroidManifest.xml` wants
/// `io.flutter.embedding.android.EnableFlutterGPU`, which the engine reads with
/// a default of false. Without it the shader library does not initialise and the
/// game draws nothing, with nothing in the log naming the cause.
///
/// **Written because two applications had already shipped without it.** The
/// dungeon and the platformer built for Android, and their APKs would have drawn
/// an empty screen on any phone; nobody had noticed because nobody had a phone.
/// The macOS plists had carried the key since the beginning, which is exactly
/// how a per-platform setting rots — the platform somebody uses is right, and
/// the ones nobody uses are whatever the template left.
///
/// Only platforms an application actually has are checked. A game with no `ios/`
/// is not missing a flag; it is missing a platform, which is a different thing
/// and not this rule's business.
///
/// **The key is matched where it stands, not anywhere in the file.** This asked
/// whether the text contained the name, which a misspelling that keeps the name
/// as a substring satisfies: a plist saying `FLTEnableFlutterGPU_MUTATED` passed,
/// and so would a sentence in a comment about the key beside a plist that has
/// not got it — which is the likelier accident, since the Android manifest
/// already carries a comment naming the Apple key. Both are the failure this
/// rule exists for, wearing the disguise of a rule that passes.
List<Finding> _gpuIsEnabled() {
  // The key in the position that makes it a key: `<key>…</key>` in a plist,
  // and the quoted value of `android:name` in a manifest. Whitespace inside
  // the element is allowed because a formatter may put it there; a longer name
  // is not, because that is the misspelling.
  final appleKey = RegExp(r'<key>\s*FLTEnableFlutterGPU\s*</key>');
  final androidKey = RegExp(
    r'android:name\s*=\s*"io\.flutter\.embedding\.android\.EnableFlutterGPU"',
  );

  final found = <Finding>[];
  for (final entry in apps.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    // An application that does not reach the engine draws nothing through it
    // and has nothing to enable.
    if (!RegExp(
      r'^\s+flutter3d(_app|_backend)?:',
      multiLine: true,
    ).hasMatch(pubspec.readAsStringSync())) {
      continue;
    }

    for (final platform in const <String>['macos', 'ios']) {
      final plist = File('${entry.value.path}/$platform/Runner/Info.plist');
      if (!plist.existsSync()) continue;
      if (!appleKey.hasMatch(plist.readAsStringSync())) {
        found.add(
          Finding(
            '${entry.key}/$platform/Runner/Info.plist',
            'has no FLTEnableFlutterGPU key, so the shader library will not '
                'initialise and the application draws nothing',
          ),
        );
      }
    }

    final manifest = File(
      '${entry.value.path}/android/app/src/main/AndroidManifest.xml',
    );
    if (manifest.existsSync() &&
        !androidKey.hasMatch(manifest.readAsStringSync())) {
      found.add(
        Finding(
          '${entry.key}/android/app/src/main/AndroidManifest.xml',
          'has no io.flutter.embedding.android.EnableFlutterGPU meta-data; the '
              'engine defaults it to false, so the application draws nothing',
        ),
      );
    }
  }
  return found;
}

/// Every package appears in the publishing order, and nothing else does.
///
/// **Written because it had already drifted.** The list once said "twenty
/// packages" for months while there were twenty-two, with three missing from it
/// and one on it that no longer existed. Nothing anywhere would have said so:
/// the order is read on the day somebody publishes, which is the worst day to
/// discover that two of the things being published are not in the plan.
///
/// **And the order is checked against the pubspecs** (Must 7 of
/// `tasks/1.0-arch-review.md`). It used to be checked for membership only,
/// on the reasoning that deriving it would re-derive what the document
/// records; the document then put `flutter3d_plugin_api` after packages that
/// need it, and three tiers held dependencies inside themselves. Each step
/// is now a layer of the runtime graph: a package stands in a later step than
/// everything in its `dependencies:`, a dev dependency is published before
/// it unless [devDependencyPublishedLater] says why not, and nothing
/// published names the unpublished step. [publishingOrderBreaks] is the
/// check, proved in `proveDetectorsWork`.
List<Finding> _publishingOrder() {
  final file = File('${repositoryRoot.path}/ARCHITECTURE.md');
  if (!file.existsSync()) {
    return <Finding>[const Finding('ARCHITECTURE.md', 'is not there')];
  }

  final text = file.readAsStringSync();
  // The marker moved when the day came: "when the day comes" became "used on
  // the day" the day the packages went to pub.dev.
  final steps = text.split('**The order, used on the day**');
  if (steps.length != 2) {
    return <Finding>[
      const Finding(
        'ARCHITECTURE.md',
        'no longer names the publishing order, so nothing here can tell '
            'whether every package is in it',
      ),
    ];
  }

  // Only the numbered list: the prose around it names packages too, and a
  // package mentioned in a sentence is not a package anybody will publish.
  //
  // Continuation lines count. A step with five packages wraps, and reading only
  // the lines that begin with a number reports the wrapped ones as missing —
  // which is what this did on its first run, against a document that was right.
  final block = StringBuffer();
  var inList = false;
  for (final line in steps[1].split('\n')) {
    if (RegExp(r'^\s*\d+\.').hasMatch(line)) {
      inList = true;
    } else if (line.trim().isEmpty) {
      if (inList) break;
      continue;
    }
    if (inList) block.writeln(line);
  }

  final listed = <String>{
    for (final match in RegExp('`([a-z0-9_]+)`').allMatches(block.toString()))
      match.group(1)!,
  };

  final found = <Finding>[];
  for (final name in packages.keys.toList()..sort()) {
    if (!listed.contains(name)) {
      found.add(
        Finding(
          'ARCHITECTURE.md',
          '$name is a package and is not in the publishing order',
        ),
      );
    }
  }
  for (final name in listed.toList()..sort()) {
    if (!packages.containsKey(name)) {
      found.add(
        Finding(
          'ARCHITECTURE.md',
          '$name is in the publishing order and is not a package',
        ),
      );
    }
  }

  final graph = <String, ({Set<String> runtime, Set<String> dev})>{
    for (final MapEntry(key: name, value: dir) in packages.entries)
      if (File('${dir.path}/pubspec.yaml') case final pubspec
          when pubspec.existsSync())
        name: (
          runtime: pubspecSection(pubspec.readAsStringSync(), 'dependencies'),
          dev: pubspecSection(pubspec.readAsStringSync(), 'dev_dependencies'),
        ),
  };
  for (final sentence in publishingOrderBreaks(
    publishingLayers(block.toString()),
    graph,
    devDependencyPublishedLater,
  )) {
    found.add(Finding('ARCHITECTURE.md', sentence));
  }
  return found;
}

// ------------------------------------------------------------- the exemptions

/// Every path an exemption table names, checked against the tree **by string**.
///
/// **Not `File.existsSync()`, and that is the whole point of this rule.** macOS
/// is case-insensitive by default and Linux is not, so an exemption written
/// `Testing.dart` resolves on the machine it was written on and silently stops
/// matching on the machine CI runs on — where the rule it exempts from would
/// then fire on a file nobody meant to change. Comparing against the directory
/// listing makes the case exact everywhere, which is the only way a developer
/// on a Mac finds out before the Linux runner does.
///
/// The other half is rot: an exemption naming a file that has moved is a rule
/// quietly wider than it reads, and nothing else would ever say so.
List<Finding> _exemptionsResolve() {
  final found = <Finding>[];

  // Applications too, because `notARigCamera` names one: the rule it belongs to
  // scans both, so the check that its entries resolve has to look in both.
  void check(String label, String package, String path) {
    final dir = packages[package] ?? apps[package];
    if (dir == null) {
      found.add(Finding(label, '$package is not there'));
      return;
    }
    final real = dartFilesIn(
      Directory(dir.path),
    ).map((File f) => relative(f, dir)).toSet();
    if (!real.contains(path)) {
      final near = real.firstWhere(
        (String r) => r.toLowerCase() == path.toLowerCase(),
        orElse: () => '',
      );
      found.add(
        Finding(
          '$label → $package/$path',
          near.isEmpty
              ? 'names a file that is not there; the exemption is wider than '
                    'it reads'
              : 'is spelled differently from the file, which is `$near`. That '
                    'resolves on a case-insensitive filesystem and not on Linux',
        ),
      );
    }
  }

  for (final entry in genreMayDraw.entries) {
    for (final path in entry.value) {
      check('genreMayDraw', entry.key, path);
    }
  }
  for (final entry in genreBridgeHalf.entries) {
    for (final path in entry.value) {
      check('genreBridgeHalf', entry.key, path);
    }
  }
  for (final entry in repeatableStepExempt.entries) {
    for (final path in entry.value.keys) {
      check('repeatableStepExempt', entry.key, path);
    }
  }
  // Checked since the applications joined the scan, which brought a table of
  // their files with it: a demo is edited more often than a package, and a
  // file it moved would leave an exemption wider than it reads.
  for (final entry in portableStepExempt.entries) {
    for (final path in entry.value.keys) {
      check('portableStepExempt', entry.key, path);
    }
  }
  for (final name in notARepeatedApp.keys) {
    if (!apps.containsKey(name)) {
      found.add(
        Finding(
          name,
          'is excused from the determinism scans as an application and is '
          'not one — the exemption outlived its subject',
        ),
      );
    }
  }
  // Keyed by the whole path, package and file in one string, because that is
  // the shape the camera rule reads it in — split back apart here rather than
  // stored twice and allowed to disagree.
  for (final key in notARigCamera.keys) {
    final cut = key.indexOf('/');
    if (cut < 0) {
      found.add(Finding('notARigCamera → $key', 'is not a package and a path'));
      continue;
    }
    check('notARigCamera', key.substring(0, cut), key.substring(cut + 1));
  }
  // The exclusion list rots the other way: a package excused from the rule and
  // then deleted leaves a sentence explaining why a thing that is not there is
  // not scanned, and the next reader takes it for a package that exists.
  for (final name in notARepeatableStep.keys) {
    if (!packages.containsKey(name)) {
      found.add(
        Finding(
          name,
          'is excused from the repeatable-step rule and is not a package — '
          'the exemption outlived its subject',
        ),
      );
    }
  }
  for (final path in engineCompilesOffDevice.keys) {
    check('engineCompilesOffDevice', 'flutter3d', path);
  }

  // The scene-count exemptions are keyed on a path *and* on the sentence, so
  // they rot two ways: a file that moved, and a sentence that was rewritten
  // while the exemption sparing it stayed behind. The second is the dangerous
  // one — the rule reads as if it covers the file, and quietly does not.
  for (final entry in goldenCountExempt.entries) {
    final file = File('${repositoryRoot.path}/${entry.key}');
    if (!file.existsSync()) {
      found.add(
        Finding(
          'goldenCountExempt → ${entry.key}',
          'names a file that is not there; the exemption is wider than it reads',
        ),
      );
      continue;
    }
    final text = _claimsRead(file, entry.key);
    for (final fragment in entry.value.keys) {
      if (!text.contains(fragment)) {
        found.add(
          Finding(
            'goldenCountExempt → ${entry.key}',
            'spares "$fragment", which the file no longer says',
          ),
        );
      }
    }
  }

  // `hardwareMayUseFlutter` is keyed on basenames rather than paths, because
  // that is what the rule matches on. Same rot, same case trap.
  final hardware = packages['flutter3d_hardware'];
  if (hardware != null) {
    final names = dartFilesIn(
      Directory(hardware.path),
    ).map((File f) => f.uri.pathSegments.last).toSet();
    for (final name in hardwareMayUseFlutter.keys) {
      if (!names.contains(name)) {
        found.add(
          Finding(
            'hardwareMayUseFlutter → $name',
            'no file in flutter3d_hardware is called that',
          ),
        );
      }
    }
  }
  return found;
}

// -------------------------------------------------------------- odds and ends

List<Finding> _noTemporaryMutes() {
  // The prose that tells this story (tasks/, the CHANGELOGs) is markdown and
  // is not looked at; everything that runs is, whatever its language.
  const Set<String> prose = <String>{'.md'};
  final ProcessResult listed;
  try {
    listed = Process.runSync('git', <String>[
      'ls-files',
    ], workingDirectory: repositoryRoot.path);
  } on ProcessException {
    return const <Finding>[];
  }
  if (listed.exitCode != 0) return const <Finding>[];
  final found = <Finding>[];
  for (final path in (listed.stdout as String).split('\n')) {
    if (path.isEmpty) continue;
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && prose.contains(path.substring(dot))) continue;
    final file = File('${repositoryRoot.path}/$path');
    if (!file.existsSync()) continue;
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue; // binary: an image or a compiled bundle says nothing here
    }
    for (final line in temporaryMutesIn(text)) {
      found.add(
        Finding(
          '$path:$line',
          'is marked $temporaryMuteMarker, a local mute meant to be reverted '
              'before committing',
        ),
      );
    }
  }
  return found;
}

List<Finding> _noSilencedPrints() {
  // `avoid_print` is on, so the only way one reaches an application's lib/ is
  // with an `// ignore:` above it — which is what somebody writes while chasing
  // a bug and forgets while fixing it. Two of them shipped in the editor.
  final found = <Finding>[];
  for (final entry in apps.entries) {
    for (final file in dartFilesIn(Directory('${entry.value.path}/lib'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'ignore.*avoid_print').hasMatch(lines[i])) {
          found.add(
            Finding(
              '${entry.key}/${relative(file, entry.value)}:${i + 1}',
              'a print in an application, with the lint silenced above it',
            ),
          );
        }
      }
    }
  }
  return found;
}

/// A script in the Impeller backend that drives an application in the
/// engine's example and reads a verdict off what it prints.
///
/// [verdictIn] is the file the verdict line is written in — the entry point
/// itself, or a report class it prints — and [marker] is the part of that
/// line both it and the script's grep must contain.
typedef _Runner = ({
  String script,
  String entryPoint,
  String verdictIn,
  String marker,
});

/// The scripts that run something on a live GPU, each with the entry point it
/// drives and the line it reads its verdict from.
const List<_Runner> _impellerRunnerList = <_Runner>[
  (
    script: 'tool/conformance.sh',
    entryPoint: 'lib/conformance_main.dart',
    verdictIn: 'lib/conformance_main.dart',
    marker: 'passed, ',
  ),
  (
    script: 'tool/surface_probe.sh',
    entryPoint: 'lib/surface_probe_main.dart',
    verdictIn: 'lib/surface_probe_report.dart',
    marker: 'surface probe done, ',
  ),
];

List<Finding> _impellerRunners() {
  // Flutter GPU needs Impeller, which a headless `flutter test` does not
  // enable, so this backend's conformance — and its surface probe, which is
  // the same shape — run from a script driving an application. A pointer
  // that has rotted is worse than no pointer, and the second script would
  // have rotted the way the first once did: nothing but this compares its
  // grep with the line the application prints.
  final dir = packages['flutter3d_impeller'];
  if (dir == null) {
    return <Finding>[const Finding('flutter3d_impeller', 'is not there')];
  }
  return <Finding>[
    for (final runner in _impellerRunnerList) ..._runnerFindings(dir, runner),
  ];
}

List<Finding> _runnerFindings(Directory backend, _Runner runner) {
  final scriptWhere = 'flutter3d_impeller/${runner.script}';
  final script = File('${backend.path}/${runner.script}');
  if (!script.existsSync()) {
    return <Finding>[
      Finding(scriptWhere, 'is how this backend is run, and it is not there'),
    ];
  }

  final found = <Finding>[];
  // The owner-execute bit, which is a POSIX idea. Windows reports a mode of
  // nought for every file, so asking there would fail this rule on a machine
  // that cannot run a shell script in the first place — a false red about
  // something the developer could not act on.
  if (!Platform.isWindows && script.statSync().mode & 0x40 == 0) {
    found.add(
      Finding(
        scriptWhere,
        'is not executable, so the one thing that runs it cannot run',
      ),
    );
  }

  final source = script.readAsStringSync();
  if (!source.contains(runner.entryPoint)) {
    found.add(
      Finding(scriptWhere, 'no longer names the entry point it drives'),
    );
  }
  if (!source.contains(runner.marker)) {
    found.add(
      Finding(
        scriptWhere,
        'no longer greps for `${runner.marker}`, the line the verdict is '
        'read from',
      ),
    );
  }

  final example = '${repositoryRoot.path}/packages/flutter3d/example';
  final app = File('$example/${runner.entryPoint}');
  final appWhere = 'flutter3d/example/${runner.entryPoint}';
  if (!app.existsSync()) {
    found.add(
      Finding(appWhere, 'the script drives an entry point that is not there'),
    );
    return found;
  }
  if (!app.readAsStringSync().contains('exit(')) {
    found.add(
      Finding(
        appWhere,
        'no longer exits with a code, so the script would wait for ever',
      ),
    );
  }

  final verdict = File('$example/${runner.verdictIn}');
  final verdictWhere = 'flutter3d/example/${runner.verdictIn}';
  if (!verdict.existsSync()) {
    found.add(
      Finding(
        verdictWhere,
        'is where the verdict line lived, and is not there',
      ),
    );
  } else if (!verdict.readAsStringSync().contains(runner.marker)) {
    found.add(
      Finding(
        verdictWhere,
        'no longer prints the line the script reads its verdict from',
      ),
    );
  }
  return found;
}

List<Finding> _testCount() {
  // A count is not a quality measure and is not treated as one. What it catches
  // is a document quietly describing a repository from a year ago — it said
  // "1230 tests in 12 packages" when there were 2732 in 24, because a number in
  // prose is a number nobody recounts.
  final root = repositoryRoot;
  final declaration = RegExp(r'^\s*(test|testWidgets|testWithFlameGame)\(');
  int testsIn(Directory dir) => dartFilesIn(dir)
      .map((f) => f.readAsLinesSync().where(declaration.hasMatch).length)
      .fold(0, (a, b) => a + b);

  // Broken out per directory rather than summed as it goes, because the site's
  // testing page prints the breakdown as a table and a table nothing counts is
  // a table that drifts. That one did: its rows summed to 145 fewer than the
  // headline three lines above them, each stale by a different amount, which
  // is the failure mode this whole rule exists for wearing a different hat.
  //
  // The keys are the labels the table uses — a package by its own name, an
  // application prefixed `apps/`.
  final perDirectory = <String, int>{
    for (final entry in packages.entries)
      entry.key: testsIn(Directory('${entry.value.path}/test')),
    for (final entry in apps.entries)
      'apps/${entry.key}': testsIn(Directory('${entry.value.path}/test')),
  };
  final inExamples = packages.values
      .map((p) => testsIn(Directory('${p.path}/example/test')))
      .fold(0, (a, b) => a + b);
  final inTable = perDirectory.values.fold(0, (a, b) => a + b);
  final counted = inTable + inExamples;

  // **Two documents, because checking one of them taught the other to lie.**
  // ARCHITECTURE.md was held to this count and stayed right; the README, which
  // nothing checked, went on saying "1242 tests across thirteen packages" while
  // the architecture document beside it said 2874 across 22. A reader who finds
  // two numbers in one repository disagreeing has no way to tell which of the
  // others to trust.
  final found = <Finding>[];

  final architecture = File('${root.path}/ARCHITECTURE.md').readAsStringSync();
  final claimed = RegExp(
    r'\*\*(\d+) tests\*\* across (\d+) packages',
  ).firstMatch(architecture);
  if (claimed == null) {
    found.add(
      const Finding(
        'ARCHITECTURE.md',
        'no test count to compare against, so nothing here can tell whether '
            'it is right',
      ),
    );
  } else {
    if (claimed.group(1) != '$counted') {
      found.add(
        Finding(
          'ARCHITECTURE.md',
          'says ${claimed.group(1)} tests; there are $counted. '
              'Update the document, or say why the count moved',
        ),
      );
    }
    if (claimed.group(2) != '${packages.length}') {
      found.add(
        Finding(
          'ARCHITECTURE.md',
          'says ${claimed.group(2)} packages; there are ${packages.length}',
        ),
      );
    }
  }

  // The README says it in digits too, which is what this rule reads: a number
  // in prose is one nobody recounts, and a digit is what a reader and a rule
  // both read the same way. Written as a word, it is a finding of its own.
  final readme = File('${root.path}/README.md').readAsStringSync();
  final saidInProse = _countPhrasing(
    r'(\d+) tests across # packages',
  ).firstMatch(readme);
  if (saidInProse == null) {
    found.add(
      const Finding(
        'README.md',
        'no longer says how many tests there are, so nothing here can tell '
            'whether it is right',
      ),
    );
  } else {
    if (saidInProse.group(1) != '$counted') {
      found.add(
        Finding(
          'README.md',
          'says ${saidInProse.group(1)} tests; there are $counted',
        ),
      );
    }
    // The whole workspace, which is what the sentence names — the same fact
    // ARCHITECTURE.md states. It used to be held to the packages that carry a
    // test, and the two counts sitting three apart across two documents read
    // as one of them being wrong rather than as two facts.
    final said = saidInProse.group(2)!;
    if (int.tryParse(said) == null) {
      found.add(_spelledOut('README.md', saidInProse.group(0)!, said));
    } else if (said != '${packages.length}') {
      found.add(
        Finding(
          'README.md',
          'says $said packages; there are ${packages.length}',
        ),
      );
    }
  }

  // The site quotes the number too — the testing page's headline, the
  // quickstart, the home page's stat tile — and so does CONTRIBUTING.md when
  // it wants to. None of them was compared with anything, which is how every
  // page said 2901 while the tree said 2968. A page is only held to a claim
  // it makes; none is required to state a count.
  for (final page in _prosePages()) {
    final text = page.readAsStringSync();
    final where = _inRepository(page);
    final claims = <RegExpMatch>[
      ..._countPhrasing('# tests across').allMatches(text),
      ...RegExp(r'of (\d+) tests').allMatches(text),
      ...RegExp(r'Tests</dt><dd>(\d+)').allMatches(text),
    ];
    for (final m in claims) {
      final claim = m.group(1)!;
      final number = int.tryParse(claim);
      if (number == null) {
        found.add(_spelledOut(where, m.group(0)!, claim));
      } else if (number != counted) {
        found.add(Finding(where, 'says $claim tests; there are $counted'));
      }
    }
    for (final m in _countPhrasing(
      'tests across # packages',
    ).allMatches(text)) {
      if (int.tryParse(m.group(1)!) == null) {
        found.add(_spelledOut(where, m.group(0)!, m.group(1)!));
      } else if (m.group(1) != '${packages.length}') {
        found.add(
          Finding(
            where,
            'says tests across ${m.group(1)} packages; '
            'there are ${packages.length}',
          ),
        );
      }
    }
  }

  // A package README that counts its own tests is held to its own directory,
  // not to the workspace. This is the number a stranger meets first, because it
  // is the one on pub.dev, and it was the last one nobody recounted:
  // `packages/flutter3d/README.md` said 682 twice — stated once in the feature
  // list and once in the layout tree — while its own test directory held nearly
  // eight hundred. Only a README that states a count is held to it; none has
  // to, which is why every other package passes this by having nothing to say.
  for (final entry in packages.entries) {
    final readme = File('${entry.value.path}/README.md');
    if (!readme.existsSync()) continue;
    final own = perDirectory[entry.key] ?? 0;
    for (final m in RegExp(
      r'(\d+) tests',
    ).allMatches(readme.readAsStringSync())) {
      if (m.group(1) != '$own') {
        found.add(
          Finding(
            _inRepository(readme),
            'says ${m.group(1)} tests; ${entry.key}/test holds $own',
          ),
        );
      }
    }
  }

  // The per-package table on the testing page, which is the same scan told
  // one directory at a time. A row is held to its directory, a directory with
  // tests is held to having a row, and the sentence under the table that
  // reconciles the two totals is held to both.
  final breakdown = File('${root.path}/site/content/reference/testing.md');
  if (breakdown.existsSync()) {
    final text = breakdown.readAsStringSync();
    final where = _inRepository(breakdown);
    final rows = <String, int>{
      for (final m in RegExp(r'\| `([\w/]+)` \| (\d+) \|').allMatches(text))
        m.group(1)!: int.parse(m.group(2)!),
    };
    for (final row in rows.entries) {
      final actual = perDirectory[row.key];
      if (actual == null) {
        found.add(
          Finding(
            where,
            'has a row for ${row.key}, which is not a '
            'package or an application',
          ),
        );
      } else if (actual != row.value) {
        found.add(
          Finding(
            where,
            '${row.key}: the table says ${row.value}; '
            'there are $actual',
          ),
        );
      }
    }
    for (final entry in perDirectory.entries) {
      if (entry.value > 0 && !rows.containsKey(entry.key)) {
        found.add(
          Finding(where, '${entry.key} has ${entry.value} tests and no row'),
        );
      }
    }
    final sum = RegExp(r'rows sum to (\d+) rather than (\d+)').firstMatch(text);
    if (sum == null) {
      found.add(
        Finding(
          where,
          'no longer reconciles the table with the total, so '
          'nothing here can tell whether the gap is still what it says',
        ),
      );
    } else if (sum.group(1) != '$inTable' || sum.group(2) != '$counted') {
      found.add(
        Finding(
          where,
          'says the rows sum to ${sum.group(1)} rather than '
          '${sum.group(2)}; they sum to $inTable rather than $counted',
        ),
      );
    }
  }
  return found;
}

/// The compiled shader bundle is not older than the GLSL it was built from.
///
/// **The trap this closes cost an afternoon, and it fails in the worst way
/// available.** Editing a `.frag` changes nothing until `build_shaders.sh` runs
/// again: the bundle is a build artefact and gitignored, so an application goes
/// on loading the stage compiled before the edit. What that looks like is not a
/// shader that behaves oddly — it is a *bind failure*, because the renderer
/// binds a slot the new source declares and the old binary has not got, and
/// binding a slot a compiled shader does not have takes the frame down.
///
/// The error says "failed to bind texture" and names nothing that would lead
/// anybody to the shader they just edited.
///
/// **Skipped when there is no bundle at all**, which is every fresh checkout and
/// every CI run: the bundle cannot be built without `impellerc`, and a rule
/// that demanded one would be red on the machines least able to do anything
/// about it. This is a rule about a bundle that exists being current, not about
/// there being one.
///
/// **Two bundles, one rule.** The example's own loadable bundle —
/// `flutter3d/example/assets/shaders/example.f3dshaders`, what the
/// `loaded-shader` golden loads on all three backends — is gitignored for the
/// same reason and goes stale the same way, against the example's own GLSL and
/// against the engine's, which it `#include`s. Left out, the golden keeps
/// passing on the code compiled before the edit, which is exactly the silence
/// this rule exists to break.
List<Finding> _shaderBundleIsCurrent() {
  final impeller = packages['flutter3d_impeller'];
  if (impeller == null) {
    return <Finding>[const Finding('flutter3d_impeller', 'is not there')];
  }
  final engine = packages['flutter3d'];
  if (engine == null) {
    return <Finding>[const Finding('flutter3d', 'is not there')];
  }
  final sources = packages['flutter3d_shaders'];
  if (sources == null) {
    return <Finding>[const Finding('flutter3d_shaders', 'is not there')];
  }

  final engineGlsl = Directory('${sources.path}/shaders');
  return <Finding>[
    ..._bundleOlderThan(
      File('${impeller.path}/assets/shaders/flutter3d.shaderbundle'),
      'flutter3d_impeller/assets/shaders/flutter3d.shaderbundle',
      <Directory>[engineGlsl],
      rebuild: '(cd packages/flutter3d_impeller && ./tool/build_shaders.sh)',
    ),
    ..._bundleOlderThan(
      File('${engine.path}/example/assets/shaders/example.f3dshaders'),
      'flutter3d/example/assets/shaders/example.f3dshaders',
      <Directory>[Directory('${engine.path}/example/shaders'), engineGlsl],
      rebuild: '(cd packages/flutter3d/example && ./tool/build_shaders.sh)',
    ),
  ];
}

/// The finding for [bundle] being older than any GLSL under [sourceDirs], or
/// nothing — including when there is no bundle, for the reason the rule gives.
List<Finding> _bundleOlderThan(
  File bundle,
  String where,
  List<Directory> sourceDirs, {
  required String rebuild,
}) {
  if (!bundle.existsSync()) return const <Finding>[];

  final built = bundle.lastModifiedSync();
  final newer =
      sourceDirs
          .where((dir) => dir.existsSync())
          .expand((dir) => dir.listSync(recursive: true).whereType<File>())
          .where(
            (file) =>
                file.path.endsWith('.frag') ||
                file.path.endsWith('.vert') ||
                file.path.endsWith('.glsl') ||
                file.path.endsWith('.shaderbundle.json'),
          )
          .where((file) => file.lastModifiedSync().isAfter(built))
          .map((file) => file.path.split('/').last)
          .toList()
        ..sort();
  if (newer.isEmpty) return const <Finding>[];

  return <Finding>[
    Finding(
      where,
      'is older than ${newer.length} of its sources '
      '(${newer.take(4).join(', ')}${newer.length > 4 ? ', …' : ''}). '
      'Rebuild it: $rebuild. Until then an application loads the stage '
      'compiled before the edit, and a slot the new source declares fails '
      'to bind',
    ),
  ];
}

/// Every package's SDK floor is the workspace's, and every sibling constraint
/// matches the version that sibling actually declares.
///
/// **Nothing checked either, and both were wrong.** Four packages declared
/// `sdk: ^3.10.0` with `flutter: ">=3.44.0"` while the workspace resolves
/// everything against the root's `^3.12.2`; one declared a *stricter* Flutter
/// than every sibling and two declared `>=3.3.0`. Under `resolution: workspace`
/// a single lock file is resolved against the root, and CI pins one SDK — so no
/// declared floor is ever exercised, in either direction. `tool/publish_check.sh`
/// nonetheless reported every one of them "ready", which is one command away from
/// shipping packages whose stated floor cannot compile the siblings they depend
/// on.
///
/// A constraint mismatch is the same failure with a shorter fuse: a package
/// depending on `flutter3d_hardware: ^0.2.0` resolves from the checkout like
/// everything else and would resolve to something else entirely from a server.
///
/// Reads the pubspecs as text rather than through a YAML parser, for the reason
/// every other rule here does: the scan has no dependencies and runs before
/// `pub get`, which is what lets it be the first step.
List<Finding> _versionsAgree() {
  final found = <Finding>[];

  final root = File('${repositoryRoot.path}/pubspec.yaml');
  if (!root.existsSync()) {
    return <Finding>[const Finding('pubspec.yaml', 'is not there')];
  }
  final wantedSdk = _fieldIn(root.readAsStringSync(), 'sdk');
  if (wantedSdk == null) {
    return <Finding>[
      const Finding(
        'pubspec.yaml',
        'names no `environment: sdk:` to compare against',
      ),
    ];
  }

  // What each package calls itself, so a constraint on one can be checked
  // against what that one declares.
  final declared = <String, String>{};
  for (final entry in packages.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final version = _fieldIn(pubspec.readAsStringSync(), 'version');
    if (version != null) declared[entry.key] = version;
  }

  String? flutterFloor;
  String? flutterFloorFrom;

  for (final entry in packages.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final text = pubspec.readAsStringSync();
    final where = '${entry.key}/pubspec.yaml';

    final sdk = _fieldIn(text, 'sdk');
    if (sdk != null && sdk != wantedSdk) {
      found.add(
        Finding(
          where,
          'says `sdk: $sdk` where the workspace says `$wantedSdk`. Nothing '
          'resolves against it — the workspace has one lock file — so it is a '
          'floor nobody has ever compiled and `pub publish` would believe it',
        ),
      );
    }

    // The Flutter bound is not compared against the root, which does not state
    // one; it is compared against whatever the other packages say, because a
    // set of packages released together cannot disagree about it.
    final flutter = _fieldIn(text, 'flutter');
    if (flutter != null) {
      if (flutterFloor == null) {
        flutterFloor = flutter;
        flutterFloorFrom = where;
      } else if (flutter != flutterFloor) {
        found.add(
          Finding(
            where,
            'says `flutter: $flutter` and $flutterFloorFrom says '
            '`$flutterFloor`. These are released as a set, so one of the two '
            'is a floor that has never been tried',
          ),
        );
      }
    }

    for (final sibling in declared.entries) {
      final match = RegExp(
        '^  ${RegExp.escape(sibling.key)}:[ \\t]*\\^?([0-9][^\\s]*)\\s*\$',
        multiLine: true,
      ).firstMatch(text);
      if (match == null) continue;
      final asked = match.group(1)!;
      // Caret-compatible rather than equal, since a patch release moved one
      // package ahead of the set: `^0.4.0` genuinely covers a sibling that
      // declares 0.4.1, and demanding equality would force every dependent to
      // chase a constraint pub already satisfies. What this still catches is
      // the real failure — a caret that cannot reach what the sibling
      // declares, which a workspace hides and a server would refuse.
      if (!caretAdmits(asked, sibling.value)) {
        found.add(
          Finding(
            where,
            'asks for ${sibling.key} ^$asked, which declares ${sibling.value} '
            'and is outside that range. A workspace resolves it from the '
            'checkout whatever it says; a server would not',
          ),
        );
      }
    }
  }

  return found;
}

/// The value of a one-line `key: value` under `environment:` or at the top
/// level, with quotes taken off. Null when the key is absent.
String? _fieldIn(String pubspec, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}:[ \\t]+(.+)\$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) return null;
  return match.group(1)!.trim().replaceAll("'", '').replaceAll('"', '');
}

/// The recorded reference sets, and the one place this repository lists them.
///
/// **It was a local in one rule until a fourth set arrived.** The three that
/// came before were written into `_goldenFiguresExist` and nowhere else, so the
/// only question anything asked about a set was "does the picture this page
/// shows exist in it". Recording WebGPU's set made the other question the
/// interesting one — whether the sets still hold the *same* scenes — and a map
/// that lives inside one function cannot be asked it. So it is up here, both
/// rules below read it, and registering a fifth backend is one line rather than
/// two edits and a chance to forget the second.
const Map<String, String> _goldenSets = <String, String>{
  'impeller': 'packages/flutter3d/test/goldens',
  'cpu': 'packages/flutter3d_cpu/test/goldens',
  'webgl': 'packages/flutter3d_webgl/test/goldens',
  'webgpu': 'packages/flutter3d_webgpu/test/goldens',
};

/// Which set is counted, and which the others are held to.
///
/// The software one, because it is recorded off a rasteriser rather than off a
/// device: no browser, no GPU and no SDK stands between a scene existing and
/// its picture being on disk, so it is the set that is complete first and stays
/// complete.
const String _countedGoldenSet = 'cpu';

/// A scene a set deliberately does not hold, and why the picture was refused.
///
/// **A missing reference and a refused one look identical on disk, and they are
/// opposites.** The first is a set somebody forgot to finish; the second is a
/// backend saying, in the one place a picture could have said otherwise, that
/// it does not draw this. So the difference is written here rather than left to
/// a file count: naming a scene costs a sentence, and a set that quietly loses
/// one fails [_goldenSceneCount] instead of passing it a scene lighter.
///
/// The reverse also holds. Take a name out of this table without recording the
/// picture and the rule reports the gap it was hiding; record the picture and
/// leave the name here, and the rule reports the entry as spent. Neither state
/// survives a run.
final Map<String, Map<String, String>> _goldenSetGaps =
    <String, Map<String, String>>{};

/// The scene names a set has recorded.
///
/// `.actual.png` is what a failed comparison leaves beside a reference, and
/// counting one made this rule report a scene that does not exist — the same
/// slip the site's build had, where those files were being published.
Set<String> _scenesRecordedIn(Directory goldens) => goldens
    .listSync()
    .whereType<File>()
    .map((File it) => it.uri.pathSegments.last)
    .where((String it) => it.endsWith('.png') && !it.endsWith('.actual.png'))
    .map((String it) => it.substring(0, it.length - 4))
    .toSet();

/// Whether every registered set holds the scenes [counted] holds.
///
/// Two findings, and they are opposite mistakes. A set short of a scene it has
/// no entry in [_goldenSetGaps] for is a recording somebody abandoned halfway —
/// the reference set the browser stand walked away from after a stall, most
/// likely, since that is the way a set loses one picture and keeps the rest. A
/// set holding a scene its gap entry says it refused is the happier failure: the
/// picture exists now, so the sentence explaining its absence is no longer true
/// and has to go, along with whatever comparison was skipping the scene on the
/// strength of it.
///
/// A gap naming a scene nobody records is reported too. That is an entry that
/// outlived its scene, and it would otherwise sit there excusing a set from
/// holding a picture nothing was going to ask it for.
List<Finding> _goldenSetsAgree(Set<String> counted) {
  final found = <Finding>[];
  for (final set in _goldenSets.entries) {
    final gaps = _goldenSetGaps[set.key] ?? const <String, String>{};
    for (final name in gaps.keys) {
      if (counted.contains(name)) continue;
      found.add(
        Finding(
          '_goldenSetGaps → ${set.key}',
          'excuses "$name", which is not a scene the '
              '$_countedGoldenSet set records',
        ),
      );
    }
    if (set.key == _countedGoldenSet) continue;
    final goldens = Directory('${repositoryRoot.path}/${set.value}');
    if (!goldens.existsSync()) {
      found.add(Finding(set.value, 'is not there'));
      continue;
    }
    final recorded = _scenesRecordedIn(goldens);
    for (final name in counted.difference(recorded)) {
      if (gaps.containsKey(name)) continue;
      found.add(
        Finding(
          set.value,
          'has no "$name", and nothing in _goldenSetGaps says why this set '
          'does not draw it',
        ),
      );
    }
    for (final name in recorded.intersection(gaps.keys.toSet())) {
      found.add(
        Finding(
          set.value,
          'holds "$name" now, so take it out of _goldenSetGaps: it is '
          'recorded as refused for "${gaps[name]}"',
        ),
      );
    }
  }
  return found;
}

/// The golden scene count, wherever it is written in prose.
///
/// **Three files carried three different answers** — "thirty scenes" in
/// `tool/ci.sh`, "twenty-six scenes" in `golden_web.sh`, "32 scenes" in
/// `ARCHITECTURE.md` — against thirty-two on disk. That is the shape the test
/// count and the rule count already have scans for, and for the reason
/// `_testCount` gives about itself: a number in prose is a number nobody
/// recounts, and a reader who finds one wrong cannot tell which of the others
/// are.
///
/// Counted from the software backend's set, which is the one committed in full
/// and the one the other two are held against.
/// The site's pictures are `{{golden name}}` references resolved at build
/// time against the golden sets, so a scene renamed or dropped would break
/// the site's build — and the site is built on deploy, not in CI. This is the
/// same check run here, where every push sees it: each name a page shows has
/// a PNG in every set the figure draws from.
List<Finding> _goldenFiguresExist() {
  final found = <Finding>[];
  final content = Directory('${repositoryRoot.path}/site/content');
  if (!content.existsSync()) return found;
  final reference = RegExp(r'\{\{(golden3?)\s+([\w-]+)');
  for (final file in content.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    final where = relative(file, content);
    for (final match in reference.allMatches(file.readAsStringSync())) {
      final kind = match.group(1)!;
      final name = match.group(2)!;
      // A `golden3` figure is the one that puts a scene's picture from every
      // recorded set side by side, so it is checked against every set this
      // repository has — the fourth included, and including it is the point.
      // The alternative is a figure that shows what it happens to have, which
      // is how a page comes to compare three backends and call it all of them.
      for (final set in _goldenSets.entries) {
        if (kind == 'golden' && set.key != 'impeller') continue;
        if (_goldenSetGaps[set.key]?.containsKey(name) ?? false) continue;
        final png = File('${repositoryRoot.path}/${set.value}/$name.png');
        if (!png.existsSync()) {
          found.add(
            Finding(
              where,
              'shows "$name", and the ${set.key} set has no such golden',
            ),
          );
        }
      }
    }
  }
  return found;
}

/// **It reads Dart now, and that is where most of the wrong numbers were.**
/// `ssao_test.dart` said "thirty-one goldens" for eight scenes past the point
/// where it was true, and said so in the same breath as the rule that was
/// supposed to have caught it — which reads the scripts, `ARCHITECTURE.md` and
/// the site, and not a line of code. `cpu_shaders_builtin.dart` opened on "all
/// twenty-four of them". A number in a doc comment is a number nobody recounts,
/// exactly like a number in a document, and there are far more of them.
///
/// Two things had to come with it. A comment wraps, so the claims are read out
/// of [proseOf] rather than off the file — half of them cross a line. And Dart
/// is where this repository keeps its history, so the sentences that are right
/// about a past afternoon live in [goldenCountExempt] with the reason; that
/// table is the rule, as much as the regular expression is.
///
/// **The count is digits wherever it is held**, because a number in prose is
/// one nobody recounts and a digit is what a reader and a rule both read the
/// same way. A count of the scenes written as a word is refused by itself, even
/// where the word happens to be right.
List<Finding> _goldenSceneCount() {
  final where = _goldenSets[_countedGoldenSet]!;
  final goldens = Directory('${repositoryRoot.path}/$where');
  if (!goldens.existsSync()) {
    return <Finding>[Finding(where, 'is not there')];
  }
  final counted = _scenesRecordedIn(goldens);
  if (counted.isEmpty) {
    return <Finding>[Finding(where, 'holds no PNGs to count')];
  }
  final count = counted.length;
  final found = <Finding>[
    // **The number in the documents is one claim; that the sets still make it
    // true is another.** Counting one set and scanning prose against it says
    // nothing about the other three, and a set that lost a picture would sail
    // past this rule while every sentence about it stayed correct. So each
    // registered set is held to the counted one, name by name, and what a set
    // may be missing is exactly what [_goldenSetGaps] says it may be missing.
    ..._goldenSetsAgree(counted),
  ];
  // The site tells the same story on half a dozen pages, and its testing page
  // was still saying "thirty scenes" two recounts later — so the prose pages
  // are scanned along with the scripts and ARCHITECTURE.md, and every Dart file
  // in the repository along with those.
  final files = <File>[
    for (final where in <String>[
      'tool/ci.sh',
      'packages/flutter3d_webgl/tool/golden_web.sh',
      'ARCHITECTURE.md',
      // The README's own count of the scenes was left at seventy-eight when
      // the seventy-ninth landed: it was the one page that says it and that
      // nothing here read.
      'README.md',
    ])
      File('${repositoryRoot.path}/$where'),
    ..._prosePages(),
    ..._everyDartFile(),
  ];
  // Only the phrasings that are actually about the scenes, so a stray "32"
  // elsewhere in a long document is not a false positive. `goldens` is here
  // because that is the word the code uses for them; the documents say scenes.
  final claim = _countPhrasing(
    r'# (?:golden )?(?:scenes|goldens)\b',
    caseSensitive: false,
  );
  for (final file in files) {
    final where = _inRepository(file);
    if (!file.existsSync()) {
      found.add(Finding(where, 'is not there'));
      continue;
    }
    final text = _claimsRead(file, where);
    final spared = goldenCountExempt[where] ?? const <String, String>{};
    for (final match in claim.allMatches(text)) {
      final said = match.group(1)!;
      if (said == '$count') continue;
      if (_sparedAt(text, match.start, spared.keys)) continue;
      found.add(
        int.tryParse(said) == null
            ? _spelledOut(where, match.group(0)!, said)
            : Finding(where, 'says "${match.group(0)}"; there are $count'),
      );
    }
  }
  return found;
}

/// Public members nothing in the repository names, and what they say for
/// themselves.
///
/// **Deleting them is the wrong fix, which is why this is a rule and not a
/// cull.** A published package's public member with no caller here has exactly
/// one kind of caller: somebody outside. Taking it out is a breaking change for
/// the only person it was ever for, and leaving it is fine — what is not fine is
/// that nothing says so. The next reader finds an accessor with a one-line
/// restatement of its own name, no caller, and no way to tell a considered part
/// of the surface from something left behind by a refactor. Both were in the
/// found set.
///
/// So: a sentence naming who reaches for it. `SphereVehicle.groundSample` and
/// `SoLoudBackend.failedAssets` already had one — "read by whoever wants to know
/// which surface the tyres are on", "kept so a caller can say which sounds a
/// level is missing" — which is where the register comes from. The check is
/// [saysWhoReachesForIt], and it is honest about what it can see: whether the
/// sentence names anybody, not whether it names the right body.
///
/// **Named, not exported, and the difference is deliberate.** Working out what a
/// barrel re-exports needs a resolver; a public name under `lib/` that nothing
/// mentions is either surface with no caller here — this rule — or dead code
/// behind a barrel that never exported it. That is the same finding with a
/// different fix, and the sentence a writer has to produce is what tells the two
/// apart.
List<Finding> _unreferencedPublicMembers() {
  final found = <Finding>[];
  final sources = <File, String>{
    for (final file in _everyDartFile()) file: file.readAsStringSync(),
  };

  // How often each identifier is written anywhere in the repository — tests,
  // examples, applications and this tool included. A member used once is used
  // by its own declaration and by nobody.
  //
  // **Code, not prose**, and this rule taught itself that lesson: naming
  // `SphereVehicle.groundSample` in the paragraph above as an example of a
  // member that gets this right silenced the check for it. A `[member]` in a doc
  // comment is a cross-reference, not a caller, and a rule that counted them
  // would go quiet on exactly the members somebody had already thought about.
  final named = <String, int>{};
  final identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
  for (final source in sources.values) {
    for (final match in identifier.allMatches(codeOf(source))) {
      named.update(match.group(0)!, (int n) => n + 1, ifAbsent: () => 1);
    }
  }

  for (final entry in sources.entries) {
    final where = _inRepository(entry.key);
    // A package's own `lib/` only. An application's members are for that
    // application and a test's are for that test, neither of which has an
    // outside caller to be for — and `example/lib/` is an application that
    // happens to live in a package.
    if (!RegExp(r'^packages/[^/]+/lib/').hasMatch(where)) continue;
    for (final member in publicMembersIn(entry.value)) {
      if ((named[member.name] ?? 0) > 1) continue;
      if (saysWhoReachesForIt(member.doc)) continue;
      found.add(
        Finding(
          '$where:${member.line}',
          '`${member.name}` is public and nothing in the repository names it, '
              'and its doc comment does not say who does. Say who reaches for '
              'it — deleting it is a breaking change for exactly that caller',
        ),
      );
    }
  }
  return found;
}

/// A file's sentences, with the wrap undone, in the form a claim is matched in.
///
/// Dart comes through [proseOf], which is comments only. Markdown and shell are
/// prose throughout, so a line is joined to the next unless a blank line ends
/// the paragraph — the same reason and the same result: a claim written across
/// two lines is one sentence to a reader and has to be one here.
///
/// The exemption table's fragments are matched against this, which is why it is
/// one function: a fragment that reads right and matched something else would be
/// an exemption sparing a claim nobody chose.
String _claimsRead(File file, String where) {
  final source = file.readAsStringSync();
  return where.endsWith('.dart')
      ? proseOf(source)
      : source
            .replaceAll(RegExp(r'[ \t]*\n[ \t]*(?=\S)'), ' ')
            .replaceAll(RegExp(r'[ \t]+'), ' ');
}

/// Whether an exempt sentence covers the claim at [at].
///
/// Spanning rather than merely present: `engine_shaders.dart` restates the same
/// sentence six times, and a fragment found once would have spared a seventh
/// claim somewhere else in the file that nobody had looked at.
bool _sparedAt(String text, int at, Iterable<String> fragments) {
  for (final fragment in fragments) {
    for (var from = text.indexOf(fragment); from >= 0;) {
      if (at >= from && at < from + fragment.length) return true;
      from = text.indexOf(fragment, from + 1);
    }
  }
  return false;
}

/// Every Dart file in the repository: packages, applications and this tool.
///
/// This tool included, and not as a flourish: `rules.dart` quotes the three
/// wrong answers the scene count was written for, so a rule that read every
/// Dart file but its own would be exempting itself by omission.
///
/// **`repository.dart` is the one file left out, and only it.** That is where
/// the exemption table lives, and every entry in it quotes the sentence it
/// spares — so scanning it would need an exemption for each exemption, which is
/// a table nobody could read and nothing anybody could be wrong about. The rules
/// and the detectors are scanned; the list of what is spared is not.
List<File> _everyDartFile() => <File>[
  for (final where in <String>['packages', 'apps', 'tool'])
    ...dartFilesIn(Directory('${repositoryRoot.path}/$where')),
].where((File f) => !f.path.endsWith('structure/repository.dart')).toList();

/// CONTRIBUTING.md, ROADMAP.md and every Markdown page of the documentation
/// site.
///
/// The three counting rules read these along with the README and
/// `ARCHITECTURE.md`, because the site restates the same numbers in prose and
/// drifted the same way: its testing page said 2901 tests, its glossary said
/// nineteen scans, and nothing compared either with the tree. A page here is
/// only held to a count it states; none is required to state one.
///
/// Both root pages are looked for rather than assumed. A repository can be
/// checked out without them and this list is built at every run, so a missing
/// file has to read as a page with no counts in it rather than as a crash that
/// takes every other rule down with it.
List<File> _prosePages() {
  final pages = <File>[];
  final contributing = File('${repositoryRoot.path}/CONTRIBUTING.md');
  if (contributing.existsSync()) pages.add(contributing);
  final roadmap = File('${repositoryRoot.path}/ROADMAP.md');
  if (roadmap.existsSync()) pages.add(roadmap);
  final content = Directory('${repositoryRoot.path}/site/content');
  if (content.existsSync()) {
    pages.addAll(
      content
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.md')),
    );
  }
  pages.sort((File a, File b) => a.path.compareTo(b.path));
  return pages;
}

/// How many checks the conformance suite says it runs, against how many it has.
///
/// **Three wrong answers at once, and one of them in the file the count is
/// about.** `flutter3d_conformance.dart` said "five of the twelve now link
/// stages and draw" when eighteen of twenty-six did; the software backend's
/// harness opened with "the seven checks" when it ran twenty-six; and two
/// places said `ARCHITECTURE.md` §7.2 states nine rules when it states
/// fourteen. None of it is load-bearing on its own — and together they are a
/// backend author's only map of how much of the contract the suite covers,
/// which is why "two of the nine" reads as most of §7.2 being enforced when it
/// is two of fourteen.
///
/// Counted from the lists rather than from a list of counts: a check is a
/// record with a `name` and a `run`, and there is nowhere else one can be
/// declared. The §7.2 rules are the bold bullets of that section, which is what
/// the section's own sentence means by "these".
///
/// Shown to fire by putting both old numbers back — "the seven checks" and "two
/// of the nine rules" — and watching it name each file and each right answer.
///
/// **Two suites live in the package now, and they are counted apart.** The
/// plugin suite (`lib/plugins.dart`, its checks under `lib/src/plugins/`) is
/// written as the same `name`/`run` records, because that is what a check is
/// here — and counted into the backend total it would have told a backend
/// author they were held to five checks that never see a device. So the
/// backend total leaves `lib/src/plugins/` out, and "the five plugin checks"
/// is a claim of its own, held to that directory alone, in the same files plus
/// the package README a plugin author reads. Shown to fire by adding a sixth
/// plugin check: the plugin sentences go stale and the backend ones do not.
List<Finding> _conformanceCheckCount() {
  final lib = Directory(
    '${repositoryRoot.path}/packages/flutter3d_conformance/lib',
  );
  if (!lib.existsSync()) {
    return <Finding>[
      const Finding('flutter3d_conformance/lib', 'is not there'),
    ];
  }

  // The escaped-quote alternation is not decoration: one check is named "a pass
  // does not inherit the previous pass's scissor", and a pattern that stopped
  // at the first quote counted twenty-five where there are twenty-six. Both
  // quote characters, for the same reason from the other side: a name written
  // with double quotes to avoid escaping its apostrophe is a check the count
  // would silently not see, and a rule that can be walked past by a keystroke
  // is not holding anything.
  final record = RegExp(
    '''name: (?:'(?:[^'\\\\]|\\\\.)*'|"(?:[^"\\\\]|\\\\.)*"),\\s*run:''',
  );
  int checksIn(String source) => record.allMatches(source).length;

  final library = File('${lib.path}/flutter3d_conformance.dart');
  if (!library.existsSync()) {
    return <Finding>[
      const Finding('flutter3d_conformance.dart', 'is not there'),
    ];
  }
  final librarySource = library.readAsStringSync();
  final pluginDir = '${lib.path}/src/plugins/';
  bool isPluginCheck(File f) =>
      f.path.replaceAll(Platform.pathSeparator, '/').startsWith(pluginDir);
  final total = dartFilesIn(lib)
      .where((File f) => !isPluginCheck(f))
      .map((File f) => checksIn(f.readAsStringSync()))
      .fold(0, (int a, int b) => a + b);
  final plugin = dartFilesIn(lib)
      .where(isPluginCheck)
      .map((File f) => checksIn(f.readAsStringSync()))
      .fold(0, (int a, int b) => a + b);

  final opens = librarySource.indexOf('get shaderChecks =>');
  final closes = opens < 0 ? -1 : librarySource.indexOf('\n];', opens);
  if (closes < 0) {
    return <Finding>[
      const Finding(
        'flutter3d_conformance.dart',
        'has no shaderChecks list to count, so nothing here can tell whether '
            'the counts beside it are right',
      ),
    ];
  }
  final shader = checksIn(librarySource.substring(opens, closes));

  final architecture = File('${repositoryRoot.path}/ARCHITECTURE.md');
  final text = architecture.existsSync() ? architecture.readAsStringSync() : '';
  final section = text.indexOf('### 7.2');
  final semantics = section < 0
      ? 0
      : RegExp(
          r'^- \*\*',
          multiLine: true,
        ).allMatches(text.substring(section, text.indexOf('### 7.3'))).length;

  // Each phrasing is distinctive enough that a number elsewhere in a long
  // comment is not read as a claim about the suite — the same rule the golden
  // scenes are counted by, for the same reason.
  final claims = <(RegExp, int Function(RegExpMatch), String)>[
    (
      _countPhrasing('# of the # link stages and draw'),
      (RegExpMatch m) => shader,
      'checks that link stages and draw',
    ),
    (
      _countPhrasing('# shader checks'),
      (RegExpMatch m) => shader,
      'shader checks',
    ),
    (
      _countPhrasing('[Tt]he # checks, against a backend'),
      (RegExpMatch m) => total,
      'checks in all',
    ),
    (
      _countPhrasing(r'the # rules ARCHITECTURE\.md §7\.2 states'),
      (RegExpMatch m) => semantics,
      'rules in ARCHITECTURE.md §7.2',
    ),
    (
      _countPhrasing('[Tt]he # plugin checks'),
      (RegExpMatch m) => plugin,
      'plugin checks',
    ),
  ];

  // The site restates all of it — the backends page is where a third party
  // reads how much of §7 the suite will hold them to, and it said fifteen when
  // there were twenty. Held to the same lists as the library, in the same
  // phrasings, so neither can be corrected without the other.
  final found = <Finding>[];
  for (final file in <File>[
    ...dartFilesIn(lib),
    ...<String>[
      'packages/flutter3d_cpu/test/conformance_test.dart',
      'packages/flutter3d_webgl/test/conformance_test.dart',
      'packages/flutter3d/example/lib/conformance_main.dart',
      'packages/flutter3d_conformance/README.md',
    ].map((String at) => File('${repositoryRoot.path}/$at')),
    ..._prosePages(),
  ]) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    for (final (pattern, expected, what) in claims) {
      for (final match in pattern.allMatches(source)) {
        final want = expected(match);
        // Both halves of "18 of the 26", when the phrasing has
        // two: the second is the total and drifts on its own.
        final said = <(String, int)>[
          (match.group(1)!, want),
          if (match.groupCount > 1 && match.group(2) != null)
            (match.group(2)!, total),
        ];
        for (final (claim, against) in said) {
          final number = int.tryParse(claim);
          if (number == null) {
            found.add(_spelledOut(_inRepository(file), match.group(0)!, claim));
          } else if (number != against) {
            found.add(
              Finding(
                _inRepository(file),
                'says $claim $what; there are $against',
              ),
            );
          }
        }
      }
    }
  }
  return found;
}

/// Numbers as a sentence would spell them, kept only to catch a count written
/// that way.
///
/// **The counts are digits now, everywhere a rule holds one.** A number in prose
/// is one nobody recounts, and a word made it worse: every rule carried its own
/// list of spellings, each one ran out a few numbers past the day it was written,
/// and running out reported the prose as wrong rather than the list as short. A
/// digit is what a reader and a rule both read the same way, so this list no
/// longer reads a count — it only recognises one written as a word, so that
/// nobody drifts back to it.
const List<String> _countedInWords = <String>[
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'twenty-one',
  'twenty-two', 'twenty-three', 'twenty-four', 'twenty-five', 'twenty-six',
  'twenty-seven', 'twenty-eight', 'twenty-nine', 'thirty', 'thirty-one',
  'thirty-two', 'thirty-three', 'thirty-four', 'thirty-five', 'thirty-six',
  'thirty-seven', 'thirty-eight', 'thirty-nine', 'forty', 'forty-one',
  'forty-two', 'forty-three', 'forty-four', 'forty-five', 'forty-six',
  'forty-seven', 'forty-eight', 'forty-nine', 'fifty', 'fifty-one',
  'fifty-two', 'fifty-three', 'fifty-four', 'fifty-five', 'fifty-six',
  'fifty-seven', 'fifty-eight', 'fifty-nine', 'sixty', 'sixty-one',
  'sixty-two', 'sixty-three', 'sixty-four', 'sixty-five', 'sixty-six',
  'sixty-seven', 'sixty-eight', 'sixty-nine', 'seventy', 'seventy-one',
  'seventy-two', 'seventy-three', 'seventy-four', 'seventy-five',
  'seventy-six', 'seventy-seven', 'seventy-eight', 'seventy-nine', 'eighty',
  'eighty-one', 'eighty-two', 'eighty-three', 'eighty-four', 'eighty-five',
  'eighty-six', 'eighty-seven', 'eighty-eight', 'eighty-nine', 'ninety',
  'ninety-one', 'ninety-two', 'ninety-three', 'ninety-four', 'ninety-five',
  'ninety-six', 'ninety-seven', 'ninety-eight', 'ninety-nine', 'one hundred',
];

/// Where a count goes in a phrasing: digits, or a number written as a word.
///
/// Both, so that one pattern finds the claim and the claim written the wrong
/// way. Longest spelling first, so "twenty-one" is not read as the "one" at its
/// end, and neither side may touch a letter or a hyphen, so "one" is not read
/// out of "someone" or "one-off".
final String _countSlot = () {
  final spellings = <String>{
    for (final word in _countedInWords) ...<String>[
      word,
      '${word[0].toUpperCase()}${word.substring(1)}',
    ],
  }.toList()..sort((String a, String b) => b.length.compareTo(a.length));
  return '(?<![\\w-])(\\d+|${spellings.join('|')})(?![\\w-])';
}();

/// A phrasing that states a count, with `#` where the number goes.
///
/// The group a `#` becomes holds digits for a claim to compare, or a word for a
/// claim to refuse with [_spelledOut].
RegExp _countPhrasing(String phrasing, {bool caseSensitive = true}) =>
    RegExp(phrasing.replaceAll('#', _countSlot), caseSensitive: caseSensitive);

/// The finding for a count spelled as a word where the rule wants digits.
Finding _spelledOut(String where, String phrase, String word) => Finding(
  where,
  'says "$phrase", which writes the count as a word; write it as digits '
  '(${_countedInWords.indexOf(word.toLowerCase())})',
);

/// How many enums `formats.dart` declares, against how many the promise says.
///
/// **§7.1 promises stability for "the eighteen enums in `formats.dart`" and
/// there are twenty.** The two the count leaves out — `DepthRange` and
/// `FramebufferOrigin` — are named in §7.2's "ask before requesting" list, so
/// the promise reaches them by another road; what does not reach them is the
/// sentence a person checks before renaming a value. The bullet's own
/// justification is the Impeller mapping, which asserts eighteen of them map to
/// the flutter_gpu value of the same name, and eighteen was the right number for
/// *that* clause on the day it was written — which is how a count comes to be
/// half true and stay there.
///
/// The names are gathered as well as counted, because "twenty" sends nobody
/// anywhere: a finding that says which enum arrived is a finding somebody can
/// act on.
///
/// Shown to fire by writing nineteen into the bullet and watching it name the
/// document, the number and the list.
List<Finding> _hardwareEnumCount() {
  final formats = File(
    '${repositoryRoot.path}/packages/flutter3d_hardware/lib/src/formats.dart',
  );
  if (!formats.existsSync()) {
    return <Finding>[
      const Finding(
        'flutter3d_hardware/lib/src/formats.dart',
        'is not there, so the promise §7.1 makes about its enums has no '
            'subject — move the promise or restore the file',
      ),
    ];
  }
  final declared = RegExp(r'^enum\s+(\w+)', multiLine: true)
      .allMatches(formats.readAsStringSync())
      .map((RegExpMatch m) => m.group(1)!)
      .toList();

  final claim = _countPhrasing(r'[Tt]he # enums in `formats\.dart`');
  return <Finding>[
    for (final at in <String>['ARCHITECTURE.md', 'README.md'])
      if (File('${repositoryRoot.path}/$at').existsSync())
        for (final match in claim.allMatches(
          File('${repositoryRoot.path}/$at').readAsStringSync(),
        ))
          if (int.tryParse(match.group(1)!) == null)
            _spelledOut(at, match.group(0)!, match.group(1)!)
          else if (int.parse(match.group(1)!) != declared.length)
            Finding(
              at,
              'says ${match.group(1)} enums in formats.dart; there are '
              '${declared.length} — ${declared.join(', ')}',
            ),
  ];
}

/// Every entry point a bundle must answer to, against the list the site prints.
///
/// **The backends page told a third party its bundle needed twenty-six names
/// when the engine asked for thirty-seven**, and printed the twenty-six as a
/// table, so the eleven it left out were invisible rather than merely uncounted:
/// `Renderer.create` throws on the first name it cannot find, and the page is
/// the only place a backend author reads that list before writing one.
///
/// A test already keeps `requiredShaders` and the bundle manifest in step with
/// each other. Nothing kept the page in step with either, which is how a list
/// that was right on the day it was typed came to be eleven short — the sky, the
/// object-id pass, the x-ray stage, instanced and lightmapped vertices, SSAO,
/// luminance and the probe prefilter all arrived after it.
///
/// Both halves are checked, because they rot apart: the names in the table, and
/// the count wherever a page states one in prose. The names are the load-bearing
/// half — a count that is right about a table that is wrong is worse than
/// neither.
///
/// Shown to fire by deleting `Xray` from the table and by writing "twenty-six"
/// back into the sentence above it, and watching it name each one.
List<Finding> _shaderEntryPoints() {
  final declared = File(
    '${repositoryRoot.path}/packages/flutter3d_shaders/lib/'
    'flutter3d_shaders.dart',
  );
  if (!declared.existsSync()) {
    return <Finding>[
      const Finding(
        'flutter3d_shaders/lib/flutter3d_shaders.dart',
        'is not there, so nothing here can tell which names a bundle must '
            'answer to',
      ),
    ];
  }
  final required = RegExp(r"\(name: '(\w+)', fragment:")
      .allMatches(declared.readAsStringSync())
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
  if (required.isEmpty) {
    return <Finding>[
      const Finding(
        'flutter3d_shaders/lib/flutter3d_shaders.dart',
        'no longer declares its entry points as `(name:, fragment:)` records, '
            'so nothing here can count them',
      ),
    ];
  }

  const page = 'site/content/core/backends.md';
  final found = <Finding>[];
  final file = File('${repositoryRoot.path}/$page');
  if (!file.existsSync()) {
    found.add(const Finding(page, 'is not there'));
  } else {
    final text = file.readAsStringSync();
    final header = text.indexOf('| Stage | Names |');
    if (header < 0) {
      found.add(
        const Finding(
          page,
          'no longer lists the entry points by stage, so nothing here can '
          'tell whether the list is whole',
        ),
      );
    } else {
      final ends = text.indexOf('\n\n', header);
      final listed = RegExp(r'`(\w+)`')
          .allMatches(text.substring(header, ends < 0 ? text.length : ends))
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      final missing = required.difference(listed).toList()..sort();
      final extra = listed.difference(required).toList()..sort();
      if (missing.isNotEmpty) {
        found.add(
          Finding(
            page,
            'does not name ${missing.join(', ')}, which a bundle must answer '
            'to all the same',
          ),
        );
      }
      if (extra.isNotEmpty) {
        found.add(
          Finding(
            page,
            'names ${extra.join(', ')}, which nothing asks a bundle for',
          ),
        );
      }
    }
  }

  final claim = _countPhrasing('# shader entry points');
  for (final prose in _prosePages()) {
    for (final match in claim.allMatches(prose.readAsStringSync())) {
      final said = match.group(1)!;
      final number = int.tryParse(said);
      if (number == null) {
        found.add(_spelledOut(_inRepository(prose), match.group(0)!, said));
      } else if (number != required.length) {
        found.add(
          Finding(
            _inRepository(prose),
            'says $said shader entry points; there are ${required.length}',
          ),
        );
      }
    }
  }
  return found;
}

/// Where a file is, said the way a finding says it: relative to the root.
String _inRepository(File file) =>
    file.path.substring(repositoryRoot.path.length + 1);

/// Refuses an enum in a published package unless a table says why it is
/// machinery.
///
/// **A published enum is a closed list somebody else's `switch` is written
/// against.** Adding a value to it breaks every one of those, so for a package
/// whose purpose is that other people build on it, an enum is a promise the
/// list is finished. Sometimes it is — a mirror of an API somebody else
/// defines, a document key the engine has to understand to act on. Usually it
/// is not, and the audit in `doc/boundary-0.5.0.md` found four that were not:
/// what a weapon fires, what a monster is doing, what a stick is for, and how
/// a camera projects.
///
/// The alternative each time is the shape `LightingModel` has had since before
/// this rule: a `final class` with `static const` instances, which is an enum
/// that anybody can add to and nothing can switch over exhaustively.
///
/// Applications are not checked. A game's own enum is closed against nobody.
List<Finding> _boundaryEnums() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    if (boundaryEnumPackageExempt.containsKey(entry.key)) continue;

    final lib = Directory('${entry.value.path}/lib');
    for (final file in dartFilesIn(lib)) {
      final where = '${entry.key}/${relative(file, entry.value)}';
      final allowed = boundaryEnumExempt[where] ?? const <String, String>{};
      for (final name in unexemptedEnumsIn(
        file.readAsStringSync(),
        allowed.keys.toSet(),
      )) {
        found.add(
          Finding(
            where,
            '`$name` is an enum in a published package. Adding a value to it '
            'breaks every switch anybody has written against it. Either say '
            'why it is machinery in `boundaryEnumExempt`, or make it a final '
            'class with const instances the way `LightingModel` is',
          ),
        );
      }
    }
  }
  return found;
}

// ------------------------------------------- a step asks no machine anything

/// Nothing a fixed step runs may call a transcendental from `dart:math`.
///
/// **The measurement this exists because of.** `flutter3d_sim`'s parity test
/// asked twelve `dart:math` functions for twenty thousand answers apiece under
/// the VM and under Chrome: `sqrt` and `pow` matched and every transcendental
/// did not, because on the VM they are the host's libm and in a browser they
/// are whatever that engine ships. A character controller reached almost none
/// of the disagreeing arguments and replayed identically; a car is made of them
/// and diverged at twenty-three of forty checkpoints. So "a replay is the same
/// run" was true for one genre and false for another, which is the worst shape
/// a guarantee can have — and a verifying server rests entirely on it.
///
/// `Portable` answers the same questions out of `+`, `-`, `*`, `/` and `sqrt`,
/// all of which the specification pins. This rule is what keeps a call site
/// from drifting back: the substitution is invisible at a glance, a `math.sin`
/// added next year would compile and pass every test, and the failure would
/// arrive as one player's run being rejected by a server months later.
///
/// **Scanned by exclusion, like the repeatable-step rule beside it**, and over
/// exactly the same set: a package a run steps through is a package both rules
/// apply to. See [notARepeatableStep] and [notARepeatedApp] for what that set
/// is — applications included since step 8 of `tasks/0.9-plugins.md` — and
/// [portableStepExempt] for the files inside it that draw rather than step.
List<Finding> _portableStepArithmetic() {
  final found = <Finding>[];
  for (final entry in _steppedDirectories.entries) {
    final dir = entry.value;
    final exempt = portableStepExempt[entry.key] ?? const <String, String>{};

    for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
      final path = relative(file, dir);
      if (exempt.containsKey(path)) continue;
      final source = _withoutComments(file.readAsStringSync());

      // An unprefixed import would let `sin(x)` through the scan below, so it
      // is refused outright rather than answered with a cleverer regex.
      if (source.contains("import 'dart:math';")) {
        found.add(
          Finding(
            '${entry.key}/$path',
            "imports `dart:math` without a prefix, so a bare `sin(x)` in it "
                'would be invisible to this rule. Import it `as math`',
          ),
        );
      }

      for (final match in _machineArithmetic.allMatches(source)) {
        found.add(
          Finding(
            '${entry.key}/$path',
            'calls `math.${match.group(1)}`, whose answer is the platform\'s '
                'libm rather than a number. Call `Portable.${match.group(1)}` '
                'instead, or say in `portableStepExempt` why this file is not '
                'part of a run',
          ),
        );
      }
      for (final match in _machineGeometry.allMatches(source)) {
        found.add(
          Finding(
            '${entry.key}/$path',
            'calls `${match.group(0)!.replaceAll(RegExp(r'\s*\($'), '')}`, '
                'which vector_math answers with `dart:math`\'s sin, cos or '
                'acos, so the libm again. Build the turn from '
                '`Portable.sinCos`/`Portable.acos`, or say in '
                '`portableStepExempt` why this file is not part of a run',
          ),
        );
      }
    }
  }
  return found;
}

// -------------------------------------- the view reads the published state

/// No library outside [simulationStack] reaches into a run's live world.
///
/// **A world behind an isolate is not there to read.** With the simulation
/// in its own isolate the view holds a `PublishedState` and nothing else, so
/// a library that reads `run.world` or `simulation.world` works inline and
/// breaks the day an application moves its simulation off the UI isolate.
/// The same read is also a back door past determinism: the view can take
/// a value the step never published and never taped.
///
/// [readsSimulationWorld] lists the libraries still doing it, each with the
/// work that takes it off the list.
List<Finding> _noWorldOutsideSimulation() {
  final world = RegExp(r'\b(?:run|simulation)\.world\b');
  final found = <Finding>[];
  final dirs = <String, Directory>{
    for (final entry in packages.entries)
      if (!simulationStack.contains(entry.key)) entry.key: entry.value,
    ...apps,
  };
  for (final entry in dirs.entries) {
    for (final file in dartFilesIn(Directory('${entry.value.path}/lib'))) {
      final path = '${entry.key}/${relative(file, entry.value)}';
      if (readsSimulationWorld.containsKey(path)) continue;
      if (world.hasMatch(_withoutComments(file.readAsStringSync()))) {
        found.add(
          Finding(
            path,
            'reads a run\'s live world, which a simulation in its own '
            'isolate does not have: read the published state (a probe, '
            'a component in `PublishedState`), or say in '
            '`readsSimulationWorld` what takes this file off the list',
          ),
        );
      }
    }
  }
  for (final path in readsSimulationWorld.keys) {
    final slash = path.indexOf('/');
    final dir = dirs[path.substring(0, slash)];
    final file = dir == null
        ? null
        : File('${dir.path}/${path.substring(slash + 1)}');
    if (file == null ||
        !file.existsSync() ||
        !world.hasMatch(_withoutComments(file.readAsStringSync()))) {
      found.add(
        Finding(
          path,
          'is listed in `readsSimulationWorld` and no longer reads the '
          'world: take it off the list',
        ),
      );
    }
  }
  return found;
}

/// [source] with its comments taken out.
///
/// So that a doc comment naming `math.sin` — this rule's own explanation does,
/// and so does the library it points at — is not read as a call. Crude on
/// purpose: it is looking for one shape and a string containing `//` costs
/// nothing here but a line the scan does not see.
String _withoutComments(String source) => source
    .split('\n')
    .map((String line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

/// A call to one of the functions whose answer belongs to the machine.
///
/// **`pow` was left out of this list once, and the reason it was left out is
/// worth keeping.** The first parity sweep ran on one machine — macOS-arm64,
/// under the VM and under Chrome — and `pow` agreed in both places while every
/// transcendental beside it disagreed. Two runtimes agreeing looked like the
/// specification pinning an answer. It was not: a third machine, an x86-64
/// Ubuntu, answers `pow` differently from either, so what the first measurement
/// found was two runtimes sharing one host's libm. `Portable.pow` exists now
/// and this rule asks for it.
///
/// `sqrt` is the one still missing from the list, and it is the one that
/// belongs missing: IEEE 754 requires a correctly rounded square root, so there
/// is a single right answer and every platform is obliged to give it. That is a
/// guarantee rather than a measurement, which is the difference between the two
/// cases.
final RegExp _machineArithmetic = RegExp(
  r'\bmath\.(sin|cos|tan|asin|acos|atan2|atan|exp|log|pow)\s*\(',
);

/// The vector_math calls that reach the same functions without naming them.
///
/// A turn built as `Quaternion.axisAngle(axis, a)` is `math.sin(a / 2)` one
/// call down, and a ragdoll's bone turned through `fromTwoVectors` was the
/// `acos` this rule had been refusing by name for a year. The list is what
/// the library's source calls `dart:math` from on a turn or an angle.
final RegExp _machineGeometry = RegExp(
  r'\b(?:Matrix[34]\.rotation[XYZ]|Quaternion\.(?:axisAngle|euler|fromTwoVectors)'
  r'|\.(?:setRotation[XYZ]|setAxisAngle|setEuler|setFromTwoVectors|setRotationYawPitchRoll|angleTo|angleToSigned))\s*\(',
);

// ------------------------------------------------------------------- skills

/// Every `skills/<name>/SKILL.md`, held to what `dart run skills@ get` reads.
///
/// **The failure this exists for is silence.** The `skills` CLI installs a
/// package's skills into a consumer's agent directory, and it skips — without a
/// word, as a matter of documented policy — any skill whose directory does not
/// begin with the package's own name. Ten skills in this repository sat in
/// exactly that state: shipped in two archives, listed in two READMEs, and
/// invisible to the one command a consumer runs to get them.
///
/// So the three facts a skill needs are checked here rather than remembered:
/// the directory is named for the package it ships from, it holds a `SKILL.md`,
/// and the `name` in that file is the directory it is in. The third matters on
/// its own — a directory is what lands on disk and a name is what an agent asks
/// for, so the two can disagree with nothing failing to load, and then a skill
/// is installed under one name and invoked under another.
///
/// `flutter3d/test/skills_test.dart` asks the same questions of one package,
/// which is where the mutations for them are written down. This asks them of
/// every package, which is the half a test in one package cannot cover.
List<Finding> _skillNames() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    final skills = Directory('${entry.value.path}/skills');
    if (!skills.existsSync()) continue;

    // Underscores or hyphens: the CLI accepts the package name either way, and
    // this repository writes hyphens because a skill name is read aloud more
    // often than a package name is.
    final prefixes = <String>[
      '${entry.key}-',
      '${entry.key.replaceAll('_', '-')}-',
    ];

    for (final directory in skills.listSync().whereType<Directory>()) {
      final name = directory.path.split('/').last;
      final where = '${entry.key}/skills/$name';

      if (!prefixes.any(name.startsWith)) {
        found.add(
          Finding(
            where,
            'does not start with "${prefixes.last}", so the skills CLI '
            'installs it for nobody and says nothing',
          ),
        );
      }

      final file = File('${directory.path}/SKILL.md');
      if (!file.existsSync()) {
        found.add(Finding(where, 'holds no SKILL.md'));
        continue;
      }

      final text = file.readAsStringSync();
      final declared = _frontmatterValue(text, 'name');
      if (declared == null) {
        found.add(Finding(where, 'has no name in its frontmatter'));
      } else if (declared != name) {
        found.add(Finding(where, 'names itself "$declared"'));
      }

      final description = _frontmatterValue(text, 'description');
      if (description == null || description.isEmpty) {
        found.add(
          Finding(
            where,
            'has no description, which is the line an agent decides by, so '
            'the skill is shipped and never loaded',
          ),
        );
      }
    }
  }
  return found;
}

/// The value of a one-line `key: value` in a leading `---` frontmatter block.
String? _frontmatterValue(String text, String key) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') return null;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim() != key) continue;
    return line.substring(colon + 1).trim();
  }
  return null;
}

/// `gfx-51n`: no vertex stage reaches for `texelFetch`.
///
/// **Bisected rather than assumed, and the account is in the shader that went
/// the long way round.** `lib/morph.glsl` records it: impellerc crashes on
/// `texelFetch` in a *vertex* stage — SIGABRT, no diagnostic, exit 134 —
/// while the same call in a fragment stage compiles, `gl_VertexIndex` alone
/// compiles, and `texture()` in a vertex stage compiles. It is that one
/// combination.
///
/// The survey this row came from said something wider — that `texelFetch`
/// aborts at the default GLES target and needs
/// `--gles-language-version=300` — and the bundle builds today with three
/// fragment stages that would have contradicted it. The narrower claim is the
/// one with a bisection behind it, so it is the one enforced.
///
/// So a vertex stage that wants an exact texel builds the coordinate by hand,
/// `(index + 0.5) / size`, with a nearest clamped sampler and the size passed
/// down in a uniform rather than read from `textureSize`. This rule is what
/// says so at a moment somebody can act on: the failure it prevents is an
/// abort with no line number during a bundle build, on the one backend whose
/// build a shader author may not be running.
///
/// Comments do not count, and that is not a detail — the file carrying the
/// clearest account of this constraint is the one that names `texelFetch`
/// most often, and a rule that flagged it would punish the documentation.
List<Finding> _noTexelFetchInVertexStages() {
  final sources = packages['flutter3d_shaders'];
  if (sources == null) {
    return <Finding>[const Finding('flutter3d_shaders', 'is not there')];
  }
  final dir = Directory('${sources.path}/shaders');
  if (!dir.existsSync()) {
    return <Finding>[
      const Finding('flutter3d_shaders/shaders', 'is not there'),
    ];
  }

  return <Finding>[
    for (final file in dir.listSync(recursive: true).whereType<File>())
      // `.vert` is a vertex stage outright; a `.glsl` may be included by one,
      // and `lib/morph.glsl` is exactly that case.
      if (file.path.endsWith('.vert') || file.path.endsWith('.glsl'))
        if (_withoutComments(file.readAsStringSync()).contains('texelFetch'))
          Finding(
            'flutter3d_shaders/${relative(file, sources)}',
            'reaches for texelFetch where a vertex stage can see it, which '
                'impellerc aborts on with exit 134 and no diagnostic. Build '
                'the coordinate by hand and sample with a nearest clamped '
                'sampler, the way lib/morph.glsl does and says why',
          ),
  ];
}

/// `gfx-58n`: the surface buffer keeps carrying depth, whatever upstream does.
///
/// **A gate with an argument attached, and the argument is the whole row.**
/// `#192449` — no way to sample a depth texture — is the most defensible
/// filing in `doc/upstream.md` on merit, and it is the one that would do the
/// most damage if it landed and nobody thought about it: the temptation would
/// be to throw away `surface.a` and read a depth attachment instead.
///
/// `surface.a` is view-axis depth **in metres**, which is not what a depth
/// attachment holds. The thin-lens circle of confusion in
/// `depth_of_field.frag` needs metres; the shafts convert along the ray with
/// it; the occlusion and reflection marches unproject with it. A window depth
/// would make all four mean different things near and far. So the channel
/// stays whether or not the filing lands, and this is what says so in a place
/// that fails rather than in a paragraph nobody reads.
List<Finding> _surfaceDepthStays() {
  final sources = packages['flutter3d_shaders'];
  if (sources == null) {
    return <Finding>[const Finding('flutter3d_shaders', 'is not there')];
  }
  final found = <Finding>[];

  // The write, which everything else depends on.
  final color = File('${sources.path}/shaders/lib/color.glsl');
  if (!color.existsSync()) {
    found.add(
      const Finding('flutter3d_shaders/shaders/lib/color.glsl', 'is not there'),
    );
  } else if (!color.readAsStringSync().contains('ViewDepth()')) {
    found.add(
      const Finding(
        'flutter3d_shaders/shaders/lib/color.glsl',
        'no longer writes ViewDepth() into the surface buffer. Four passes '
            'read that channel as metres along the view axis — see gfx-58n '
            'in doc/upstream.md, which is why the channel outlives #192449 '
            'either way',
      ),
    );
  }

  // And no shader declaring a depth sampler, which is the shape the
  // temptation would arrive in.
  final dir = Directory('${sources.path}/shaders');
  if (dir.existsSync()) {
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.frag') && !file.path.endsWith('.glsl')) {
        continue;
      }
      final text = file.readAsStringSync();
      if (text.contains('sampler2DShadow') ||
          text.contains('texture2DShadow')) {
        found.add(
          Finding(
            'flutter3d_shaders/${relative(file, sources)}',
            'declares a depth sampler. flutter_gpu cannot sample one — '
                '#192449 — and the engine reads depth out of the surface '
                'buffer instead, in metres. See gfx-58n',
          ),
        );
      }
    }
  }
  return found;
}

// --------------------------------------------------------------------- web

/// The libraries pub.dev counts against the web: an import of one, from
/// anything a package's libraries reach in the browser's build, and pub.dev
/// lists the package without the web — stub or not, run there or not.
const Set<String> _notOnTheWeb = <String>{
  'dart:io',
  'dart:isolate',
  'dart:ffi',
  'dart:mirrors',
  'dart:cli',
};

/// A package whose pubspec lists `web:` under `platforms:` reaches none of
/// [_notOnTheWeb] through the imports and exports the browser's build
/// follows: into this repository's packages, and down the web branch of a
/// conditional one. `flutter3d` was listed without the web while it ran
/// there, for one `dart:io` it imported to name an exception.
List<Finding> _webPackagesReachNoIo() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    final pubspec = File('${entry.value.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    if (!RegExp(
      r'^platforms:\n(?:  \w+:\n)*  web:',
      multiLine: true,
    ).hasMatch(pubspec.readAsStringSync())) {
      continue;
    }
    final seen = <String>{};
    // From its public libraries, as pub.dev reads it: what `lib/src` holds
    // counts only where one of them reaches it.
    final queue = <File>[
      ...Directory(
        '${entry.value.path}/lib',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
    ];
    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!seen.add(file.absolute.path) || !file.existsSync()) continue;
      for (final uri in _webDirectives(file.readAsStringSync())) {
        if (_notOnTheWeb.contains(uri)) {
          found.add(
            Finding(
              file.path.substring(file.path.indexOf('packages/')),
              'reaches $uri in the browser, though ${entry.key} says it runs '
              'there: choose it by `if (dart.library.js_interop)`',
            ),
          );
          continue;
        }
        final next = _resolveInRepository(uri, file);
        if (next != null) queue.add(next);
      }
    }
  }
  return found;
}

// --------------------------------------------------------------- platforms

/// Every published package declares `platforms:`, `SUPPORT.md` lists each
/// one with the same set, and names every backend.
///
/// **Four of forty-seven pubspecs declared it on 2026-10-08**, so pub.dev
/// guessed the rest from imports, and a guess is not a promise anybody can
/// hold a release to. The declaration is the promise; the table in
/// `SUPPORT.md` is where a reader finds it; and this keeps the two the same
/// thing, in both directions, because a table that lists a package the tree
/// no longer publishes is as wrong as one that leaves a package out.
///
/// A backend is a published package with a class that implements
/// `GraphicsDevice`, other than `flutter3d_hardware`, whose own
/// `RecordingDevice` wraps one. Each has to be named in `SUPPORT.md`, so a
/// fifth backend arrives with a column of support levels or not at all.
///
/// Mutation: delete the `platforms:` block from any published pubspec, add
/// `web` to one row of the table, or rename `flutter3d_cpu` in `SUPPORT.md`,
/// and this names the file and what disagrees.
List<Finding> _platformsDeclared() {
  final found = <Finding>[];
  final support = File('${repositoryRoot.path}/SUPPORT.md');
  final table = support.existsSync()
      ? packagePlatformRows(support.readAsStringSync())
      : null;
  if (table == null) {
    found.add(
      const Finding(
        'SUPPORT.md',
        'is not there: the platform matrix and the support policy live in it',
      ),
    );
  }
  final published = _publishedPackages;

  for (final entry in published.entries) {
    final where = '${entry.key}/pubspec.yaml';
    final declared = declaredPlatforms(
      File('${entry.value.path}/pubspec.yaml').readAsStringSync(),
    );
    if (declared == null || declared.isEmpty) {
      found.add(
        Finding(
          where,
          'declares no `platforms:`, so pub.dev guesses them from imports. '
          'Say which of ${knownPlatforms.join(', ')} it runs on, and list it '
          'in SUPPORT.md',
        ),
      );
      continue;
    }
    final unknown = declared.difference(knownPlatforms);
    if (unknown.isNotEmpty) {
      found.add(
        Finding(
          where,
          'declares ${unknown.join(', ')}, which pub.dev does not know; it '
          'knows ${knownPlatforms.join(', ')}',
        ),
      );
    }
    if (table == null) continue;
    final listed = table[entry.key];
    if (listed == null) {
      found.add(
        Finding(
          'SUPPORT.md',
          'has no row for `${entry.key}`, which declares '
              '${(declared.toList()..sort()).join(', ')}',
        ),
      );
    } else if (listed.length != declared.length ||
        !listed.containsAll(declared)) {
      found.add(
        Finding(
          'SUPPORT.md',
          'says `${entry.key}` runs on ${(listed.toList()..sort()).join(', ')}; '
              'its pubspec declares ${(declared.toList()..sort()).join(', ')}',
        ),
      );
    }
  }

  if (table == null) return found;
  for (final name in table.keys) {
    if (!published.containsKey(name)) {
      found.add(
        Finding(
          'SUPPORT.md',
          'lists `$name`, which is not a published package here',
        ),
      );
    }
  }

  final text = support.readAsStringSync();
  for (final entry in published.entries) {
    if (entry.key == 'flutter3d_hardware') continue;
    final isBackend = dartFilesIn(
      Directory('${entry.value.path}/lib'),
    ).any((File file) => implementsGraphicsDevice(file.readAsStringSync()));
    if (isBackend && !text.contains('`${entry.key}`')) {
      found.add(
        Finding(
          'SUPPORT.md',
          'never names `${entry.key}`, which implements GraphicsDevice: a '
              'backend needs its support levels written down',
        ),
      );
    }
  }
  return found;
}

// ------------------------------------------------------------ plugin markers

/// Every `flutter3d_plugins:` entry of a package names one of its own
/// libraries, and that library reaches a class of the name it gives — and
/// no package of this repository still uses the marker of before 1.0,
/// `flutter3d: plugin:`, which discovery reads only as a deprecated alias.
///
/// **A marker is a string nothing compiles.** Discovery copies it into an
/// application's `plugins.g.dart`, so a library that moved or a class that
/// was renamed is found by the first application that builds against the
/// package — somebody else's, after it is published. `flutter3d_post` holds
/// twenty-three of them in one pubspec, and the merge that made it moved
/// every library they name; this is what said each one still resolves.
///
/// The library has to be the package's own, as discovery insists, and the
/// class is looked for in the library and in what it exports from inside
/// the package, the way a family's barrel hands out its `src/` classes.
///
/// Mutation: rename `BloomAddon` in `flutter3d_post`'s marker, or point a
/// library key at `lights.dart`, and this names the entry.
List<Finding> _pluginMarkersResolve() {
  final found = <Finding>[];
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    final text = pubspec.readAsStringSync();
    final entries = pluginMarkerEntries(text);
    if (entries == null) continue;
    final where = '$name/pubspec.yaml';
    if (usesLegacyPluginMarker(text)) {
      found.add(
        Finding(
          where,
          'marks its plugins with `flutter3d: plugin:`, the key before 1.0: '
          'move them to `flutter3d_plugins:`',
        ),
      );
    }
    if (entries.isEmpty) {
      found.add(
        Finding(where, 'has a `flutter3d_plugins:` that names nothing'),
      );
    }
    for (final entry in entries) {
      final hash = entry.lastIndexOf('#');
      final import = hash < 0 ? '' : entry.substring(0, hash);
      final className = hash < 0 ? '' : entry.substring(hash + 1);
      final own = 'package:$name/';
      final path = import.startsWith('package:')
          ? (import.startsWith(own) ? import.substring(own.length) : null)
          : import;
      if (hash < 0 || path == null || !path.endsWith('.dart')) {
        found.add(
          Finding(
            where,
            '`$entry` is not `<one of $name\'s libraries>#<Class>`',
          ),
        );
        continue;
      }
      final library = File('${dir.path}/lib/$path');
      if (!library.existsSync()) {
        found.add(
          Finding(where, '`$entry` names lib/$path, which is not there'),
        );
        continue;
      }
      if (!_reachesClass(library, className, <String>{})) {
        found.add(
          Finding(
            where,
            '`$entry`: lib/$path declares no class `$className` and exports '
            'none from the package',
          ),
        );
      }
    }
  }
  return found;
}

/// Whether [library], or a library of the same package it exports, declares
/// a class named [className].
bool _reachesClass(File library, String className, Set<String> seen) {
  if (!seen.add(library.absolute.path) || !library.existsSync()) return false;
  final source = library.readAsStringSync();
  if (RegExp(
    '^(?:[a-z]+ )*class ${RegExp.escape(className)}\\b',
    multiLine: true,
  ).hasMatch(source)) {
    return true;
  }
  for (final m in RegExp(
    r"^export\s+'([^':]+)'([^;]*);",
    multiLine: true,
  ).allMatches(source)) {
    final hide = RegExp(r'\bhide\s+([\w\s,]+)').firstMatch(m.group(2)!);
    if (hide != null &&
        hide
            .group(1)!
            .split(',')
            .map((String s) => s.trim())
            .contains(className)) {
      continue;
    }
    final show = RegExp(r'\bshow\s+([\w\s,]+)').firstMatch(m.group(2)!);
    if (show != null &&
        !show
            .group(1)!
            .split(',')
            .map((String s) => s.trim())
            .contains(className)) {
      continue;
    }
    final next = File.fromUri(library.absolute.uri.resolve(m.group(1)!));
    if (_reachesClass(next, className, seen)) return true;
  }
  return false;
}

// ------------------------------------------------------- a world's numbers

/// No library writes a world's gravity, air or sea as a number.
///
/// **Twenty-five places had their own 9.81** — a cloth's default, a fire's
/// embers, a weir's flow, a diver's depth gauge — beside a core whose world
/// already had a gravity a game could set. A level on the Moon would have
/// been the Moon for the bodies and the Earth for everything around them,
/// and nothing would have said so. What belongs to the world is read from
/// the world (`NativeWorld.gravity`, `gravityMagnitude`, `airTemperature`,
/// `airPressure`); what belongs to a substance from its preset
/// (`NativeLiquidProperties.water`); and each default is written once,
/// in `flutter3d_physics`' `standard_world.dart` or on its preset.
///
/// **Any gravity of a game's own counts too** (decision 1 of
/// `tasks/1.0-physics-audit.md`): a gravity-named default given a number, a
/// down vector where gravity is named, a buoyancy as an acceleration and a
/// particle falling by a number of its own of eight or more — so a dynamics
/// at 22 beside characters at 24 and a car at 20 cannot come back. A game's
/// world is set once where it stages, and [worldLiteralExempt] names those
/// lines with the game they tune.
///
/// Every library, applications and the education packages included —
/// a demo's diver is a consumer like any other. [worldLiteralExempt] names
/// the definitions and the numbers that only look like one, each with its
/// reason; an entry that no longer matches is reported, so the list cannot
/// outlive what it excuses.
List<Finding> _worldNumbersFromTheWorld() {
  final found = <Finding>[];
  final education = Directory('${repositoryRoot.path}/packages/education');
  final scanned = <String, Directory>{
    ...packages,
    ...apps,
    if (education.existsSync())
      for (final dir in education.listSync().whereType<Directory>())
        if (File('${dir.path}/pubspec.yaml').existsSync())
          'education/${dir.path.split(Platform.pathSeparator).last}': dir,
  };
  final used = <String, Set<String>>{};
  for (final entry in scanned.entries) {
    for (final file in dartFilesIn(Directory('${entry.value.path}/lib'))) {
      final where = '${entry.key}/${relative(file, entry.value)}';
      final exempt = worldLiteralExempt[where] ?? const <String, String>{};
      for (final hit in worldLiteralsIn(file.readAsStringSync())) {
        if (exempt.containsKey(hit.literal)) {
          (used[where] ??= <String>{}).add(hit.literal);
          continue;
        }
        found.add(
          Finding(
            '$where:${hit.line}',
            '${hit.literal} is ${hit.what} — read it from the world it '
                'belongs to (`CollisionWorld.properties`, `NativeWorld`), or '
                'the substance\'s catalogue entry (`Materials`); a default is '
                'written once, in standard_world.dart or the catalogue, and '
                'a game\'s own world once, where it stages',
          ),
        );
      }
    }
  }
  for (final entry in worldLiteralExempt.entries) {
    for (final literal in entry.value.keys) {
      if (!(used[entry.key]?.contains(literal) ?? false)) {
        found.add(
          Finding(
            'worldLiteralExempt → ${entry.key}',
            'excuses $literal, which is no longer there; take it off the list',
          ),
        );
      }
    }
  }
  return found;
}

// ------------------------------------------------------- a light's number

/// No light is lit with a number in the renderer's pre-1.0 unit.
///
/// **Lights became lux and candela in 1.0, and a literal does not move with
/// them.** `migrate` carried code that wrote `x * Photometric.legacyUnit`,
/// but a plain `intensity: 16.0` stayed 16 — and 16 candela where 92 650 was
/// meant is a starter project that opens on a black screen, a default sun of
/// 2.6 lux in `Daylight`, and a showcase page lit by a candle. Each was
/// found by an audit rather than by anything that runs.
///
/// Libraries, examples, applications, and the Dart in the site's pages and
/// the READMEs: a snippet somebody copies is a scene somebody lights. A light
/// meant to be that dim says so with a comment naming its unit on the line
/// or the line above, which [smallLightIntensitiesIn] reads as kept.
List<Finding> _lightIntensitiesInLux() {
  final found = <Finding>[];
  void scan(String where, String source) {
    for (final hit in smallLightIntensitiesIn(source)) {
      found.add(
        Finding(
          '$where:${hit.line}',
          'intensity ${hit.literal} reads as the pre-1.0 unit, but since 1.0 '
              'it is ${hit.literal} lux or candela — write the light in lux '
              'or candela, or say in a comment on the line that it is meant '
              'to be that dim',
        ),
      );
    }
  }

  final root = repositoryRoot.path;
  for (final entry in <String, Directory>{...packages, ...apps}.entries) {
    for (final sub in const <String>['lib', 'example/lib']) {
      for (final file in dartFilesIn(Directory('${entry.value.path}/$sub'))) {
        scan(
          '${entry.key}/${relative(file, entry.value)}',
          file.readAsStringSync(),
        );
      }
    }
    for (final name in const <String>['README.md', 'example/example.md']) {
      final file = File('${entry.value.path}/$name');
      if (file.existsSync()) {
        scan('${entry.key}/$name', dartBlocksOf(file.readAsStringSync()));
      }
    }
  }
  final site = Directory('$root/site/content');
  if (site.existsSync()) {
    for (final file in site.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.md')) continue;
      scan(
        'site/content/${relative(file, site)}',
        dartBlocksOf(file.readAsStringSync()),
      );
    }
  }
  return found;
}

/// The C core reads a substance's number, nature's constants and the
/// standard world from the header generated from the catalogue, and the
/// header is what the catalogue makes.
///
/// **Two halves.** The header (`csrc/src/f3d_materials.g.h`) is written by
/// `flutter3d_physics_native`'s `tool/gen_materials.dart` from
/// `flutter3d_physics`' `Materials`, `physical_constants.dart` and
/// `standard_world.dart`; `--check` says whether it is current. That needs
/// the resolved workspace, so before `pub get` the half says nothing, as the
/// API rule does, and `tool/ci.sh` runs the scan again after. The other half
/// reads every C source of the core for a `#define` that is a second copy:
/// water's, the air's, the world's or σ under a name of its own
/// ([cDefinesCopyingTheWorldIn]), or a material's number under its name
/// ([cDefinesCopyingMaterialsIn]) — the way water's specific heat came to
/// be 4186 in the heat model and 4182 everywhere else.
///
/// Mutation: put `#define F3D_WATER_HEAT F3D_R(4186.0)` back into
/// `f3d_heat.c`, or change water's density in `materials.dart` without
/// regenerating, and this names the file.
List<Finding> _coreReadsTheCatalogue() {
  final found = <Finding>[];
  final native = packages['flutter3d_physics_native'];
  if (native == null) return found;
  final header = File('${native.path}/csrc/src/f3d_materials.g.h');
  if (!header.existsSync()) {
    return <Finding>[
      Finding(
        'flutter3d_physics_native/csrc/src/f3d_materials.g.h',
        'missing: run `dart run tool/gen_materials.dart` in '
            'flutter3d_physics_native',
      ),
    ];
  }
  final headerText = header.readAsStringSync();
  final values = materialValuesIn(headerText, materialNamesIn(headerText));
  final sources =
      Directory('${native.path}/csrc')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (File f) =>
                (f.path.endsWith('.c') || f.path.endsWith('.h')) &&
                !f.path.endsWith('f3d_materials.g.h'),
          )
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final file in sources) {
    final text = file.readAsStringSync();
    final where = 'flutter3d_physics_native/${relative(file, native)}';
    for (final hit in cDefinesCopyingTheWorldIn(text)) {
      found.add(
        Finding(
          '$where:${hit.line}',
          '${hit.name} is a copy of a world\'s, water\'s, air\'s or nature\'s '
              'number: use the F3D_STANDARD_* / F3D_MAT_* / '
              'F3D_STEFAN_BOLTZMANN the generated header gives',
        ),
      );
    }
    for (final hit in cDefinesCopyingMaterialsIn(text, values: values)) {
      found.add(
        Finding(
          '$where:${hit.line}',
          '${hit.name} copies a number of the catalogue\'s material: use its '
              'F3D_MAT_* from the generated header',
        ),
      );
    }
  }
  final config = File('${repositoryRoot.path}/.dart_tool/package_config.json');
  if (!config.existsSync()) return found;
  final result = Process.runSync(Platform.resolvedExecutable, <String>[
    'run',
    'tool/gen_materials.dart',
    '--check',
  ], workingDirectory: native.path);
  if (result.exitCode != 0) {
    found.add(
      Finding(
        'flutter3d_physics_native/csrc/src/f3d_materials.g.h',
        'is not what the catalogue makes: run `dart run '
            'tool/gen_materials.dart` in flutter3d_physics_native '
            '(${'${result.stderr}'.trim().split('\n').last})',
      ),
    );
  }
  return found;
}

/// Every import and export in [source], each as the browser's build takes
/// it: a conditional one by its web branch when it names one, by its
/// default when it asks for `dart.library.io` the browser has not.
Iterable<String> _webDirectives(String source) sync* {
  final directive = RegExp(
    r"^(?:import|export)\s+'([^']+)'((?:\s+if\s*\([^)]*\)\s*'[^']+')*)",
    multiLine: true,
  );
  final branch = RegExp(r"if\s*\(([^)]*)\)\s*'([^']+)'");
  for (final match in directive.allMatches(source)) {
    var chosen = match.group(1)!;
    for (final condition in branch.allMatches(match.group(2) ?? '')) {
      final asks = condition.group(1)!.trim();
      if (asks.contains('js_interop') ||
          asks.contains('dart.library.html') ||
          asks.contains('dart.library.js')) {
        chosen = condition.group(2)!;
        break;
      }
    }
    yield chosen;
  }
}

/// [uri], imported from [from], as a file in this repository; null for the
/// SDK's libraries and packages from elsewhere.
File? _resolveInRepository(String uri, File from) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    final home = packages[rest.substring(0, slash)];
    if (home == null) return null;
    return File('${home.path}/lib/${rest.substring(slash + 1)}');
  }
  return File.fromUri(from.absolute.uri.resolve(uri));
}

// -------------------------------------------------------- the public API

/// Every package that goes to pub.dev, by name: `packages/*` and
/// `packages/education/*`, without the ones whose pubspec says
/// `publish_to: none`.
Map<String, Directory> get _publishedPackages {
  final education = Directory('${repositoryRoot.path}/packages/education');
  final all = <String, Directory>{
    ...packages,
    if (education.existsSync())
      for (final dir in education.listSync().whereType<Directory>())
        if (File('${dir.path}/pubspec.yaml').existsSync())
          dir.path.split(Platform.pathSeparator).last: dir,
  };
  return <String, Directory>{
    for (final entry in all.entries)
      if (!RegExp(
        r'''^publish_to:\s*['"]?none''',
        multiLine: true,
      ).hasMatch(File('${entry.value.path}/pubspec.yaml').readAsStringSync()))
        entry.key: entry.value,
  };
}

Version? _pubspecVersion(String pubspec) {
  final line = _pubspecVersionText(pubspec);
  return line == null ? null : parseVersion(line);
}

/// The pubspec's `version:` as written, pre-release and all.
String? _pubspecVersionText(String pubspec) =>
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);

/// Every published package's `api/<package>.api` is what its source makes.
///
/// **The one rule here that needs a resolved workspace**, because the
/// snapshot is parsed by the analyzer and this scan runs before `pub get`.
/// So it starts `tool/api` as a program, and on a checkout with no
/// `.dart_tool/package_config.json` naming the analyzer it has nothing to run
/// and says nothing — which is the shader-freshness shape, answered the same
/// way: `tool/ci.sh` asks for this rule again by name after `pub get`, where
/// it cannot be skipped.
///
/// Mutation: add a member to any public type, or rename a parameter, without
/// `--update`, and this names the package with the count of breaks.
List<Finding> _apiSnapshotsCurrent() => _snapshotsCurrent(
  program: 'api_snapshot',
  update: 'dart run api_snapshot --update',
);

/// Every published package's `api/<package>.mcp` and `api/<package>.vm` are
/// what its source makes: the tools its MCP servers offer an agent, and the
/// VM service extensions and game events a running game offers an editor.
///
/// **The API rule's shape, for callers that never compile.** A host config
/// names a tool, a model reads a schema, and an attached editor calls
/// `ext.flutter3d.level.apply` with string parameters; a rename breaks all
/// three and nothing here fails, because the callers are not here. Like the
/// API rule it needs the resolved workspace — the tool builds the plain Dart
/// servers and parses the rest — so it says nothing before `pub get`, and
/// `tool/ci.sh` asks for it again by name after (its name holds the words
/// that step asks for).
///
/// Mutation: rename a tool, add a required argument to one, or stop reading
/// a parameter in an extension's handler, without `--update`, and this
/// names the package and the file with the count of breaks.
List<Finding> _schemaSnapshotsCurrent() => _snapshotsCurrent(
  program: 'api_snapshot:schema_snapshot',
  update: 'dart run api_snapshot:schema_snapshot --update',
);

/// Runs `tool/api`'s [program] with `--check --brief` and reads its lines.
List<Finding> _snapshotsCurrent({
  required String program,
  required String update,
}) {
  final root = repositoryRoot;
  final config = File('${root.path}/.dart_tool/package_config.json');
  if (!config.existsSync() ||
      !config.readAsStringSync().contains('"name": "analyzer"')) {
    return const <Finding>[];
  }
  final result = Process.runSync(Platform.resolvedExecutable, <String>[
    'run',
    program,
    '--check',
    '--brief',
  ], workingDirectory: '${root.path}/tool/api');
  if (result.exitCode == 0) return const <Finding>[];
  final lines = (result.stdout as String)
      .split('\n')
      .where((String l) => l.contains('\t'))
      .toList();
  if (lines.isEmpty) {
    return <Finding>[
      Finding(
        'tool/api',
        'the snapshot tool failed (exit ${result.exitCode}): '
            '${(result.stderr as String).trim()}',
      ),
    ];
  }
  return <Finding>[
    for (final line in lines)
      if (line.split('\t') case [final name, final what])
        Finding(
          'packages/$name',
          what.startsWith('there is no')
              ? '$what: a published package without one has a surface '
                    'nobody is watching. Run `$update $name` in tool/api'
              : '$what. If it is deliberate, decide the version, write it '
                    'in CHANGELOG.md, and run `$update $name` in tool/api; '
                    '`dart run $program $name` there shows each change '
                    'classified',
        ),
  ];
}

/// A change to a published API since the last release is versioned as what
/// it is, and a break is labelled in the CHANGELOG.
///
/// **Against the last release, not the last commit.** The snapshot the
/// previous rule holds is always current, so on its own it says nothing about
/// what the next release owes: a break committed in March is just as much a
/// break in June. The baseline is `api/<package>.api` and the pubspec version
/// at the newest `vX.Y.Z` tag — read with `git show`, which changes nothing.
/// A package with no snapshot at that tag has no promise to break yet, so the
/// pre-1.0 baseline asks nothing of anybody.
///
/// What it asks, classified by `classifyApi` in `api.dart`:
///
///  * a break: the pubspec has moved a major (a minor, before 1.0) past the
///    tag, and the top CHANGELOG section has a `**Breaking:` entry naming
///    each broken name as code;
///  * an addition: the pubspec has moved a minor past the tag (any release,
///    before 1.0). A patch adds nothing.
///
/// Mutation: remove a public member, regenerate the snapshot, and this asks
/// for the label and the major until both are there.
List<Finding> _apiBreaksLabelled() => _breaksSinceRelease(
  surface: 'the API',
  snapshotsOf: (String name) => <String>['api/$name.api'],
  classify: classifyApi,
  diff: 'dart run api_snapshot --diff',
);

/// A change to the tools a published package offers an agent or an editor
/// since the last release is versioned as what it is, and a break is
/// labelled in the CHANGELOG — the API rule above, over `api/<package>.mcp`
/// and `api/<package>.vm`, classified by `classifySchema` in `schema.dart`.
///
/// **And a server's own number moves with it.** Each server announces a
/// schema version in its `initialize` result, so a host can tell whether the
/// tool list it cached still holds; a change that needs a major or a minor
/// of the package needs the same of that number, read from the snapshot's
/// `schema` line at the tag and now.
///
/// Mutation: drop a tool, or add a required argument to one, regenerate the
/// snapshot, and this asks for the major, the schema version and the
/// labelled CHANGELOG entry naming the tool, until all three are there.
List<Finding> _schemaBreaksLabelled() => _breaksSinceRelease(
  surface: 'the tools',
  snapshotsOf: (String name) => <String>['api/$name.mcp', 'api/$name.vm'],
  classify: classifySchema,
  diff: 'dart run api_snapshot:schema_snapshot --diff',
  versionsIn: schemaVersions,
);

/// What [_apiBreaksLabelled] and [_schemaBreaksLabelled] share: each
/// snapshot [snapshotsOf] names for a published package, at the newest
/// `vX.Y.Z` tag against now, classified by [classify], and the pubspec, the
/// CHANGELOG and — when [versionsIn] reads any from the snapshot — each
/// server's own schema version held to what the changes need.
List<Finding> _breaksSinceRelease({
  required String surface,
  required List<String> Function(String package) snapshotsOf,
  required List<ApiChange> Function(String before, String after) classify,
  required String diff,
  Map<String, String> Function(String snapshot)? versionsIn,
}) {
  final root = repositoryRoot;
  String? git(List<String> args) {
    try {
      final result = Process.runSync('git', args, workingDirectory: root.path);
      return result.exitCode == 0 ? result.stdout as String : null;
    } on ProcessException {
      return null;
    }
  }

  // Newest first in semver's order, so `v1.0.0` is newer than the
  // `v1.0.0-rc.1` before it rather than tied with it.
  final tags =
      <String>[
        for (final tag in (git(<String>['tag', '--list', 'v*']) ?? '').split(
          '\n',
        ))
          if (parseVersion(tag.trim().replaceFirst('v', '')) != null)
            tag.trim(),
      ]..sort(
        (String a, String b) =>
            compareVersionTexts(b.substring(1), a.substring(1))!,
      );
  if (tags.isEmpty) return const <Finding>[];
  final tag = tags.first;
  final atTag =
      (git(<String>['ls-tree', '-r', '--name-only', tag, '--', 'packages']) ??
              '')
          .split('\n')
          .toSet();

  final found = <Finding>[];
  for (final entry in _publishedPackages.entries) {
    final name = entry.key;
    final home = entry.value.path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    for (final snapshot in snapshotsOf(name)) {
      final path = '$home/$snapshot';
      if (!atTag.contains(path)) continue;
      final released = git(<String>['show', '$tag:$path']);
      final file = File('${root.path}/$path');
      if (released == null || !file.existsSync()) continue;
      final current = file.readAsStringSync();
      final changes = classify(released, current);
      final needed = requiredBump(changes);
      if (needed == Bump.none) continue;
      final hint =
          '${changes.length} changes; run `$diff` in tool/api against '
          '`git show $tag:$path` to see them';

      final then = _pubspecVersionText(
        git(<String>['show', '$tag:$home/pubspec.yaml']) ?? '',
      );
      final now = _pubspecVersionText(
        File('${entry.value.path}/pubspec.yaml').readAsStringSync(),
      );
      if (then != null && now != null && !bumpIsEnoughFrom(needed, then, now)) {
        found.add(
          Finding(
            '$home/pubspec.yaml',
            '$surface ${needed == Bump.major ? 'broke' : 'grew'} since $tag '
                '($hint), and $now is not '
                '${preReleaseOf(then).isEmpty ? 'a ${needed == Bump.major ? 'major' : 'minor'} release' : 'a release'} '
                'past $then',
          ),
        );
      }

      // Each server's own schema version, against what its changes need.
      if (versionsIn != null) {
        final promised = versionsIn(released);
        final announced = versionsIn(current);
        for (final server in promised.keys.where(announced.containsKey)) {
          final own = requiredBump(
            changes.where((ApiChange c) => c.library == server),
          );
          final v0 = parseVersion(promised[server]!);
          final v1 = parseVersion(announced[server]!);
          if (own == Bump.none || v0 == null || v1 == null) continue;
          if (!bumpIsEnough(own, v0, v1)) {
            found.add(
              Finding(
                path,
                'the server `$server` ${own == Bump.major ? 'broke' : 'grew'} '
                'since $tag ($hint), and its schema version '
                '${announced[server]} is not a '
                '${own == Bump.major ? 'major' : 'minor'} past '
                '${promised[server]}: move the constant it announces',
              ),
            );
          }
        }
      }

      if (needed != Bump.major) continue;
      final changelog = File('${entry.value.path}/CHANGELOG.md');
      final section = topSection(
        changelog.existsSync() ? changelog.readAsStringSync() : '',
      );
      if (breakingEntries(section.text).isEmpty) {
        found.add(
          Finding(
            '$home/CHANGELOG.md',
            '$surface broke since $tag and the ${section.heading} section '
                'has no "$breakingLabel" entry',
          ),
        );
        continue;
      }
      for (final subject in unnamedBreaks(changes, section.text)) {
        found.add(
          Finding(
            '$home/CHANGELOG.md',
            '`$subject` broke since $tag and no "$breakingLabel" entry of '
                'the ${section.heading} section names it',
          ),
        );
      }
    }
  }
  return found;
}

/// Every `@Deprecated` in a published package says when it was deprecated,
/// when it goes, and what to use instead, in the one format
/// `deprecationVersions` reads; no bare `@deprecated`, which says none of it.
///
/// **A deprecation is a date with the people who call it.** Without the
/// versions nobody can tell which ones the next major is allowed to remove,
/// and without the replacement the warning tells a caller to stop without
/// telling them what to do. One overdue — still here at or past its removal
/// version — fails too, because a promise to remove that is not kept teaches
/// callers that the dates mean nothing.
///
/// Mutation: drop the version sentence from any of them, or bump a package
/// to its removal version, and this names the file and line.
List<Finding> _deprecationsDated() {
  final found = <Finding>[];
  for (final entry in _publishedPackages.entries) {
    final version = _pubspecVersion(
      File('${entry.value.path}/pubspec.yaml').readAsStringSync(),
    );
    if (version == null) continue;
    for (final file in dartFilesIn(Directory('${entry.value.path}/lib'))) {
      for (final d in deprecationsIn(file.readAsStringSync())) {
        final where = '${_inRepository(file)}:${d.line}';
        final message = d.message;
        if (message == null) {
          found.add(
            Finding(
              where,
              'a deprecation with no message as a string literal: write '
              "@Deprecated('Use X. Deprecated in A.B.C, removed in "
              "N.0.0.')",
            ),
          );
          continue;
        }
        final problem = deprecationProblem(message, version);
        if (problem != null) found.add(Finding(where, 'its message $problem'));
      }
    }
  }
  return found;
}

/// Every break of a published API since the newest release tag has an entry
/// in a migration table, `packages/flutter3d_build/lib/migrations/*.yaml`:
/// a fix `dart fix` or the `flutter3d_lints` migrator carries out, or a
/// `manual` entry saying what a person does, or a `none` entry saying why
/// no call is affected.
///
/// **A break comes with its migration.** The rule above makes a break a
/// version decision and a CHANGELOG line; this one makes it the work of
/// moving somebody's code too, written down where the tools read it. The
/// release's API is `tool/api/baseline/<tag>/` when the release predates
/// the snapshots (0.8.5, written by `api_snapshot:api_baseline`), and the
/// snapshot at the tag otherwise; each published package's
/// `api/<package>.api` is now. What counts as covered, and the three changes
/// the classifier calls breaks that no call can see, are in `migration.dart`.
///
/// It also holds what the tables generate to the tables: each generated
/// `fix_data.yaml` and the plugin's `table.g.dart` carry the stamp of the
/// tables they came from, and a stale one is named. And `packages:
/// versions:` names every published package not on the engine's number.
///
/// Mutation: remove a public member and regenerate its snapshot, and this
/// names it until an entry covers it (`dart run api_snapshot:migration_seed`
/// drafts one); edit a table without running `generate_migrations.dart`, and
/// this names each stale output.
List<Finding> _breaksHaveMigrations() {
  final root = repositoryRoot;
  final found = <Finding>[];
  final dir = Directory('${root.path}/packages/flutter3d_build/lib/migrations');
  if (!dir.existsSync()) return found;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  final texts = <String>[for (final f in files) f.readAsStringSync()];
  final tables = <MigrationTable>[];
  for (var i = 0; i < files.length; i++) {
    final where = _inRepository(files[i]);
    final table = readMigrationTable(texts[i]);
    tables.add(table);
    for (final (line, what) in migrationTableProblems(table)) {
      found.add(Finding('$where:$line', what));
    }
  }

  // The generated outputs carry the tables' stamp.
  final stamp = tableStamp(texts.join('\n'));
  final generated = <File>[
    File(
      '${root.path}/packages/flutter3d_lints/lib/src/migration/table.g.dart',
    ),
    for (final package in packages.values)
      File('${package.path}/lib/fix_data.yaml'),
  ];
  for (final file in generated) {
    if (!file.existsSync()) continue;
    final said = RegExp(
      r'table-stamp: (\S+)',
    ).firstMatch(file.readAsStringSync())?.group(1);
    if (said == null) continue;
    if (said != stamp) {
      found.add(
        Finding(
          _inRepository(file),
          'was generated from another version of the migration tables: run '
          '`dart run tool/generate_migrations.dart` in flutter3d_build',
        ),
      );
    }
  }

  String? git(List<String> args) {
    try {
      final result = Process.runSync('git', args, workingDirectory: root.path);
      return result.exitCode == 0 ? result.stdout as String : null;
    } on ProcessException {
      return null;
    }
  }

  final tags =
      <String>[
        for (final tag in (git(<String>['tag', '--list', 'v*']) ?? '').split(
          '\n',
        ))
          if (parseVersion(tag.trim().replaceFirst('v', '')) != null)
            tag.trim(),
      ]..sort(
        (String a, String b) =>
            compareVersionTexts(b.substring(1), a.substring(1))!,
      );
  if (tags.isEmpty) return found;
  final tag = tags.first;
  final version = tag.substring(1);

  // The release's API: a baseline written for it, or the snapshots at it.
  final baseline = Directory('${root.path}/tool/api/baseline/$tag');
  final released = <String, String>{};
  if (baseline.existsSync()) {
    for (final f in baseline.listSync().whereType<File>()) {
      if (!f.path.endsWith('.api')) continue;
      released[f.uri.pathSegments.last.replaceAll('.api', '')] = f
          .readAsStringSync();
    }
  } else {
    for (final MapEntry(key: name, value: dir) in _publishedPackages.entries) {
      final home = dir.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      final text = git(<String>['show', '$tag:$home/api/$name.api']);
      if (text != null) released[name] = text;
    }
  }
  if (released.isEmpty) return found;
  final current = <String, String>{
    for (final MapEntry(key: name, value: dir) in _publishedPackages.entries)
      if (File('${dir.path}/api/$name.api') case final f when f.existsSync())
        name: f.readAsStringSync(),
  };

  final index = tables.indexWhere((MigrationTable t) => t.from == version);
  final table = index < 0
      ? readMigrationTable('from: $version\n')
      : tables[index];
  final tableName = index < 0
      ? 'a migration table from $version'
      : _inRepository(files[index]);
  final left = uncoveredBreaks(
    released: released,
    current: current,
    table: table,
  );
  for (final b in left) {
    found.add(
      Finding(
        'packages/${b.package}',
        '`${breakSymbol(b.change)}` broke since $tag (${b.change.what.length > 120 ? '${b.change.what.substring(0, 120)}…' : b.change.what}) '
            'and no entry of $tableName covers it: '
            '`dart run api_snapshot:migration_seed --append` in tool/api '
            'drafts one',
      ),
    );
  }

  // A published package off the engine's number is named with its own.
  if (index >= 0) {
    for (final MapEntry(key: name, value: dir) in _publishedPackages.entries) {
      final now = _pubspecVersionText(
        File('${dir.path}/pubspec.yaml').readAsStringSync(),
      );
      if (now == null || now == table.to) continue;
      if (table.versions[name] != '^$now') {
        found.add(
          Finding(
            tableName,
            '`$name` is at $now, not ${table.to}: `packages: versions:` has '
            'to say `$name: ^$now`, or `migrate` moves its dependents to a '
            'version it does not have',
          ),
        );
      }
    }
  }
  return found;
}

/// The migration tables, read without a parser, and the file each came from.
List<(File, MigrationTable)> _migrationTables() {
  final dir = Directory(
    '${repositoryRoot.path}/packages/flutter3d_build/lib/migrations',
  );
  if (!dir.existsSync()) return const <(File, MigrationTable)>[];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  return <(File, MigrationTable)>[
    for (final f in files) (f, readMigrationTable(f.readAsStringSync())),
  ];
}

/// The `manual` entries of the migration tables stay at or under
/// `manualCeiling` in `migration.dart`, unless `manualAllowlist` there names
/// the entry with the reason no kind carries it out.
///
/// **A manual entry is a TODO in somebody's code.** The tools carry out
/// renames, moves, parameters, rewrites, regrouped arguments, switches over
/// a type that stopped being an enum, records that became classes and calls
/// that throw where they answered null; what is left is what a person has
/// to decide. The count only goes down without anyone saying why.
///
/// Mutation: append a `manual` entry to a table, and this names it with the
/// kind its text reads like.
List<Finding> _manualCeiling() {
  final tables = _migrationTables();
  final where = tables.isEmpty ? '' : _inRepository(tables.last.$1);
  return <Finding>[
    for (final (id, what) in manualCeilingProblems(<MigrationTable>[
      for (final (_, t) in tables) t,
    ]))
      Finding('$where ($id)', '`$id` $what'),
  ];
}

/// The README's "Coming from 0.8" and the hand-written half of the site's
/// migration guide state no count the tables do not: no "about two hundred
/// places", and an `N entries` or `N by hand` is the tables' N. The guide's
/// generated half (`generate_migrations.dart`) writes its numbers from the
/// table already.
///
/// Mutation: write "about three hundred places" in the README's migration
/// section, or change the table without the sentence that counts it.
List<Finding> _migrationNumbers() {
  final tables = _migrationTables();
  if (tables.isEmpty) return const <Finding>[];
  final counts = migrationCounts(<MigrationTable>[
    for (final (_, t) in tables) t,
  ]);
  final found = <Finding>[];
  final readme = File('${repositoryRoot.path}/README.md');
  if (readme.existsSync()) {
    final text = readme.readAsStringSync();
    final start = text.indexOf('\n## Coming from');
    if (start >= 0) {
      final end = text.indexOf('\n## ', start + 1);
      for (final p in migrationNumberProblems(
        text.substring(start, end < 0 ? text.length : end),
        counts: counts,
      )) {
        found.add(Finding(_inRepository(readme), p));
      }
    }
  }
  final guide = File(
    '${repositoryRoot.path}/site/content/reference/migrating-to-1.0.md',
  );
  if (guide.existsSync()) {
    final text = guide.readAsStringSync();
    const start = '<!-- migration-table:start -->';
    const end = '<!-- migration-table:end -->';
    final a = text.indexOf(start);
    final b = text.indexOf(end);
    final written = a < 0 || b < a
        ? text
        : text.substring(0, a) + text.substring(b + end.length);
    for (final p in migrationNumberProblems(written, counts: counts)) {
      found.add(Finding(_inRepository(guide), p));
    }
  }
  return found;
}

/// `packages/flutter3d_build/api/flutter3d_build.cli` is what the `flutter3d`
/// command prints for `help --surface`, and a subcommand or a flag gone since
/// the last release is labelled a break.
///
/// **Item 32 of `tasks/1.0-scope-additions.md`: the command is a contract.**
/// Its subcommands, flags and exit codes are what CI scripts and the cloud
/// service call, and none of them compiles against this repository, so the
/// only place a rename shows is a snapshot of the text that lists them.
/// `tool/cli_surface.dart` imports nothing but the contract's own file, so
/// this runs in a second without a resolved workspace for the converters.
///
/// Mutation: drop `--dry-run` from `convertUsage` without regenerating the
/// snapshot, and this names the file; regenerate it, and with a release tag
/// before it this asks for the `**Breaking:**` entry naming `--dry-run`.
List<Finding> _cliSurfaceCurrent() {
  final home = '${repositoryRoot.path}/packages/flutter3d_build';
  final snapshot = File('$home/api/flutter3d_build.cli');
  const update =
      'run `dart tool/cli_surface.dart > api/flutter3d_build.cli` in '
      'packages/flutter3d_build';
  if (!snapshot.existsSync()) {
    return <Finding>[
      Finding(
        'packages/flutter3d_build/api/flutter3d_build.cli',
        'is missing: the command\'s surface is a contract nobody is '
            'watching; $update',
      ),
    ];
  }
  final ProcessResult result;
  try {
    result = Process.runSync(Platform.resolvedExecutable, <String>[
      'tool/cli_surface.dart',
    ], workingDirectory: home);
  } on ProcessException {
    return const <Finding>[];
  }
  if (result.exitCode != 0) {
    return <Finding>[
      Finding(
        'packages/flutter3d_build/tool/cli_surface.dart',
        'failed (exit ${result.exitCode}): ${(result.stderr as String).trim()}',
      ),
    ];
  }
  final found = <Finding>[];
  final committed = snapshot.readAsStringSync();
  if (result.stdout as String != committed) {
    found.add(
      Finding(
        'packages/flutter3d_build/api/flutter3d_build.cli',
        'is not what `flutter3d help --surface` prints now. If the change is '
            'deliberate, write it in CHANGELOG.md (a removed command or flag is '
            '**Breaking:**) and $update',
      ),
    );
  }

  // Against the last release: what was promised there and is gone now.
  final tags =
      <String>[
        for (final tag
            in ((Process.runSync('git', <String>[
                      'tag',
                      '--list',
                      'v*',
                    ], workingDirectory: repositoryRoot.path).stdout
                    as String)
                .split('\n')))
          if (parseVersion(tag.trim().replaceFirst('v', '')) != null)
            tag.trim(),
      ]..sort(
        (String a, String b) =>
            compareVersionTexts(b.substring(1), a.substring(1))!,
      );
  if (tags.isEmpty) return found;
  final released = Process.runSync('git', <String>[
    'show',
    '${tags.first}:packages/flutter3d_build/api/flutter3d_build.cli',
  ], workingDirectory: repositoryRoot.path);
  if (released.exitCode != 0) return found;
  final gone = cliSurfaceWords(
    released.stdout as String,
  ).difference(cliSurfaceWords(committed));
  if (gone.isEmpty) return found;
  final changelog = File('$home/CHANGELOG.md');
  final top = changelog.existsSync()
      ? changelog.readAsStringSync().split(RegExp(r'^## ', multiLine: true))
      : const <String>[];
  final section = top.length > 1 ? top[1] : '';
  for (final word in gone) {
    if (section.contains('**Breaking:') && section.contains('`$word`')) {
      continue;
    }
    found.add(
      Finding(
        'packages/flutter3d_build/CHANGELOG.md',
        '`$word` was in the command\'s surface at ${tags.first} and is gone: '
            'a script that calls it breaks, so the top section needs a '
            '**Breaking:** entry naming `$word`',
      ),
    );
  }
  return found;
}

/// Each format a published package declares with a `FormatSpec`, and each in
/// `versionedFormats`, has a fixture at every version from its `since` to the
/// number its reader declares; every format version constant in a published
/// package is named by a `FormatSpec`, listed there, or in
/// `notAVersionedFormat`; and no published reader gates on the exact version.
///
/// **The registry is read from the code.** `formatSpecsIn` finds each
/// `FormatSpec(...)` the way the engine's `FormatRegistry` is filled, so a
/// format is checked because it says it is one, whatever its constant is
/// called; the name pattern stays only as the net for a version constant
/// nobody declared.
///
/// **A 1.x engine reads every 1.x file** (decision 8 of
/// `tasks/1.0-stability.md`). The test that proves it reads a file minted at
/// that version, and a bump that arrives without one leaves the promise
/// unchecked from the day it is made. A test cannot see its own absence, so
/// the count of fixtures against the constant lives here. The exact gate is
/// the other way the promise was broken before 1.0: `!=` against the current
/// version refuses every file the previous release wrote.
///
/// Mutation: bump `f3dVersion` to 2 without `v2/box.f3d`, add a
/// `static const int formatVersion` to any published reader without listing
/// it, or write `if (version != formatVersion)` in one, and this names it.
List<Finding> _formatFixtures() {
  final found = <Finding>[];
  final listed = <String>{};
  for (final MapEntry(key: name, value: format) in versionedFormats.entries) {
    listed.add('${format.reader}#${format.constant}');
    final reader = File('${repositoryRoot.path}/${format.reader}');
    if (!reader.existsSync()) {
      found.add(Finding(format.reader, 'the $name reader is not there'));
      continue;
    }
    final current = formatVersionsIn(
      reader.readAsStringSync(),
    )[format.constant];
    if (current == null) {
      found.add(
        Finding(
          format.reader,
          'declares no `${format.constant}`, so nothing says which $name '
          'versions it reads',
        ),
      );
      continue;
    }
    for (var version = format.since; version <= current; version++) {
      final fixture = format.fixture.replaceAll('<N>', '$version');
      if (!File('${repositoryRoot.path}/$fixture').existsSync()) {
        found.add(
          Finding(
            fixture,
            'is missing: $name reads version $version, and only a file '
            'minted at that version shows it still opens',
          ),
        );
      }
    }
  }

  // The registry as the code declares it: every `FormatSpec` in a published
  // package, with its fixtures read from that package's root.
  for (final package in _publishedPackages.values) {
    for (final file in dartFilesIn(Directory('${package.path}/lib'))) {
      final where = _inRepository(file);
      for (final spec in formatSpecsIn(file.readAsStringSync())) {
        if (spec.versionConstant case final String constant) {
          listed.add('$where#$constant');
        }
        final version = spec.version;
        if (version == null) {
          found.add(
            Finding(
              where,
              'declares format "${spec.id}" with a version this check cannot '
              'read: name a `const int` of the same file, or write the number',
            ),
          );
          continue;
        }
        final fixture = spec.fixture;
        if (fixture == null) {
          if (!formatWithoutFixture.containsKey(spec.id)) {
            found.add(
              Finding(
                where,
                'declares format "${spec.id}" with no `fixture:`: every '
                'version a 1.x build reads needs a file minted at it, or a '
                'reason in `formatWithoutFixture`',
              ),
            );
          }
          continue;
        }
        for (var at = spec.since; at <= version; at++) {
          final path = '${package.path}/${fixture.replaceAll('<N>', '$at')}';
          if (!File(path).existsSync()) {
            found.add(
              Finding(
                _inRepository(File(path)),
                'is missing: format "${spec.id}" reads version $at, and '
                'only a file minted at that version shows it still opens',
              ),
            );
          }
        }
      }
    }
  }

  for (final package in _publishedPackages.values) {
    for (final file in dartFilesIn(Directory('${package.path}/lib'))) {
      final where = _inRepository(file);
      final source = file.readAsStringSync();
      for (final constant in formatVersionsIn(source).keys) {
        final key = '$where#$constant';
        if (!listed.contains(key) && !notAVersionedFormat.containsKey(key)) {
          found.add(
            Finding(
              where,
              'declares `$constant`, a format version nobody listed: declare '
              'the format with a `FormatSpec` naming it and its fixture, or '
              'say in `notAVersionedFormat` why it is not one',
            ),
          );
        }
      }
      for (final line in exactVersionGatesIn(source)) {
        found.add(
          Finding(
            '$where:$line',
            'gates a read on the exact version, which refuses every file the '
                'previous release wrote: read every version up to the current '
                'one and refuse only a newer one',
          ),
        );
      }
    }
  }
  return found;
}

/// No format's code writes or reads an enum by its ordinal.
///
/// **Must 4 of `tasks/1.0-arch-review.md`.** `.f3d` wrote `alphaMode.index`,
/// the wrap modes and a track's path and interpolation by ordinal and read
/// them back with `values[i]`, so reordering an enum in a major would have
/// changed every existing file without a word. The codes are explicit
/// tables now (`f3d_wire.dart`); this keeps `.index` and `values[` out of
/// every path in [formatCodePaths].
///
/// Mutation: write `material.alphaMode.index` back in
/// `f3d_writer_materials.dart`, and this names the line.
List<Finding> _noEnumOrdinalsInFormats() {
  final found = <Finding>[];
  for (final path in formatCodePaths) {
    final directory = Directory('${repositoryRoot.path}/$path');
    final file = File('${repositoryRoot.path}/$path');
    final files = directory.existsSync()
        ? dartFilesIn(directory)
        : file.existsSync()
        ? <File>[file]
        : const <File>[];
    if (files.isEmpty) {
      found.add(Finding(path, 'is in `formatCodePaths` and is not there'));
      continue;
    }
    for (final each in files) {
      for (final line in enumOrdinalsIn(each.readAsStringSync())) {
        found.add(
          Finding(
            '${_inRepository(each)}:$line',
            'writes or reads an enum by its ordinal: give it a code in an '
                'explicit table, as `f3d_wire.dart` does',
          ),
        );
      }
    }
  }
  return found;
}

// ------------------------------------------------------ 1.0: the contract
// ------------------------------------------------------ 1.0: the contract

/// The published snapshots, by package: `api/<package>.api` for every
/// package that goes to pub.dev and has one.
Map<String, String> get _publishedSnapshots => <String, String>{
  for (final entry in _publishedPackages.entries)
    if (File('${entry.value.path}/api/${entry.key}.api') case final file
        when file.existsSync())
      entry.key: file.readAsStringSync(),
};

/// No published type is an `interface class`, except a marker or a value
/// shape [interfaceClassAllowed] names with its reason.
///
/// **Decision 5 of `tasks/1.0-api-review.md`, and why it is a rule.** A
/// member added to an interface in a minor release breaks every class
/// somebody wrote against it; the same member added to an `abstract base
/// class` with a default body breaks nobody. Under strict semver that is the
/// difference between a type that can grow in 1.x and one frozen until 2.0.
///
/// **It reads the snapshots, not the source**, because the snapshot is the
/// promise: an interface behind a `src/` path nobody exports is nobody's
/// problem. And it starts with a debt: [interfaceClassPending] is every
/// interface on the day this was written, which wave 3 converts. The rule
/// fails on an interface in neither table, and on an entry in either that no
/// snapshot declares as an interface any more, so the pending list cannot
/// outlive its work.
///
/// Mutation: make `abstract base class BusEvent` an `abstract interface
/// class`, regenerate the snapshot, and this names it.
List<Finding> _noNewInterfaces() {
  final found = <Finding>[];
  final declared = <String, Set<String>>{
    for (final entry in _publishedSnapshots.entries)
      entry.key: interfaceClassesIn(entry.value),
  };
  for (final entry in declared.entries) {
    final pending = interfaceClassPending[entry.key] ?? const <String>{};
    for (final name in entry.value.toList()..sort()) {
      if (interfaceClassAllowed.containsKey(name)) continue;
      if (pending.contains(name)) continue;
      found.add(
        Finding(
          '${entry.key}/api/${entry.key}.api',
          '`$name` is an interface class. Make it an abstract base class with '
              'default bodies (a member added to it later then breaks nobody), '
              'or say in `interfaceClassAllowed` why it is a marker or a value '
              'shape that can never grow',
        ),
      );
    }
  }
  for (final entry in interfaceClassPending.entries) {
    for (final name in entry.value) {
      if (declared[entry.key]?.contains(name) ?? false) continue;
      found.add(
        Finding(
          'tool/structure/repository.dart',
          '`interfaceClassPending` still lists `$name` under ${entry.key}, '
              'which no longer declares it as an interface. Take the entry '
              'out, so the list says what is left to convert',
        ),
      );
    }
  }
  final everywhere = <String>{for (final names in declared.values) ...names};
  for (final name in interfaceClassAllowed.keys) {
    if (everywhere.contains(name)) continue;
    found.add(
      Finding(
        'tool/structure/repository.dart',
        '`interfaceClassAllowed` names `$name`, which no snapshot declares as '
            'an interface. Take the entry out',
      ),
    );
  }
  return found;
}

/// Every published exception reaches `Flutter3dException`, none is named
/// `…Error`, and each is named `…Exception` (decision H) unless
/// [exceptionNamePending] still lists it.
///
/// **Decision 4 and item 21.** A caller who wants to report everything the
/// engine refused catches one type, and a caller who acts on one kind of
/// refusal catches its family: format, capability, plugin, resource, all in
/// `flutter3d_plugin_api`. Before wave 3 there were sixty-odd exception types
/// with no common root, six of them named `…Error`, and one capability
/// refusal that was an `UnsupportedError`.
///
/// The hierarchy is read across every snapshot at once, because a leaf in
/// one package extends a family declared in another. A type is an exception
/// when it reaches `Exception` or one of the SDK's own exceptions
/// ([kSdkExceptions]); the root is the one type allowed to implement
/// `Exception` directly.
///
/// Mutation: make `DracoException` implement `Exception` again, regenerate
/// the snapshot, and this names it.
List<Finding> _exceptionsHaveTheRoot() {
  final snapshots = _publishedSnapshots;
  final hierarchy = <String, Set<String>>{};
  final home = <String, String>{};
  for (final entry in snapshots.entries) {
    for (final type in supertypesIn(entry.value).entries) {
      (hierarchy[type.key] ??= <String>{}).addAll(type.value);
      home.putIfAbsent(type.key, () => entry.key);
    }
  }
  final found = <Finding>[
    for (final (name, why) in exceptionsOutsideTheRoot(
      hierarchy,
      namedOtherwise: exceptionNamePending.keys.toSet(),
    ))
      Finding('${home[name]}/api/${home[name]}.api', '`$name` $why'),
  ];
  // The pending list only shrinks: an entry whose type is gone, or is now
  // named `…Exception`, is taken out.
  for (final name in exceptionNamePending.keys) {
    if (!hierarchy.containsKey(name)) {
      found.add(
        Finding(
          'tool/structure/repository.dart',
          '`exceptionNamePending` names `$name`, which no snapshot declares. '
              'Take the entry out',
        ),
      );
    }
  }
  return found;
}

// ------------------------------------------------------------ 1.0: naming

/// One of the naming rules of item 28 (`naming.dart`): [detect] over every
/// published snapshot, less what [allowed] excuses with its reason — and an
/// excuse nothing needs any more is a finding too, so the list only says
/// what is true.
///
/// Mutation, for each: rename a published member back to the name the rule
/// forbids (`sunColor` to `sunColour`, `drainDelta` to `takeDelta`,
/// `halfAngle` to `halfAngleDegrees`, `isGrounded` to `grounded`,
/// `f3dVersion` to `kF3dVersion`, drop a field from a settings class's
/// `copyWith`), regenerate the snapshot, and the rule names it.
List<Finding> _namingRule(
  List<NamingProblem> Function(String snapshot, String package) detect,
  Map<String, String> allowed,
) {
  final found = <Finding>[];
  final used = <String>{};
  for (final MapEntry(key: package, value: snapshot)
      in _publishedSnapshots.entries) {
    for (final problem in detect(snapshot, package)) {
      if (allowed.containsKey(problem.subject)) {
        used.add(problem.subject);
        continue;
      }
      found.add(
        Finding(
          '$package/api/$package.api',
          '`${problem.subject}` ${problem.what}',
        ),
      );
    }
  }
  for (final name in allowed.keys) {
    if (used.contains(name)) continue;
    found.add(
      Finding(
        'tool/structure/repository.dart',
        'an exemption names `$name`, which no snapshot breaks the rule with '
            'any more: take the entry out',
      ),
    );
  }
  return found;
}

/// Every published package's public `double` fields and getters say their
/// unit in their doc comment (item 29, the units contract in
/// `docs/CONTRACTS.md`).
///
/// **It starts with a debt, counted rather than listed.** About eleven
/// hundred numbers predate the rule; [unitsUndocumentedPending] holds each
/// package's count, and a package may be at or under its count, never over.
/// A package that has paid some of it down is held to the new number — the
/// count has to come down with it — so the table only ever shrinks, the way
/// [interfaceClassPending] did.
///
/// Mutation: delete the unit from a field's doc ("in metres"), and the
/// package is one over its count.
List<Finding> _unitsDocumented() {
  final found = <Finding>[];
  for (final MapEntry(key: package, value: dir) in _publishedPackages.entries) {
    final lib = Directory('${dir.path}/lib');
    if (!lib.existsSync()) continue;
    var count = 0;
    final named = <String>[];
    for (final file in dartFilesIn(lib)) {
      final missing = undocumentedUnitsIn(file.readAsStringSync());
      count += missing.length;
      if (named.length < 5) {
        named.addAll(missing.map((String m) => '${relative(file, dir)}#$m'));
      }
    }
    final pending = unitsUndocumentedPending[package] ?? 0;
    if (count > pending) {
      found.add(
        Finding(
          '$package/lib',
          '$count public numbers do not say their unit in their doc, '
              '$pending allowed: say metres, seconds, radians, a fraction… '
              '(${named.take(5).join(', ')})',
        ),
      );
    } else if (count < pending) {
      found.add(
        Finding(
          'tool/structure/repository.dart',
          '`unitsUndocumentedPending` allows $package $pending undocumented '
              'numbers and there are $count: lower it to $count, so the debt '
              'only shrinks',
        ),
      );
    }
  }
  return found;
}

// ------------------------------------------------------------------ layers

/// Every package depends at run time only on packages in the layers below
/// its own (`tool/structure/layers.dart`, the target map of
/// `tasks/1.0-boundaries.md`), and on none the map forbids.
///
/// **There are no exceptions.** The boundary work kept a list of the
/// dependencies the map refused while its moves took them out, which only
/// shrank; step C emptied it, and the list went with its last entry. A
/// dependency the map refuses is a finding, with no list to park it on.
List<Finding> _layersBelow() {
  final dependencies = <String, Set<String>>{
    for (final MapEntry(key: name, value: dir) in packages.entries)
      name: pubspecSection(
        File('${dir.path}/pubspec.yaml').readAsStringSync(),
        'dependencies',
      ),
  };
  final found = <Finding>[
    for (final (package, dependency, why) in layerProblems(
      dependencies,
      layers: packageLayers,
      forbidden: layerForbidden,
    ))
      dependency == null
          ? Finding(package, why)
          : Finding(package, 'depends on $dependency, which $why'),
  ];
  for (final name in packageLayers.keys) {
    if (!packages.containsKey(name) && !plannedPackages.contains(name)) {
      found.add(
        Finding(
          'packageLayers → $name',
          'is not a package and not a planned one: take it off',
        ),
      );
    }
  }
  for (final name in plannedPackages) {
    if (packages.containsKey(name)) {
      found.add(
        Finding(
          'plannedPackages → $name',
          'is a package now: take it off the planned list',
        ),
      );
    }
  }
  return found;
}

/// The simulation stack ([simulationStack]: sim, physics, physics_native,
/// elements, matter, foundation) imports no package of
/// [simulationMayNotImport] (the core, the hardware layer, the shaders, the
/// particles) from its `lib/`. Rule 6 of `tasks/1.0-boundaries.md`.
///
/// Mutation: import `flutter3d_core` from a file of `flutter3d_elements`,
/// and this names the file and the package.
List<Finding> _simulationDrawsNothing() {
  final found = <Finding>[];
  for (final name in simulationStack) {
    final dir = packages[name];
    if (dir == null) {
      found.add(Finding(name, 'is in the simulation stack and not a package'));
      continue;
    }
    final imports = <String, List<String>>{
      for (final file in dartFilesIn(Directory('${dir.path}/lib')))
        '$name/${relative(file, dir)}': <String>[
          for (final m in RegExp(
            r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            m.group(1)!,
        ],
    };
    for (final (path, package) in simulationImportProblems(
      imports,
      forbidden: simulationMayNotImport.keys.toSet(),
    )) {
      found.add(
        Finding(
          path,
          'imports $package (${simulationMayNotImport[package]}): the '
          'simulation draws nothing',
        ),
      );
    }
  }
  return found;
}

/// The runtime (the application, the game packages, the elements and their
/// views, the audio) depends at run time on no editor, build tool, agent
/// server or modeller's core: rule 7 of `tasks/1.0-boundaries.md`.
///
/// **What a player's game resolves is what it ships.** The application
/// depended on the editor's document layer to load a level until 1.0.0-rc.1;
/// nothing failed, and every game resolved an editor it never opened. Dev
/// dependencies are not asked about, because a test may drive an editor;
/// a deliberate run-time one is in [runtimeToolDependencyAllowed] with its
/// reason, and an entry there that is no longer a dependency is a finding.
List<Finding> _runtimeIsNoTool() {
  final dependencies = <String, Set<String>>{
    for (final MapEntry(key: name, value: dir) in packages.entries)
      name: pubspecSection(
        File('${dir.path}/pubspec.yaml').readAsStringSync(),
        'dependencies',
      ),
  };
  final found = <Finding>[];
  final allowedNow = <String>{};
  for (final (package, tool) in runtimeToolDependencies(
    dependencies,
    runtime: isRuntimePackage,
    tools: runtimeMayNotDependOn.keys.toSet(),
  )) {
    final key = '$package -> $tool';
    if (runtimeToolDependencyAllowed.containsKey(key)) {
      allowedNow.add(key);
      continue;
    }
    found.add(
      Finding(
        package,
        'depends on $tool (${runtimeMayNotDependOn[tool]}) at run time: the '
        'runtime is not a tool. Move what it needs under both, or make '
        'it a dev dependency if only a test wants it',
      ),
    );
  }
  for (final key in runtimeToolDependencyAllowed.keys) {
    if (!allowedNow.contains(key)) {
      found.add(
        Finding(
          'runtimeToolDependencyAllowed → $key',
          'is no longer a dependency: take it off',
        ),
      );
    }
  }
  return found;
}

/// The plugin API declares the contract and nothing else: every type it
/// declares is reachable from the contract's signatures, the number of them
/// is within [pluginApiTypeBudget], and no loop phase it declares is named
/// after one package.
///
/// **Read off the API snapshot**, `api/flutter3d_plugin_api.api`, which the
/// snapshot rule holds to the source: what the package declares, with every
/// member's signature, and the names it re-exports from the foundation.
///
/// **Why a budget as well as reachability.** Reachability says a type is
/// the contract's; it does not say the contract should have grown. The
/// plugin API had grown to 77 types, the foundation's and a simulation
/// host's among them, before the boundary work; a budget makes the next
/// type a decision someone takes in review rather than a drift nobody
/// notices.
List<Finding> _pluginContract() {
  final dir = packages['flutter3d_plugin_api'];
  if (dir == null) {
    return <Finding>[
      const Finding('flutter3d_plugin_api', 'is not a package any more'),
    ];
  }
  final snapshot = File('${dir.path}/api/flutter3d_plugin_api.api');
  if (!snapshot.existsSync()) {
    return <Finding>[
      const Finding(
        'flutter3d_plugin_api',
        'has no api/flutter3d_plugin_api.api to read the contract from',
      ),
    ];
  }
  final library = parseApi(
    snapshot.readAsStringSync(),
  )['package:flutter3d_plugin_api/flutter3d_plugin_api.dart'];
  if (library == null) {
    return <Finding>[
      const Finding(
        'flutter3d_plugin_api/api/flutter3d_plugin_api.api',
        'has no main library',
      ),
    ];
  }
  final declarations = <String, ({String header, List<String> members})>{
    for (final MapEntry(key: name, value: block)
        in library.declarations.entries)
      name: (header: block.header, members: block.members),
  };
  final reexported = <String>{
    for (final block in library.exports.values)
      if (RegExp(r' show (.*)$').firstMatch(block.header) case final match?)
        ...match.group(1)!.split(',').map((String n) => n.trim()),
  };
  final found = <Finding>[
    for (final name in unreachableContractTypes(
      declarations,
      roots: pluginContractRoots,
      reexported: reexported,
    ).toList()..sort())
      Finding(
        'flutter3d_plugin_api: $name',
        'is a type nothing in the contract names, so a plugin is never '
            'handed it or asked for it: move it to the package that uses '
            'it',
      ),
  ];

  final types = declarations.values
      .where(
        (({String header, List<String> members}) b) =>
            isTypeDeclaration(b.header),
      )
      .length;
  if (types > pluginApiTypeBudget) {
    found.add(
      Finding(
        'flutter3d_plugin_api',
        'declares $types types, over its budget of $pluginApiTypeBudget: a '
            'type the contract needs raises pluginApiTypeBudget by hand, '
            'with its reason in review',
      ),
    );
  } else if (types < pluginApiTypeBudget) {
    found.add(
      Finding(
        'tool/structure/layers.dart',
        'pluginApiTypeBudget is $pluginApiTypeBudget and the plugin API '
            'declares $types types: lower the budget to $types',
      ),
    );
  }

  final loop = File('${dir.path}/lib/src/loop.dart');
  final phases = loop.existsSync()
      ? declaredLoopPhases(loop.readAsStringSync())
      : const <String>{};
  if (phases.isEmpty) {
    found.add(
      const Finding(
        'flutter3d_plugin_api/lib/src/loop.dart',
        'declares no loop phase this rule can read',
      ),
    );
  }
  final namedForAPackage = phasesNamedForAPackage(phases, <String>{
    ...packages.keys,
    ...packageLayers.keys,
  });
  for (final phase in namedForAPackage.toList()..sort()) {
    if (loopPhaseSharesAPackageName.containsKey(phase)) continue;
    found.add(
      Finding(
        'flutter3d_plugin_api/lib/src/loop.dart',
        'the phase "$phase" is named after flutter3d_$phase: an engine phase '
            'is every plugin\'s, so name it for what runs in it, or say in '
            'loopPhaseSharesAPackageName why every package may call it its '
            'own',
      ),
    );
  }
  for (final phase in loopPhaseSharesAPackageName.keys) {
    if (!namedForAPackage.contains(phase)) {
      found.add(
        Finding(
          'loopPhaseSharesAPackageName → $phase',
          'is no longer a phase named like a package: take it off',
        ),
      );
    }
  }
  return found;
}

// ------------------------------------------------------- names and doors

/// A public name is declared by one published package
/// (`tool/structure/boundaries.dart`, [namesWithTwoHomes]), read off every
/// package's API snapshot, which the snapshot rule holds to the source.
/// [publicNameSharedOnPurpose] lists the exceptions with their reasons, and
/// an exception that is no longer one is a finding.
List<Finding> _oneHomePerName() {
  final snapshots = <String, String>{
    for (final MapEntry(key: name, value: dir) in _publishedPackages.entries)
      if (File('${dir.path}/api/$name.api') case final f when f.existsSync())
        name: f.readAsStringSync(),
  };
  final homes = publicNameHomes(snapshots);
  return <Finding>[
    for (final (name, packages) in namesWithTwoHomes(
      homes,
      allowed: publicNameSharedOnPurpose,
    ))
      Finding(
        '`$name`',
        'is declared by ${packages.join(' and ')}: a public name has one '
            'home, so the more specific one takes a name that says what it '
            'is, or both use one declaration',
      ),
    for (final name in publicNameSharedOnPurpose.keys)
      if ((homes[name]?.length ?? 0) < 2)
        Finding(
          'publicNameSharedOnPurpose → $name',
          'is no longer declared by two packages: take it off',
        ),
  ];
}

/// Shipped code — `lib/` and `bin/` of every package and application —
/// reaches another package's `internal.dart`, `builtin.dart` or
/// `testing.dart` only where [restrictedLibraryUsers] says so
/// (`tool/structure/boundaries.dart`); tests may import them anywhere. An
/// allowance nothing uses any more, or for a library that is not there, is
/// a finding.
List<Finding> _restrictedLibraries() {
  final uses = <String, Set<String>>{};
  final where = <(String, String), String>{};
  for (final MapEntry(key: name, value: dir) in <String, Directory>{
    ...packages,
    ...apps,
  }.entries) {
    final reached = <String>{};
    for (final sub in const <String>['lib', 'bin']) {
      for (final file in dartFilesIn(Directory('${dir.path}/$sub'))) {
        for (final library in restrictedLibrariesIn(file.readAsStringSync())) {
          reached.add(library);
          where[(name, library)] ??= _inRepository(file);
        }
      }
    }
    uses[name] = reached;
  }
  final found = <Finding>[
    for (final (package, library, why) in restrictedLibraryProblems(
      uses,
      allowed: restrictedLibraryUsers,
    ))
      Finding(
        where[(package, library)] ?? package,
        'imports $library, which $why',
      ),
  ];
  for (final MapEntry(key: library, value: users)
      in restrictedLibraryUsers.entries) {
    final owner = packages[packageOfUri(library)];
    final file = library.substring(library.indexOf('/') + 1);
    if (owner == null || !File('${owner.path}/lib/$file').existsSync()) {
      found.add(
        Finding(
          'restrictedLibraryUsers → $library',
          'is not a library of the repository: take it off',
        ),
      );
      continue;
    }
    for (final user in users.keys) {
      if (!(uses[user]?.contains(library) ?? false)) {
        found.add(
          Finding(
            'restrictedLibraryUsers → $library → $user',
            'is no longer reached from $user\'s shipped code: take it off',
          ),
        );
      }
    }
  }
  return found;
}

// ------------------------------------------------------------- re-exports

/// The `package:` re-exports of every package's `lib/`, by package and file.
Map<String, Map<String, List<({String uri, bool named})>>> _packageExports() =>
    <String, Map<String, List<({String uri, bool named})>>>{
      for (final MapEntry(key: name, value: dir) in packages.entries)
        name: <String, List<({String uri, bool named})>>{
          for (final file in dartFilesIn(Directory('${dir.path}/lib')))
            if (packageExportsIn(file.readAsStringSync()) case final e
                when e.isNotEmpty)
              _inRepository(file): e,
        },
    };

/// A package re-exports another package of the repository only where
/// [reexportsAllowed] (`tool/structure/boundaries.dart`) says so, and names
/// what it admits unless [reexportedWhole] allows the whole library: rule 3
/// of `tasks/1.0-boundaries.md`. An allowance nothing uses any more is a
/// finding, so the list does not outlive its reasons.
///
/// Mutation: put `export 'package:flutter3d_physics/flutter3d_physics.dart'
/// show CollisionWorld;` back in `flutter3d_sim.dart`, and this names the
/// file and the package it hands on.
List<Finding> _reexportsAllowedOnly() {
  final exports = _packageExports();
  final found = <Finding>[
    for (final (_, file, why) in reexportProblems(
      exports,
      repository: packages.keys.toSet(),
      allowed: reexportsAllowed,
      whole: reexportedWhole,
    ))
      Finding(file, why),
  ];
  final made = <String>{};
  final wholeMade = <String>{};
  for (final MapEntry(key: package, value: files) in exports.entries) {
    for (final list in files.values) {
      for (final e in list) {
        final key = '$package -> ${packageOfUri(e.uri)}';
        made.add(key);
        if (!e.named) wholeMade.add(key);
      }
    }
  }
  for (final key in reexportsAllowed.keys) {
    if (!made.contains(key)) {
      found.add(
        Finding(
          'reexportsAllowed → $key',
          'is no longer a re-export: take it off',
        ),
      );
    }
  }
  for (final key in reexportedWhole.keys) {
    if (!wholeMade.contains(key)) {
      found.add(
        Finding(
          'reexportedWhole → $key',
          'no longer re-exports a whole library: take it off',
        ),
      );
    }
  }
  return found;
}

/// No package depends on another only to re-export it, unless
/// [reexportsAllowed] names the pair: rule 2 of `tasks/1.0-boundaries.md`.
/// A dependency counts as used when an `import` of its shipped code —
/// `lib/`, `bin/` or `hook/` — names it.
///
/// Mutation: make `flutter3d` depend on `flutter3d_sim` again and re-export
/// `EngineLoop` from its barrel, and this names the dependency (and the
/// re-export rule the export).
List<Finding> _noReexportOnlyDependency() {
  final dependencies = <String, Set<String>>{};
  final imported = <String, Set<String>>{};
  final exported = <String, Set<String>>{};
  final directive = RegExp(
    r"""^(import|export)\s+['"]package:(\w+)/""",
    multiLine: true,
  );
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    dependencies[name] = pubspecSection(
      File('${dir.path}/pubspec.yaml').readAsStringSync(),
      'dependencies',
    ).where(packages.containsKey).toSet();
    final imports = imported[name] = <String>{};
    final exports = exported[name] = <String>{};
    for (final sub in const <String>['lib', 'bin', 'hook']) {
      for (final file in dartFilesIn(Directory('${dir.path}/$sub'))) {
        for (final m in directive.allMatches(file.readAsStringSync())) {
          (m.group(1) == 'import' ? imports : exports).add(m.group(2)!);
        }
      }
    }
  }
  return <Finding>[
    for (final (package, dependency) in reexportOnlyDependencies(
      dependencies,
      imported: imported,
      exported: exported,
      allowed: reexportsAllowed,
    ))
      Finding(
        '$package/pubspec.yaml',
        'depends on $dependency only to re-export it: a caller that needs '
            '$dependency depends on it itself, or the pair goes on '
            '`reexportsAllowed` with its reason',
      ),
  ];
}

/// A file of a package or an application — `lib/` and `bin/` — that names
/// a type another package declares is in a package that depends on that
/// one, or on a facade whose allowed re-exports carry the name: rule 4 of
/// `tasks/1.0-boundaries.md`, declare what you name.
///
/// **Read off the snapshots**, which the snapshot rule holds to the source:
/// where each type is declared, and what each allowed re-export admits. A
/// name two packages declare is the one-home rule's finding, not this
/// one's.
///
/// Mutation: drop `flutter3d_physics` from an application's pubspec that
/// names `CollisionWorld` through `flutter3d_sim`'s import, and this names
/// the file, the type and the package it is declared in.
List<Finding> _declareWhatYouName() {
  final snapshots = <String, Map<String, ApiLibrary>>{
    for (final MapEntry(key: name, value: dir) in _publishedPackages.entries)
      if (File('${dir.path}/api/$name.api') case final f when f.existsSync())
        name: parseApi(f.readAsStringSync()),
  };
  final declaredBy = <String, Set<String>>{};
  for (final MapEntry(key: package, value: libraries) in snapshots.entries) {
    for (final library in libraries.values) {
      for (final MapEntry(key: name, value: block)
          in library.declarations.entries) {
        if (name.isEmpty || name.startsWith('_')) continue;
        if (!isTypeDeclaration(block.header)) continue;
        (declaredBy[name] ??= <String>{}).add(package);
      }
    }
  }
  final homes = <String, String>{
    for (final MapEntry(key: name, value: at) in declaredBy.entries)
      if (at.length == 1) name: at.single,
  };
  final carried = <String, Set<String>>{
    for (final MapEntry(key: package, value: libraries) in snapshots.entries)
      package: <String>{
        for (final library in libraries.values)
          for (final MapEntry(key: uri, value: block)
              in library.exports.entries)
            if (uri.startsWith('package:') &&
                reexportsAllowed.containsKey(
                  '$package -> ${packageOfUri(uri)}',
                ))
              for (final member in block.members)
                member.trim().split(' ').first,
      },
  };
  final dependencies = <String, Set<String>>{};
  final named = <String, Map<String, Set<String>>>{};
  final declared = <String, Set<String>>{};
  for (final MapEntry(key: name, value: dir) in <String, Directory>{
    ...packages,
    ...apps,
  }.entries) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    dependencies[name] = pubspecSection(
      pubspec.readAsStringSync(),
      'dependencies',
    );
    final files = named[name] = <String, Set<String>>{};
    final own = declared[name] = <String>{};
    for (final sub in const <String>['lib', 'bin']) {
      for (final file in dartFilesIn(Directory('${dir.path}/$sub'))) {
        final names = typeNamesIn(file.readAsStringSync());
        files[_inRepository(file)] = names.named;
        own.addAll(names.declared);
      }
    }
  }
  final found = <Finding>[
    for (final name in typeNamesDeclaredOutside.keys)
      if (!homes.containsKey(name))
        Finding(
          'typeNamesDeclaredOutside → $name',
          'is no longer a type one package declares: take it off',
        ),
  ];
  return found..addAll(<Finding>[
    for (final (package, file, name, home) in undeclaredNames(
      named,
      declared: declared,
      homes: homes,
      dependencies: dependencies,
      carried: carried,
      sdk: typeNamesDeclaredOutside,
    ))
      Finding(
        file,
        'names `$name`, which $home declares, and $package does not depend '
        'on $home: add it to the pubspec\'s dependencies, or name it '
        'through a facade `reexportsAllowed` lists',
      ),
  ]);
}

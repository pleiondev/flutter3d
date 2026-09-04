/// The rules, each a walk of the tree returning what it found.
///
/// A rule is a name and a function. It reports rather than asserts, so the
/// runner can show every offence in one pass instead of the first one — which
/// matters for a rule that fires across twenty packages at once, where the
/// first offender says nothing about whether it is one mistake or twenty.
library;

import 'dart:io';

import 'detectors.dart';
import 'repository.dart';

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
  (name: 'a step reaches for no clock and no loose dice', run: _repeatableStep),
  (name: 'the simulation names no Flutter', run: _simNamesNoFlutter),
  (name: 'the hardware layer names no graphics API', run: _hardwareNamesNoApi),
  (name: 'the engine names no backend', run: _engineNamesNoBackend),
  (name: 'each assembly has one home per application', run: _oneAssembly),
  (name: 'no test builds its own world', run: _noHarnessAssembly),
  (name: 'the repository lists agree with the workspace', run: _listsAgree),
  (name: 'every exemption names a file that is there', run: _exemptionsResolve),
  (name: 'no application silences a print', run: _noSilencedPrints),
  (name: 'the Impeller runners are reachable', run: _impellerRunners),
  (name: 'the document says how many tests there are', run: _testCount),
  (
    name: 'an application that draws asks its platform for the GPU',
    run: _gpuIsEnabled,
  ),
  (name: 'the publishing order names every package', run: _publishingOrder),
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

List<Finding> _genreIsolation() {
  final found = <Finding>[];
  for (final genre in genrePackages) {
    final dir = packages[genre];
    if (dir == null) continue;
    final mayDraw = genreMayDraw[genre] ?? const <String>{};

    for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
      final path = relative(file, dir);
      if (mayDraw.contains(path)) continue;
      if (_draws(file.readAsStringSync())) {
        found.add(
          Finding(
            '$genre/$path',
            'the simulation half draws — move it into the bridge, or add it to '
                'genreMayDraw and say why',
          ),
        );
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
List<Finding> _repeatableStep() {
  final found = <Finding>[];
  for (final entry in packages.entries) {
    if (notARepeatableStep.containsKey(entry.key)) continue;
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

// ---------------------------------------------------------- the server's half

/// `flutter3d_sim` may not name Flutter — in its library, its tests or its
/// binaries.
///
/// **This is the rule the package was created to make checkable.** A server
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
/// Tests and `bin/` are scanned as well as `lib/`, deliberately. A suite that
/// needs `flutter_test` to run is a suite CI can only run through Flutter, and
/// then the claim "this package stands alone" is true of the library and false
/// of the thing anybody actually executes.
List<Finding> _simNamesNoFlutter() {
  final package = packages['flutter3d_sim'];
  if (package == null) {
    return <Finding>[
      const Finding(
        'flutter3d_sim',
        'is not a package any more, so the rule that it stays plain Dart has '
            'outlived its subject — delete the rule or restore the package',
      ),
    ];
  }

  // `package:flutter/`, `dart:ui` and `flutter_test` together, for the reason
  // `hardwareMayUseFlutter` gives about the first two: widgets re-export half
  // of `dart:ui`, so naming one without the other is a rule with a door in it.
  final forbidden = RegExp(
    r"'(package:flutter/|package:flutter_test/|dart:ui)",
  );
  final found = <Finding>[];
  for (final where in <String>['lib', 'test', 'bin']) {
    for (final file in dartFilesIn(Directory('${package.path}/$where'))) {
      if (!forbidden.hasMatch(file.readAsStringSync())) continue;
      found.add(
        Finding(
          relative(file, repositoryRoot),
          'names Flutter. This package is what a server runs without a Flutter '
          'SDK; whatever wants Flutter belongs in flutter3d_game',
        ),
      );
    }
  }
  return found;
}

// ------------------------------------------------------- backend containment

List<Finding> _hardwareNamesNoApi() {
  final dir = packages['flutter3d_hardware'];
  if (dir == null) {
    return <Finding>[const Finding('flutter3d_hardware', 'is not there')];
  }
  final found = <Finding>[];
  final files = dartFilesIn(Directory('${dir.path}/lib'));
  if (files.isEmpty) {
    return <Finding>[
      const Finding(
        'flutter3d_hardware',
        'has no lib/ — a scan that finds '
            'nothing proves nothing',
      ),
    ];
  }

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final source = file.readAsStringSync();
    final where = 'flutter3d_hardware/${relative(file, dir)}';
    if (reaches(source, 'flutter_gpu')) {
      found.add(Finding(where, 'reaches a backend'));
    }
    if (hardwareMayUseFlutter.containsKey(name)) continue;
    if (reaches(source, 'dart:ui') || reaches(source, 'package:flutter/')) {
      found.add(
        Finding(
          where,
          "reaches Flutter — this package's vocabulary is its own. If this is "
          'genuinely something every backend must answer, name it in '
          'hardwareMayUseFlutter with the reason',
        ),
      );
    }
  }

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

List<Finding> _engineNamesNoBackend() {
  final dir = packages['flutter3d'];
  if (dir == null) return <Finding>[const Finding('flutter3d', 'is not there')];
  final found = <Finding>[];

  for (final file in dartFilesIn(Directory('${dir.path}/lib'))) {
    if (reaches(file.readAsStringSync(), 'flutter_gpu')) {
      found.add(
        Finding(
          'flutter3d/${relative(file, dir)}',
          'names flutter_gpu, which this package must not know exists — '
              'whatever it needs belongs on GraphicsDevice or CommandEncoder',
        ),
      );
    }
  }

  final pubspec = File('${dir.path}/pubspec.yaml').readAsStringSync();
  for (final forbidden in <String>['flutter_gpu', 'flutter3d_impeller']) {
    // The import scan misses this: depending on a backend and using it through
    // the umbrella library names nothing textually and still welds the engine
    // to one.
    if (pubspec.contains('\n  $forbidden:')) {
      found.add(
        Finding(
          'flutter3d',
          'depends on $forbidden — an application chooses a backend, the '
              'engine does not',
        ),
      );
    }
  }
  if (!pubspec.contains('flutter3d_hardware:')) {
    found.add(
      const Finding(
        'flutter3d',
        'no longer depends on the hardware layer, so it is written against '
            'nothing and the two checks above are vacuous',
      ),
    );
  }

  for (final entry in engineAlsoFreeOfDartUi.entries) {
    final file = File('${dir.path}/${entry.key}');
    if (!file.existsSync()) {
      found.add(
        Finding(
          'flutter3d/${entry.key}',
          'moved or was renamed; the rule moves with it',
        ),
      );
    } else if (reaches(file.readAsStringSync(), 'dart:ui')) {
      found.add(
        Finding('flutter3d/${entry.key}', 'reaches dart:ui — ${entry.value}'),
      );
    }
  }

  for (final entry in engineCompilesOffDevice.entries) {
    final file = File('${dir.path}/${entry.key}');
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
String? _resolveImport(String uri, String from, Map<String, String> roots) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final root = roots[rest.substring(0, slash)];
    return root == null ? null : '$root/${rest.substring(slash + 1)}';
  }
  return File('${File(from).parent.path}/$uri').absolute.path;
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
      if (member.startsWith('- packages/flutter3d_game_'))
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
/// The count is a word in the README and a digit in `ARCHITECTURE.md`, because
/// that is what reads well in each. Both are checked.
List<Finding> _ruleCount() {
  const List<String> words = <String>[
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
    'twenty',
    'twenty-one',
    'twenty-two',
    'twenty-three',
    'twenty-four',
    'twenty-five',
    'twenty-six',
    'twenty-seven',
    'twenty-eight',
    'twenty-nine',
    'thirty',
  ];
  final actual = allRules.length;
  final found = <Finding>[];

  void check(String path, RegExp pattern, String Function(String) read) {
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
    final said = read(match.group(1)!);
    if (said != '$actual') {
      found.add(Finding(path, 'says $said rules; there are $actual'));
    }
  }

  check(
    'README.md',
    // `[\w-]`, because the twenty-first rule is the first count whose word
    // carries a hyphen — and `\w+` matching "one" out of "twenty-one" would
    // have been a wrong number reported as a missing sentence.
    RegExp(r'its ([\w-]+) rules'),
    (String word) => '${words.indexOf(word)}',
  );
  check(
    'ARCHITECTURE.md',
    RegExp(r'Structure rules \| (\d+),'),
    (String digits) => digits,
  );

  // The site and CONTRIBUTING.md state the count too, each in the phrasing
  // its own sentence needed — "eighteen rules, under a second", "one of
  // nineteen scans" — and those were three different wrong answers at once.
  // Matched by phrasing, the way the golden scenes are, so "two rules check
  // it" about a pair of rules is not read as a claim about the total.
  final phrasings = <RegExp>[
    RegExp('([\\w-]+) rules, under a second', caseSensitive: false),
    RegExp('holds ([\\w-]+) rules'),
    RegExp('one of ([\\w-]+) scans', caseSensitive: false),
    RegExp('([\\w-]+) green scans'),
    RegExp('([\\w-]+) checks that read source text'),
    RegExp('one of the ([\\w-]+) checks it'),
  ];
  for (final page in _prosePages()) {
    final text = page.readAsStringSync();
    for (final pattern in phrasings) {
      for (final match in pattern.allMatches(text)) {
        final claim = match.group(1)!;
        final number =
            int.tryParse(claim) ?? words.indexOf(claim.toLowerCase());
        if (number < 0) continue;
        if (number != actual) {
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

  found.addAll(_theTestingPageAddsUp(actual, words));

  if (actual >= words.length) {
    found.add(
      Finding(
        'tool/structure/rules.dart',
        'there are $actual rules and this check can only spell '
            '${words.length - 1}. Extend the list.',
      ),
    );
  }
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
List<Finding> _theTestingPageAddsUp(int actual, List<String> words) {
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

  final rest = RegExp(r'([\w-]+) more check the lists').firstMatch(text);
  if (rest == null) {
    return <Finding>[
      const Finding(
        page,
        'no longer says how many rules its table leaves out, so nothing here '
        'can tell whether the page adds up',
      ),
    ];
  }
  final said =
      int.tryParse(rest.group(1)!) ??
      words.indexOf(rest.group(1)!.toLowerCase());
  if (said == actual - rows) return const <Finding>[];
  return <Finding>[
    Finding(
      page,
      'names $rows rules in its table and says ${rest.group(1)} more, which is '
      '${said < 0 ? 'not a number' : said + rows} of $actual',
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
List<Finding> _gpuIsEnabled() {
  const String appleKey = 'FLTEnableFlutterGPU';
  const String androidKey = 'io.flutter.embedding.android.EnableFlutterGPU';

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
      if (!plist.readAsStringSync().contains(appleKey)) {
        found.add(
          Finding(
            '${entry.key}/$platform/Runner/Info.plist',
            'has no $appleKey, so the shader library will not initialise and '
                'the application draws nothing',
          ),
        );
      }
    }

    final manifest = File(
      '${entry.value.path}/android/app/src/main/AndroidManifest.xml',
    );
    if (manifest.existsSync() &&
        !manifest.readAsStringSync().contains(androidKey)) {
      found.add(
        Finding(
          '${entry.key}/android/app/src/main/AndroidManifest.xml',
          'has no $androidKey meta-data; the engine defaults it to false, so '
              'the application draws nothing',
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
/// Only membership is checked, not the order itself. The order encodes which
/// package depends on which, and a rule deriving that from the pubspecs would be
/// re-deriving what the document exists to record — while the failure that
/// actually happens is a package nobody added.
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

  void check(String label, String package, String path) {
    final dir = packages[package];
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
  for (final entry in repeatableStepExempt.entries) {
    for (final path in entry.value.keys) {
      check('repeatableStepExempt', entry.key, path);
    }
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
  for (final path in engineAlsoFreeOfDartUi.keys) {
    check('engineAlsoFreeOfDartUi', 'flutter3d', path);
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
  final declaration = RegExp(r'^\s*(test|testWidgets)\(');
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

  // The README says it in words, because that is what reads well in prose —
  // and a word is exactly the kind of number that is never recounted.
  const List<String> words = <String>[
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
    'twenty',
    'twenty-one',
    'twenty-two',
    'twenty-three',
    'twenty-four',
    'twenty-five',
  ];
  final readme = File('${root.path}/README.md').readAsStringSync();
  final saidInProse = RegExp(
    r'(\d+) tests across ([a-z-]+) packages',
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
    // ARCHITECTURE.md states in digits. It used to be held to the packages
    // that carry a test, and the two counts sitting three apart across two
    // documents read as one of them being wrong rather than as two facts.
    final expected = packages.length < words.length
        ? words[packages.length]
        : '${packages.length}';
    if (saidInProse.group(2) != expected) {
      found.add(
        Finding(
          'README.md',
          'says ${saidInProse.group(2)} packages; '
              'there are ${packages.length} ($expected)',
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
    final claims = <String>[
      for (final m in RegExp(r'([\w-]+) tests across').allMatches(text))
        m.group(1)!,
      for (final m in RegExp(r'of (\d+) tests').allMatches(text)) m.group(1)!,
      for (final m in RegExp(r'Tests</dt><dd>(\d+)').allMatches(text))
        m.group(1)!,
    ];
    for (final claim in claims) {
      final number = int.tryParse(claim) ?? words.indexOf(claim.toLowerCase());
      if (number < 0) continue;
      if (number != counted) {
        found.add(Finding(where, 'says $claim tests; there are $counted'));
      }
    }
    for (final m in RegExp(r'tests across (\d+) packages').allMatches(text)) {
      if (m.group(1) != '${packages.length}') {
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
      if (!_caretCovers(asked, sibling.value)) {
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

/// Whether `^asked` admits [declared], by pub's caret rule: below 1.0.0 the
/// minor is the breaking number, so `^0.4.0` reaches 0.4.x and stops at 0.5;
/// from 1.0.0 the major is, so `^1.2.0` reaches 1.x from 1.2 up.
bool _caretCovers(String asked, String declared) {
  List<int>? parts(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return null;
    return <int>[for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final a = parts(asked);
  final d = parts(declared);
  if (a == null || d == null) return asked == declared;

  final sameFloor = a[0] == 0 ? d[0] == 0 && d[1] == a[1] : d[0] == a[0];
  if (!sameFloor) return false;
  for (var i = 0; i < 3; i++) {
    if (d[i] != a[i]) return d[i] > a[i];
  }
  return true;
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
  final sets = <String, String>{
    'impeller': 'packages/flutter3d/test/goldens',
    'cpu': 'packages/flutter3d_cpu/test/goldens',
    'webgl': 'packages/flutter3d_webgl/test/goldens',
  };
  final reference = RegExp(r'\{\{(golden3?)\s+([\w-]+)');
  for (final file in content.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    final where = relative(file, content);
    for (final match in reference.allMatches(file.readAsStringSync())) {
      final kind = match.group(1)!;
      final name = match.group(2)!;
      for (final set in sets.entries) {
        if (kind == 'golden' && set.key != 'impeller') continue;
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
List<Finding> _goldenSceneCount() {
  final goldens = Directory(
    '${repositoryRoot.path}/packages/flutter3d_cpu/test/goldens',
  );
  if (!goldens.existsSync()) {
    return <Finding>[
      const Finding('flutter3d_cpu/test/goldens', 'is not there'),
    ];
  }
  final count = goldens
      .listSync()
      .where((FileSystemEntity it) => it.path.endsWith('.png'))
      .length;
  if (count == 0) {
    return <Finding>[
      const Finding('flutter3d_cpu/test/goldens', 'holds no PNGs to count'),
    ];
  }
  if (count >= _countedInWords.length) {
    return <Finding>[
      Finding(
        'tool/structure/rules.dart',
        'there are $count scenes and this check can only spell '
            '${_countedInWords.length - 1}. Extend the list.',
      ),
    ];
  }

  final word = _countedInWords[count];
  final found = <Finding>[];
  // The site tells the same story on half a dozen pages, and its testing page
  // was still saying "thirty scenes" two recounts later — so the prose pages
  // are scanned along with the scripts and ARCHITECTURE.md, and every Dart file
  // in the repository along with those.
  final files = <File>[
    for (final where in <String>[
      'tool/ci.sh',
      'packages/flutter3d_webgl/tool/golden_web.sh',
      'ARCHITECTURE.md',
    ])
      File('${repositoryRoot.path}/$where'),
    ..._prosePages(),
    ..._everyDartFile(),
  ];
  // Only the phrasings that are actually about the scenes, so a stray "32"
  // elsewhere in a long document is not a false positive. `goldens` is here
  // because that is the word the code uses for them; the documents say scenes.
  final claim = RegExp(
    r'([\w-]+) (?:golden )?(?:scenes|goldens)\b',
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
      final said = match.group(1)!.toLowerCase();
      if (said == '$count' || said == word) continue;
      // A word that is not a number at all — "the scenes", "particle goldens" —
      // is not a claim about how many there are.
      final number = int.tryParse(said) ?? _countedInWords.indexOf(said);
      if (number < 0) continue;
      if (_sparedAt(text, match.start, spared.keys)) continue;
      found.add(
        Finding(where, 'says "${match.group(0)}"; there are ${_spell(count)}'),
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

/// CONTRIBUTING.md and every Markdown page of the documentation site.
///
/// The three counting rules read these along with the README and
/// `ARCHITECTURE.md`, because the site restates the same numbers in prose and
/// drifted the same way: its testing page said 2901 tests, its glossary said
/// nineteen scans, and nothing compared either with the tree. A page here is
/// only held to a count it states; none is required to state one.
List<File> _prosePages() {
  final pages = <File>[];
  final contributing = File('${repositoryRoot.path}/CONTRIBUTING.md');
  if (contributing.existsSync()) pages.add(contributing);
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
  final total = dartFilesIn(lib)
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
      RegExp(r'([\w-]+) of the ([\w-]+) link stages and draw'),
      (RegExpMatch m) => shader,
      'checks that link stages and draw',
    ),
    (
      RegExp(r'([\w-]+) shader checks'),
      (RegExpMatch m) => shader,
      'shader checks',
    ),
    (
      RegExp(r'[Tt]he ([\w-]+) checks, against a backend'),
      (RegExpMatch m) => total,
      'checks in all',
    ),
    (
      RegExp(r'the ([\w-]+) rules ARCHITECTURE\.md §7\.2 states'),
      (RegExpMatch m) => semantics,
      'rules in ARCHITECTURE.md §7.2',
    ),
  ];

  const words = _countedInWords;
  const spell = _spell;

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
    ].map((String at) => File('${repositoryRoot.path}/$at')),
    ..._prosePages(),
  ]) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    for (final (pattern, expected, what) in claims) {
      for (final match in pattern.allMatches(source)) {
        final want = expected(match);
        // Both halves of "eighteen of the twenty-six", when the phrasing has
        // two: the second is the total and drifts on its own.
        final said = <(String, int)>[
          (match.group(1)!, want),
          if (match.groupCount > 1 && match.group(2) != null)
            (match.group(2)!, total),
        ];
        for (final (claim, against) in said) {
          final number =
              int.tryParse(claim) ?? words.indexOf(claim.toLowerCase());
          // Not a number at all — "the checks, against a backend" — so not a
          // claim about how many there are.
          if (number < 0) continue;
          if (number != against) {
            found.add(
              Finding(
                _inRepository(file),
                'says $claim $what; there are ${spell(against)}',
              ),
            );
          }
        }
      }
    }
  }
  return found;
}

/// Numbers as the documents spell them, because a doc comment says "eighteen"
/// and not "18" — and a word is exactly the kind of number nobody recounts.
const List<String> _countedInWords = <String>[
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'twenty-one',
  'twenty-two', 'twenty-three', 'twenty-four', 'twenty-five', 'twenty-six',
  'twenty-seven', 'twenty-eight', 'twenty-nine', 'thirty', 'thirty-one',
  'thirty-two', 'thirty-three', 'thirty-four', 'thirty-five', 'thirty-six',
  'thirty-seven', 'thirty-eight', 'thirty-nine', 'forty',
];

/// A count said both ways, so a finding can be read and searched for.
String _spell(int n) =>
    n < _countedInWords.length ? '$n (${_countedInWords[n]})' : '$n';

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

  final claim = RegExp(r'[Tt]he ([\w-]+) enums in `formats\.dart`');
  return <Finding>[
    for (final at in <String>['ARCHITECTURE.md', 'README.md'])
      if (File('${repositoryRoot.path}/$at').existsSync())
        for (final match in claim.allMatches(
          File('${repositoryRoot.path}/$at').readAsStringSync(),
        ))
          if ((int.tryParse(match.group(1)!) ??
                  _countedInWords.indexOf(match.group(1)!.toLowerCase())) !=
              declared.length)
            Finding(
              at,
              'says ${match.group(1)} enums in formats.dart; there are '
              '${_spell(declared.length)} — ${declared.join(', ')}',
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
/// A test already keeps `kRequiredShaders` and the bundle manifest in step with
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

  final claim = RegExp(r'([\w-]+) shader entry points');
  for (final prose in _prosePages()) {
    for (final match in claim.allMatches(prose.readAsStringSync())) {
      final said = match.group(1)!;
      final number =
          int.tryParse(said) ?? _countedInWords.indexOf(said.toLowerCase());
      if (number < 0) continue;
      if (number != required.length) {
        found.add(
          Finding(
            _inRepository(prose),
            'says $said shader entry points; there are '
            '${_spell(required.length)}',
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

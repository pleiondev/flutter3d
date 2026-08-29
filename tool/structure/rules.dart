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
  (name: 'the hardware layer names no graphics API', run: _hardwareNamesNoApi),
  (name: 'the engine names no backend', run: _engineNamesNoBackend),
  (name: 'each assembly has one home per application', run: _oneAssembly),
  (name: 'no test builds its own world', run: _noHarnessAssembly),
  (name: 'the repository lists agree with the workspace', run: _listsAgree),
  (name: 'every exemption names a file that is there', run: _exemptionsResolve),
  (name: 'no application silences a print', run: _noSilencedPrints),
  (
    name: 'the Impeller conformance runner is reachable',
    run: _conformanceRunner,
  ),
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
  (name: 'the documents agree on how many rules there are', run: _ruleCount),
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
  return found;
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

List<Finding> _conformanceRunner() {
  // Flutter GPU needs Impeller, which a headless `flutter test` does not
  // enable, so this backend's conformance runs from a script driving an
  // application. A pointer that has rotted is worse than no pointer.
  final found = <Finding>[];
  final dir = packages['flutter3d_impeller'];
  if (dir == null) {
    return <Finding>[const Finding('flutter3d_impeller', 'is not there')];
  }

  final script = File('${dir.path}/tool/conformance.sh');
  if (!script.existsSync()) {
    return <Finding>[
      const Finding(
        'flutter3d_impeller/tool/conformance.sh',
        'is how this backend is checked, and it is not there',
      ),
    ];
  }
  // The owner-execute bit, which is a POSIX idea. Windows reports a mode of
  // nought for every file, so asking there would fail this rule on a machine
  // that cannot run a shell script in the first place — a false red about
  // something the developer could not act on.
  if (!Platform.isWindows && script.statSync().mode & 0x40 == 0) {
    found.add(
      const Finding(
        'flutter3d_impeller/tool/conformance.sh',
        'is not executable, so the one thing that runs the checks cannot run',
      ),
    );
  }

  final source = script.readAsStringSync();
  if (!source.contains('lib/conformance_main.dart')) {
    found.add(
      const Finding(
        'flutter3d_impeller/tool/conformance.sh',
        'no longer names the entry point it drives',
      ),
    );
  }

  final app = File(
    '${repositoryRoot.path}/packages/flutter3d/example/lib/conformance_main.dart',
  );
  if (!app.existsSync()) {
    found.add(
      const Finding(
        'flutter3d/example/lib/conformance_main.dart',
        'the script drives an entry point that is not there',
      ),
    );
    return found;
  }
  final appSource = app.readAsStringSync();
  if (!appSource.contains('passed, ')) {
    found.add(
      const Finding(
        'flutter3d/example/lib/conformance_main.dart',
        'no longer prints the line the script reads its verdict from',
      ),
    );
  }
  if (!appSource.contains('exit(')) {
    found.add(
      const Finding(
        'flutter3d/example/lib/conformance_main.dart',
        'no longer exits with a code, so the script would wait for ever',
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
  var counted = 0;
  for (final dir in <Directory>[
    for (final p in packages.values) Directory('${p.path}/test'),
    for (final p in packages.values) Directory('${p.path}/example/test'),
    for (final a in apps.values) Directory('${a.path}/test'),
  ]) {
    for (final file in dartFilesIn(dir)) {
      counted += file.readAsLinesSync().where(declaration.hasMatch).length;
    }
  }

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
List<Finding> _shaderBundleIsCurrent() {
  final dir = packages['flutter3d_impeller'];
  if (dir == null) {
    return <Finding>[const Finding('flutter3d_impeller', 'is not there')];
  }

  final bundle = File('${dir.path}/assets/shaders/flutter3d.shaderbundle');
  if (!bundle.existsSync()) return const <Finding>[];

  final sources = packages['flutter3d_shaders'];
  if (sources == null) {
    return <Finding>[const Finding('flutter3d_shaders', 'is not there')];
  }

  final built = bundle.lastModifiedSync();
  final newer = <String>[];
  for (final file in Directory(
    '${sources.path}/shaders',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.frag') &&
        !file.path.endsWith('.vert') &&
        !file.path.endsWith('.glsl')) {
      continue;
    }
    if (file.lastModifiedSync().isAfter(built)) {
      newer.add(file.path.split('/').last);
    }
  }
  if (newer.isEmpty) return const <Finding>[];

  newer.sort();
  return <Finding>[
    Finding(
      'flutter3d_impeller/assets/shaders/flutter3d.shaderbundle',
      'is older than ${newer.length} of its sources '
          '(${newer.take(4).join(', ')}${newer.length > 4 ? ', …' : ''}). '
          'Rebuild it: (cd packages/flutter3d_impeller && '
          './tool/build_shaders.sh). Until then an application loads the stage '
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
/// nonetheless reports all twenty-three "ready", which is one command away from
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
      if (asked != sibling.value) {
        found.add(
          Finding(
            where,
            'asks for ${sibling.key} ^$asked, which declares ${sibling.value}. '
            'A workspace resolves that from the checkout whatever it says; a '
            'server would not',
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

  final word = _numberWords[count];
  final found = <Finding>[];
  // The site tells the same story on half a dozen pages, and its testing page
  // was still saying "thirty scenes" two recounts later — so the prose pages
  // are scanned along with the scripts and ARCHITECTURE.md.
  final files = <File>[
    for (final where in <String>[
      'tool/ci.sh',
      'packages/flutter3d_webgl/tool/golden_web.sh',
      'ARCHITECTURE.md',
    ])
      File('${repositoryRoot.path}/$where'),
    ..._prosePages(),
  ];
  for (final file in files) {
    final where = _inRepository(file);
    if (!file.existsSync()) {
      found.add(Finding(where, 'is not there'));
      continue;
    }
    final text = file.readAsStringSync();
    // Only the phrasings that are actually about the scenes, so a stray "32"
    // elsewhere in a long document is not a false positive.
    final claims = RegExp(
      r'([\w-]+) (?:golden )?scenes',
      caseSensitive: false,
    ).allMatches(text).map((RegExpMatch m) => m.group(1)!).toSet();
    for (final claim in claims) {
      if (claim == '$count' || claim.toLowerCase() == word) continue;
      // A word that is not a number at all — "the scenes", "thirty-two golden
      // scenes" already matched — is not a claim about how many there are.
      if (int.tryParse(claim) == null &&
          !_numberWords.containsValue(claim.toLowerCase())) {
        continue;
      }
      found.add(
        Finding(where, 'says "$claim scenes"; there are $count ($word)'),
      );
    }
  }
  return found;
}

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

/// Where a file is, said the way a finding says it: relative to the root.
String _inRepository(File file) =>
    file.path.substring(repositoryRoot.path.length + 1);

/// Enough of them to name the counts this repository actually writes down.
const Map<int, String> _numberWords = <int, String>{
  24: 'twenty-four',
  25: 'twenty-five',
  26: 'twenty-six',
  27: 'twenty-seven',
  28: 'twenty-eight',
  29: 'twenty-nine',
  30: 'thirty',
  31: 'thirty-one',
  32: 'thirty-two',
  33: 'thirty-three',
  34: 'thirty-four',
  35: 'thirty-five',
  36: 'thirty-six',
};

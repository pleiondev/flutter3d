/// Two rules about where a public name lives and who may reach a library
/// that is not the package's public face: the detectors, and the lists of
/// what is allowed on purpose.
///
/// Plain Dart over strings, like `layers.dart`: the detectors take the facts
/// as arguments, so `proveDetectorsWork` can run them on a made-up tree
/// before the real one is read.
library;

import 'api.dart';

/// Every public name the snapshots in [snapshots] (each package's
/// `api/<package>.api`, by package) declare, with the packages declaring
/// it. A name a package re-exports is not a declaration of that package's,
/// and a name declared in two libraries of one package is one home.
Map<String, Set<String>> publicNameHomes(Map<String, String> snapshots) {
  final homes = <String, Set<String>>{};
  for (final MapEntry(key: package, value: text) in snapshots.entries) {
    for (final library in parseApi(text).values) {
      for (final name in library.declarations.keys) {
        if (name.isEmpty || name.startsWith('_')) continue;
        (homes[name] ??= <String>{}).add(package);
      }
    }
  }
  return homes;
}

/// The names of [homes] declared by more than one package, each with its
/// packages in order, leaving out those [allowed] names.
///
/// **A public name has one home across the published packages.** Two
/// `Brush`es, two `EnumHint`s, two `engineShaders` made every file that
/// needed both write `hide` or `as`, and made a reader of one package's
/// documentation meet the other's type under the same word. The more
/// specific of the two takes a name that says what it is.
List<(String, List<String>)> namesWithTwoHomes(
  Map<String, Set<String>> homes, {
  required Map<String, String> allowed,
}) => <(String, List<String>)>[
  for (final name in homes.keys.toList()..sort())
    if (homes[name]!.length > 1 && !allowed.containsKey(name))
      (name, homes[name]!.toList()..sort()),
];

/// Names more than one published package may declare, each with why.
///
/// Empty: every duplicate the boundary work found was renamed or given one
/// home (move 13 of `tasks/1.0-boundaries.md`). A name goes here only when
/// two packages that are never imported together must both use it, and the
/// reason says so; an entry no longer declared twice is a finding.
const Map<String, String> publicNameSharedOnPurpose = <String, String>{};

/// The libraries named `internal.dart`, `builtin.dart` or `testing.dart`
/// that [source] imports or exports, as their `package:` URIs. Only
/// directives at the start of a line count; a doc comment showing one is
/// prose.
Set<String> restrictedLibrariesIn(String source) => <String>{
  for (final match in RegExp(
    r"""^\s*(?:import|export)\s+['"](package:\w+/(?:internal|builtin|testing)\.dart)['"]""",
    multiLine: true,
  ).allMatches(source))
    match.group(1)!,
};

/// The package a `package:` [uri] is in.
String packageOfUri(String uri) =>
    uri.substring('package:'.length, uri.indexOf('/'));

/// What is wrong with [uses] (each package's shipped code — `lib/` and
/// `bin/` — with the restricted libraries it reaches) against [allowed], as
/// `(package, library, why)`.
///
/// **`internal.dart`, `builtin.dart` and `testing.dart` are not a package's
/// public face.** They are there so the engine's own packages can share
/// what a game should not build on: the shader sources the renderers
/// compile, the software device's built-in stages, a device set up the way
/// a test wants one. A test may import any of them; shipped code imports
/// one only when [allowed] names its package for that library, with the
/// reason. A package importing its own is its own business.
List<(String, String, String)> restrictedLibraryProblems(
  Map<String, Set<String>> uses, {
  required Map<String, Map<String, String>> allowed,
}) => <(String, String, String)>[
  for (final package in uses.keys.toList()..sort())
    for (final library in uses[package]!.toList()..sort())
      if (packageOfUri(library) != package &&
          allowed[library]?[package] == null)
        (
          package,
          library,
          'is not the public face of ${packageOfUri(library)}: shipped code '
              'reaches it only when `restrictedLibraryUsers` '
              '(tool/structure/boundaries.dart) names the package, with its '
              'reason; a test may import it anywhere',
        ),
];

/// Who outside the package may reach each restricted library from shipped
/// code, and why.
const Map<String, Map<String, String>> restrictedLibraryUsers =
    <String, Map<String, String>>{
      'package:flutter3d_shaders/internal.dart': <String, String>{
        'flutter3d_core':
            'the renderer binds the engine\'s own shader sources by name',
        'flutter3d_cpu':
            'a backend: the software device ports the engine\'s shaders',
        'flutter3d_impeller':
            'a backend: it loads the engine\'s shaders as compiled bundles',
        'flutter3d_webgl':
            'a backend: it compiles the engine\'s shaders as GLSL ES',
        'flutter3d_webgpu':
            'a backend: it compiles the engine\'s shaders as WGSL',
      },
      'package:flutter3d_cpu/builtin.dart': <String, String>{
        'flutter3d_app':
            'the material language previews a material on the software '
            'device through its built-in stages',
      },
      'package:flutter3d_cpu/testing.dart': <String, String>{
        'flutter3d_testing':
            'the test harness: a frame rendered the way a test wants one',
        'flutter3d_editor_core':
            'the light optimiser shades a level on a software device set up '
            'as a headless one is',
        'flutter3d_mcp':
            'an agent\'s view of a level is drawn headless, on the software '
            'device',
        'flutter3d_sim_mcp':
            'the diagnostic frame an agent asks for is drawn headless, on '
            'the software device',
      },
      'package:flutter3d_hardware/testing.dart': <String, String>{
        'flutter3d_build':
            'the plugin template writes a render test that imports it; the '
            'import is in the template\'s text, not in the tool',
      },
    };

// ------------------------------------------------------------- re-exports

/// The re-exports of another package of the repository a package may make,
/// as `'<package> -> <re-exported package>'`, each with why (rule 3 of
/// `tasks/1.0-boundaries.md`).
///
/// **A re-export is a dependency the reader does not see.** `flutter3d_sim`
/// re-exported about eighty-five names of the physics, so some two hundred
/// files in twenty packages named `CollisionWorld` through the simulation,
/// and nine packages used the physics without depending on it. Step C took
/// every such re-export out but these: the one facade a game is written
/// against, the shell over the core it was split from, and three packages
/// whose own API is the other's. A new entry is a decision taken in review,
/// with its sentence; an entry nothing re-exports any more is a finding.
const Map<String, String> reexportsAllowed = <String, String>{
  'flutter3d_game -> flutter3d':
      'the one facade: a first game takes two imports, Flutter\'s and this',
  'flutter3d_game -> flutter3d_app':
      'the one facade: the view a game opens a window with, by name',
  'flutter3d_game -> flutter3d_sim':
      'the one facade: the level, the step loop and its input, by name',
  'flutter3d_game -> flutter3d_physics':
      'the one facade: the collision world a first game walks, by name',
  'flutter3d_game -> flutter3d_audio_core':
      'the one facade: the listener, the emitters and the sound bank, by '
      'name',
  'flutter3d -> flutter3d_core':
      'the Flutter shell over the core split out of it: its barrel names '
      'what an application spells of the core, so the two are one API',
  'flutter3d -> flutter3d_hardware':
      'the shell\'s API is written in the graphics vocabulary (a '
      '`RenderMaterial` holds a `SamplerDescriptor`), named, and never a '
      'backend',
  'flutter3d -> flutter3d_foundation':
      'the colour, the position and the exception roots the shell\'s API '
      'and the core\'s are written in, named',
  'flutter3d_plugin_api -> flutter3d_foundation':
      'the value types the contract\'s signatures name, so a plugin sees '
      'the contract from one import',
  'flutter3d_audio -> flutter3d_audio_core':
      'the documented facade over the audio model: the SoLoud backend and '
      'the model it plays are one import, named',
  'flame_multiplayer -> flutter3d_net':
      'the wire, the room and the rollback moved from here to the network '
      'core before 1.0, and are still named from here',
};

/// Allowed re-exports that admit a whole library rather than a `show`
/// list, each with why. Every other allowed re-export names what it
/// admits, so a name added to the package underneath is not the facade's
/// until somebody lists it.
const Map<String, String> reexportedWhole = <String, String>{
  'flutter3d_game -> flutter3d':
      'the shell\'s barrel is itself a list of names, and the facade is the '
      'shell and more',
};

/// The `export 'package:…'` directives of [source], as each one's URI and
/// whether it names what it admits (`show`). Only directives at the start
/// of a line count; a doc comment showing one is prose.
List<({String uri, bool named})> packageExportsIn(String source) =>
    <({String uri, bool named})>[
      for (final match in RegExp(
        r"""^export\s+['"](package:[^'"]+)['"]([^;]*);""",
        multiLine: true,
      ).allMatches(source))
        (
          uri: match.group(1)!,
          named: RegExp(r'\bshow\b').hasMatch(match.group(2)!),
        ),
    ];

/// What is wrong with [exports] (each package's `lib/` files, by package,
/// with the package exports each makes) against [allowed] and [whole], as
/// `(package, file, why)`: a re-export of another package of [repository]
/// that [allowed] does not name, or one it names that admits a whole
/// library [whole] does not allow. A package re-exporting its own libraries,
/// or one from pub.dev, is not asked about.
List<(String, String, String)> reexportProblems(
  Map<String, Map<String, List<({String uri, bool named})>>> exports, {
  required Set<String> repository,
  required Map<String, String> allowed,
  required Map<String, String> whole,
}) => <(String, String, String)>[
  for (final package in exports.keys.toList()..sort())
    for (final file in exports[package]!.keys.toList()..sort())
      for (final export in exports[package]![file]!)
        if (packageOfUri(export.uri) case final target
            when target != package && repository.contains(target))
          if (!allowed.containsKey('$package -> $target'))
            (
              package,
              file,
              're-exports $target: a package re-exports another\'s API only '
                  'where `reexportsAllowed` (tool/structure/boundaries.dart) '
                  'says so, with the reason; a caller that needs $target '
                  'imports it and depends on it',
            )
          else if (!export.named && !whole.containsKey('$package -> $target'))
            (
              package,
              file,
              're-exports the whole of ${export.uri}: an allowed re-export '
                  'names what it admits with `show`',
            ),
];

/// Rule 2 of `tasks/1.0-boundaries.md`: the dependencies among
/// [dependencies] (each package's run-time sibling dependencies) that its
/// shipped code only re-exports — named by an `export` of [exported] and by
/// no `import` of [imported] — and that [allowed] does not name, as
/// `(package, dependency)`.
///
/// **A dependency held only to hand it on is the facade the rules forbid.**
/// `flutter3d` depended on the simulation, the physics and the audio's
/// model for nothing but three re-exports; a game reading its pubspec saw
/// an engine that needed all three.
List<(String, String)> reexportOnlyDependencies(
  Map<String, Set<String>> dependencies, {
  required Map<String, Set<String>> imported,
  required Map<String, Set<String>> exported,
  required Map<String, String> allowed,
}) => <(String, String)>[
  for (final package in dependencies.keys.toList()..sort())
    for (final dependency in dependencies[package]!.toList()..sort())
      if ((exported[package]?.contains(dependency) ?? false) &&
          !(imported[package]?.contains(dependency) ?? false) &&
          !allowed.containsKey('$package -> $dependency'))
        (package, dependency),
];

/// The capitalised identifiers [source] names in code — not in a comment
/// and not in a string — and the ones it declares itself, as type names.
///
/// A plain scan, not a parser: a name in a string's interpolation is
/// skipped with the string, which only ever lets a use through.
({Set<String> named, Set<String> declared}) typeNamesIn(String source) {
  final code = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      continue;
    }
    if (c == '/' && next == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = source.startsWith('$c$c$c', i);
      final quote = triple ? '$c$c$c' : c;
      final raw = i > 0 && source[i - 1] == 'r';
      var j = i + quote.length;
      while (j < source.length) {
        if (!raw && source[j] == r'\') {
          j += 2;
          continue;
        }
        if (source.startsWith(quote, j)) break;
        if (!triple && source[j] == '\n') break;
        j++;
      }
      code.write(' ');
      i = j + quote.length;
      continue;
    }
    code.write(c);
    i++;
  }
  final text = code.toString();
  return (
    named: <String>{
      for (final m in RegExp(r'(?<![\w$.])([A-Z][\w$]*)').allMatches(text))
        m.group(1)!,
    },
    declared: <String>{
      for (final m in RegExp(
        r'\b(?:class|mixin|enum|typedef|extension\s+type|extension)\s+([A-Z][\w$]*)',
      ).allMatches(text))
        m.group(1)!,
    },
  );
}

/// Rule 4 of `tasks/1.0-boundaries.md`, declare what you name: the type
/// names each file of [named] (by package, then file) names that another
/// package of [homes] declares, when the package declares no type of that
/// name itself ([declared]) and neither depends on that one
/// ([dependencies]) nor on a package whose allowed re-exports carry the
/// name ([carried]), as `(package, file, name, home)`. A name of [sdk] — a
/// package outside the repository declares one too — is not asked about.
///
/// **A name is reached through the pubspec, not around it.** A file that
/// spells `CollisionWorld` uses `flutter3d_physics`, whatever it imported
/// it through, and a package that does not say so resolves the physics by
/// luck — until the package it came through stops handing it on. A facade
/// on the allow list is the one way around: what `flutter3d_game` carries
/// is a game's to name.
List<(String, String, String, String)> undeclaredNames(
  Map<String, Map<String, Set<String>>> named, {
  required Map<String, Set<String>> declared,
  required Map<String, String> homes,
  required Map<String, Set<String>> dependencies,
  required Map<String, Set<String>> carried,
  required Map<String, String> sdk,
}) => <(String, String, String, String)>[
  for (final package in named.keys.toList()..sort())
    for (final file in named[package]!.keys.toList()..sort())
      for (final name in named[package]![file]!.toList()..sort())
        if (homes[name] case final home?
            when home != package &&
                !sdk.containsKey(name) &&
                !(declared[package]?.contains(name) ?? false) &&
                !(dependencies[package]?.contains(home) ?? false) &&
                !(dependencies[package] ?? const <String>{}).any(
                  (String via) => carried[via]?.contains(name) ?? false,
                ))
          (package, file, name, home),
];

/// Type names a package of the repository declares that the Dart or Flutter
/// SDK, or a package from pub.dev, declares too, each with where: a file
/// that names one is as likely to mean the other, and [undeclaredNames]
/// cannot tell which without the resolver. An entry no package declares any
/// more is a finding.
const Map<String, String> typeNamesDeclaredOutside = <String, String>{
  'Match': '`dart:core`, the result of a `RegExp`',
  'Key': 'Flutter\'s widget key',
  'Link': 'Flutter\'s `widgets.dart`, a link a screen reader announces',
  'PluginRegistry':
      '`analysis_server_plugin`, which the lints\' analyzer plugin registers '
      'its rules with',
};

/// Every generator that writes a document the repository ships, by the name
/// the documents know it by.
///
/// **Keyed by the path the document names, resolved.** A document's
/// `generatedBy` is part of the document and so of its digest, which recorded
/// runs are checked against — so the documents keep naming the scripts that
/// first wrote them, and this table is where each of those names now leads.
/// A name is resolved the way it always was: against the application that
/// owns the document first, then the repository root (see [generatorFor]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

import 'dungeon.dart' as dungeon;

import 'platformer.dart' as platformer;
import 'racing.dart' as racing;
import 'strategy.dart' as strategy;
import 'templates.dart' as templates;

/// The generators, by repository-relative script path, in the order they run.
///
/// **The order is load-bearing once:** the templates read the strategy map, so
/// the map's generator runs first. Sorted by path it does, as it always did.
final Map<String, LevelGenerator> shippedGenerators = <String, LevelGenerator>{
  'apps/flutter3d_demo_dungeon/tool/make_cistern.py': dungeon.cistern,
  'apps/flutter3d_demo_dungeon/tool/make_crypt.py': dungeon.crypt,
  'apps/flutter3d_demo_dungeon/tool/make_deep.py': dungeon.deep,
  'apps/flutter3d_demo_dungeon/tool/make_sanctum.py': dungeon.sanctum,
  'apps/flutter3d_demo_dungeon/tool/make_vaults.py': dungeon.vaults,
  'apps/flutter3d_demo_platformer/tool/make_cisterns.py': platformer.cisterns,
  'apps/flutter3d_demo_platformer/tool/make_first_steps.py':
      platformer.firstSteps,
  'apps/flutter3d_demo_platformer/tool/make_foundry.py': platformer.foundry,
  'apps/flutter3d_demo_platformer/tool/make_level.py': platformer.ascent,
  'apps/flutter3d_demo_platformer/tool/make_spire.py': platformer.spire,
  'apps/flutter3d_demo_racing/tool/make_track.py': racing.tracks,
  'apps/flutter3d_demo_strategy/tool/make_map.py': strategy.map,
  'tool/make_templates.py': templates.templates,
};

/// The key in [shippedGenerators] for a document at [document] (relative to
/// the root) that says it was written by [generatedBy], or null when the name
/// leads nowhere — which is an error for the caller to report, because a
/// document naming a generator nobody can find is exactly the drift the
/// regeneration check exists for.
String? generatorFor(String document, String generatedBy) {
  final owner = document.split('/').take(2).join('/');
  for (final candidate in <String>['$owner/$generatedBy', generatedBy]) {
    if (shippedGenerators.containsKey(candidate)) return candidate;
  }
  return null;
}

/// The files under a checkout, for a generator to read.
final class CheckoutSource implements GeneratorSource {
  const CheckoutSource(this.root);

  /// The repository root.
  final String root;

  @override
  String read(String path) => File('$root/$path').readAsStringSync();

  @override
  List<String> list(String directory) {
    final names = <String>[
      for (final entity in Directory('$root/$directory').listSync())
        if (entity is File) entity.uri.pathSegments.last,
    ]..sort();
    return names;
  }
}

/// The repository root above [from]: the first directory whose pubspec
/// declares the workspace.
String repositoryRoot(String from) {
  var dir = Directory(from).absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no workspace pubspec above $from');
    }
    dir = parent;
  }
}

/// Every tracked document that names a generator, grouped by the generator it
/// resolves to. Throws on a name that resolves to none.
///
/// `git ls-files` rather than a walk, because `build/` is full of copies of
/// these documents and a walk would count each once per platform that had
/// ever been built.
Map<String, List<String>> trackedDocuments(String root) {
  final listed = Process.runSync('git', <String>[
    'ls-files',
    'apps/*/assets/**/*.json',
    'apps/*/assets/*.json',
  ], workingDirectory: root);
  if (listed.exitCode != 0) {
    throw StateError('git ls-files failed: ${listed.stderr}');
  }
  final found = <String, List<String>>{};
  for (final path in (listed.stdout as String? ?? '').split('\n')) {
    if (path.isEmpty) continue;
    final text = File('$root/$path').readAsStringSync();
    // Cheap first: a texture atlas or an icon table need not be parsed.
    if (!text.contains('"generatedBy"')) continue;
    final named = (jsonDecode(text) as Map<String, Object?>)['generatedBy'];
    if (named is! String || named.isEmpty) continue;
    final key = generatorFor(path, named);
    if (key == null) {
      throw StateError(
        '$path says it was written by "$named", and no generator by that '
        'name is registered for ${path.split('/').take(2).join('/')} or the '
        'repository root',
      );
    }
    (found[key] ??= <String>[]).add(path);
  }
  return found;
}

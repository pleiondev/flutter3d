/// Applies every migration from flutter3d 0.8 that needs the resolved code,
/// across a project: the quick fixes the `flutter3d_migrate` diagnostics
/// offer one at a time in the editor, all at once.
///
/// ```
/// dart pub global run flutter3d_lints:migrate [--dry-run] [--json] <project>
/// ```
///
/// `dart run flutter3d_build:migrate` runs this after `dart fix`, which
/// cannot apply a plugin's fixes in bulk. What it does to each Dart file of
/// the project:
///
///  * rewrites each use a `rewrite` entry describes — `device.supportsStencil`
///    to `device.features.has(DeviceFeature.stencil)` — importing what the
///    rewrite names when the library cannot see it yet;
///  * moves a type 1.0 made a `base mixin class` from `implements` to
///    `with`, and makes the class `base`;
///  * hides, on the flutter3d import, a name 1.0 started exporting that the
///    project declares itself — the ambiguous import a new name causes;
///  * puts a `// TODO(flutter3d-1.0):` above each use a person has to
///    change, with the guide's link, and lists it.
///
/// The project has to resolve against 1.0 already — `pub get` after the
/// constraints moved — or there is nothing to resolve the uses against.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter3d_lints/src/migration/migration_rule.dart';
import 'package:flutter3d_lints/src/migration/migration_scan.dart';
import 'package:flutter3d_lints/src/migration/table.g.dart';

const String _usage = '''
Applies the flutter3d 1.0 migrations that need the resolved code.

  dart run flutter3d_lints:migrate [--dry-run] [--json] <project dir>

  --rules=<file>  check against the rules in this JSON file (a list of
                  what flutter3d_build's lintsRules writes) instead of
                  the shipped table: how a test runs a table of its own
''';

Future<void> main(List<String> args) async {
  final paths = args.where((String a) => !a.startsWith('--')).toList();
  if (paths.length != 1 || args.contains('--help')) {
    stderr.write(_usage);
    exitCode = 2;
    return;
  }
  final dryRun = args.contains('--dry-run');
  final json = args.contains('--json');
  final rulesFile = args
      .where((String a) => a.startsWith('--rules='))
      .map((String a) => a.substring('--rules='.length))
      .firstOrNull;
  final rules = rulesFile == null
      ? migrationRules
      : <MigrationRule>[
          for (final r
              in jsonDecode(File(rulesFile).readAsStringSync())
                  as List<Object?>)
            MigrationRule.fromJson(r! as Map<String, Object?>),
        ];
  final project = Directory(paths.single).absolute;
  // Absolute and normalised, with no trailing separator, as the analyzer
  // wants it; the reports are relative to it.
  var normalised = project.uri.normalizePath().toFilePath();
  while (normalised.length > 1 && normalised.endsWith(Platform.pathSeparator)) {
    normalised = normalised.substring(0, normalised.length - 1);
  }
  final collection = AnalysisContextCollection(
    includedPaths: <String>[normalised],
  );
  final root = '$normalised${Platform.pathSeparator}';
  final separator = Platform.pathSeparator;

  // Two passes: a part file's imports live in its library's file, so what a
  // part needs imported or hidden is asked of the library and written there.
  final work = _Work();
  final units = <String, ResolvedUnitResult>{};
  for (final context in collection.contexts) {
    final files =
        context.contextRoot
            .analyzedFiles()
            .where(
              (String p) =>
                  p.endsWith('.dart') &&
                  !p.contains('$separator.dart_tool$separator') &&
                  !p.contains('${separator}build$separator'),
            )
            .toList()
          ..sort();
    for (final path in files) {
      final result = await context.currentSession.getResolvedUnit(path);
      if (result is! ResolvedUnitResult) continue;
      units[path] = result;
      _scan(result, work, rules);
    }
  }
  for (final MapEntry(key: path, value: names) in work.hide.entries) {
    if (units[path] case final unit?) _hideNewNames(unit, names, work);
  }
  for (final MapEntry(key: path, value: uris) in work.imports.entries) {
    if (units[path] case final unit?) _addImports(unit, uris, work);
  }
  await collection.dispose();

  final reports = <Map<String, Object?>>[];
  for (final path in <String>{
    ...work.edits.keys,
    ...work.manual.keys,
  }.toList()..sort()) {
    final source = units[path]!.content;
    final text = _apply(source, work.edits[path] ?? const <MigrationEdit>[]);
    reports.add(<String, Object?>{
      'file': path.startsWith(root) ? path.substring(root.length) : path,
      'applied': work.applied[path] ?? const <String>[],
      'manual': work.manual[path] ?? const <Map<String, Object?>>[],
      'hidden': (work.hidden[path] ?? const <String>{}).toList()..sort(),
    });
    if (!dryRun && text != source) File(path).writeAsStringSync(text);
  }

  if (json) {
    for (final r in reports) {
      stdout.writeln(jsonEncode(r));
    }
    return;
  }
  for (final r in reports) {
    final applied = r['applied']! as List<Object?>;
    final manual = r['manual']! as List<Object?>;
    final hidden = r['hidden']! as List<Object?>;
    stdout.writeln(
      '${r['file']}: ${applied.length} rewritten, ${manual.length} to do'
      '${hidden.isEmpty ? '' : ', hid ${hidden.join(', ')}'}',
    );
    for (final m in manual.cast<Map<String, Object?>>()) {
      stdout.writeln('  line ${m['line']}: ${m['message']} ${m['link']}');
    }
  }
}

/// What the passes collect, by file path.
final class _Work {
  final Map<String, List<MigrationEdit>> edits =
      <String, List<MigrationEdit>>{};
  final Map<String, List<String>> applied = <String, List<String>>{};
  final Map<String, List<Map<String, Object?>>> manual =
      <String, List<Map<String, Object?>>>{};

  /// Library file to the names its imports have to hide.
  final Map<String, Set<String>> hide = <String, Set<String>>{};

  /// Library file to the imports a part of it needs.
  final Map<String, Set<String>> imports = <String, Set<String>>{};

  /// Library file to the names hidden in it.
  final Map<String, Set<String>> hidden = <String, Set<String>>{};

  void edit(String path, MigrationEdit e) =>
      (edits[path] ??= <MigrationEdit>[]).add(e);
}

String _libraryPathOf(ResolvedUnitResult unit) =>
    unit.libraryElement.firstFragment.source.fullName;

/// The first pass over [unit]: its findings, and what its library has to
/// import or hide for it.
void _scan(ResolvedUnitResult unit, _Work work, List<MigrationRule> rules) {
  final path = unit.path;
  final source = unit.content;
  final isPart = unit.unit.directives.any(
    (Directive d) => d is PartOfDirective,
  );
  final library = _libraryPathOf(unit);
  final todos = <(int, String)>{};
  for (final f in scanForMigrations(unit.unit, source, rules)) {
    if (f.automatic) {
      for (final e in f.edits) {
        final import = RegExp(r"import '([^']+)';").firstMatch(e.replacement);
        if (import != null && e.length == 0) {
          // Asked of the library, which the second pass writes once.
          (work.imports[library] ??= <String>{}).add(import.group(1)!);
        } else {
          work.edit(path, e);
        }
      }
      (work.applied[path] ??= <String>[]).add(f.rule.id);
      continue;
    }
    // An earlier run's TODO stays the one TODO.
    final already = source
        .substring(0, f.todo.offset)
        .endsWith(f.todo.replacement);
    if (!already && todos.add((f.todo.offset, f.rule.id))) {
      work.edit(path, f.todo);
    }
    (work.manual[path] ??= <Map<String, Object?>>[]).add(<String, Object?>{
      'id': f.rule.id,
      'line': unit.lineInfo.getLocation(f.offset).lineNumber,
      'message': f.rule.message,
      'link': f.rule.link,
    });
  }
  for (final d in unit.diagnostics) {
    if (d.diagnosticCode.lowerCaseName != 'ambiguous_import') continue;
    final name = source
        .substring(d.offset, d.offset + d.length)
        .split('.')
        .last;
    (work.hide[library] ??= <String>{}).add(name);
  }
  if (!isPart) work.edits.putIfAbsent(path, () => <MigrationEdit>[]);
  if (work.edits[path]?.isEmpty ?? false) work.edits.remove(path);
}

/// Hides [names] on the flutter3d imports of library [unit] that bring
/// them, where the clash is with the project's own code: a name 1.0 began
/// to export that the project already had.
void _hideNewNames(ResolvedUnitResult unit, Set<String> names, _Work work) {
  final hides = <ImportDirective, Set<String>>{};
  final imports = unit.unit.directives.whereType<ImportDirective>().toList();
  for (final name in names) {
    final ours = <ImportDirective>[];
    var theirs = false;
    for (final d in imports) {
      final library = d.libraryImport?.importedLibrary;
      if (library == null || library.exportNamespace.get2(name) == null) {
        continue;
      }
      final uri = d.uri.stringValue ?? '';
      final package = uri.startsWith('package:')
          ? uri.substring(8).split('/').first
          : '';
      if (ownedPackage(package)) {
        ours.add(d);
      } else {
        theirs = true;
      }
    }
    final declaredHere = unit.libraryElement.children.any(
      (e) => e.name == name,
    );
    // Two flutter3d libraries clashing is the engine's to fix, not this
    // tool's: hide only against the project's own name.
    if (ours.isEmpty || (!theirs && !declaredHere)) continue;
    for (final d in ours) {
      if (d.combinators.any((Combinator c) => c is ShowCombinator)) continue;
      (hides[d] ??= <String>{}).add(name);
    }
  }
  for (final MapEntry(key: d, value: hide) in hides.entries) {
    final sorted = hide.toList()..sort();
    final existing = d.combinators.whereType<HideCombinator>().firstOrNull;
    work.edit(
      unit.path,
      existing != null
          ? MigrationEdit(existing.end, 0, ', ${sorted.join(', ')}')
          : MigrationEdit(d.semicolon.offset, 0, ' hide ${sorted.join(', ')}'),
    );
    (work.hidden[unit.path] ??= <String>{}).addAll(sorted);
  }
}

/// Adds the imports [uris] to library [unit] that it does not have.
void _addImports(ResolvedUnitResult unit, Set<String> uris, _Work work) {
  final directives = unit.unit.directives;
  final have = <String?>{
    for (final d in directives.whereType<ImportDirective>()) d.uri.stringValue,
  };
  final missing = uris.where((String u) => !have.contains(u)).toList()..sort();
  if (missing.isEmpty) return;
  final at = directives.isEmpty ? 0 : directives.last.end;
  final text = missing.map((String u) => "import '$u';").join('\n');
  work.edit(
    unit.path,
    MigrationEdit(at, 0, directives.isEmpty ? '$text\n' : '\n$text'),
  );
}

/// [source] with [edits] applied from the end, skipping one that overlaps
/// an edit already taken.
String _apply(String source, List<MigrationEdit> edits) {
  final sorted = edits.toList()
    ..sort((MigrationEdit a, MigrationEdit b) {
      final c = b.offset.compareTo(a.offset);
      return c != 0 ? c : b.length.compareTo(a.length);
    });
  var text = source;
  var floor = source.length + 1;
  for (final e in sorted) {
    if (e.offset + e.length > floor) continue;
    text = text.replaceRange(e.offset, e.offset + e.length, e.replacement);
    if (e.length > 0) floor = e.offset;
  }
  return text;
}

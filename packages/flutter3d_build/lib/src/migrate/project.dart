/// The `migrate` command's own work on a project — the part neither `dart
/// fix` nor the analyzer plugin can do: the pubspec, and imports of
/// libraries that moved between packages. Then it runs those two and puts
/// one report together.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../plugin_discovery.dart' show pluginMarkerKey;
import 'table.dart';

/// One change to a text, by offset.
typedef TextEdit = ({int offset, int length, String text});

String _apply(String source, List<TextEdit> edits) {
  final sorted = edits.toList()
    ..sort((TextEdit a, TextEdit b) => b.offset.compareTo(a.offset));
  var out = source;
  for (final e in sorted) {
    out = out.replaceRange(e.offset, e.offset + e.length, e.text);
  }
  return out;
}

/// The sections of a pubspec that name packages.
const List<String> dependencySections = <String>[
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

/// [pubspec] with every dependency on a package of [table]'s repository
/// moved to its new constraint, and renamed packages renamed. What it could
/// not move — a path or git dependency, a removed package — goes into
/// [notes] as a sentence.
///
/// **The plugin marker moves too** (decision D of
/// `tasks/1.0-arch-review.md`): a top-level `flutter3d:` key, which `pub
/// publish` warns about because it is named like a package, becomes
/// `flutter3d_plugins:`, with what is under it unchanged. A pubspec that
/// has both keys keeps both, and [notes] says to merge them by hand.
String migratePubspec(
  String pubspec,
  MigrationTable table, {
  required List<String> notes,
}) {
  final doc = loadYaml(pubspec);
  if (doc is! YamlMap) return pubspec;
  final edits = <TextEdit>[];
  // What each section names once the renames are made. Several packages
  // can become one (`flutter3d_addon_hud` and `flutter3d_addon_touch` are
  // both `flutter3d_game_ui`), and a pubspec may name a key once: the first
  // entry is renamed and the rest go, as does a dev dependency on what
  // `dependencies` already has.
  final names = <String, Set<String>>{
    for (final section in dependencySections)
      section: <String>{
        if (doc.nodes[section] case final YamlMap deps)
          for (final k in deps.keys)
            if (!table.renamedPackages.containsKey('$k')) '$k',
      },
  };
  for (final section in dependencySections) {
    final deps = doc.nodes[section];
    if (deps is! YamlMap) continue;
    for (final MapEntry(key: keyNode, value: value) in deps.nodes.entries) {
      final key = keyNode as YamlNode;
      final name = '${key.value}';
      if (!table.owns(name)) continue;
      if (table.removedPackages[name] case final guidance?) {
        notes.add('`$name` is gone in ${table.to}: $guidance');
        continue;
      }
      final renamed = table.renamedPackages[name];
      final target = renamed ?? name;
      if (renamed != null &&
          (names[section]!.contains(renamed) ||
              (section == 'dev_dependencies' &&
                  names['dependencies']!.contains(renamed)))) {
        final start = pubspec.lastIndexOf('\n', key.span.start.offset) + 1;
        final last = value.span.end.offset > key.span.end.offset
            ? value.span.end.offset
            : key.span.end.offset;
        final newline = pubspec.indexOf('\n', last);
        final end = newline < 0 ? pubspec.length : newline + 1;
        edits.add((offset: start, length: end - start, text: ''));
        notes.add(
          '`$name` is part of `$renamed` in ${table.to}, which the pubspec '
          'already names: its entry went',
        );
        continue;
      }
      names[section]!.add(target);
      if (renamed != null) {
        edits.add((
          offset: key.span.start.offset,
          length: key.span.length,
          text: renamed,
        ));
      }
      final constraint = table.constraintFor(target);
      switch (value) {
        case YamlScalar(value: null):
          // `flutter3d:` alone: any version. Pin it to the release.
          final colon = pubspec.indexOf(':', key.span.end.offset);
          edits.add((offset: colon + 1, length: 0, text: ' $constraint'));
        case YamlScalar(value: final String _):
          edits.add((
            offset: value.span.start.offset,
            length: value.span.length,
            text: constraint,
          ));
        case YamlMap():
          if (value.containsKey('path') || value.containsKey('git')) {
            if (section != 'dependency_overrides') {
              notes.add(
                '`$target` is a ${value.containsKey('path') ? 'path' : 'git'} '
                'dependency, left as it is: point it at ${table.to}',
              );
            }
          } else if (value.nodes['version'] case final YamlScalar v) {
            edits.add((
              offset: v.span.start.offset,
              length: v.span.length,
              text: constraint,
            ));
          }
        default:
          break;
      }
    }
  }
  if (migratePluginKey(doc, notes: notes) case final TextEdit edit) {
    edits.add(edit);
  }
  return _apply(pubspec, edits);
}

/// The key plugins were declared under before 1.0, still read until 2.0.
const String _legacyPluginKey = 'flutter3d';

/// The edit that renames [doc]'s top-level `flutter3d:` key to
/// [pluginMarkerKey]; null when it has none, or has both (said in [notes]).
TextEdit? migratePluginKey(YamlMap doc, {required List<String> notes}) {
  const legacyPluginKey = _legacyPluginKey;
  const pluginKey = pluginMarkerKey;
  final legacy = <YamlNode>[
    for (final key in doc.nodes.keys)
      if (key case YamlNode(value: legacyPluginKey)) key,
  ];
  if (legacy.isEmpty) return null;
  if (doc.containsKey(pluginKey)) {
    notes.add(
      'the pubspec has both `$legacyPluginKey:` and `$pluginKey:`; move what '
      'is under `$legacyPluginKey:` into `$pluginKey:` and remove it',
    );
    return null;
  }
  final key = legacy.single;
  notes.add(
    'the `$legacyPluginKey:` key is `$pluginKey:` in 1.0: renamed, with what '
    'is under it unchanged',
  );
  return (
    offset: key.span.start.offset,
    length: key.span.length,
    text: pluginKey,
  );
}

/// The packages [pubspec] depends on, in `dependencies` and in
/// `dev_dependencies`.
({Set<String> main, Set<String> dev}) declaredDependencies(String pubspec) {
  final doc = loadYaml(pubspec);
  Set<String> keys(String section) => doc is YamlMap && doc[section] is YamlMap
      ? <String>{for (final k in (doc[section] as YamlMap).keys) '$k'}
      : <String>{};
  return (main: keys('dependencies'), dev: keys('dev_dependencies'));
}

/// [pubspec] with [add] — name to constraint — added to [section].
String addDependencies(
  String pubspec,
  Map<String, String> add, {
  String section = 'dependencies',
}) {
  if (add.isEmpty) return pubspec;
  final lines = (add.keys.toList()..sort())
      .map((String n) => '  $n: ${add[n]}\n')
      .join();
  final header = RegExp(
    '^$section:[ \\t]*(#.*)?\\n',
    multiLine: true,
  ).firstMatch(pubspec);
  if (header == null) {
    final sep = pubspec.endsWith('\n') ? '' : '\n';
    return '$pubspec$sep\n$section:\n$lines';
  }
  return pubspec.replaceRange(header.end, header.end, lines);
}

/// [source] with its import and export URIs moved: whole URIs in [uris],
/// then the longest prefix of [uris] that ends in `/` (a directory that
/// moved, `package:old/src/` to `package:new/src/old/`), then
/// `package:old/` prefixes in [packages].
String migrateDirectives(
  String source, {
  required Map<String, String> uris,
  required Map<String, String> packages,
}) {
  final prefixes = <String>[
    for (final from in uris.keys)
      if (from.endsWith('/')) from,
  ]..sort((String a, String b) => b.length.compareTo(a.length));
  String moved(String uri) {
    if (uris[uri] case final to?) return to;
    for (final from in prefixes) {
      if (uri.startsWith(from)) {
        return '${uris[from]}${uri.substring(from.length)}';
      }
    }
    final package = RegExp(r'^package:(\w+)/').firstMatch(uri)?.group(1);
    if (packages[package] case final renamed?) {
      return uri.replaceFirst('package:$package/', 'package:$renamed/');
    }
    return uri;
  }

  return source.replaceAllMapped(
    RegExp(r'''^(\s*(?:import|export)\s+)(['"])([^'"]+)\2''', multiLine: true),
    (Match m) => '${m.group(1)}${m.group(2)}${moved(m.group(3)!)}${m.group(2)}',
  );
}

/// The packages [source] imports or exports through `package:` URIs.
Set<String> referencedPackages(String source) => <String>{
  for (final m in RegExp(
    r'''^\s*(?:import|export)\s+['"]package:(\w+)/''',
    multiLine: true,
  ).allMatches(source))
    m.group(1)!,
};

/// The directories of a project whose Dart files a migration touches.
const List<String> sourceDirectories = <String>[
  'lib',
  'bin',
  'test',
  'tool',
  'integration_test',
  'test_driver',
  'example',
  'hook',
  'benchmark',
];

/// Directories whose imports make a dependency a dev dependency.
const Set<String> devDirectories = <String>{
  'test',
  'tool',
  'integration_test',
  'test_driver',
  'benchmark',
};

/// Every Dart file of [project] a migration may touch.
List<File> projectDartFiles(Directory project) => <File>[
  for (final dir in sourceDirectories)
    if (Directory('${project.path}/$dir') case final d when d.existsSync())
      for (final f in d.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !f.path.contains('/.dart_tool/') &&
            !f.path.contains('/build/'))
          f,
]..sort((File a, File b) => a.path.compareTo(b.path));

/// What `migrate` did and left, for the person who ran it.
final class MigrationReport {
  /// Files whose text changed, relative to the project.
  final List<String> changed = <String>[];

  /// Sentences about the pubspec.
  final List<String> pubspecNotes = <String>[];

  /// What a person has to do: (file, line, entry id, message, link).
  final List<({String file, int line, String id, String message, String link})>
  manual =
      <({String file, int line, String id, String message, String link})>[];

  /// The steps that ran, and how each went.
  final List<String> steps = <String>[];

  /// Dependencies added for imports the fixes introduced.
  final Map<String, String> added = <String, String>{};

  /// Names hidden on a flutter3d import because the project declares them.
  final Set<String> hidden = <String>{};

  /// Entry id to the uses `flutter3d_lints:migrate` rewrote for it.
  final Map<String, int> rewritten = <String, int>{};

  bool failed = false;

  String describe({required bool dryRun, required MigrationTable table}) {
    final out = StringBuffer()
      ..writeln(
        '${dryRun ? 'Would migrate' : 'Migrated'} from ${table.from} to '
        '${table.to}.',
      )
      ..writeln();
    for (final s in steps) {
      out.writeln('  $s');
    }
    out
      ..writeln()
      ..writeln(
        '${changed.length} files ${dryRun ? 'would change' : 'changed'}:',
      );
    for (final c in changed) {
      out.writeln('  $c');
    }
    if (rewritten.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Rewritten with the resolved code:');
      for (final id in rewritten.keys.toList()..sort()) {
        out.writeln('  ${rewritten[id]} × $id');
      }
    }
    if (added.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Dependencies added for the new imports:');
      for (final MapEntry(:key, :value) in added.entries) {
        out.writeln('  $key: $value');
      }
    }
    if (hidden.isNotEmpty) {
      out
        ..writeln()
        ..writeln(
          'Hidden on a flutter3d import, because the project declares them '
          'too: ${(hidden.toList()..sort()).join(', ')}',
        );
    }
    final todo = <String>[
      ...pubspecNotes,
      for (final m in manual) '${m.file}:${m.line}: ${m.message} ${m.link}',
    ];
    out
      ..writeln()
      ..writeln(
        todo.isEmpty
            ? 'Nothing is left to do by hand.'
            : '${todo.length} things to do by hand '
                  '(each use also has a TODO(flutter3d-1.0) above it):',
      );
    for (final t in todo) {
      out.writeln('  $t');
    }
    out
      ..writeln()
      ..writeln('The guide: ${table.guide}')
      ..write('Next: run `flutter analyze` (or `dart analyze`).');
    return out.toString();
  }
}

/// Runs [executable] in [dir], recording it in [report].
Future<ProcessResult> runStep(
  MigrationReport report,
  String label,
  String executable,
  List<String> args,
  Directory dir,
) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: dir.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  report.steps.add(
    '${result.exitCode == 0 ? 'ok    ' : 'failed'} $label '
    '(`$executable ${args.join(' ')}`)',
  );
  if (result.exitCode != 0) {
    report.failed = true;
    final why = '${result.stderr}${result.stdout}'.trim().split('\n');
    for (final line in why.take(8)) {
      report.steps.add('         $line');
    }
  }
  return result;
}

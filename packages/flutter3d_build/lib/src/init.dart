/// `ap-10`: `dart run flutter3d_build:init` — writes what a project needs
/// for `ap-05`'s hook to run on every build, without a person wiring
/// `pubspec.yaml` and `hook/build.dart` by hand.
///
/// Four things, each idempotent on its own: `hook/build.dart` (the body
/// [buildAssets]'s own doc comment names), a `dev_dependencies:` line on
/// this package, a `flutter: assets:` entry naming
/// [AssetLayout.generatedDir]'s own name, and a `.gitignore` line so that
/// directory never gets committed. A second run of any of the four is a
/// no-op — [planInit] answers "what would change" without changing
/// anything, which is both `--check`'s own report and the plan a real run
/// carries out. A `hook/build.dart` a person has edited away from what this
/// writes is left alone and reported rather than overwritten, unless
/// `--force` says otherwise.
library;

import 'dart:io';

import 'build_assets.dart';
import 'layout.dart';

/// The version constraint this package's own siblings write for each other
/// — every package in the workspace moves as one release
/// (`ARCHITECTURE.md` §16), so this is the same string `flutter3d_build`'s
/// own `pubspec.yaml` writes for `flutter3d_formats`, updated at whatever
/// release bumps this package's own version.
const String kFlutter3dBuildVersionConstraint = '^0.6.0';

/// `hook/build.dart`'s own body — [buildAssets]'s doc comment names this
/// exact text, kept here as the one place that spells it out so the two
/// cannot drift apart.
const String kHookBuildContent = '''
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, buildAssets);
}
''';

/// The `.gitignore` line naming [AssetLayout.generatedDir] — rooted
/// (`/`-prefixed) so a project with some unrelated directory of the same
/// name elsewhere is not swept up by accident, and directory-only (a
/// trailing `/`) so a same-named file would not be either.
const String kGitignoreEntry = '/flutter3d_generated/';

/// One change [planInit] found `init` would make, or one it refuses to
/// make without `--force`.
final class InitStep {
  const InitStep({required this.description, this.blocked = false, this.apply});

  /// What this step does, or — for a [blocked] step — why it did not.
  /// The line both `--check` and a real run print.
  final String description;

  /// `true` for a `hook/build.dart` a person edited, found without
  /// `--force`: [apply] is `null` and a real run leaves the file alone.
  final bool blocked;

  /// Carries out the change. `null` only when [blocked].
  final void Function()? apply;
}

/// Plans every change `init` would make against [projectRoot], writing
/// nothing itself — the one answer `--check` and a real run both read, so
/// "is this project already set up" cannot say two different things for
/// the same tree.
List<InitStep> planInit(Directory projectRoot, {bool force = false}) {
  final layout = AssetLayout(projectRoot: projectRoot);
  final steps = <InitStep>[];

  final hookFile = File('${projectRoot.path}/hook/build.dart');
  if (!hookFile.existsSync()) {
    steps.add(
      InitStep(
        description: 'write ${hookFile.path}',
        apply: () {
          hookFile.parent.createSync(recursive: true);
          hookFile.writeAsStringSync(kHookBuildContent);
        },
      ),
    );
  } else if (hookFile.readAsStringSync() != kHookBuildContent) {
    if (force) {
      steps.add(
        InitStep(
          description: 'overwrite ${hookFile.path} (--force)',
          apply: () => hookFile.writeAsStringSync(kHookBuildContent),
        ),
      );
    } else {
      steps.add(
        InitStep(
          description:
              '${hookFile.path} exists and does not match what init '
              'writes — refusing to overwrite without --force',
          blocked: true,
        ),
      );
    }
  }

  final pubspecFile = File('${projectRoot.path}/pubspec.yaml');
  final pubspecLines = pubspecFile.existsSync()
      ? pubspecFile.readAsLinesSync()
      : const <String>[];

  final withDependency = _withDevDependency(pubspecLines);
  if (withDependency != null) {
    steps.add(
      InitStep(
        description:
            'add flutter3d_build to pubspec.yaml dev_dependencies',
        apply: () => pubspecFile.writeAsStringSync(_join(withDependency)),
      ),
    );
  }

  final basePubspecLines = withDependency ?? pubspecLines;
  final generatedEntries = _generatedAssetEntries(layout);
  final missingEntries = generatedEntries
      .where((entry) => !_hasTopLevelAssetEntry(basePubspecLines, entry))
      .toList();
  if (missingEntries.isNotEmpty) {
    steps.add(
      InitStep(
        description:
            'add ${missingEntries.join(', ')} to pubspec.yaml flutter: assets:',
        apply: () {
          var lines = basePubspecLines;
          for (final entry in missingEntries) {
            lines = _withGeneratedAsset(lines, entry) ?? lines;
          }
          pubspecFile.writeAsStringSync(_join(lines));
        },
      ),
    );
  }

  final gitignoreFile = File('${projectRoot.path}/.gitignore');
  final gitignoreLines = gitignoreFile.existsSync()
      ? gitignoreFile.readAsLinesSync()
      : const <String>[];
  if (!gitignoreLines.any((line) => line.trim() == kGitignoreEntry)) {
    steps.add(
      InitStep(
        description: 'add $kGitignoreEntry to .gitignore',
        apply: () {
          final result = List<String>.from(gitignoreLines);
          if (result.isNotEmpty && result.last.trim().isNotEmpty) {
            result.add('');
          }
          result.add(kGitignoreEntry);
          gitignoreFile.writeAsStringSync(_join(result));
        },
      ),
    );
  }

  return steps;
}

/// Every `flutter: assets:` entry [layout]'s generated output actually
/// needs — the directory itself (for [buildAssets]'s own cache file) plus
/// one entry per subdirectory that holds at least one converted file.
///
/// **Flutter's own directory-asset bundling does not recurse.**
/// `flutter_tools`' `_parseAssetsFromFolder` lists a declared directory
/// with plain `listSync()` — no `recursive: true` — so a single
/// `flutter3d_generated/` line only ever bundles what sits directly in
/// it, never a subdirectory. [AssetLayout.plan] preserves each source's
/// own relative directory under `assets_src/` in its output path (a
/// `assets_src/models/chair.glb` converts to
/// `flutter3d_generated/models/chair.f3d`), so a project whose sources
/// live in a subdirectory — every project this pipeline has actually
/// shipped so far — needs that subdirectory named too, or a real build
/// bundles the hook's own bookkeeping file and silently drops every model
/// it converted. Found by shipping it, not by reading the framework's own
/// contract for what `assets:` promises: `ap-12` in
/// `doc/asset-pipeline-plan.md` names the failure directly.
Set<String> _generatedAssetEntries(AssetLayout layout) {
  final root = layout.generatedDir.path;
  final relatives = <String>{''};
  for (final plan in layout.plan()) {
    var directory = File(plan.destination).parent.path;
    while (directory.length > root.length) {
      relatives.add(directory.substring(root.length + 1));
      directory = File(directory).parent.path;
    }
  }
  final name = root.split('/').last;
  return <String>{
    for (final relative in relatives)
      relative.isEmpty ? '- $name/' : '- $name/$relative/',
  };
}

/// Whether [entryText] already sits inside `pubspec.yaml`'s active
/// `flutter: assets:` list — the same "commented `# assets:` does not
/// count" rule [_withGeneratedAsset] applies when adding one.
bool _hasTopLevelAssetEntry(List<String> lines, String entryText) {
  final flutterStart = _topLevelKey(lines, 'flutter');
  if (flutterStart == null) return false;
  final flutterEnd = _blockEnd(lines, flutterStart, indent: 0);
  for (var i = flutterStart + 1; i < flutterEnd; i++) {
    if (lines[i].trim() != 'assets:' || lines[i].trimLeft().startsWith('#')) {
      continue;
    }
    final assetsIndent = _indentOf(lines[i]);
    final listEnd = _blockEnd(lines, i, indent: assetsIndent);
    return lines
        .sublist(i + 1, listEnd)
        .any((line) => line.trim() == entryText);
  }
  return false;
}

/// `pubspec.yaml` with a `dev_dependencies: flutter3d_build: ...` line, or
/// `null` if one — any version constraint, not just this one — is already
/// there: a person who pinned a different constraint on purpose keeps it.
List<String>? _withDevDependency(List<String> lines) {
  const key = 'dev_dependencies';
  final entry = '  flutter3d_build: $kFlutter3dBuildVersionConstraint';
  final start = _topLevelKey(lines, key);
  if (start == null) {
    final result = List<String>.from(lines);
    if (result.isNotEmpty && result.last.trim().isNotEmpty) result.add('');
    result
      ..add('$key:')
      ..add(entry);
    return result;
  }
  final end = _blockEnd(lines, start, indent: 0);
  final already = lines
      .sublist(start + 1, end)
      .any((line) => RegExp(r'^\s*flutter3d_build\s*:').hasMatch(line));
  if (already) return null;
  return _insertAtEndOfBlock(lines, start, end, [entry]);
}

/// `pubspec.yaml` with [entryText] named under an active `flutter: assets:`
/// list, or `null` if it is already there. A commented-out `# assets:` —
/// the ordinary shape `flutter create` itself writes — does not count as
/// active: it is never read by the tool that reads this file, so `init`
/// treats it exactly like an absent key.
List<String>? _withGeneratedAsset(List<String> lines, String entryText) {
  final flutterStart = _topLevelKey(lines, 'flutter');
  if (flutterStart == null) {
    final result = List<String>.from(lines);
    if (result.isNotEmpty && result.last.trim().isNotEmpty) result.add('');
    result
      ..add('flutter:')
      ..add('  assets:')
      ..add('    $entryText');
    return result;
  }

  final flutterEnd = _blockEnd(lines, flutterStart, indent: 0);
  int? assetsLine;
  for (var i = flutterStart + 1; i < flutterEnd; i++) {
    final trimmed = lines[i].trim();
    if (trimmed == 'assets:' && !lines[i].trimLeft().startsWith('#')) {
      assetsLine = i;
      break;
    }
  }

  if (assetsLine == null) {
    return _insertAtEndOfBlock(lines, flutterStart, flutterEnd, [
      '  assets:',
      '    $entryText',
    ]);
  }

  final assetsIndent = _indentOf(lines[assetsLine]);
  final listEnd = _blockEnd(lines, assetsLine, indent: assetsIndent);
  final already = lines
      .sublist(assetsLine + 1, listEnd)
      .any((line) => line.trim() == entryText);
  if (already) return null;

  var itemIndent = assetsIndent + 2;
  for (var i = assetsLine + 1; i < listEnd; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('-') && !trimmed.startsWith('#')) {
      itemIndent = _indentOf(lines[i]);
      break;
    }
  }
  return _insertAtEndOfBlock(lines, assetsLine, listEnd, [
    '${' ' * itemIndent}$entryText',
  ]);
}

/// The line a top-level (column-zero) `key:` starts at, or `null` if
/// `lines` has none — a line-based stand-in for a YAML mapping lookup that
/// keeps every comment and every other key's own formatting untouched,
/// which a real parse-and-re-emit round trip through `package:yaml` does
/// not promise.
int? _topLevelKey(List<String> lines, String key) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('$key:')) return i;
  }
  return null;
}

/// The first line after [start] that belongs to an outer block — non-blank
/// and indented no more than [indent] — or `lines.length` if the block
/// runs to the end of the file.
int _blockEnd(List<String> lines, int start, {required int indent}) {
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    if (_indentOf(lines[i]) <= indent) return i;
  }
  return lines.length;
}

int _indentOf(String line) {
  var count = 0;
  while (count < line.length && line[count] == ' ') {
    count++;
  }
  return count;
}

/// [entries], inserted right after the last non-blank line inside
/// `(start, end)` — after whatever [key] already holds, rather than before
/// a trailing blank line that would otherwise land between the block's
/// header and its newest entry.
List<String> _insertAtEndOfBlock(
  List<String> lines,
  int start,
  int end,
  List<String> entries,
) {
  var insertAt = start + 1;
  for (var i = start + 1; i < end; i++) {
    if (lines[i].trim().isNotEmpty) insertAt = i + 1;
  }
  final result = List<String>.from(lines);
  result.insertAll(insertAt, entries);
  return result;
}

String _join(List<String> lines) => '${lines.join('\n')}\n';

const String initUsage = '''
Usage: dart run flutter3d_build:init [options] [project-directory]

Writes hook/build.dart, a pubspec.yaml dev_dependencies: flutter3d_build
line, a pubspec.yaml flutter: assets: entry for the generated directory,
and a .gitignore line for it — everything ap-05's build hook needs to run
on every build. project-directory defaults to the current directory.

Options:
  --check      Report what a run would change, without changing it. Exits
               non-zero if anything is pending.
  --force      Overwrite hook/build.dart even if its content does not
               match what init writes. Otherwise a hook a person has
               edited is left alone and reported instead of overwritten.
  -h, --help   Show this text.
''';

/// `dart run flutter3d_build:init`'s own `main`, factored out so a test can
/// call it against a temporary directory and capture its output rather
/// than a real project and the real `stdout`.
Future<int> runInit(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
  Directory? projectRoot,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  var check = false;
  var force = false;
  String? directory;
  for (final argument in arguments) {
    if (argument == '--check') {
      check = true;
    } else if (argument == '--force') {
      force = true;
    } else if (argument.startsWith('-')) {
      // Covers `-h`/`--help` too — same convention `runConvert` uses: the
      // usage text is what an unrecognised option gets, not a separate
      // success path, so `--help` and a typo answer identically.
      stderrSink.writeln(initUsage);
      return 2;
    } else {
      directory = argument;
    }
  }

  final root = projectRoot ?? Directory(directory ?? '.');
  if (!root.existsSync()) {
    stderrSink.writeln('No such directory: ${root.path}');
    return 1;
  }

  final steps = planInit(root, force: force);
  if (steps.isEmpty) {
    stdoutSink.writeln('flutter3d_build: already up to date');
    return 0;
  }

  var blocked = false;
  for (final step in steps) {
    if (step.blocked) {
      stderrSink.writeln(step.description);
      blocked = true;
      continue;
    }
    stdoutSink.writeln(step.description);
    if (!check) step.apply!();
  }

  if (check) return 1;
  return blocked ? 1 : 0;
}

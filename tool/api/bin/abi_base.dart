/// Records the base the ABI and vocabulary rules measure against: the
/// shader ABI and the three languages' vocabularies, as a tag holds them.
///
/// ```
/// cd tool/api
/// dart run api_snapshot:abi_base v1.0.0-rc.1      # a step of tagging rc.1
/// dart run api_snapshot:abi_base --working-tree   # before the tag, by hand
/// ```
///
/// **The base is the tagged commit's, not a day's.** `the shader ABI only
/// grows` and `a language's vocabulary grows only with its version` hold
/// each package's file to `tool/api/abi_base/`; a base copied on an
/// ordinary day leaves every change between that day and the tag outside
/// the promise, or fails the rules on work the release still has to do.
/// So tagging a release records the base from the tag, beside the API
/// baseline (`api_snapshot:api_baseline`), and the commit after the tag
/// carries it; the rule then holds the base to the tag's files line by
/// line, so a base edited by hand afterwards is caught.
///
/// The files are read with `git show <tag>:<path>`, which changes nothing
/// in the working tree; each is committed under the tag, kept current
/// there by its package's own test. `--working-tree` copies today's files
/// instead, which is only right before the tag exists: a change of the
/// release candidate's own that drops or changes a line re-records the
/// base, and its commit says so.
library;

import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart' show repositoryRootFrom;

/// Each file the rules measure, by its path in the repository, with the
/// name of its base under `tool/api/abi_base/`.
const Map<String, String> abiBaseFiles = <String, String>{
  'packages/flutter3d_shaders/api/flutter3d_shaders.abi':
      'flutter3d_shaders.abi',
  'packages/flutter3d_core/api/material_language.vocabulary':
      'material_language.vocabulary',
  'packages/flutter3d_shaders/api/kernel_language.vocabulary':
      'kernel_language.vocabulary',
  'packages/flutter3d_plugin_runtime/api/wasm_abi.vocabulary':
      'wasm_abi.vocabulary',
};

const String _usage = '''
Records the shader ABI and the languages' vocabularies as the base.

  dart run api_snapshot:abi_base <tag>            from a release tag
  dart run api_snapshot:abi_base --working-tree   from today's files, before the tag
''';

void main(List<String> args) {
  if (args.length != 1 || args.contains('--help')) {
    stderr.write(_usage);
    exitCode = 2;
    return;
  }
  final root = repositoryRootFrom(Directory.current);
  String? git(List<String> command) {
    final result = Process.runSync('git', command, workingDirectory: root.path);
    return result.exitCode == 0 ? result.stdout as String : null;
  }

  final fromTree = args.single == '--working-tree';
  final String source;
  if (fromTree) {
    source = 'the working tree (no release tagged yet)';
  } else {
    final tag = args.single;
    final commit = git(<String>['rev-list', '-n', '1', tag])?.trim();
    if (commit == null) {
      stderr.writeln('$tag is not a tag here: tag the release first');
      exitCode = 1;
      return;
    }
    source = '$tag (${commit.substring(0, 12)})';
  }
  for (final MapEntry(key: path, value: name) in abiBaseFiles.entries) {
    final text = fromTree
        ? File('${root.path}/$path').readAsStringSync()
        : git(<String>['show', '${args.single}:$path']);
    if (text == null) {
      stderr.writeln('${args.single} has no $path');
      exitCode = 1;
      return;
    }
    File('${root.path}/tool/api/abi_base/$name').writeAsStringSync(
      '# Recorded from $source by `dart run api_snapshot:abi_base`.\n'
      '$text',
    );
    stdout.writeln('recorded tool/api/abi_base/$name from $source');
  }
}

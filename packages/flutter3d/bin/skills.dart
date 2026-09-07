// Unpacks this package's agent skills into a repository that uses it.
//
//     dart run flutter3d:skills            # into ./.claude/skills
//     dart run flutter3d:skills --list     # name them and stop
//     dart run flutter3d:skills --into docs/skills
//     dart run flutter3d:skills --force    # overwrite files somebody edited
//
// **The skills are prose, and prose that lives in one repository is prose
// nobody else has.** What is written down here — that a test is shown to fail
// before it is believed, that the structure scan runs first because it needs
// nothing, that a black viewport has half a dozen causes the picture cannot
// tell apart — is the part of this engine that took the longest to learn and
// is the easiest to lose. An agent working in somebody else's game has no way
// to read `CONTRIBUTING.md` from a package in a pub cache, so this copies the
// files to where such an agent looks.
//
// `.claude/skills` under the current directory by default, because that is a
// path a consumer's own repository carries: the copy travels with their code,
// gets reviewed with their code, and is theirs to edit afterwards. Which is
// also why an edited file is left alone — see below.
//
// **Why `bin/` and not a shell script.** `dart run <package>:<executable>`
// makes pub find the package the script lives in. A package installed from
// pub.dev sits in a version-stamped cache directory nobody can write down, and
// bootstrapping that lookup by hand is the same `package_config.json` walk
// every consumer already has done for them.
//
// Only `dart:io` and `dart:isolate`, deliberately. This runs under a plain
// `dart run`, in whatever the consumer's toolchain is; a single Flutter import
// would make it a command that works for the people who happen to have a
// Flutter SDK on the path and fails for everyone else, with a message about a
// missing library rather than about anything the reader did.

import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> arguments) async {
  final force = arguments.contains('--force');
  final list = arguments.contains('--list');
  final into = _valueOf(arguments, '--into');

  if (into != null && into.isEmpty) {
    stderr.writeln('skills: --into needs a directory');
    exitCode = 1;
    return;
  }

  // Resolving a `package:` URI rather than looking at Platform.script, which is
  // a trap here: `dart run flutter3d:skills` first compiles this file into
  // `<consumer>/.dart_tool/pub/bin/flutter3d/skills.dart-*.snapshot` and runs
  // *that*, so Platform.script points into the consumer's build directory and
  // its parent.parent is nothing at all. The package URI is resolved through
  // the same package_config.json `dart run` itself leaned on to get here, and
  // survives the snapshot.
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter3d/flutter3d.dart'),
  );
  if (libraryUri == null) {
    stderr.writeln('skills: cannot resolve package:flutter3d');
    exitCode = 1;
    return;
  }
  // .../flutter3d/lib/flutter3d.dart -> .../flutter3d
  final ownPackage = File.fromUri(libraryUri).parent.parent;
  final source = Directory('${ownPackage.path}/skills');

  // A `.gitignore` reaches into `pub publish` — pub drops ignored files from
  // the archive — and `.claude/` is ignored at this repository's root, which is
  // exactly why these files live under `skills/` inside the package instead.
  // Two releases of flutter3d_impeller went out without their shader bundle for
  // the same reason, and said nothing until somebody tried to draw. So this
  // says which copy is short rather than reporting an empty success.
  if (!source.existsSync()) {
    stderr.writeln('skills: missing ${source.path}');
    stderr.writeln('This copy of flutter3d did not ship its skills.');
    exitCode = 1;
    return;
  }

  final files = _skillFilesIn(source);
  if (files.isEmpty) {
    stderr.writeln('skills: ${source.path} holds no SKILL.md');
    stderr.writeln('This copy of flutter3d did not ship its skills.');
    exitCode = 1;
    return;
  }

  if (list) {
    for (final name in _namesOf(files, source)) {
      stdout.writeln(name);
    }
    return;
  }

  final target = Directory(into ?? '${Directory.current.path}/.claude/skills');
  var written = 0;
  var kept = 0;
  for (final file in files) {
    final destination = File(
      '${target.path}/${_relative(file.path, source.path)}',
    );
    // An installed copy is the consumer's file from the moment it lands, and
    // people annotate these — a note about their own layout beside a paragraph
    // about ours. Overwriting that on the next upgrade would teach them not to
    // run the upgrade. Byte equality is the whole test for "edited": an
    // untouched copy is identical to the one in the archive, and a copy that is
    // not identical is somebody's, whichever of us changed it.
    if (destination.existsSync() &&
        destination.readAsStringSync() != file.readAsStringSync()) {
      if (!force) {
        stdout.writeln('kept   ${destination.path} (differs; --force to take)');
        kept++;
        continue;
      }
    }
    destination.parent.createSync(recursive: true);
    file.copySync(destination.path);
    written++;
  }

  stdout.writeln(
    'skills: $written written into ${target.path}'
    '${kept == 0 ? '' : ', $kept kept as they were'}',
  );
}

/// The value after `--flag`, or after the `=` in `--flag=value`.
///
/// Empty when the flag is there and its value is not, which the caller reports
/// rather than treating as absent. `--into --list` counts as missing too: a
/// directory literally named `--list` is not what anybody meant, and silently
/// creating one is the sort of help nobody thanks you for.
String? _valueOf(List<String> arguments, String flag) {
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == flag) {
      final next = i + 1 < arguments.length ? arguments[i + 1] : '';
      return next.startsWith('-') ? '' : next;
    }
    if (argument.startsWith('$flag=')) {
      return argument.substring(flag.length + 1);
    }
  }
  return null;
}

/// Every `SKILL.md` under [source], and whatever sits beside one.
///
/// A skill is a directory rather than a file so it can carry references later;
/// walking the tree rather than listing `*/SKILL.md` means the day one does,
/// nothing here has to change.
List<File> _skillFilesIn(Directory source) {
  final directories =
      source
          .listSync()
          .whereType<Directory>()
          .where((it) => File('${it.path}/SKILL.md').existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return <File>[
    for (final directory in directories)
      ...directory.listSync(recursive: true).whereType<File>(),
  ];
}

/// The skill names, in the order they were found, each named once.
List<String> _namesOf(List<File> files, Directory source) {
  final names = <String>[];
  for (final file in files) {
    final name = _relative(file.path, source.path).split('/').first;
    if (!names.contains(name)) names.add(name);
  }
  return names;
}

String _relative(String path, String root) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;

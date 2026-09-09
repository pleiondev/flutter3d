/// What this process may actually write to, asked rather than assumed.
///
///     flutter run -d macos --release --dart-define=sandbox=true
///
/// Reached through `sandbox_probe.dart`, which is a conditional export:
/// `path_provider` has no web implementation, so a web build must not import
/// this file at all.
///
/// **`p0-13n` of the plan, and it exists because the level editor next door
/// gave up on the sandbox rather than measure it.** Its `Release.entitlements`
/// turns the sandbox off with a comment saying that writing a document back
/// failed with `PathAccessException` on a path that was plainly there. That is
/// the right call for a developer tool that runs beside the repository, and the
/// wrong one for something handed to somebody else — so the modeller keeps the
/// sandbox, and this is what says exactly which writes survive it.
///
/// Three questions, because the answer differs by *where*, not by *how*:
///
///   1. **The container** — the directory the sandbox grants outright. Both a
///      direct write and a temporary-file-and-rename should work here, and if
///      they do not, autosave has no home at all.
///   2. **Outside it** — the home directory, which nothing granted. A refusal
///      here is the sandbox working; a success means the entitlements are not
///      what this file thinks they are.
///   3. **A file the person chose**, which is the interesting one and the one
///      no probe can ask on its own: the grant arrives with the panel. That
///      part is the button in the application, and its result is written down
///      in `doc/model-editor.md` §6 by whoever ran it.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One line of the probe: what was tried, and what the platform said.
typedef ProbeLine = ({String what, bool worked, String said});

/// Runs the two questions a process can answer about itself.
Future<List<ProbeLine>> probeSandbox() async {
  final lines = <ProbeLine>[];

  Future<ProbeLine> tryWrite(String what, File file) async {
    try {
      await file.writeAsBytes(<int>[1, 2, 3], flush: true);
      final length = await file.length();
      await file.delete();
      return (what: what, worked: true, said: 'wrote $length bytes');
    } on FileSystemException catch (error) {
      return (what: what, worked: false, said: error.message);
    }
  }

  Future<ProbeLine> tryRename(String what, Directory directory) async {
    final temporary = File('${directory.path}/probe.tmp');
    final target = File('${directory.path}/probe.out');
    try {
      await temporary.writeAsBytes(<int>[1, 2, 3], flush: true);
      await temporary.rename(target.path);
      await target.delete();
      return (what: what, worked: true, said: 'renamed over the target');
    } on FileSystemException catch (error) {
      return (what: what, worked: false, said: error.message);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  final container = await getApplicationSupportDirectory();
  lines.add(
    await tryWrite('the container, directly', File('${container.path}/probe')),
  );
  lines.add(await tryRename('the container, temp + rename', container));

  // Outside the container: the home directory, which the sandbox rewrites to
  // the container's own path unless the process is unsandboxed — so this line
  // says which of the two this build is as much as it says what is allowed.
  final home = Platform.environment['HOME'];
  if (home != null) {
    lines.add(
      await tryWrite('the home directory, directly', File('$home/.f3d-probe')),
    );
    lines.add((what: 'HOME resolves to', worked: true, said: home));
  }

  return lines;
}

/// The probe as the lines a screen or a console shows.
String describeProbe(List<ProbeLine> lines) => <String>[
  'sandbox probe:',
  for (final line in lines)
    '  ${line.worked ? "yes" : "no "}  ${line.what.padRight(30)} ${line.said}',
].join('\n');

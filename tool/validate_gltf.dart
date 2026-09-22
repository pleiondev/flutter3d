/// Runs the real Khronos glTF validator against a fresh `GltfWriter` export
/// of every source `gltf_validate_test.dart` already trusts — `qa-09`,
/// against `fmt-11`'s own acceptance: zero errors, and a broken `min`/`max`
/// is one.
///
///     dart run tool/validate_gltf.dart
///
/// ## Why the CLI and not the npm package of the same name
///
/// `fmt-11`'s own row names three options: the Dart `gltf` package, `npx
/// gltf-validator`, or a checker of our own. The engine took the third —
/// see `packages/flutter3d_core/lib/src/formats/gltf/gltf_validate.dart`'s own
/// doc comment for why a package that resolves without Node has no business
/// reaching for one. This script is the second option, asked for here
/// instead: `tool/` already shells out to external toolchains that are not
/// pub or npm dependencies — `glslangValidator` and `naga`, both fetched by
/// `.github/workflows/ci.yml` and simply required on `PATH` by `tool/ci.sh`
/// — and the real validator earns the same treatment for the same reason: it
/// knows things this repository's own checker was never asked to (image
/// content, extension schemas, the whole of the 2.0 spec) and a script here
/// costs nothing a package would have to carry forever.
///
/// It is not, in the end, `npx gltf-validator`. That npm package has no
/// `bin` entry — it is the validator compiled to a JS *library*, meant to be
/// `require()`d — so `npx` finds nothing to run
/// ("npm error could not determine executable to run"). Khronos ships the
/// actual command-line tool as a native binary on its GitHub releases, the
/// same shape glslang's is fetched in already, and that is what
/// `.github/workflows/ci.yml` installs and what this script calls.
///
/// ## What is validated, and what deliberately is not
///
/// `fmt-11`'s row asks for "validation of the export" — so this validates
/// `GltfWriter`'s *output*, not every third-party fixture this repository
/// happens to carry for other tests to load. [_sources] is the same small
/// corpus `gltf_validate_test.dart` already checks bounds on: each one is
/// loaded and re-written through `tool/convert_asset`, a real export built
/// fresh rather than read off disk, and only the export is handed to the
/// validator.
///
/// The larger rigged/skinned samples (`RobotExpressive.glb`,
/// `RiggedFigure.glb` and others `gltf_writer_test.dart` never round-trips
/// through this exact byte-for-byte corpus either) are deliberately left
/// out. They are third-party downloads, not something this repository
/// produces, and the real validator has an opinion about them that predates
/// this script: `RobotExpressive.glb` round-trips its `WEIGHTS_0` accessor
/// unchanged, and several of its joint weights do not sum to 1 — a real
/// `ACCESSOR_WEIGHTS_NON_NORMALIZED` finding, confirmed by hand while writing
/// this script, and one this repository's own writer neither introduces nor
/// silently fixes. Gating `qa-09` on that file would fail the build over a
/// pre-existing property of a downloaded fixture that has nothing to do with
/// this task; re-normalizing (or replacing) that sample is a separate change
/// for whoever owns the animation/skinning fixtures to make.
///
/// ## Severity
///
/// The validator's own report carries four buckets — errors, warnings,
/// infos, hints — and `GltfWriter`'s real output already carries infos
/// (an unused `TEXCOORD_0` on a material with no texture, and similar): the
/// gate this script keeps is `numErrors == 0`, the same line `fmt-11`'s own
/// acceptance draws. A warning or an info is reported, never failed on.
library;

import 'dart:convert';
import 'dart:io';

const String _validator = 'gltf_validator';

/// The sources `gltf_validate_test.dart` already trusts, each re-exported
/// through `tool/convert_asset` before it is handed to the real validator.
/// Kept in one place and named after its own test rather than duplicated by
/// hand, so a source added there is the thing a reader of this file is told
/// to add here too.
const List<String> _sources = <String>[
  'Box.glb',
  'BoxTextured.glb',
  'BoxVertexColors.glb',
  'NormalTangentTest.glb',
  'Triangle.gltf',
  'teapot.obj',
];

Future<void> main(List<String> arguments) async {
  if (!_onPath(_validator)) {
    stderr.writeln(
      '$_validator is not on PATH.\n'
      '\n'
      'This step runs the real Khronos glTF validator, not this '
      "repository's own — see this file's own doc comment for why. "
      '.github/workflows/ci.yml installs a pinned release for CI; running '
      'this locally needs the same binary on PATH:\n'
      '  https://github.com/KhronosGroup/glTF-Validator/releases\n'
      '  (download the archive for your platform, unpack it, and put '
      '`gltf_validator` on PATH)',
    );
    exitCode = 1;
    return;
  }

  final scratch = Directory.systemTemp.createTempSync('gltf_validate_');
  try {
    final targets = await _prepareFixtures(scratch);
    if (targets.length != _sources.length) {
      // A source this script names is not the same thing as a fixture this
      // script built — see the per-source message on stderr above for which
      // one and why. Silently checking fewer files than were asked for is
      // exactly the "reports green" failure mode `tool/ci.sh`'s own header
      // warns against.
      stderr.writeln(
        'built ${targets.length} of ${_sources.length} fixtures; see above',
      );
      exitCode = 1;
      return;
    }

    var totalErrors = 0;
    var totalWarnings = 0;
    for (final target in targets) {
      final report = await _validate(target);
      totalErrors += report.numErrors;
      totalWarnings += report.numWarnings;
      final label = target.path.substring(scratch.path.length + 1);
      stdout.writeln(
        '  $label: ${report.numErrors} error(s), '
        '${report.numWarnings} warning(s)',
      );
      for (final message in report.errorMessages) {
        stdout.writeln('    ✗ ${message.pointer}: ${message.text}');
      }
    }

    stdout.writeln(
      '\n${targets.length} file(s), $totalErrors error(s), '
      '$totalWarnings warning(s)',
    );
    if (totalErrors > 0) {
      exitCode = 1;
      return;
    }
    stdout.writeln('✓ every glTF/GLB asset validates clean');
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// Builds one fresh `GltfWriter` export per entry of [_sources] inside
/// [scratch], each by copying the source there and running it through
/// `tool/convert_asset` — the same CLI `fmt-14` shipped, rather than a
/// second copy of the loader/writer wiring here.
Future<List<File>> _prepareFixtures(Directory scratch) async {
  final targets = <File>[];
  for (final name in _sources) {
    final source = File('packages/flutter3d_samples/assets/$name');
    if (!source.existsSync()) {
      stderr.writeln('missing fixture source: ${source.path}');
      continue;
    }
    final copy = File('${scratch.path}/$name');
    await copy.writeAsBytes(await source.readAsBytes());

    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final exportName = '${base}_export';
    final result = await Process.run('dart', <String>[
      'run',
      'tool/convert_asset/bin/convert_asset.dart',
      copy.path,
      '-f',
      'glb',
      '-o',
      exportName,
    ]);
    if (result.exitCode != 0) {
      stderr
        ..writeln('convert_asset could not export $name:')
        ..writeln(result.stdout)
        ..writeln(result.stderr);
      continue;
    }
    targets.add(File('${scratch.path}/$exportName.glb'));
  }
  return targets;
}

/// One file's report, narrowed to the two numbers this script gates on and
/// the messages worth printing when it fails.
final class _Report {
  const _Report({
    required this.numErrors,
    required this.numWarnings,
    required this.errorMessages,
  });

  final int numErrors;
  final int numWarnings;
  final List<_Issue> errorMessages;
}

final class _Issue {
  const _Issue({required this.pointer, required this.text});

  final String pointer;
  final String text;
}

/// Runs the validator on [file] with `--stdout`, so the JSON report never
/// touches disk beside a tracked asset, and `--all` so every severity is
/// counted rather than just errors — a warning this repository picks up
/// later is worth seeing even though it never fails the build.
Future<_Report> _validate(File file) async {
  final result = await Process.run(_validator, <String>[
    '--stdout',
    '--all',
    file.path,
  ]);
  final Object? decoded = jsonDecode(result.stdout as String);
  if (decoded is! Map<String, Object?> ||
      decoded['issues'] is! Map<String, Object?>) {
    // The validator ran and said nothing this script can parse — a changed
    // report shape is not the same thing as a clean file, so this counts as
    // one error of its own rather than silently passing.
    return _Report(
      numErrors: 1,
      numWarnings: 0,
      errorMessages: <_Issue>[
        _Issue(
          pointer: file.path,
          text:
              'gltf_validator produced an unreadable report: '
              '${result.stdout}${result.stderr}',
        ),
      ],
    );
  }
  final issues = decoded['issues']! as Map<String, Object?>;
  final messages = (issues['messages'] as List?) ?? const <Object?>[];
  return _Report(
    numErrors: (issues['numErrors'] as num?)?.toInt() ?? 0,
    numWarnings: (issues['numWarnings'] as num?)?.toInt() ?? 0,
    errorMessages: <_Issue>[
      for (final message in messages)
        if (message is Map<String, Object?> && message['severity'] == 0)
          _Issue(
            pointer: '${message['pointer']}',
            text: '${message['message']}',
          ),
    ],
  );
}

bool _onPath(String program) {
  try {
    Process.runSync(program, const <String>['--help']);
    return true;
  } on ProcessException {
    return false;
  }
}
